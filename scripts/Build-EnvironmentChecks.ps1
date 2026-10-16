$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Build-Environment.ps1')
function Assert-PathEqual([string]$Actual, [string]$Expected) {
    if ($Actual -cne $Expected) { throw "Unexpected compact build PATH: $Actual" }
}
$initial = 'C:\Flutter\bin;C:\Java\bin;C:\Custom Tools;C:\Windows\System32'
$repeated = ('C:\Flutter\bin;C:\Java\bin;' * 300) + $initial
Assert-PathEqual (Get-CompactBuildPath $repeated) $initial
Assert-PathEqual (Get-CompactBuildPath 'C:\Tools\;c:/tools;"C:\Tools";C:\Other') 'C:\Tools\;C:\Other'
Assert-PathEqual (Get-CompactBuildPath ' ; C:\First ;; C:\Second; ') 'C:\First;C:\Second'
Assert-PathEqual (Get-CompactBuildPath (Get-CompactBuildPath $repeated)) $initial
Assert-PathEqual (Get-CompactBuildPath 'C:\;C:;C:\') 'C:\;C:'
Write-Output '5 build PATH checks passed: repeated activation, equivalent paths, blanks, idempotence and drive roots.'
