$ErrorActionPreference = "Stop"

Get-CimInstance Win32_Process |
    Where-Object {
        $_.Name -eq "powershell.exe" -and
        $_.CommandLine -match "upload-github-release-asset"
    } |
    Select-Object ProcessId, CreationDate, CommandLine
