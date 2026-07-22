$ErrorActionPreference = "Stop"

$path = "C:\ProgramData\MT5GoldResearch\ai-credentials.json"
$root = Split-Path $path
New-Item -ItemType Directory -Path $root -Force | Out-Null
& icacls $root /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" | Out-Null
$key = Read-Host "Enter the new AI API Key" -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($key)
try {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ([string]::IsNullOrWhiteSpace($plain)) { throw "API Key must not be empty" }
    @{
        base_url = "https://api.deepseek.com"
        model = "deepseek-v4-pro"
        thinking = $true
        reasoning_effort = "high"
        ca_file = "C:\ProgramData\MT5GoldResearch\mozilla-cacert.pem"
        api_key = $plain
        configured_utc = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json | Set-Content $path -Encoding ascii
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
}
& icacls $path /inheritance:r /grant:r "SYSTEM:F" "Administrators:F" | Out-Null
Write-Output "AI credentials saved outside the project with restricted ACLs."
