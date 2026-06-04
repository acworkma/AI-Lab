#!/usr/bin/env python3
"""
Azure OpenAI (Legacy) API Client — Chat via Private APIM (/aoai)

Usage:
    python scripts/chat-aoai.py "What is Azure OpenAI?"
    python scripts/chat-aoai.py --stream "Tell me a joke"
    python scripts/chat-aoai.py  # interactive mode

Requires:
    pip install openai azure-identity
"""

import sys
import os
from openai import AzureOpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

APIM_ENDPOINT = os.environ.get("APIM_ENDPOINT", "https://apim-ai-lab-private.azure-api.net")
DEPLOYMENT = os.environ.get("AOAI_DEPLOYMENT", "gpt-4.1")
API_VERSION = "2024-10-21"

# The AzureOpenAI SDK appends /openai automatically, but our APIM routes
# the legacy service under /aoai. We use the base_url override to control the path.
BASE_URL = f"{APIM_ENDPOINT}/aoai"


def get_client() -> AzureOpenAI:
    token_provider = get_bearer_token_provider(
        DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default"
    )
    return AzureOpenAI(
        base_url=f"{BASE_URL}",
        azure_ad_token_provider=token_provider,
        api_version=API_VERSION,
    )


def chat(client: AzureOpenAI, message: str, stream: bool = False):
    messages = [{"role": "user", "content": message}]

    if stream:
        response = client.chat.completions.create(
            model=DEPLOYMENT, messages=messages, stream=True
        )
        for chunk in response:
            if chunk.choices and chunk.choices[0].delta.content:
                print(chunk.choices[0].delta.content, end="", flush=True)
        print()
    else:
        response = client.chat.completions.create(
            model=DEPLOYMENT, messages=messages, max_tokens=500
        )
        print(response.choices[0].message.content)


def interactive(client: AzureOpenAI, stream: bool = False):
    print(f"Chat with {DEPLOYMENT} via private APIM /aoai (Ctrl+C to exit)\n")
    while True:
        try:
            user_input = input("You: ")
            if not user_input.strip():
                continue
            print("AI: ", end="")
            chat(client, user_input, stream=stream)
            print()
        except (KeyboardInterrupt, EOFError):
            print("\nBye!")
            break


def main():
    stream = "--stream" in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith("--")]

    client = get_client()

    if args:
        chat(client, " ".join(args), stream=stream)
    else:
        interactive(client, stream=stream)


if __name__ == "__main__":
    main()
