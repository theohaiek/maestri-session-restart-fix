Set-StrictMode -Version 2

$script:MsrfName = 'maestri-session-restart-fix'
$script:SessionIdPattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
$script:ShellNames = @('powershell', 'pwsh', 'cmd', 'bash', 'sh', 'zsh', 'fish', 'nu', 'conhost', 'openconsole')
$script:PassThroughFlags = @('-p', '--print', '-c', '--continue', '-h', '--help', '-v', '--version')
$script:AutoStartSeconds = 120
$script:HookMarker = 'msrf-record-session.ps1'
$script:ProfileMarker = 'msrf-profile.ps1'

function Get-MsrfHome {
    if ($env:MSRF_HOME) { return $env:MSRF_HOME }
    if ((Split-Path $PSScriptRoot -Leaf) -eq 'bin') { return (Split-Path $PSScriptRoot -Parent) }
    return Join-Path $env:LOCALAPPDATA $script:MsrfName
}

function Get-MsrfTabsDir { return Join-Path (Get-MsrfHome) 'tabs' }

function Get-ClaudeConfigDir {
    if ($env:CLAUDE_CONFIG_DIR) { return $env:CLAUDE_CONFIG_DIR }
    return Join-Path $HOME '.claude'
}

function Get-MaestriDataDir {
    if ($env:MAESTRI_DATA_DIR) { return $env:MAESTRI_DATA_DIR }
    return Join-Path $HOME '.maestri'
}

function Write-MsrfLog([string]$Message) {
    try {
        New-Item -ItemType Directory -Force -Path (Get-MsrfHome) -ErrorAction Stop | Out-Null
        $logPath = Join-Path (Get-MsrfHome) 'msrf.log'
        if ((Test-Path $logPath) -and (Get-Item $logPath).Length -gt 512KB) {
            $lines = [IO.File]::ReadAllLines($logPath)
            [IO.File]::WriteAllLines($logPath, $lines[[int]($lines.Count / 2)..($lines.Count - 1)])
        }
        $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        [IO.File]::AppendAllText($logPath, "$stamp $Message`n")
    } catch { }
}

function Test-SessionId([string]$Value) {
    return [bool]($Value -and $Value -match $script:SessionIdPattern)
}

function Get-TabMap {
    $map = @{}
    $folder = Get-MsrfTabsDir
    if (-not (Test-Path $folder)) { return $map }
    foreach ($file in Get-ChildItem -Path $folder -Filter '*.txt') {
        $value = ([IO.File]::ReadAllText($file.FullName)).Trim().ToLower()
        if (Test-SessionId $value) { $map[$file.BaseName.ToLower()] = $value }
    }
    return $map
}

function Set-TabSession([string]$Terminal, [string]$SessionId) {
    $Terminal = $Terminal.ToLower()
    $SessionId = $SessionId.ToLower()
    $folder = Get-MsrfTabsDir
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    foreach ($file in Get-ChildItem -Path $folder -Filter '*.txt') {
        if ($file.BaseName.ToLower() -eq $Terminal) { continue }
        if (([IO.File]::ReadAllText($file.FullName)).Trim().ToLower() -eq $SessionId) {
            Remove-Item -LiteralPath $file.FullName -Force
            Write-MsrfLog "moved $SessionId from $($file.BaseName)"
        }
    }
    $target = Join-Path $folder "$Terminal.txt"
    $temporary = "$target.tmp"
    [IO.File]::WriteAllText($temporary, $SessionId)
    Move-Item -LiteralPath $temporary -Destination $target -Force
}

