[CmdletBinding()]
param()
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'windows\MsrfCore.ps1')

$script:failures = 0
function Write-Check([string]$Status, [string]$Text) {
    $color = @{ OK = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; INFO = 'Gray' }[$Status]
    Write-Host ('{0,-5} {1}' -f $Status, $Text) -ForegroundColor $color
    if ($Status -eq 'FAIL') { $script:failures++ }
}

Write-Check INFO "PowerShell $($PSVersionTable.PSVersion), language mode $($ExecutionContext.SessionState.LanguageMode)"
$claude = Find-ClaudeExecutable
if ($claude) { Write-Check OK "Claude Code: $claude" } else { Write-Check FAIL 'Claude Code not found on PATH' }

$policy = Get-NewShellExecutionPolicy
if (Test-PolicyAllowsLocalScripts $policy.Policy) { Write-Check OK "Execution policy for new shells: $($policy.Policy) ($($policy.Scope))" }
else { Write-Check FAIL "Execution policy for new shells: $($policy.Policy) ($($policy.Scope)); the profile will not load" }

$binDir = Join-Path (Get-MsrfHome) 'bin'
$missing = @('MsrfCore.ps1', 'msrf-claude-tab.ps1', 'msrf-record-session.ps1', 'msrf-profile.ps1') | Where-Object { -not (Test-Path (Join-Path $binDir $_)) }
if ($missing) { Write-Check FAIL "Missing in ${binDir}: $($missing -join ', ')" } else { Write-Check OK "Scripts installed in $binDir" }

$settingsPath = Join-Path (Get-ClaudeConfigDir) 'settings.json'
try {
    $settings = Read-JsonFile $settingsPath
    foreach ($event in @('UserPromptSubmit', 'SessionStart')) {
        $present = $settings.PSObject.Properties['hooks'] -and $settings.hooks.PSObject.Properties[$event] -and
            (($settings.hooks.$event | ConvertTo-Json -Depth 16) -like "*$($script:HookMarker)*")
        if ($present) { Write-Check OK "$event hook present in $settingsPath" } else { Write-Check FAIL "$event hook missing in $settingsPath" }
    }
    if ($settings.PSObject.Properties['disableAllHooks'] -and $settings.disableAllHooks) { Write-Check FAIL 'disableAllHooks is true in the Claude settings' }
} catch {
    Write-Check FAIL "$settingsPath is not valid JSON"
}

foreach ($profilePath in Get-ProfilePaths) {
    $lines = if (Test-Path $profilePath) { @(Get-Content $profilePath) } else { @() }
    if ($lines | Where-Object { $_.Contains($script:ProfileMarker) }) { Write-Check OK "Profile loads the fix: $profilePath" }
    else { Write-Check FAIL "Profile does not load the fix: $profilePath" }
    foreach ($other in $lines | Where-Object { -not $_.Contains($script:ProfileMarker) -and $_ -match '(function\s+claude\b|Set-Alias.+\bclaude\b|claude-aba)' }) {
        Write-Check WARN "Another claude wrapper in ${profilePath}: $other"
    }
}

$config = Get-MsrfConfig
Write-Check INFO "Session defaults: effort $($config.effort), ultracode $(if ($config.ultracode) { 'on' } else { 'off' })"

$preferred = Get-MaestriPreferredShell
if (Test-SupportedShellPath $preferred) { Write-Check OK "Maestri default shell: $(if ($preferred) { $preferred } else { 'automatic (PowerShell)' })" }
else { Write-Check FAIL "Maestri default shell is $preferred; set it to PowerShell" }

$tabs = @(Get-MaestriClaudeTabs)
$map = Get-TabMap
$unmapped = @($tabs | Where-Object { -not $map.ContainsKey($_.Id) -or -not (Get-Transcript $map[$_.Id]) })
foreach ($tab in $tabs | Where-Object { -not (Test-SupportedShellPath $_.ShellPath) }) { Write-Check FAIL "Tab '$($tab.Name)' uses $($tab.ShellPath); switch it to PowerShell" }
if ($tabs.Count -eq 0) { Write-Check WARN "No Claude Code tabs found in $(Get-MaestriDataDir)" }
elseif ($unmapped.Count -eq 0) { Write-Check OK "All $($tabs.Count) Claude Code tabs have a session to reopen" }
else {
    Write-Check WARN "$($unmapped.Count) of $($tabs.Count) Claude Code tabs have no session yet (send one message in each, or run the installer again to read the open sessions):"
    foreach ($tab in $unmapped) { Write-Host "        - $($tab.Name)" }
}

try {
    $live = @(Get-LiveClaudeSessions)
    $matching = 0
    foreach ($session in $live) {
        $terminal = Get-ProcessEnvironmentVariable $session.ProcessId 'MAESTRI_TERMINAL_ID'
        if ($terminal -and $map[$terminal.ToLower()] -eq $session.SessionId) { $matching++ }
    }
    Write-Check INFO "Open Claude sessions: $($live.Count); open in the tab the fix expects: $matching"
} catch {
    Write-Check INFO "Could not read the open sessions: $($_.Exception.Message)"
}

$logPath = Join-Path (Get-MsrfHome) 'msrf.log'
if (Test-Path $logPath) {
    $recent = Get-Content $logPath -Tail 200
    $errors = @($recent | Where-Object { $_ -match ' error ' })
    $recorded = @($recent | Where-Object { $_ -match ' recorded ' })
    Write-Check INFO "Hook log: $($recorded.Count) recordings and $($errors.Count) errors in the last 200 lines ($logPath)"
    if ($errors) { Write-Check WARN "Last hook error: $($errors[-1])" }
} else {
    Write-Check INFO 'Hook log not created yet (it appears after the first prompt in a Maestri tab)'
}

if ($script:failures -gt 0) { exit 1 }
exit 0
