[CmdletBinding()]
param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$Model = "huihui_ai/Qwen3.6-abliterated:35b"
)

$ErrorActionPreference = "Stop"
$body = @{
    model = $Model
    messages = @(
        @{ role = "user"; content = "Reply with exactly: Intel Arc llama.cpp is working" }
    )
    temperature = 0
    max_tokens = 32
} | ConvertTo-Json -Depth 5

$request = @{
    Uri = "$BaseUrl/v1/chat/completions"
    Method = "Post"
    ContentType = "application/json"
    Body = $body
    TimeoutSec = 600
}
$response = Invoke-RestMethod @request
$response.choices[0].message.content
