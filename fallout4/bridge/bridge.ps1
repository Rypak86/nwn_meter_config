$ErrorActionPreference = "Stop"

$Root = "C:\Fallout4_Modding"
$BridgeRoot = Join-Path $Root "Bridge"
$JobsRoot = Join-Path $BridgeRoot "Jobs"
$ReadyRoot = Join-Path $Root "VortexReady"
$StateFile = Join-Path $BridgeRoot "state.json"
$LogFile = Join-Path $BridgeRoot "bridge.log"

$BaseUrl = "https://raw.githubusercontent.com/Rypak86/nwn_meter_config/fallout4-build-bridge/fallout4"

New-Item -ItemType Directory -Force -Path $BridgeRoot,$JobsRoot,$ReadyRoot | Out-Null

function Log([string]$m) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Get-State {
    if (Test-Path $StateFile) {
        try { return (Get-Content $StateFile -Raw | ConvertFrom-Json) } catch {}
    }
    return [pscustomobject]@{ last_success = ""; last_attempt = "" }
}

function Save-State($success,$attempt) {
    [ordered]@{ last_success=$success; last_attempt=$attempt } |
        ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8
}

Log "Bridge started"

while ($true) {
    try {
        $manifestText = (Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/manifest.json" -TimeoutSec 15).Content
        $manifest = $manifestText | ConvertFrom-Json

        if (-not $manifest.build_id) { throw "Manifest has no build_id" }

        $state = Get-State
        if ($state.last_success -ne $manifest.build_id -and $state.last_attempt -ne $manifest.build_id) {
            Save-State $state.last_success $manifest.build_id
            Log "New build: $($manifest.build_id)"

            $jobDir = Join-Path $JobsRoot $manifest.build_id
            Remove-Item $jobDir -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Force -Path $jobDir | Out-Null

            foreach ($relative in $manifest.files) {
                $local = Join-Path $jobDir $relative
                $parent = Split-Path -Parent $local
                New-Item -ItemType Directory -Force -Path $parent | Out-Null

                $urlPath = ($relative -replace "\\","/")
                $uri = "$BaseUrl/$urlPath"
                Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $local -TimeoutSec 30
            }

            $entry = Join-Path $jobDir $manifest.entrypoint
            if (-not (Test-Path $entry)) { throw "Entrypoint missing: $entry" }

            $stdout = Join-Path $jobDir "stdout.log"
            $stderr = Join-Path $jobDir "stderr.log"

            $p = Start-Process powershell.exe -ArgumentList @(
                "-NoProfile",
                "-ExecutionPolicy","Bypass",
                "-File",$entry
            ) -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr

            if ($p.ExitCode -ne 0) {
                $err = ""
                if (Test-Path $stderr) { $err = Get-Content $stderr -Raw -ErrorAction SilentlyContinue }
                Log "Build failed exit=$($p.ExitCode) $err"
                Remove-Item (Join-Path $ReadyRoot "BUILD_FAILED.txt") -Force -ErrorAction SilentlyContinue
                @"
BUILD FAILED
ID: $($manifest.build_id)
Time: $(Get-Date -Format o)
Exit: $($p.ExitCode)

$err

See:
$jobDir
"@ | Set-Content (Join-Path $ReadyRoot "BUILD_FAILED.txt") -Encoding UTF8

                # Permit retry when the cloud build id changes. Do not hammer the same broken job.
                Save-State $state.last_success $manifest.build_id
            }
            else {
                if (-not (Test-Path $manifest.output)) {
                    throw "Build returned success but expected output is missing: $($manifest.output)"
                }

                Remove-Item (Join-Path $ReadyRoot "BUILD_FAILED.txt") -Force -ErrorAction SilentlyContinue
                Save-State $manifest.build_id $manifest.build_id
                Log "Build OK: $($manifest.output)"
            }
        }
    }
    catch {
        Log "Bridge error: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 15
}
