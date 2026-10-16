param(
    [string]$Toolchain = 'C:\Users\x1\Documents\Codex\android-toolchain',
    [switch]$BuildOnly,
    [switch]$PushAfterBuild
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$deliverables = Split-Path -Parent $repo
$flutterSdk = Join-Path $Toolchain 'flutter-sdk\flutter'
$flutterCommand = Join-Path $flutterSdk 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutterCommand)) { throw 'Flutter SDK not found. Pass -Toolchain with the installed toolchain folder.' }
. (Join-Path $Toolchain 'Activate.ps1')
$env:PUB_CACHE = Join-Path $Toolchain 'pub-cache'
$env:CI = 'true'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:CUEKEEPER_FLUTTER_STATE_DIR = Join-Path $Toolchain 'flutter-state'
New-Item -ItemType Directory -Path $env:CUEKEEPER_FLUTTER_STATE_DIR -Force | Out-Null
$env:Path = "$flutterSdk\bin;$env:Path"
$log = Join-Path $deliverables 'prototype-build.log'
function Invoke-Flutter {
    param([string[]]$ToolArgs)
    Write-Host "Running: flutter $($ToolArgs -join ' ')"
    # Native console inheritance is not reliably captured by PS 5.1 transcripts.
    # Route every native output line through PowerShell's host explicitly.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $flutterCommand @ToolArgs 2>&1 | ForEach-Object { Write-Host "$_" }
        $flutterExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($flutterExit -ne 0) { throw "Flutter failed: $($ToolArgs -join ' ') (exit $flutterExit). See $log" }
}
Start-Transcript -Path $log -Force | Out-Null
Push-Location -LiteralPath $repo
try {
    $sdkPath = $env:ANDROID_HOME.Replace('\', '/')
    $flutterPath = $flutterSdk.Replace('\', '/')
    "sdk.dir=$sdkPath`nflutter.sdk=$flutterPath`n" | Set-Content -LiteralPath 'android\local.properties' -Encoding ASCII
    Invoke-Flutter -ToolArgs @('--version')
    if (-not $BuildOnly) {
        Invoke-Flutter -ToolArgs @('pub', 'get')
        Invoke-Flutter -ToolArgs @('analyze')
        Invoke-Flutter -ToolArgs @('test', '--update-goldens')
    } else { Write-Host 'Build-only mode: existing analysis/test evidence must be checked separately.' }
    Invoke-Flutter -ToolArgs @('build', 'apk', '--debug')
    $apk = Join-Path $repo 'build\app\outputs\flutter-apk\app-debug.apk'
    if (-not (Test-Path -LiteralPath $apk)) { throw 'Build did not produce the expected APK.' }
    $target = Join-Path $deliverables 'Cuekeeper-prototype.apk'
    Copy-Item -LiteralPath $apk -Destination $target -Force
    $signatureTool = Join-Path $env:ANDROID_HOME 'build-tools\36.0.0\apksigner.bat'
    & $signatureTool verify --verbose $target
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
    $result = [ordered]@{
        status='built'; apk=$target; sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        completedAt=(Get-Date).ToString('o'); flutter='3.47.7'; tests=$(if ($BuildOnly) { 'Not rerun in this build-only invocation' } else { 'flutter test --update-goldens passed' })
        physicalHardware='Not tested; simulator only'; nativeRuntime='Requires installation test on Android'
    }
    $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $deliverables 'prototype-build-result.json') -Encoding UTF8
    Write-Host "APK ready: $target"
    Write-Host 'Return to Codex for APK verification and the final build report.'
} finally {
    Pop-Location
    Stop-Transcript | Out-Null
}
if ($PushAfterBuild) { & (Join-Path $PSScriptRoot 'Push-With-Wsl.ps1') }
