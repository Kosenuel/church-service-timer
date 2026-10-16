# Preserve executable search order while repeated toolchain activation adds folders.
# This only produces a process PATH; it never changes user or machine settings.
function Get-CompactBuildPath {
    param([string]$PathValue)
    $seen = @{}
    $entries = foreach ($rawEntry in ($PathValue -split ';')) {
        $entry = $rawEntry.Trim()
        if (-not $entry) { continue }
        $key = $entry.Trim('"').Replace('/', '\')
        if ($key.Length -gt 3) { $key = $key.TrimEnd('\') }
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $entry
        }
    }
    return ($entries -join ';')
}