function Get-Transcript([string]$SessionId) {
    if (-not (Test-SessionId $SessionId)) { return $null }
    $pattern = Join-Path (Get-ClaudeConfigDir) "projects\*\$SessionId.jsonl"
    return Get-Item -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Test-TranscriptHasPrompt($Transcript) {
    if (-not $Transcript) { return $false }
    $count = 0
    foreach ($line in [IO.File]::ReadLines($Transcript.FullName)) {
        if ($line.Contains('"type":"user"')) { return $true }
        $count++
        if ($count -ge 300) { break }
    }
    return $false
}

function Get-ProcessRecord([int]$ProcessId) {
    if ($null -eq $script:ProcessTable -and (Import-MsrfNative)) {
        $script:ProcessTable = @{}
        foreach ($row in [MsrfNative]::ListProcesses()) {
            $parts = $row.Split('|')
            $script:ProcessTable[[int]$parts[0]] = [pscustomobject]@{ ProcessId = [int]$parts[0]; ParentProcessId = [int]$parts[1]; Name = $parts[2] }
        }
    }
    if ($null -ne $script:ProcessTable) { return $script:ProcessTable[$ProcessId] }
    return Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -Property ProcessId, ParentProcessId, Name -ErrorAction SilentlyContinue
}

function Get-NormalizedProcessName([string]$Name) {
    return ([IO.Path]::GetFileNameWithoutExtension($Name)).TrimStart('-').ToLower()
}

function Test-ShellProcessName([string]$Name) { return $script:ShellNames -contains (Get-NormalizedProcessName $Name) }

function Test-MaestriProcessName([string]$Name) { return (Get-NormalizedProcessName $Name).StartsWith('maestri') }

function Test-LaunchedFromTab([int]$ClaudeProcessId) {
    $claude = Get-ProcessRecord $ClaudeProcessId
    if (-not $claude) { return $false }
    $parentId = $claude.ParentProcessId
    for ($hop = 0; $hop -lt 4; $hop++) {
        $parent = Get-ProcessRecord $parentId
        if (-not $parent) { return $false }
        if (Test-MaestriProcessName $parent.Name) { return ($hop -gt 0) }
        if (-not (Test-ShellProcessName $parent.Name)) { return $false }
        $parentId = $parent.ParentProcessId
    }
    return $false
}

function Find-HookOwnerProcessId([int]$HookProcessId) {
    $current = Get-ProcessRecord $HookProcessId
    if (-not $current) { return $null }
    $candidateId = $current.ParentProcessId
    for ($hop = 0; $hop -lt 3; $hop++) {
        $candidate = Get-ProcessRecord $candidateId
        if (-not $candidate) { return $null }
        if (-not (Test-ShellProcessName $candidate.Name)) { return $candidate.ProcessId }
        $candidateId = $candidate.ParentProcessId
    }
    return $null
}

function Test-ShellOwnedByMaestri([int]$ShellProcessId) {
    $shell = Get-ProcessRecord $ShellProcessId
    if (-not $shell) { return $false }
    $parentId = $shell.ParentProcessId
    for ($hop = 0; $hop -lt 2; $hop++) {
        $parent = Get-ProcessRecord $parentId
        if (-not $parent) { return $false }
        if (Test-MaestriProcessName $parent.Name) { return $true }
        if (-not (Test-ShellProcessName $parent.Name)) { return $false }
        $parentId = $parent.ParentProcessId
    }
    return $false
}

function Get-LiveClaudeSessions {
    $sessions = @()
    $folder = Join-Path (Get-ClaudeConfigDir) 'sessions'
    foreach ($file in Get-ChildItem -Path $folder -Filter '*.json' -ErrorAction SilentlyContinue) {
        try {
            $data = [IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
            $process = Get-Process -Id ([int]$file.BaseName) -ErrorAction SilentlyContinue
            if (-not $process -or @('claude', 'node', 'bun') -notcontains $process.ProcessName.ToLower()) { continue }
            if ($data.PSObject.Properties['procStart'] -and $data.procStart) {
                $difference = [math]::Abs($process.StartTime.ToFileTimeUtc() - [int64]$data.procStart)
                if ($difference -gt 20000000) { continue }
            }
            $sessions += [pscustomobject]@{ ProcessId = $process.Id; SessionId = ([string]$data.sessionId).ToLower() }
        } catch { }
    }
    return $sessions
}

function Test-SessionLive([string]$SessionId) {
    return [bool](Get-LiveClaudeSessions | Where-Object { $_.SessionId -eq $SessionId })
}

function Find-ClaudeExecutable {
    $found = Get-Command claude -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notlike "*$($script:MsrfName)*" } | Select-Object -First 1
    if ($found) { return $found.Source }
    $native = Join-Path $HOME '.local\bin\claude.exe'
    if (Test-Path $native) { return $native }
    return $null
}

function Get-ResumeRequest([string[]]$Arguments) {
    $index = -1
    for ($position = 0; $position -lt $Arguments.Count; $position++) {
        if ($Arguments[$position] -eq '--resume' -or $Arguments[$position] -eq '-r') { $index = $position; break }
    }
    $value = $null
    if ($index -ge 0 -and $index + 1 -lt $Arguments.Count -and -not $Arguments[$index + 1].StartsWith('-')) {
        $value = $Arguments[$index + 1].ToLower()
    }
    $remaining = New-Object System.Collections.Generic.List[string]
    for ($position = 0; $position -lt $Arguments.Count; $position++) {
        if ($position -eq $index) { continue }
        if ($value -and $position -eq $index + 1) { continue }
        $remaining.Add($Arguments[$position])
    }
    return [pscustomobject]@{ Index = $index; Value = $value; Remaining = [string[]]$remaining.ToArray() }
}

function Select-MsrfLaunch {
    param(
        [string[]]$Arguments,
        [string]$Terminal,
        [hashtable]$TabMap,
        [bool]$IsAutoStart,
        [scriptblock]$FindTranscript,
        [scriptblock]$HasPrompt,
        [scriptblock]$IsLive
    )
    $request = Get-ResumeRequest $Arguments
    $tabSession = $TabMap[$Terminal]
    $tabTranscript = if ($tabSession) { & $FindTranscript $tabSession } else { $null }
    if (-not $tabTranscript) { $tabSession = $null }
    $requestedTranscript = if ($request.Value) { & $FindTranscript $request.Value } else { $null }
    $ownedByOtherTab = [bool]($request.Value -and ($TabMap.Keys | Where-Object { $_ -ne $Terminal -and $TabMap[$_] -eq $request.Value }))

    $chosen = $null
    if ($requestedTranscript) {
        if ($request.Value -eq $tabSession) { $chosen = $request.Value }
        elseif (-not $IsAutoStart) { $chosen = $request.Value }
        elseif ($ownedByOtherTab) { $chosen = $tabSession }
        elseif ($tabSession -and (& $HasPrompt $requestedTranscript) -and $requestedTranscript.LastWriteTime -gt $tabTranscript.LastWriteTime) { $chosen = $request.Value }
        elseif ($tabSession) { $chosen = $tabSession }
        elseif (& $HasPrompt $requestedTranscript) { $chosen = $request.Value }
    } else {
        $chosen = $tabSession
    }

    $message = $null
    $alreadyOpen = $false
    if ($chosen -and (& $IsLive $chosen)) {
        $message = "Session $chosen is already open in another process; starting a new session in this tab."
        $chosen = $null
        $alreadyOpen = $true
    }

    if ($chosen) {
        return [pscustomobject]@{ Arguments = [string[]](@('--resume', $chosen) + $request.Remaining); Session = $chosen; Queue = $IsAutoStart; Message = $message }
    }
    if (-not $IsAutoStart -and -not $alreadyOpen) {
        return [pscustomobject]@{ Arguments = $Arguments; Session = $null; Queue = $false; Message = $message }
    }
    return [pscustomobject]@{ Arguments = $request.Remaining; Session = $null; Queue = $false; Message = $message }
}

function Get-MsrfConfig {
    $path = Join-Path (Get-MsrfHome) 'config.json'
    $config = [pscustomobject]@{ effort = 'default'; ultracode = $false }
    try {
        $saved = [IO.File]::ReadAllText($path) | ConvertFrom-Json
        if ($saved.PSObject.Properties['effort']) { $config.effort = [string]$saved.effort }
        if ($saved.PSObject.Properties['ultracode']) { $config.ultracode = [bool]$saved.ultracode }
    } catch { }
    return $config
}

function Save-MsrfConfig([string]$Effort, [bool]$Ultracode) {
    New-Item -ItemType Directory -Force -Path (Get-MsrfHome) | Out-Null
    Write-JsonFile (Join-Path (Get-MsrfHome) 'config.json') ([pscustomobject]@{ effort = $Effort; ultracode = $Ultracode })
    $sessionSettings = Join-Path (Get-MsrfHome) 'session-settings.json'
    if ($Ultracode) { Write-JsonFile $sessionSettings ([pscustomobject]@{ ultracode = $true }) }
    elseif (Test-Path $sessionSettings) { Remove-Item -LiteralPath $sessionSettings -Force }
}

function Add-SessionDefaults([string[]]$Arguments) {
    $config = Get-MsrfConfig
    $result = @($Arguments)
    if ($config.effort -and $config.effort -ne 'default' -and $result -notcontains '--effort') { $result += @('--effort', $config.effort) }
    $sessionSettings = Join-Path (Get-MsrfHome) 'session-settings.json'
    if ($config.ultracode -and $result -notcontains '--settings' -and (Test-Path $sessionSettings)) { $result += @('--settings', $sessionSettings) }
    return [string[]]$result
}

function Wait-MsrfTurn($Transcript) {
    $queuePath = Join-Path (Get-MsrfHome) 'queue.dat'
    $interval = 3 + [math]::Ceiling(4 * $Transcript.Length / 1GB)
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        try {
            $stream = [IO.File]::Open($queuePath, 'OpenOrCreate', 'ReadWrite', 'None')
        } catch {
            Start-Sleep -Milliseconds 200
            continue
        }
        try {
            $reader = New-Object IO.StreamReader($stream)
            $previous = [datetime]::MinValue
            [void][datetime]::TryParse($reader.ReadLine(), [ref]$previous)
            $now = Get-Date
            $turn = if ($previous -gt $now) { $previous } else { $now }
            $stream.SetLength(0)
            $writer = New-Object IO.StreamWriter($stream)
            $writer.WriteLine($turn.AddSeconds($interval).ToString('o'))
            $writer.Flush()
        } finally {
            $stream.Close()
        }
        $wait = [math]::Ceiling(($turn - $now).TotalSeconds)
        if ($wait -gt 0) {
            Write-Host "[$($script:MsrfName)] waiting $wait s so the tabs reopen one after another."
            Start-Sleep -Seconds $wait
        }
        return
    }
}

