"""
Foundry LLM API Client - Chat via Private APIM using a subscription key

Usage:
    set APIM_SUBSCRIPTION_KEY=<your-key>
    python scripts/chat-foundry-apim-key.py "What is Azure AI Foundry?"
    python scripts/chat-foundry-apim-key.py --stream "Tell me a joke"
    python scripts/chat-foundry-apim-key.py  # interactive mode
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


APIM_ENDPOINT = os.environ.get(
    "APIM_ENDPOINT", "https://apim-ai-lab-private.azure-api.net"
).rstrip("/")
DEPLOYMENT = os.environ.get("FOUNDRY_DEPLOYMENT", "gpt-4.1")
API_VERSION = "2024-10-21"


def get_subscription_key() -> str:
    key = os.environ.get("APIM_SUBSCRIPTION_KEY")
    if not key:
        raise RuntimeError("APIM_SUBSCRIPTION_KEY environment variable is required")
    return key


def chat(subscription_key: str, message: str, stream: bool = False) -> None:
    deployment = urllib.parse.quote(DEPLOYMENT, safe="")
    query = urllib.parse.urlencode({"api-version": API_VERSION})
    url = (
        f"{APIM_ENDPOINT}/openai/deployments/{deployment}/chat/completions?{query}"
    )
    payload = {
        "messages": [{"role": "user", "content": message}],
        "max_tokens": 500,
        "stream": stream,
    }
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Ocp-Apim-Subscription-Key": subscription_key,
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            if stream:
                for raw_line in response:
                    line = raw_line.decode("utf-8").strip()
                    if not line.startswith("data:"):
                        continue
                    data = line.removeprefix("data:").strip()
                    if data == "[DONE]":
                        break
                    chunk = json.loads(data)
                    choices = chunk.get("choices") or []
                    if choices:
                        content = (choices[0].get("delta") or {}).get("content")
                        if content:
                            print(content, end="", flush=True)
                print()
            else:
                result = json.load(response)
                print(result["choices"][0]["message"]["content"])
    except urllib.error.HTTPError as error:
        details = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"APIM request failed with HTTP {error.code}: {details}") from error
    except urllib.error.URLError as error:
        raise RuntimeError(f"Could not reach APIM: {error.reason}") from error


def interactive(subscription_key: str, stream: bool = False) -> None:
    print(f"Chat with {DEPLOYMENT} via private APIM (Ctrl+C to exit)\n")
    while True:
        try:
            user_input = input("You: ")
            if not user_input.strip():
                continue
            print("AI: ", end="")
            chat(subscription_key, user_input, stream=stream)
            print()
        except (KeyboardInterrupt, EOFError):
            print("\nBye!")
            break


def main() -> int:
    stream = "--stream" in sys.argv
    args = [argument for argument in sys.argv[1:] if not argument.startswith("--")]

    try:
        subscription_key = get_subscription_key()
        if args:
            chat(subscription_key, " ".join(args), stream=stream)
        else:
            interactive(subscription_key, stream=stream)
    except RuntimeError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
