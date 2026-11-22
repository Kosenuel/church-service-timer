<#
Packages the Windows build for people to download.

Run after `flutter build windows --release`, from the repository root:

    pwsh scripts/Package-Windows.ps1

It writes two files to dist/, each with a .sha256 checksum file beside it:

  Church-Service-Timer-<version>-windows-x64.zip   unzip anywhere and run
  Church-Service-Timer-<version>-windows-setup.exe installer (needs Inno Setup)

Neither is code-signed. With -SkipInstaller only the zip is made.
#>
param(
  [string]$Version,
  [switch]$SkipInstaller
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$release = Join-Path $root 'build\windows\x64\runner\Release'
$dist = Join-Path $root 'dist'

if (-not $Version) {
  $line = Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*([^+\s]+)'
  $Version = $line.Matches[0].Groups[1].Value
}
# Inno Setup's AppVersion takes text (0.36.0-beta.1), but the installer file's
# own version numbers must be four numbers: 0.36.0-beta.1 becomes 0.36.0.0.
if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)(-[0-9A-Za-z.]+)?$') {
  throw "'$Version' is not MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-pre.release."
}
$VersionInfo = "$($Matches[1]).$($Matches[2]).$($Matches[3]).0"
if (-not (Test-Path (Join-Path $release 'church_service_timer.exe'))) {
  throw "No Windows build at $release. Run: flutter build windows --release"
}
# The LED display fonts are copied in by windows/CMakeLists.txt; the app
# cannot draw Tinos without them.
foreach ($face in 'Regular', 'Bold', 'Italic', 'BoldItalic') {
  if (-not (Test-Path (Join-Path $release "data\display_fonts\tinos\Tinos-$face.ttf"))) {
    throw "The LED display font Tinos-$face.ttf was not bundled."
  }
}

# The Visual C++ runtime the app needs. Windows usually has it already;
# shipping these three files beside the program means a PC that does not
# still starts the app. Microsoft permits redistributing them this way.
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  $source = Join-Path $env:SystemRoot "System32\$dll"
  if (Test-Path $source) {
    Copy-Item $source $release -Force
  } else {
    Write-Warning "$dll was not found on this machine and is not bundled."
  }
}

New-Item -ItemType Directory -Force $dist | Out-Null
$zip = Join-Path $dist "Church-Service-Timer-$Version-windows-x64.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $release '*') -DestinationPath $zip

if (-not $SkipInstaller) {
  $iscc = $null
  $command = Get-Command iscc.exe -ErrorAction SilentlyContinue
  if ($command) { $iscc = $command.Source }
  if (-not $iscc) {
    $candidate = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
    if (Test-Path $candidate) { $iscc = $candidate }
  }
  if (-not $iscc) {
    throw 'Inno Setup 6 was not found. Install it (https://jrsoftware.org/isinfo.php), or pass -SkipInstaller.'
  }
  & $iscc "/DAppVersion=$Version" "/DVersionInfo=$VersionInfo" "/DSourceDir=$release" "/DOutputDir=$dist" `
    (Join-Path $root 'windows\installer\church-service-timer.iss')
  if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE." }
}

# A checksum beside each file, in the form sha256sum writes, so people
# and the app's Check for updates can tell the download is complete.
Get-ChildItem $dist -Filter "Church-Service-Timer-$Version-windows-*" |
  Where-Object { $_.Extension -ne '.sha256' } | ForEach-Object {
  $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
  $line = "$hash  $($_.Name)"
  [IO.File]::WriteAllText("$($_.FullName).sha256", "$line`n")
  $line
}