$script:ProcessTable = $null

function Import-MsrfNative([switch]$AllowCompile) {
    if ('MsrfNative' -as [type]) { return $true }
    $library = Join-Path $PSScriptRoot 'MsrfNative.dll'
    try {
        if (Test-Path $library) { Add-Type -Path $library -ErrorAction Stop; return $true }
        if ($AllowCompile) {
            Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'MsrfNative.cs'))) -ErrorAction Stop
            return $true
        }
    } catch { }
    return $false
}

function Get-ProcessEnvironmentVariable([int]$ProcessId, [string]$Name) {
    if (-not (Import-MsrfNative -AllowCompile)) { throw 'the native helper could not be loaded' }
    return [MsrfNative]::GetEnvironmentVariable($ProcessId, $Name)
}

function Invoke-MsrfSeed {
    $recorded = 0
    $skipped = 0
    foreach ($live in Get-LiveClaudeSessions) {
        $terminal = Get-ProcessEnvironmentVariable $live.ProcessId 'MAESTRI_TERMINAL_ID'
        if (-not $terminal) { continue }
        if (-not (Test-TranscriptHasPrompt (Get-Transcript $live.SessionId))) { $skipped++; continue }
        Set-TabSession $terminal $live.SessionId
        Write-MsrfLog "seeded $($terminal.ToLower()) $($live.SessionId)"
        $recorded++
    }
    return [pscustomobject]@{ Recorded = $recorded; SkippedEmpty = $skipped }
}

