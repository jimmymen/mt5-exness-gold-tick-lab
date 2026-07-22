$ErrorActionPreference = "Stop"

$root = "C:\ProgramData\MT5GoldResearch"
$path = Join-Path $root "feishu-credentials.json"
New-Item -ItemType Directory -Path $root -Force | Out-Null
& icacls $root /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" | Out-Null

$appId = Read-Host "Enter the Feishu application App ID"
$secretValue = Read-Host "Enter the rotated Feishu App Secret" -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secretValue)
try {
    $appSecret = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ([string]::IsNullOrWhiteSpace($appId) -or [string]::IsNullOrWhiteSpace($appSecret)) {
        throw "App ID and App Secret must not be empty"
    }
    $chatId = Read-Host "Enter the target chat_id (leave empty, then use list-feishu-chats.ps1)"
    $dashboardUrl = Read-Host "Dashboard URL (optional)"
    @{
        mode = "app"
        app_id = $appId
        app_secret = $appSecret
        chat_id = $chatId
        notify_rejections = $true
        dashboard_url = $dashboardUrl
        configured_utc = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json | Set-Content $path -Encoding ascii
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    $appSecret = $null
}
& icacls $path /inheritance:r /grant:r "SYSTEM:F" "Administrators:F" | Out-Null
Write-Output "Feishu application credentials saved in the restricted server file."
