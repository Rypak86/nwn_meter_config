$ErrorActionPreference = "Stop"

$Root = "C:\Fallout4_Modding"
$Project = Join-Path $Root "Projects\DogFriend"
$Ready = Join-Path $Root "VortexReady"
$EnvFile = Join-Path $Root "BuildTools\fallout4-build-env.json"
$JobDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Fail($m) { throw $m }

if (-not (Test-Path $EnvFile)) { Fail "Missing build environment: $EnvFile" }
$cfg = Get-Content $EnvFile -Raw | ConvertFrom-Json
$FO4Root = $cfg.fallout4_root
$DataDir = Join-Path $FO4Root "Data"
$XEditExe = $cfg.xedit_exe
$Compiler = $cfg.papyrus_compiler
$Flags = $cfg.papyrus_flags
$SourceRoot = $cfg.papyrus_source

New-Item -ItemType Directory -Force -Path $Project,$Ready | Out-Null
$BuildDir = Join-Path $Project "Build"
$StageDir = Join-Path $BuildDir "Vortex"
$ScriptsOut = Join-Path $StageDir "Scripts"
$SourceOut = Join-Path $BuildDir "Source"
Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $StageDir,$ScriptsOut,$SourceOut | Out-Null
Remove-Item (Join-Path $Project "DogFriend.buildinfo") -Force -ErrorAction SilentlyContinue

$XEditDir = Split-Path -Parent $XEditExe
$EditScriptsDir = Join-Path $XEditDir "Edit Scripts"
New-Item -ItemType Directory -Force -Path $EditScriptsDir | Out-Null
Copy-Item (Join-Path $JobDir "DogFriend_Build.pas") (Join-Path $EditScriptsDir "DogFriend_Build.pas") -Force

$ExistingEsp = Join-Path $DataDir "DogFriend.esp"
$BackupEsp = Join-Path $Project "DogFriend.esp.prebuild.bak"
$HadExisting = Test-Path $ExistingEsp
if ($HadExisting) {
  Copy-Item $ExistingEsp $BackupEsp -Force
  Remove-Item $ExistingEsp -Force
}

try {
  $args = @("-autoload","-nobuildrefs","-script:DogFriend_Build.pas","-autoexit")
  $p = Start-Process -FilePath $XEditExe -ArgumentList $args -WorkingDirectory $XEditDir -Wait -PassThru
  if ($p.ExitCode -ne 0) { Fail "xEdit exit code $($p.ExitCode)" }
  if (-not (Test-Path $ExistingEsp)) { Fail "xEdit did not create DogFriend.esp" }

  $BuildInfo = Join-Path $Project "DogFriend.buildinfo"
  if (-not (Test-Path $BuildInfo)) { Fail "Missing DogFriend.buildinfo" }

  $line = Get-Content $BuildInfo | Where-Object { $_ -match '^WHISTLE_FORMID=' } | Select-Object -First 1
  if (-not $line) { Fail "Missing WHISTLE_FORMID" }
  $WhistleID = ($line -split '=',2)[1].Trim()

  $StartupPsc = Join-Path $SourceOut "DogFriendStartup.psc"
  $SummonPsc = Join-Path $SourceOut "DogFriendSummonEffect.psc"

  (Get-Content (Join-Path $JobDir "DogFriendStartup.psc.in") -Raw).Replace("__WHISTLE_FORMID__", $WhistleID) | Set-Content $StartupPsc -Encoding UTF8
  (Get-Content (Join-Path $JobDir "DogFriendSummonEffect.psc.in") -Raw).Replace("__WHISTLE_FORMID__", $WhistleID) | Set-Content $SummonPsc -Encoding UTF8

  $imports = @((Join-Path $SourceRoot "Base"),(Join-Path $SourceRoot "User"),$SourceOut) | Where-Object { Test-Path $_ }
  $importArg = ($imports -join ";")

  foreach ($psc in @($StartupPsc,$SummonPsc)) {
    & $Compiler $psc "-f=$Flags" "-i=$importArg" "-o=$ScriptsOut"
    if ($LASTEXITCODE -ne 0) { Fail "Papyrus failed: $psc" }
  }

  Copy-Item $ExistingEsp (Join-Path $StageDir "DogFriend.esp") -Force
  @"
DOG FRIEND MVP

Install this ZIP with Vortex.

Dog Whistle appears in Aid and can be favorited.
Use it to call 3 friendly dogs.
They follow/fight for 180 seconds, then disappear.
No MCM. No F4SE dependency.
"@ | Set-Content (Join-Path $StageDir "README.txt") -Encoding UTF8

  $Zip = Join-Path $Ready "DogFriend_MVP_Vortex.zip"
  Remove-Item $Zip -Force -ErrorAction SilentlyContinue
  Compress-Archive -Path (Join-Path $StageDir "*") -DestinationPath $Zip -CompressionLevel Optimal
  if (-not (Test-Path $Zip)) { Fail "Final ZIP missing" }

  Set-Content (Join-Path $Ready "DogFriend_MVP_Vortex.OK.txt") "BUILD OK $(Get-Date -Format o)" -Encoding UTF8
}
finally {
  if (Test-Path $ExistingEsp) { Remove-Item $ExistingEsp -Force -ErrorAction SilentlyContinue }
  if ($HadExisting -and (Test-Path $BackupEsp)) { Copy-Item $BackupEsp $ExistingEsp -Force }
}