function Get-HookCommand {
    $script = (Join-Path (Get-MsrfHome) 'bin\msrf-record-session.ps1') -replace '\\', '/'
    return "powershell.exe -NoLogo -NoProfile -NonInteractive -File `"$script`""
}

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path $Path)) { return [pscustomobject]@{} }
    $text = [IO.File]::ReadAllText($Path)
    if (-not $text.Trim()) { return [pscustomobject]@{} }
    return $text | ConvertFrom-Json
}

function Write-JsonFile([string]$Path, $Data) {
    $text = $Data | ConvertTo-Json -Depth 64
    [IO.File]::WriteAllText($Path, $text + "`n", (New-Object Text.UTF8Encoding($false)))
}

function Update-ClaudeSettingsHooks([string]$SettingsPath, [switch]$Remove) {
    $settings = Read-JsonFile $SettingsPath
    if (-not $settings.PSObject.Properties['hooks']) {
        $settings | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([pscustomobject]@{})
    }
    $command = Get-HookCommand
    foreach ($event in @('UserPromptSubmit', 'SessionStart')) {
        $kept = @()
        if ($settings.hooks.PSObject.Properties[$event]) {
            foreach ($entry in @($settings.hooks.$event)) {
                $isOurs = $false
                if ($entry.PSObject.Properties['hooks']) {
                    foreach ($hook in @($entry.hooks)) {
                        if ($hook.PSObject.Properties['command'] -and ([string]$hook.command).Contains($script:HookMarker)) { $isOurs = $true }
                    }
                }
                if (-not $isOurs) { $kept += $entry }
            }
            $settings.hooks.PSObject.Properties.Remove($event)
        }
        if (-not $Remove) {
            $entry = [pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = $command; timeout = 15 }) }
            if ($event -eq 'SessionStart') { $entry = [pscustomobject]@{ matcher = 'resume|clear|compact'; hooks = $entry.hooks } }
            $kept += $entry
        }
        if ($kept.Count -gt 0) {
            $settings.hooks | Add-Member -NotePropertyName $event -NotePropertyValue @($kept)
        }
    }
    if (@($settings.hooks.PSObject.Properties).Count -eq 0) { $settings.PSObject.Properties.Remove('hooks') }
    New-Item -ItemType Directory -Force -Path (Split-Path $SettingsPath) | Out-Null
    Write-JsonFile $SettingsPath $settings
}

