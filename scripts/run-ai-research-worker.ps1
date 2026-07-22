$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$python = "C:\Tools\Python312\python.exe"
$credentials = "C:\ProgramData\MT5GoldResearch\ai-credentials.json"
$reports = Join-Path $projectRoot "reports"
$registryPath = Join-Path $reports "research-registry.json"
$statePath = Join-Path $reports "development-state.json"
$dashboard = Join-Path $reports "development-dashboard.html"
$parity = Join-Path $reports "parity-result.json"
$candidates = Join-Path $projectRoot "mql5\Experts\GoldResearch\Generated"
$template = Join-Path $projectRoot "mql5\Experts\GoldResearch\AdaptiveDailyStrategy.mq5"
$registrySeed = Join-Path $projectRoot "config\research-registry.seed.json"
$mutex = New-Object System.Threading.Mutex($false, "Global\MT5GoldResearchAIWorker")

if (-not $mutex.WaitOne(0, $false)) { exit 0 }

if (-not (Test-Path $registryPath)) {
    if (-not (Test-Path $registrySeed)) { throw "Missing research registry seed" }
    Copy-Item $registrySeed $registryPath
}

function Save-JsonAtomic([string]$Path, $Value) {
    $temporary = "$Path.tmp"
    $Value | ConvertTo-Json -Depth 10 | Set-Content $temporary -Encoding utf8
    Move-Item $temporary $Path -Force
}

function Render-Dashboard {
    & $python (Join-Path $projectRoot "tools\render_development_dashboard.py") `
        --state $statePath --parity $parity --registry $registryPath --output $dashboard
}

function Set-State([string]$Message, [string]$ErrorMessage = "") {
    $model = "not configured"
    if (Test-Path $credentials) {
        try {
            $model = (Get-Content $credentials -Raw | ConvertFrom-Json).model
        } catch {}
    }
    Save-JsonAtomic $statePath @{
        phase = "research"
        gate = "user_accepted"
        message = $Message
        error = $ErrorMessage
        worker_pid = $PID
        ai_model = $model
        updated_utc = (Get-Date).ToUniversalTime().ToString("o")
    }
    Render-Dashboard
}

try {
    while ($true) {
        try {
            if (-not (Test-Path $credentials)) {
                Set-State "Waiting for a new server AI API key"
                Start-Sleep -Seconds 60
                continue
            }
            $registry = Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $specPaths = @()
            $specs = @()
            foreach ($slot in 0) {
                $registry = Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $specPath = Join-Path $reports "current-ai-spec-slot$slot.json"
                Set-State "Requesting sibling AI specification $([int]$registry.attempted + 1) for slot $slot"
                & $python (Join-Path $projectRoot "tools\generate_ai_candidate.py") `
                    --credentials $credentials --registry $registryPath --template $template `
                    --output-directory $candidates --spec-output $specPath | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "AI sibling specification generation failed for slot $slot" }
                $spec = Get-Content $specPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $spec | Add-Member -NotePropertyName date_utc `
                    -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("yyyy-MM-dd"))
                $registry.attempted = [int]$registry.attempted + 1
                $registry.attempted_specs = @($registry.attempted_specs) + $spec
                Save-JsonAtomic $registryPath $registry
                $specPaths += $specPath
                $specs += $spec
            }

            $runner = Join-Path $projectRoot "scripts\run-generated-candidate.ps1"
            Set-State "MT5 test: $($specs[0].id)"
            & $runner -SpecPath $specPaths[0]
            if ($LASTEXITCODE -ne 0) { throw "MT5 candidate test failed" }
            $registry = Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
            Set-State "Candidate tests completed; next generation starts in 10 seconds"
            Start-Sleep -Seconds 10
        } catch {
            try {
                if (Test-Path $registryPath) {
                    $failedRegistry = Get-Content $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($null -eq $failedRegistry.failed) {
                        $failedRegistry | Add-Member -NotePropertyName failed -NotePropertyValue 0
                    }
                    $failedRegistry.failed = [int]$failedRegistry.failed + 1
                    Save-JsonAtomic $registryPath $failedRegistry
                }
            } catch {}
            Set-State "AI research iteration failed; retrying automatically" $_.Exception.Message
            Start-Sleep -Seconds 300
        }
    }
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
