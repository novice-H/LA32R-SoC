[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("lint", "compare", "trace", "wave-gtkwave", "wave-vaporview")]
    [string] $Action,
    [string] $Distro = "Ubuntu-26.04"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$wslInputPath = $repoRoot.Replace("\", "\\")
$linuxRoot = (& wsl.exe -d $Distro -- wslpath -u $wslInputPath).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($linuxRoot)) {
    throw "Could not map workspace path into WSL distribution '$Distro'."
}

$makeTarget = switch ($Action) {
    "lint" { "lint" }
    "compare" { "compare" }
    "trace" { "trace" }
    "wave-gtkwave" { "wave" }
    "wave-vaporview" { "trace" }
}
$linuxRootQuoted = $linuxRoot.Replace("'", "'\''")
$bashScript = @"
set -euo pipefail
cd '$linuxRootQuoted'
if [[ -z "`${LA32R_BUILD:-}" ]]; then export LA32R_BUILD="`$HOME/build/la32r"; fi
source requirements/env.sh
make -C sim $makeTarget
"@
if ($Action -in "trace", "wave-vaporview") {
    $bashScript += @"

build="`${LA32R_BUILD:-`$HOME/build/la32r}"
printf '__VCD_WSL_PATH__=%s\n' "`$build/vga/vga.vcd"
printf '__VCD_WINDOWS_PATH__=%s\n' "`$(wslpath -w "`$build/vga/vga.vcd")"
"@
}
$encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bashScript))
$wslCommand = "printf '%s' '$encoded' | base64 -d | bash"
$output = & wsl.exe -d $Distro -- bash -lc $wslCommand 2>&1
$exitCode = $LASTEXITCODE
$windowsFriendlyRoot = $repoRoot.Replace("\", "/")
$output | ForEach-Object {
    if ($_ -is [string]) {
        Write-Output $_.Replace($linuxRoot, $windowsFriendlyRoot)
    } else {
        Write-Output $_
    }
}
if ($exitCode -ne 0) { exit $exitCode }

if ($Action -eq "wave-vaporview") {
    $pathLine = $output | Where-Object { $_ -is [string] -and $_.StartsWith("__VCD_WINDOWS_PATH__=") } | Select-Object -Last 1
    if (-not $pathLine) { throw "Trace completed, but WSL did not report the VCD Windows path." }
    $vcdPath = $pathLine.Substring("__VCD_WINDOWS_PATH__=".Length)
    Write-Output "Opening VCD in VS Code: $vcdPath"
    & code --reuse-window $vcdPath
    if ($LASTEXITCODE -ne 0) { throw "VS Code CLI failed to open the VCD (exit $LASTEXITCODE)." }
}
