. (Join-Path $PSScriptRoot 'MsrfCore.ps1')

$arguments = [string[]]@($args | ForEach-Object { [string]$_ })
$claude = Find-ClaudeExecutable
if (-not $claude) {
    Write-Host "[$($script:MsrfName)] claude was not found on PATH."
    exit 1
}

function Start-Claude([string[]]$List) {
    & $claude @List
    exit $LASTEXITCODE
}

if ($arguments -contains '--new-session') {
    Start-Claude (Add-SessionDefaults ([string[]]@($arguments | Where-Object { $_ -ne '--new-session' })))
}

$terminal = "$env:MAESTRI_TERMINAL_ID".Trim().ToLower()
$passThrough = (-not $terminal) -or [bool]($arguments | Where-Object { $script:PassThroughFlags -contains $_ })
if (-not $passThrough -and -not (Test-ShellOwnedByMaestri $PID)) { $passThrough = $true }
if ($passThrough) { Start-Claude $arguments }

$shellAge = ((Get-Date) - (Get-Process -Id $PID).StartTime).TotalSeconds
$decision = Select-MsrfLaunch -Arguments $arguments -Terminal $terminal -TabMap (Get-TabMap) `
    -IsAutoStart ($shellAge -lt $script:AutoStartSeconds) `
    -FindTranscript { param($id) Get-Transcript $id } `
    -HasPrompt { param($file) Test-TranscriptHasPrompt $file } `
    -IsLive { param($id) Test-SessionLive $id }

if ($decision.Message) { Write-Host "[$($script:MsrfName)] $($decision.Message)" }
if ($decision.Session -and $decision.Queue) { Wait-MsrfTurn (Get-Transcript $decision.Session) }
Start-Claude (Add-SessionDefaults $decision.Arguments)
