[CmdletBinding()]
param([switch]$RemoveData)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows\MsrfCore.ps1')

$settingsPath = Join-Path (Get-ClaudeConfigDir) 'settings.json'
if (Test-Path $settingsPath) {
    Copy-Item -LiteralPath $settingsPath -Destination "$settingsPath.msrf-backup-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
    Update-ClaudeSettingsHooks $settingsPath -Remove
    Write-Host "OK    Hooks removed from $settingsPath"
}
foreach ($profilePath in Get-ProfilePaths) {
    if (Test-Path $profilePath) {
        Update-ProfileLine $profilePath -Remove
        Write-Host "OK    Profile line removed from $profilePath"
    }
}
$binDir = Join-Path (Get-MsrfHome) 'bin'
if (Test-Path $binDir) { Remove-Item -LiteralPath $binDir -Recurse -Force; Write-Host "OK    Removed $binDir" }
if ($RemoveData -and (Test-Path (Get-MsrfHome))) {
    Remove-Item -LiteralPath (Get-MsrfHome) -Recurse -Force
    Write-Host "OK    Removed $(Get-MsrfHome)"
}
Write-Host 'Uninstalled. Open PowerShell windows keep the claude function until they are closed.'
