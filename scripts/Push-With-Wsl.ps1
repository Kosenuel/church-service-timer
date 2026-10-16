$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { throw 'Run this from the supplied Git checkout.' }
Start-Transcript -Path (Join-Path (Split-Path -Parent $repo) 'prototype-push.log') -Force | Out-Null
try {
$convertedPath = & wsl.exe -d Ubuntu -u kosenuel --exec wslpath -u ($repo.Replace('\', '/'))
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$convertedPath)) { throw 'Cannot convert the repository path in Ubuntu WSL. Run this script in a normal PowerShell window.' }
$linuxPath = ([string]$convertedPath).Trim()
& wsl.exe -d Ubuntu -u kosenuel --exec git -c "safe.directory=$linuxPath" -C $linuxPath log -1 '--format=%h %an <%ae> %s'
if ($LASTEXITCODE -ne 0) { throw 'The local commit could not be read.' }
& wsl.exe -d Ubuntu -u kosenuel --exec git -c "safe.directory=$linuxPath" -c 'core.sshCommand=ssh -i /home/kosenuel/.ssh/id_rsa -o IdentitiesOnly=yes' -C $linuxPath push -u origin main
if ($LASTEXITCODE -ne 0) { throw 'Push failed. Review the SSH error above; the private key stays in WSL.' }
& wsl.exe -d Ubuntu -u kosenuel --exec git -c "safe.directory=$linuxPath" -c 'core.sshCommand=ssh -i /home/kosenuel/.ssh/id_rsa -o IdentitiesOnly=yes' -C $linuxPath ls-remote --heads origin main
if ($LASTEXITCODE -ne 0) { throw 'Push returned, but remote verification failed.' }
$commit = (& wsl.exe -d Ubuntu -u kosenuel --exec git -c "safe.directory=$linuxPath" -C $linuxPath rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to record the pushed commit.' }
[ordered]@{ repository='https://github.com/Kosenuel/church-service-timer'; commit=$commit; pushedAt=(Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path (Split-Path -Parent $repo) 'prototype-push-result.json') -Encoding UTF8
Write-Host 'Source pushed to the private repository: https://github.com/Kosenuel/church-service-timer'
} finally { Stop-Transcript | Out-Null }
