$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("msrf-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $sandbox | Out-Null
$env:MSRF_HOME = Join-Path $sandbox 'home'
$env:CLAUDE_CONFIG_DIR = Join-Path $sandbox 'claude'
. (Join-Path $root 'windows\MsrfCore.ps1')

$script:passed = 0
$script:failed = 0
function Assert-Equal($Expected, $Actual, [string]$Name) {
    $expectedText = ($Expected | ForEach-Object { [string]$_ }) -join ' '
    $actualText = ($Actual | ForEach-Object { [string]$_ }) -join ' '
    if ($expectedText -ceq $actualText) { $script:passed++; Write-Host "ok   $Name" }
    else { $script:failed++; Write-Host "FAIL $Name`n     expected: $expectedText`n     actual:   $actualText" -ForegroundColor Red }
}

$projects = Join-Path $env:CLAUDE_CONFIG_DIR 'projects\project-a'
New-Item -ItemType Directory -Force -Path $projects | Out-Null
function New-Transcript([string]$Id, [bool]$WithPrompt, [datetime]$Written) {
    $path = Join-Path $projects "$Id.jsonl"
    $line = if ($WithPrompt) { '{"type":"user","message":{"role":"user","content":"hi"}}' } else { '{"type":"summary"}' }
    [IO.File]::WriteAllText($path, $line + "`n")
    (Get-Item $path).LastWriteTime = $Written
}
$tabSession = '11111111-1111-1111-1111-111111111111'
$otherTabSession = '22222222-2222-2222-2222-222222222222'
$olderSession = '33333333-3333-3333-3333-333333333333'
$newerSession = '44444444-4444-4444-4444-444444444444'
$emptySession = '55555555-5555-5555-5555-555555555555'
$liveSession = '66666666-6666-6666-6666-666666666666'
New-Transcript $tabSession $true (Get-Date).AddHours(-2)
New-Transcript $otherTabSession $true (Get-Date).AddMinutes(-1)
New-Transcript $olderSession $true (Get-Date).AddDays(-3)
New-Transcript $newerSession $true (Get-Date).AddMinutes(-5)
New-Transcript $emptySession $false (Get-Date)
New-Transcript $liveSession $true (Get-Date)

$tab = 'aaaaaaaa-0000-0000-0000-000000000001'
$otherTab = 'aaaaaaaa-0000-0000-0000-000000000002'
$liveTab = 'aaaaaaaa-0000-0000-0000-000000000003'
$map = @{ $tab = $tabSession; $otherTab = $otherTabSession; $liveTab = $liveSession }

function Invoke-Decision([string[]]$Arguments, [bool]$Auto, [string]$Terminal = $tab) {
    $decision = Select-MsrfLaunch -Arguments $Arguments -Terminal $Terminal -TabMap $map -IsAutoStart $Auto `
        -FindTranscript { param($id) Get-Transcript $id } `
        -HasPrompt { param($file) Test-TranscriptHasPrompt $file } `
        -IsLive { param($id) $id -eq $liveSession }
    return $decision.Arguments
}

Assert-Equal @('--resume', $tabSession) (Invoke-Decision @() $true) 'auto start without arguments resumes the tab session'
Assert-Equal @('--resume', $tabSession) (Invoke-Decision @('--resume', '910') $true) 'cut id is replaced by the tab session'
Assert-Equal @('--resume', $tabSession) (Invoke-Decision @('--resume', $emptySession) $true) 'empty session is replaced by the tab session'
Assert-Equal @('--resume', $tabSession, '--effort', 'max') (Invoke-Decision @('--resume', '--effort', 'max') $true) 'resume without value keeps the other arguments'
Assert-Equal @('--resume', $tabSession) (Invoke-Decision @('--resume', $otherTabSession) $true) 'id owned by another tab is refused at auto start'
Assert-Equal @('--resume', $tabSession) (Invoke-Decision @('--resume', $olderSession) $true) 'older unmapped session loses to the tab session'
Assert-Equal @('--resume', $newerSession) (Invoke-Decision @('--resume', $newerSession) $true) 'newer unmapped session with prompts wins'
Assert-Equal @('--resume', $tabSession, '--dangerously-skip-permissions') (Invoke-Decision @('--dangerously-skip-permissions') $true) 'flags are kept'
Assert-Equal @() (Invoke-Decision @() $true $liveTab) 'a session already open elsewhere is not reopened'
Assert-Equal @() (Invoke-Decision @('--resume', $emptySession) $true 'aaaaaaaa-0000-0000-0000-00000000ffff') 'unknown tab with empty session starts a new session'
Assert-Equal @('--resume', $olderSession) (Invoke-Decision @('--resume', $olderSession) $false) 'typed by hand the requested session is honored'
Assert-Equal @('--resume', $tabSession) (Invoke-Decision @() $false) 'typed by hand without arguments resumes the tab session'
Assert-Equal @('--resume') (Invoke-Decision @('--resume') $false 'aaaaaaaa-0000-0000-0000-00000000ffff') 'typed by hand picker stays a picker'
Assert-Equal @() (Invoke-Decision @('--resume', $liveSession) $false) 'typed by hand a live session is not opened twice'

Set-TabSession $tab $tabSession
Set-TabSession $otherTab $tabSession
Assert-Equal @($otherTab) @((Get-TabMap).Keys) 'a session moves to the last tab that used it'

$settingsPath = Join-Path $env:CLAUDE_CONFIG_DIR 'settings.json'
[IO.File]::WriteAllText($settingsPath, '{"model":"opus","hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"other-hook"}]}]},"permissions":{"allow":["Bash(ls)"]}}')
Update-ClaudeSettingsHooks $settingsPath
Update-ClaudeSettingsHooks $settingsPath
$settings = Read-JsonFile $settingsPath
Assert-Equal 2 @($settings.hooks.UserPromptSubmit).Count 'install keeps the other hook and adds ours once'
Assert-Equal 'resume|clear|compact' $settings.hooks.SessionStart[0].matcher 'SessionStart matcher'
Assert-Equal 'Bash(ls)' $settings.permissions.allow[0] 'other settings are kept'
Update-ClaudeSettingsHooks $settingsPath -Remove
$settings = Read-JsonFile $settingsPath
Assert-Equal 'other-hook' $settings.hooks.UserPromptSubmit[0].hooks[0].command 'uninstall keeps the other hook'
Assert-Equal $false ([bool]$settings.hooks.PSObject.Properties['SessionStart']) 'uninstall removes our SessionStart entry'

$profilePath = Join-Path $sandbox 'profile.ps1'
[IO.File]::WriteAllText($profilePath, "Set-Location C:\`r`n")
Update-ProfileLine $profilePath
Update-ProfileLine $profilePath
Assert-Equal 2 @(Get-Content $profilePath).Count 'profile line is added once'
Update-ProfileLine $profilePath -Remove
Assert-Equal 'Set-Location C:\' (Get-Content $profilePath) 'profile line is removed and the rest kept'

$hook = Join-Path $root 'windows\msrf-record-session.ps1'
$env:MAESTRI_TERMINAL_ID = 'AAAAAAAA-0000-0000-0000-000000000009'
$payload = '{"session_id":"' + $newerSession + '","hook_event_name":"UserPromptSubmit","prompt":"' + [char]0x00C1 + 'gua"}'
$output = $payload | powershell.exe -NoLogo -NoProfile -NonInteractive -File $hook
Assert-Equal '' ([string]$output) 'the hook prints nothing'
$logText = [IO.File]::ReadAllText((Join-Path $env:MSRF_HOME 'msrf.log'))
Assert-Equal $true ($logText -match '(recorded|outside-tab) UserPromptSubmit: aaaaaaaa-0000-0000-0000-000000000009') 'the hook reads the payload and logs the decision'
$env:MAESTRI_TERMINAL_ID = $null

function Set-FakeProcessTable([string[]]$Rows) {
    $script:ProcessTable = @{}
    foreach ($row in $Rows) {
        $parts = $row.Split('|')
        $script:ProcessTable[[int]$parts[0]] = [pscustomobject]@{ ProcessId = [int]$parts[0]; ParentProcessId = [int]$parts[1]; Name = $parts[2] }
    }
}
Set-FakeProcessTable @('1|0|explorer.exe', '10|1|Maestri.exe', '20|10|powershell.exe', '30|20|claude.exe', '40|30|bash.exe', '41|40|bash.exe', '42|41|powershell.exe')
Assert-Equal 30 (Find-HookOwnerProcessId 42) 'hook owner skips the hook runner shells'
Assert-Equal $true (Test-LaunchedFromTab 30) 'claude typed in a Maestri tab is accepted'
Assert-Equal $true (Test-ShellOwnedByMaestri 20) 'the tab shell belongs to Maestri'
Set-FakeProcessTable @('10|1|Maestri.exe', '20|10|powershell.exe', '30|20|claude.exe', '50|30|powershell.exe', '51|50|cmd.exe', '60|51|claude.exe', '70|60|bash.exe', '71|70|bash.exe', '72|71|powershell.exe')
Assert-Equal 60 (Find-HookOwnerProcessId 72) 'nested claude owns its own hook'
Assert-Equal $false (Test-LaunchedFromTab 60) 'claude started by another claude is refused'
Set-FakeProcessTable @('10|1|Maestri.exe', '20|10|pwsh.exe', '25|20|cmd.exe', '30|25|node.exe', '40|30|powershell.exe')
Assert-Equal $true (Test-LaunchedFromTab 30) 'npm-installed claude behind a cmd shim is accepted'
Set-FakeProcessTable @('20|999|powershell.exe', '30|20|claude.exe')
Assert-Equal $false (Test-LaunchedFromTab 30) 'a broken parent chain is refused'
Set-FakeProcessTable @('10|1|Maestri.exe', '30|10|claude.exe')
Assert-Equal $false (Test-LaunchedFromTab 30) 'claude without a shell between it and Maestri is refused'
$script:ProcessTable = $null

$env:MSRF_HOME = Join-Path $sandbox 'config-home'
New-Item -ItemType Directory -Force -Path $env:MSRF_HOME | Out-Null
Save-MsrfConfig -Effort 'max' -Ultracode $true
Assert-Equal @('--resume', $tabSession, '--effort', 'max', '--settings', (Join-Path $env:MSRF_HOME 'session-settings.json')) (Add-SessionDefaults @('--resume', $tabSession)) 'configured effort and ultracode are added'
Assert-Equal @('--effort', 'low', '--settings', 'mine.json') (Add-SessionDefaults @('--effort', 'low', '--settings', 'mine.json')) 'flags the user typed win'
Assert-Equal '{"ultracode":true}' (([IO.File]::ReadAllText((Join-Path $env:MSRF_HOME 'session-settings.json'))) -replace '\s', '') 'ultracode settings file'
Save-MsrfConfig -Effort 'default' -Ultracode $false
Assert-Equal @('--resume', $tabSession) (Add-SessionDefaults @('--resume', $tabSession)) 'nothing is added when no default is chosen'

foreach ($file in Get-ChildItem (Join-Path $root 'windows'), $root -Filter '*.ps1') {
    $errors = $null
    [void][Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText($file.FullName), [ref]$errors)
    Assert-Equal 0 @($errors).Count "parses: $($file.Name)"
    Assert-Equal $false ([IO.File]::ReadAllText($file.FullName) -match '[^\x00-\x7F]') "ASCII only (Windows PowerShell 5.1 reads BOM-less files as ANSI): $($file.Name)"
}

Remove-Item -LiteralPath $sandbox -Recurse -Force
Write-Host "`n$($script:passed) passed, $($script:failed) failed"
if ($script:failed -gt 0) { exit 1 }
