$ErrorActionPreference = "Stop"
$path = "C:\ProgramData\MT5GoldResearch\feishu-credentials.json"
if (-not (Test-Path $path)) { throw "Configure Feishu credentials first" }
$credentials = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tokenBody = @{ app_id = $credentials.app_id; app_secret = $credentials.app_secret } |
    ConvertTo-Json -Compress
$token = Invoke-RestMethod -Method Post `
    -Uri "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" `
    -ContentType "application/json; charset=utf-8" `
    -Body ([Text.Encoding]::UTF8.GetBytes($tokenBody))
if ([int]$token.code -ne 0) { throw "Feishu token request failed: $($token.msg)" }
$headers = @{ Authorization = "Bearer $($token.tenant_access_token)" }
$response = Invoke-RestMethod -Method Get `
    -Uri "https://open.feishu.cn/open-apis/im/v1/chats?page_size=100" -Headers $headers
if ([int]$response.code -ne 0) { throw "Feishu chat list failed: $($response.msg)" }
$response.data.items | Select-Object name, chat_id, owner_id | Format-Table -AutoSize
$chatId = Read-Host "Enter the target chat_id from the list (leave empty to make no change)"
if (-not [string]::IsNullOrWhiteSpace($chatId)) {
    $credentials.chat_id = $chatId
    $credentials | ConvertTo-Json | Set-Content $path -Encoding ascii
    & icacls $path /inheritance:r /grant:r "SYSTEM:F" "Administrators:F" | Out-Null
    Write-Output "Target chat_id saved."
}