function Get-NewShellExecutionPolicy {
    $byScope = @{}
    foreach ($row in Get-ExecutionPolicy -List) { $byScope[[string]$row.Scope] = [string]$row.ExecutionPolicy }
    foreach ($scope in @('MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine')) {
        if ($byScope[$scope] -and $byScope[$scope] -ne 'Undefined') {
            return [pscustomobject]@{ Policy = $byScope[$scope]; Scope = $scope }
        }
    }
    return [pscustomobject]@{ Policy = 'Restricted'; Scope = 'Default' }
}

function Test-PolicyAllowsLocalScripts([string]$Policy) {
    return @('RemoteSigned', 'Unrestricted', 'Bypass') -contains $Policy
}

function Get-MaestriClaudeTabs {
    $tabs = @()
    $folder = Join-Path (Get-MaestriDataDir) 'workspaces'
    foreach ($file in Get-ChildItem -Path $folder -Filter 'workspace.json' -Recurse -Depth 1 -ErrorAction SilentlyContinue) {
        try {
            $workspace = [IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json
            foreach ($node in @($workspace.payload.nodes)) {
                if (-not $node.content.PSObject.Properties['terminal']) { continue }
                $terminal = $node.content.terminal._0
                if ([string]$terminal.agentType -ne 'claude_code') { continue }
                $shellPath = if ($terminal.PSObject.Properties['shellPath']) { [string]$terminal.shellPath } else { '' }
                $tabs += [pscustomobject]@{ Id = ([string]$terminal.id).ToLower(); Name = [string]$terminal.name; ShellPath = $shellPath }
            }
        } catch { }
    }
    return $tabs
}

function Get-MaestriPreferredShell {
    $path = Join-Path (Get-MaestriDataDir) 'preferences.json'
    try {
        $preferences = ([IO.File]::ReadAllText($path) | ConvertFrom-Json).payload
        if ($preferences.PSObject.Properties['preferredShellPath']) { return [string]$preferences.preferredShellPath }
    } catch { }
    return ''
}

function Test-SupportedShellPath([string]$ShellPath) {
    if (-not $ShellPath) { return $true }
    return @('powershell', 'pwsh') -contains (Get-NormalizedProcessName $ShellPath)
}

function Get-ProfilePaths {
    if ($env:MSRF_PROFILE_PATHS) { return @($env:MSRF_PROFILE_PATHS.Split(';') | Where-Object { $_ }) }
    $documents = [Environment]::GetFolderPath('MyDocuments')
    return @(
        (Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1')
    )
}

function Get-ProfileLine {
    return ". `"$(Join-Path (Get-MsrfHome) 'bin\msrf-profile.ps1')`""
}

function Update-ProfileLine([string]$ProfilePath, [switch]$Remove) {
    $lines = @()
    if (Test-Path $ProfilePath) { $lines = @(Get-Content $ProfilePath) }
    $kept = @($lines | Where-Object { -not $_.Contains($script:ProfileMarker) })
    if (-not $Remove) { $kept += Get-ProfileLine }
    New-Item -ItemType Directory -Force -Path (Split-Path $ProfilePath) | Out-Null
    if ($Remove -and $kept.Count -eq 0 -and (Test-Path $ProfilePath)) {
        Remove-Item -LiteralPath $ProfilePath -Force
        return
    }
    [IO.File]::WriteAllText($ProfilePath, (($kept -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($true)))
}
