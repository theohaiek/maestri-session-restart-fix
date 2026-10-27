[CmdletBinding()]
param(
    [ValidateSet('ask', 'default', 'low', 'medium', 'high', 'xhigh', 'max')]
    [string]$Effort = 'ask',
    [ValidateSet('ask', 'on', 'off')]
    [string]$Ultracode = 'ask',
    [switch]$SetExecutionPolicy,
    [switch]$NoSeed
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'windows\MsrfCore.ps1')

function Read-Choice([string]$Question, [string[]]$Options, [string]$Fallback) {
    $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    if (-not $interactive) { return $Fallback }
    while ($true) {
        $answer = (Read-Host "$Question [$($Options -join '/')] (Enter = $Fallback)").Trim().ToLower()
        if (-not $answer) { return $Fallback }
        if ($Options -contains $answer) { return $answer }
    }
}

function Stop-Install([string]$Reason, [string]$Fix) {
    Write-Host "FAIL  $Reason" -ForegroundColor Red
    if ($Fix) { Write-Host "      fix: $Fix" }
    exit 1
}

function Write-Step([string]$Text) { Write-Host "OK    $Text" -ForegroundColor Green }
function Write-Note([string]$Text) { Write-Host "WARN  $Text" -ForegroundColor Yellow }

if ($env:OS -ne 'Windows_NT') { Stop-Install 'This installer is for Windows.' 'Run ./install.sh on macOS or Linux.' }
if ($PSVersionTable.PSVersion.Major -lt 5) { Stop-Install "PowerShell $($PSVersionTable.PSVersion) is too old." 'Install Windows Management Framework 5.1 or PowerShell 7.' }
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Stop-Install "PowerShell runs in $($ExecutionContext.SessionState.LanguageMode) mode (AppLocker or WDAC policy)." 'Ask your administrator to allow scripts in your user profile; this fix cannot work without it.'
}

$claude = Find-ClaudeExecutable
if (-not $claude) { Stop-Install 'Claude Code was not found on PATH.' 'Install Claude Code (https://code.claude.com) and open a new terminal.' }
Write-Step "Claude Code found: $claude"

$policy = Get-NewShellExecutionPolicy
if (-not (Test-PolicyAllowsLocalScripts $policy.Policy)) {
    if (@('MachinePolicy', 'UserPolicy') -contains $policy.Scope) {
        Stop-Install "Group Policy sets the execution policy to $($policy.Policy)." 'Ask your administrator for RemoteSigned; the PowerShell profile cannot load otherwise.'
    }
    if (-not $SetExecutionPolicy) {
        Stop-Install "New PowerShell windows use the execution policy $($policy.Policy), so the profile would not load." 'Run the installer again with -SetExecutionPolicy (sets RemoteSigned for your user only).'
    }
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    Write-Step 'Execution policy for your user set to RemoteSigned'
} else {
    Write-Step "Execution policy allows local scripts ($($policy.Policy), $($policy.Scope))"
}

$binDir = Join-Path (Get-MsrfHome) 'bin'
New-Item -ItemType Directory -Force -Path $binDir, (Get-MsrfTabsDir) | Out-Null
foreach ($file in @('MsrfCore.ps1', 'MsrfNative.cs', 'msrf-claude-tab.ps1', 'msrf-record-session.ps1', 'msrf-profile.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "windows\$file") -Destination $binDir -Force
}
Get-ChildItem -Path $binDir | Unblock-File
Write-Step "Scripts installed in $binDir"

$library = Join-Path $binDir 'MsrfNative.dll'
$compiled = Join-Path $binDir "MsrfNative-$([guid]::NewGuid().ToString('N')).dll"
try {
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $binDir 'MsrfNative.cs'))) -OutputAssembly $compiled -OutputType Library -ErrorAction Stop
    try { Move-Item -LiteralPath $compiled -Destination $library -Force -ErrorAction Stop } catch { Remove-Item -LiteralPath $compiled -Force -ErrorAction SilentlyContinue }
    Write-Step 'Native helper compiled (process tree and environment reader)'
} catch {
    Write-Note "Native helper not compiled ($($_.Exception.Message)); the hook falls back to slower WMI queries."
}

$settingsPath = Join-Path (Get-ClaudeConfigDir) 'settings.json'
if (Test-Path $settingsPath) {
    try { Read-JsonFile $settingsPath | Out-Null } catch { Stop-Install "$settingsPath is not valid JSON." 'Fix the file (or move it away) and run the installer again.' }
    $backup = "$settingsPath.msrf-backup-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
    Copy-Item -LiteralPath $settingsPath -Destination $backup
    Write-Step "Backup of the Claude settings: $backup"
}
Update-ClaudeSettingsHooks $settingsPath
Write-Step "Hooks UserPromptSubmit and SessionStart added to $settingsPath"

foreach ($profilePath in Get-ProfilePaths) {
    Update-ProfileLine $profilePath
    Write-Step "PowerShell profile updated: $profilePath"
}

$current = Get-MsrfConfig
if ($Effort -eq 'ask') { $Effort = Read-Choice 'Effort level for the sessions the fix opens' @('default', 'low', 'medium', 'high', 'xhigh', 'max') $current.effort }
if ($Ultracode -eq 'ask') { $Ultracode = Read-Choice 'Turn ultracode on in those sessions' @('on', 'off') $(if ($current.ultracode) { 'on' } else { 'off' }) }
Save-MsrfConfig -Effort $Effort -Ultracode ($Ultracode -eq 'on')
Write-Step "Session defaults: effort $Effort, ultracode $Ultracode (flags typed in a tab always win)"

if (-not $NoSeed) {
    try {
        $seed = Invoke-MsrfSeed
        Write-Step "Tabs mapped from the sessions open right now: $($seed.Recorded) (skipped $($seed.SkippedEmpty) empty sessions)"
    } catch {
        Write-Note "Could not read the open sessions ($($_.Exception.Message)). Each tab is mapped on its next prompt."
    }
}

$preferred = Get-MaestriPreferredShell
if (-not (Test-SupportedShellPath $preferred)) { Write-Note "Maestri's default shell is $preferred. Set it to PowerShell in Maestri's settings; other shells do not load the fix." }
foreach ($tab in Get-MaestriClaudeTabs) {
    if (-not (Test-SupportedShellPath $tab.ShellPath)) { Write-Note "Tab '$($tab.Name)' uses $($tab.ShellPath); switch it to PowerShell." }
}

Write-Host ''
Write-Host 'Installed. Next:'
Write-Host '  1. Send any message in each Maestri tab whose session is not mapped yet (doctor.ps1 lists them).'
Write-Host '  2. Close and reopen Maestri. Tabs reopen one after another on their own sessions.'
Write-Host '  3. Check with: powershell -NoProfile -File .\doctor.ps1'
