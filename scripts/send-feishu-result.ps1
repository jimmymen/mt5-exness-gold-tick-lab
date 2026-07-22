param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][ValidateSet("PUBLISH", "REJECT_DEVELOPMENT", "REJECT_OOS")][string]$Decision,
    [Parameter(Mandatory = $true)][double]$DevelopmentProfit,
    [Parameter(Mandatory = $true)][double]$DevelopmentProfitFactor,
    [Parameter(Mandatory = $true)][double]$DevelopmentDrawdown,
    [Parameter(Mandatory = $true)][int]$DevelopmentActiveDays,
    [Parameter(Mandatory = $true)][int]$DevelopmentCoveredDays,
    [Parameter(Mandatory = $true)][int]$DevelopmentMissingDays,
    [double]$OosProfit = 0,
    [double]$OosProfitFactor = 0,
    [double]$OosDrawdown = 0,
    [int]$OosActiveDays = 0,
    [int]$OosCoveredDays = 0,
    [int]$OosMissingDays = 0
)

$ErrorActionPreference = "Stop"
$credentialsPath = "C:\ProgramData\MT5GoldResearch\feishu-credentials.json"
if (-not (Test-Path $credentialsPath)) { exit 0 }

$credentials = Get-Content $credentialsPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($Decision -ne "PUBLISH" -and -not [bool]$credentials.notify_rejections) { exit 0 }
$labels = @{
    PUBLISH = "PUBLISH: development and OOS passed"
    REJECT_DEVELOPMENT = "REJECT: development failed"
    REJECT_OOS = "REJECT: OOS failed"
}
$developmentCoverage = if ($DevelopmentActiveDays -gt 0) {
    "{0:P2}" -f ($DevelopmentCoveredDays / $DevelopmentActiveDays)
} else { "0.00%" }
$lines = @(
    "Gold strategy test completed: $Id",
    "Decision: $($labels[$Decision])",
    "Development: profit $($DevelopmentProfit.ToString('F2')) USD, PF $($DevelopmentProfitFactor.ToString('F4')), equity DD $($DevelopmentDrawdown.ToString('F2'))%",
    "Development coverage: $DevelopmentCoveredDays/$DevelopmentActiveDays ($developmentCoverage), missing $DevelopmentMissingDays days"
)
if ($Decision -ne "REJECT_DEVELOPMENT") {
    $oosCoverage = if ($OosActiveDays -gt 0) {
        "{0:P2}" -f ($OosCoveredDays / $OosActiveDays)
    } else { "0.00%" }
    $lines += "OOS: profit $($OosProfit.ToString('F2')) USD, PF $($OosProfitFactor.ToString('F4')), equity DD $($OosDrawdown.ToString('F2'))%"
    $lines += "OOS coverage: $OosCoveredDays/$OosActiveDays ($oosCoverage), missing $OosMissingDays days"
}
if (-not [string]::IsNullOrWhiteSpace([string]$credentials.dashboard_url)) {
    $lines += "Dashboard: $($credentials.dashboard_url)"
}
if (-not [string]::IsNullOrWhiteSpace([string]$credentials.ranking_url)) {
    $lines += "Curve ranking: $($credentials.ranking_url)"
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$receiveIdType = [string]$credentials.receive_id_type
$receiveId = [string]$credentials.receive_id
if ($receiveIdType -notin @("email", "open_id", "user_id", "union_id")) {
    throw "Feishu direct-message recipient type is not configured"
}
if ([string]::IsNullOrWhiteSpace($receiveId)) {
    throw "Feishu direct-message recipient is not configured"
}
$tokenBody = @{ app_id = $credentials.app_id; app_secret = $credentials.app_secret } |
    ConvertTo-Json -Compress
$token = Invoke-RestMethod -Method Post `
    -Uri "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" `
    -ContentType "application/json; charset=utf-8" `
    -Body ([Text.Encoding]::UTF8.GetBytes($tokenBody))
if ([int]$token.code -ne 0) { throw "Feishu token request failed: $($token.msg)" }
$headers = @{ Authorization = "Bearer $($token.tenant_access_token)" }
$messageText = $lines -join "`n"
if ($receiveIdType -eq "user_id") {
    # Existing enterprise bots can address tenant user IDs through the legacy
    # message endpoint without requesting contact-directory field access.
    $payload = @{
        user_id = $receiveId
        msg_type = "text"
        content = @{ text = $messageText }
    } | ConvertTo-Json -Depth 4 -Compress
    $uri = "https://open.feishu.cn/open-apis/message/v4/send/"
} else {
    $payload = @{
        receive_id = $receiveId
        msg_type = "text"
        content = (@{ text = $messageText } | ConvertTo-Json -Compress)
    } | ConvertTo-Json -Compress
    $uri = "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=$receiveIdType"
}
$response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers `
    -ContentType "application/json; charset=utf-8" `
    -Body ([Text.Encoding]::UTF8.GetBytes($payload))
if ([int]$response.code -ne 0) { throw "Feishu message rejected: $($response.msg)" }
