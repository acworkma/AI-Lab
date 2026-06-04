#!/usr/bin/env bash
#
# chat-aoai.sh - Quick chat test against legacy Azure OpenAI via private APIM
#
# Usage:
#   ./scripts/chat-aoai.sh "What is Azure OpenAI?"
#   ./scripts/chat-aoai.sh --stream "Tell me a joke"
#
# Requires: az CLI logged in, curl, jq
#

set -euo pipefail

APIM_ENDPOINT="${APIM_ENDPOINT:-https://apim-ai-lab-private.azure-api.net}"
DEPLOYMENT="${AOAI_DEPLOYMENT:-gpt-4.1}"
API_VERSION="2024-10-21"
STREAM=false
MESSAGE=""

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --stream) STREAM=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--stream] \"message\""
            echo "  --stream   Use server-sent events streaming"
            exit 0
            ;;
        *) MESSAGE="$1"; shift ;;
    esac
done

if [ -z "$MESSAGE" ]; then
    echo "Usage: $0 [--stream] \"message\""
    exit 1
fi

# Get token
TOKEN=$(az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv)

URL="${APIM_ENDPOINT}/aoai/deployments/${DEPLOYMENT}/chat/completions?api-version=${API_VERSION}"

BODY=$(jq -n \
    --arg msg "$MESSAGE" \
    --argjson stream "$STREAM" \
    '{messages: [{role: "user", content: $msg}], max_tokens: 500, stream: $stream}')

if [ "$STREAM" = true ]; then
    curl -sN "$URL" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$BODY" | while IFS= read -r line; do
        if [[ "$line" == data:* ]]; then
            data="${line#data: }"
            if [ "$data" = "[DONE]" ]; then
                echo ""
                break
            fi
            content=$(echo "$data" | jq -r '.choices[0].delta.content // empty' 2>/dev/null)
            if [ -n "$content" ]; then
                printf "%s" "$content"
            fi
        fi
    done
else
    curl -s "$URL" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$BODY" | jq -r '.choices[0].message.content'
fi
