param(
    [string]$Toolchain = 'C:\Users\x1\Documents\Codex\android-toolchain',
    [switch]$BuildOnly,
    [switch]$UpdateGoldens,
    [ValidateSet('release', 'profile', 'debug')][string]$BuildMode = 'release',
    [switch]$PushAfterBuild
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$deliverables = Split-Path -Parent $repo
$flutterSdk = Join-Path $Toolchain 'flutter-sdk\flutter'
$flutterCommand = Join-Path $flutterSdk 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutterCommand)) { throw 'Flutter SDK not found. Pass -Toolchain with the installed toolchain folder.' }
. (Join-Path $PSScriptRoot 'Build-Environment.ps1')
$originalBuildPath = $env:Path
$log = Join-Path $deliverables 'prototype-build.log'
$resultFile = Join-Path $deliverables 'prototype-build-result.json'
$versionLine = (Select-String -LiteralPath (Join-Path $repo 'pubspec.yaml') -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$checksPassed = $false
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
    @{status='building'; version=$versionLine; startedAt=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath $resultFile -Encoding UTF8
    . (Join-Path $Toolchain 'Activate.ps1')
    $env:PUB_CACHE = Join-Path $Toolchain 'pub-cache'
    $env:CI = 'true'
    $env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
    $env:CUEKEEPER_FLUTTER_STATE_DIR = Join-Path $Toolchain 'flutter-state'
    New-Item -ItemType Directory -Path $env:CUEKEEPER_FLUTTER_STATE_DIR -Force | Out-Null
    $expandedBuildPath = "$flutterSdk\bin;$env:Path"
    $env:Path = Get-CompactBuildPath $expandedBuildPath
    Write-Host "Build PATH: $($expandedBuildPath.Length) characters before deduplication; $($env:Path.Length) after."
    $sdkPath = $env:ANDROID_HOME.Replace('\', '/')
    $flutterPath = $flutterSdk.Replace('\', '/')
    "sdk.dir=$sdkPath`nflutter.sdk=$flutterPath`n" | Set-Content -LiteralPath 'android\local.properties' -Encoding ASCII
    Invoke-Flutter -ToolArgs @('--version')
    if (-not $BuildOnly) {
        Invoke-Flutter -ToolArgs @('pub', 'get')
        Invoke-Flutter -ToolArgs @('analyze')
        if ($UpdateGoldens) { Invoke-Flutter -ToolArgs @('test', '--update-goldens') }
        else { Invoke-Flutter -ToolArgs @('test') }
        $checksPassed = $true
    } else { Write-Host 'Build-only mode: existing analysis/test evidence must be checked separately.' }
    Invoke-Flutter -ToolArgs @('build', 'apk', "--$BuildMode")
    $apk = Join-Path $repo "build\app\outputs\flutter-apk\app-$BuildMode.apk"
    if (-not (Test-Path -LiteralPath $apk)) { throw 'Build did not produce the expected APK.' }
    $signatureTool = Join-Path $env:ANDROID_HOME 'build-tools\36.0.0\apksigner.bat'
    & $signatureTool verify --verbose $apk
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
    $versionName = $versionLine.Split('+')[0]
    $target = Join-Path $deliverables "Church-Service-Timer-$versionName.apk"
    Copy-Item -LiteralPath $apk -Destination $target -Force
    Copy-Item -LiteralPath $apk -Destination (Join-Path $deliverables 'Church-Service-Timer-prototype.apk') -Force
    $result = [ordered]@{
        status='built'; buildMode=$BuildMode; signing='Local prototype key'; apk=$target; sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        completedAt=(Get-Date).ToString('o'); version=$versionLine; flutter='3.47.7'; tests=$(if ($BuildOnly) { 'Not rerun in this build-only invocation' } elseif ($UpdateGoldens) { 'flutter test --update-goldens passed; review updated images' } else { 'flutter test passed' })
        physicalHardware='W2 protocol verified on a 32x16 red sign; see docs/w2-protocol-evidence.json for scope and app test status'; nativeRuntime='Requires installation test of this build on Android'
    }
    $result | ConvertTo-Json | Set-Content -LiteralPath $resultFile -Encoding UTF8
    Write-Host "APK ready: $target"
    Write-Host 'Return to Codex for APK verification and the final build report.'
} catch {
    @{status='failed'; version=$versionLine; completedAt=(Get-Date).ToString('o'); analysisAndTestsPassedThisRun=$checksPassed; error=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath $resultFile -Encoding UTF8
    throw
} finally {
    $env:Path = $originalBuildPath
    Pop-Location
    Stop-Transcript | Out-Null
}
if ($PushAfterBuild) { & (Join-Path $PSScriptRoot 'Push-With-Wsl.ps1') }
