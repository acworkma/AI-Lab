<#
.SYNOPSIS
    Chat with Foundry gpt-4.1 through private APIM

.DESCRIPTION
    Simple PowerShell client that sends messages to the Foundry LLM API
    through the private APIM gateway using Entra ID authentication.

.EXAMPLE
    .\scripts\Chat-Foundry.ps1 "What is Azure AI Foundry?"
    .\scripts\Chat-Foundry.ps1 -Stream "Tell me a joke"
    .\scripts\Chat-Foundry.ps1  # interactive mode
#>
param(
    [Parameter(Position = 0)]
    [string]$Message,

    [switch]$Stream,

    [string]$Deployment = "gpt-4.1",

    [string]$ApiVersion = "2024-10-21"
)

$ApimEndpoint = "https://apim-ai-lab-private.azure-api.net/openai"

function Get-Token {
    az account get-access-token --resource https://cognitiveservices.azure.com --query accessToken -o tsv
}

function Send-Chat {
    param([string]$UserMessage, [bool]$UseStream)

    $token = Get-Token
    $uri = "$ApimEndpoint/deployments/$Deployment/chat/completions?api-version=$ApiVersion"

    $body = @{
        messages   = @(@{ role = "user"; content = $UserMessage })
        max_tokens = 500
        stream     = $UseStream
    } | ConvertTo-Json -Depth 3

    if ($UseStream) {
        # Streaming with SSE
        $request = [System.Net.HttpWebRequest]::Create($uri)
        $request.Method = "POST"
        $request.ContentType = "application/json"
        $request.Headers.Add("Authorization", "Bearer $token")
        $request.AllowReadStreamBuffering = $false

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $request.ContentLength = $bytes.Length
        $reqStream = $request.GetRequestStream()
        $reqStream.Write($bytes, 0, $bytes.Length)
        $reqStream.Close()

        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())

        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ($line -match '^data: (.+)$') {
                $data = $Matches[1]
                if ($data -eq '[DONE]') { break }
                $chunk = $data | ConvertFrom-Json
                if ($chunk.choices[0].delta.content) {
                    Write-Host -NoNewline $chunk.choices[0].delta.content
                }
            }
        }
        Write-Host ""
        $reader.Close()
        $response.Close()
    }
    else {
        $response = Invoke-RestMethod -Uri $uri -Method POST -Body $body -Headers @{
            Authorization  = "Bearer $token"
            "Content-Type" = "application/json"
        }
        Write-Host $response.choices[0].message.content
    }
}

# Main
if ($Message) {
    Send-Chat -UserMessage $Message -UseStream $Stream.IsPresent
}
else {
    Write-Host "Chat with $Deployment via private APIM (type 'exit' to quit)`n" -ForegroundColor Cyan
    while ($true) {
        $input = Read-Host "You"
        if ($input -eq 'exit' -or $null -eq $input) { break }
        if ([string]::IsNullOrWhiteSpace($input)) { continue }
        Write-Host -NoNewline "AI: " -ForegroundColor Green
        Send-Chat -UserMessage $input -UseStream $Stream.IsPresent
        Write-Host ""
    }
}
