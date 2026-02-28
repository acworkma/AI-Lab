#!/usr/bin/env python3

import argparse
import ipaddress
import json
import socket
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


def log(level: str, message: str) -> None:
    print(f"[{level}] {message}")


def run_az(args: list[str]) -> str:
    process = subprocess.run(
        ["az", *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if process.returncode != 0:
        stderr = process.stderr.strip() or "Unknown Azure CLI error"
        raise RuntimeError(stderr)
    return process.stdout.strip()


def discover_account_name(resource_group: str) -> str:
    account_name = run_az([
        "cognitiveservices",
        "account",
        "list",
        "-g",
        resource_group,
        "--query",
        "[?kind=='AIServices'] | [0].name",
        "-o",
        "tsv",
    ])
    if not account_name:
        raise RuntimeError(f"No AIServices account found in resource group '{resource_group}'")
    return account_name


def discover_deployment_name(resource_group: str, account_name: str, preferred: str | None) -> str:
    if preferred:
        return preferred

    deployments_json = run_az([
        "cognitiveservices",
        "account",
        "deployment",
        "list",
        "-g",
        resource_group,
        "-n",
        account_name,
        "-o",
        "json",
    ])
    deployments = json.loads(deployments_json)
    if not deployments:
        raise RuntimeError(f"No model deployments found in account '{account_name}'")

    preferred_match = next((d for d in deployments if d.get("name") == "gpt-4.1"), None)
    if preferred_match:
        return preferred_match["name"]
    return deployments[0]["name"]


def get_account_endpoint(resource_group: str, account_name: str) -> str:
    endpoint = run_az([
        "cognitiveservices",
        "account",
        "show",
        "-g",
        resource_group,
        "-n",
        account_name,
        "--query",
        "properties.endpoint",
        "-o",
        "tsv",
    ])
    if not endpoint:
        raise RuntimeError(f"No endpoint found for account '{account_name}'")
    return endpoint.rstrip("/")


def get_aad_token() -> str:
    token = run_az([
        "account",
        "get-access-token",
        "--resource",
        "https://cognitiveservices.azure.com/",
        "--query",
        "accessToken",
        "-o",
        "tsv",
    ])
    if not token:
        raise RuntimeError("Failed to retrieve Azure AD access token")
    return token


def resolve_host(endpoint: str, require_private_dns: bool) -> tuple[str, str]:
    host = urllib.parse.urlparse(endpoint).hostname
    if not host:
        raise RuntimeError(f"Invalid endpoint URL: {endpoint}")

    resolved_ip = socket.gethostbyname(host)
    ip = ipaddress.ip_address(resolved_ip)
    if require_private_dns and not ip.is_private:
        raise RuntimeError(f"Host '{host}' resolved to non-private IP {resolved_ip}")
    return host, resolved_ip


def call_inference(endpoint: str, deployment_name: str, api_version: str, token: str, prompt: str, timeout: int) -> tuple[int, dict]:
    url = f"{endpoint}/openai/deployments/{deployment_name}/chat/completions?api-version={api_version}"
    payload = {
        "messages": [
            {
                "role": "user",
                "content": prompt,
            }
        ],
        "max_tokens": 300,
        "temperature": 0.2,
    }

    request = urllib.request.Request(
        url=url,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
        },
        data=json.dumps(payload).encode("utf-8"),
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8")
            return response.status, json.loads(body)
    except urllib.error.HTTPError as error:
        error_body = error.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(error_body)
        except json.JSONDecodeError:
            parsed = {"raw": error_body}
        return error.code, parsed


def extract_text(response_json: dict) -> str:
    choices = response_json.get("choices") or []
    if not choices:
        return ""

    first = choices[0]
    message = first.get("message") or {}
    content = message.get("content")

    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = [item.get("text", "") for item in content if isinstance(item, dict)]
        return "\n".join([part for part in parts if part]).strip()
    return ""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Send a prompt to deployed Foundry model and print response.")
    parser.add_argument("--resource-group", "-g", default="rg-ai-foundry", help="Resource group containing Foundry account")
    parser.add_argument("--account", "-a", default=None, help="Foundry AIServices account name")
    parser.add_argument("--deployment", "-d", default=None, help="Model deployment name (default auto-discover)")
    parser.add_argument("--prompt", "-p", default="Reply with: Private Foundry inference is reachable.", help="Prompt text")
    parser.add_argument("--api-version", default="2024-10-21", help="Azure OpenAI chat completions API version")
    parser.add_argument("--timeout", type=int, default=30, help="HTTP timeout in seconds")
    parser.add_argument("--allow-public-dns", action="store_true", help="Allow endpoint DNS to resolve to non-private IP")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        account_name = args.account or discover_account_name(args.resource_group)
        deployment_name = discover_deployment_name(args.resource_group, account_name, args.deployment)
        endpoint = get_account_endpoint(args.resource_group, account_name)

        host, ip_addr = resolve_host(endpoint, require_private_dns=not args.allow_public_dns)
        log("INFO", f"Account: {account_name}")
        log("INFO", f"Deployment: {deployment_name}")
        log("INFO", f"Endpoint host: {host}")
        log("INFO", f"Resolved IP: {ip_addr}")

        token = get_aad_token()
        status_code, response_json = call_inference(
            endpoint=endpoint,
            deployment_name=deployment_name,
            api_version=args.api_version,
            token=token,
            prompt=args.prompt,
            timeout=args.timeout,
        )

        if status_code >= 400:
            log("ERROR", f"Inference request failed with HTTP {status_code}")
            print(json.dumps(response_json, indent=2))
            return 6

        text = extract_text(response_json)
        if not text:
            log("ERROR", "Inference succeeded but no response text was found")
            print(json.dumps(response_json, indent=2))
            return 7

        log("SUCCESS", "Inference call succeeded")
        print("\nModel response:\n")
        print(text)
        return 0

    except socket.gaierror as error:
        log("ERROR", f"DNS resolution failed: {error}")
        return 4
    except RuntimeError as error:
        log("ERROR", str(error))
        return 3
    except Exception as error:
        log("ERROR", f"Unexpected failure: {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
