param([Parameter(Mandatory = $true)][string]$Hostname)

$ErrorActionPreference = "Stop"

$caddyRoot = "C:\Tools\Caddy"
$caddy = Join-Path $caddyRoot "caddy.exe"
$caddyFile = Join-Path $caddyRoot "Caddyfile"
$credentialsRoot = "C:\ProgramData\MT5GoldResearch"
$credentialsPath = Join-Path $credentialsRoot "dashboard-credentials.json"
$taskName = "MT5 Gold Research - Public Dashboard"

if (-not (Test-Path $caddy)) {
    throw "Missing Caddy executable: $caddy"
}
if ($Hostname -notmatch '^[A-Za-z0-9.-]+$') { throw "Invalid dashboard hostname" }
New-Item -ItemType Directory -Path $credentialsRoot -Force | Out-Null
& icacls $credentialsRoot /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" | Out-Null

if (Test-Path $credentialsPath) {
    $credentials = Get-Content $credentialsPath -Raw | ConvertFrom-Json
    $username = $credentials.username
    $password = $credentials.password
} else {
    $username = Read-Host "Dashboard username"
    if ([string]::IsNullOrWhiteSpace($username)) { throw "Username must not be empty" }
    $passwordBytes = New-Object byte[] 24
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($passwordBytes) } finally { $random.Dispose() }
    $password = [Convert]::ToBase64String($passwordBytes).TrimEnd('=').Replace('+','A').Replace('/','B')
    @{
        username = $username
        password = $password
        url = "https://$Hostname/development-dashboard.html"
        created_utc = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json | Set-Content $credentialsPath -Encoding ascii
}

$passwordHash = (& $caddy hash-password --plaintext $password).Trim()
if ($LASTEXITCODE -ne 0 -or -not $passwordHash.StartsWith("`$2a`$")) {
    throw "Failed to hash dashboard password"
}

@"
$Hostname {
    route {
        @root path /
        redir @root /development-dashboard.html

        @published path /development-dashboard.html /ranked-strategies.html /LongTrendBreakout.mq5 /published/*
        basic_auth @published {
            $username $passwordHash
        }
        reverse_proxy @published 127.0.0.1:8765

        respond 404
    }
}
"@ | Set-Content $caddyFile -Encoding ascii

& $caddy validate --config $caddyFile --adapter caddyfile
if ($LASTEXITCODE -ne 0) {
    throw "Invalid Caddy configuration"
}

& icacls $credentialsPath /inheritance:r /grant:r "SYSTEM:F" "Administrators:F" | Out-Null
& icacls $caddyFile /inheritance:r /grant:r "SYSTEM:F" "Administrators:F" | Out-Null

foreach ($port in 80, 443) {
    $ruleName = "MT5 Gold Research Dashboard HTTPS $port"
    Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow `
        -Protocol TCP -LocalPort $port -Profile Any | Out-Null
}

$action = New-ScheduledTaskAction -Execute $caddy `
    -Argument "run --config `"$caddyFile`" --adapter caddyfile" `
    -WorkingDirectory $caddyRoot
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 10 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable

Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

Write-Output "URL=https://$Hostname/development-dashboard.html"
Write-Output "USERNAME=$username"
Write-Output "Password was generated and stored in the restricted server credential file."
