param(
    [Parameter(Mandatory = $true)]
    [string]$Owner,
    [Parameter(Mandatory = $true)]
    [string]$Repository,
    [Parameter(Mandatory = $true)]
    [long]$ReleaseId,
    [Parameter(Mandatory = $true)]
    [string]$File
)

$ErrorActionPreference = "Stop"
$token = [Console]::In.ReadToEnd().Trim()
if ([string]::IsNullOrWhiteSpace($token)) {
    throw "GitHub token was not provided on standard input"
}
$name = [Uri]::EscapeDataString((Split-Path -Leaf $File))
$uri = "https://uploads.github.com/repos/$Owner/$Repository/releases/$ReleaseId/assets?name=$name"
$headers = @{
    Authorization = "Bearer $token"
    Accept = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}
try {
    $response = Invoke-RestMethod `
        -Method Post `
        -Uri $uri `
        -Headers $headers `
        -ContentType "application/octet-stream" `
        -InFile $File
    [pscustomobject]@{
        name = $response.name
        size = $response.size
        state = $response.state
        url = $response.browser_download_url
    } | ConvertTo-Json -Compress
} finally {
    $token = $null
    $headers = $null
}
