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
    @{
        mode = "app"
        app_id = $appId
        app_secret = $appSecret
        receive_id_type = ""
        receive_id = ""
        notify_rejections = $false
        dashboard_url = ""
        ranking_url = ""
        configured_utc = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json | Set-Content $path -Encoding ascii
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    $appSecret = $null
}
& icacls $path /inheritance:r /grant:r "SYSTEM:F" "Administrators:F" | Out-Null
Write-Output "Feishu application credentials saved. Run set-feishu-recipient.ps1 next."
