$ErrorActionPreference = "Stop"
$path = "C:\ProgramData\MT5GoldResearch\feishu-credentials.json"
if (-not (Test-Path $path)) { throw "Configure Feishu application credentials first" }
$credentials = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

$receiveIdType = Read-Host "Recipient ID type: email, open_id, user_id, or union_id (default: email)"
if ([string]::IsNullOrWhiteSpace($receiveIdType)) { $receiveIdType = "email" }
if ($receiveIdType -notin @("email", "open_id", "user_id", "union_id")) {
    throw "Unsupported recipient ID type"
}
$receiveId = Read-Host "Recipient $receiveIdType"
if ([string]::IsNullOrWhiteSpace($receiveId)) { throw "Recipient must not be empty" }
$dashboardUrl = Read-Host "Research dashboard URL (optional)"
$rankingUrl = Read-Host "Ranked strategy URL (optional)"

$credentials | Add-Member -NotePropertyName receive_id_type -NotePropertyValue $receiveIdType -Force
$credentials | Add-Member -NotePropertyName receive_id -NotePropertyValue $receiveId -Force
$credentials | Add-Member -NotePropertyName notify_rejections -NotePropertyValue $false -Force
if (-not [string]::IsNullOrWhiteSpace($dashboardUrl)) {
    $credentials.dashboard_url = $dashboardUrl
}
$credentials | Add-Member -NotePropertyName ranking_url -NotePropertyValue $rankingUrl -Force
$credentials | Add-Member -NotePropertyName configured_utc `
    -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("o")) -Force
$credentials | ConvertTo-Json | Set-Content $path -Encoding ascii
& icacls $path /inheritance:r /grant:r "SYSTEM:F" "Administrators:F" | Out-Null
Write-Output "Feishu direct-message recipient saved; rejection notifications are disabled."
