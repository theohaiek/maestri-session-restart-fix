try {
    . (Join-Path $PSScriptRoot 'MsrfCore.ps1')
    $terminal = "$env:MAESTRI_TERMINAL_ID".Trim().ToLower()
    if (-not $terminal) { exit 0 }

    $buffer = New-Object IO.MemoryStream
    [Console]::OpenStandardInput().CopyTo($buffer)
    $payload = [Text.Encoding]::UTF8.GetString($buffer.ToArray())

    $session = if ($payload -match '"session_id"\s*:\s*"([0-9a-fA-F-]{36})"') { $Matches[1].ToLower() } else { $null }
    $event = if ($payload -match '"hook_event_name"\s*:\s*"([A-Za-z]+)"') { $Matches[1] } else { '' }
    $source = if ($payload -match '"source"\s*:\s*"([A-Za-z]+)"') { $Matches[1] } else { '' }
    if (-not (Test-SessionId $session)) { exit 0 }

    $summary = "$event`:$source $terminal $session"
    if ($event -eq 'SessionStart' -and @('resume', 'clear', 'compact') -notcontains $source) {
        Write-MsrfLog "ignored $summary"
        exit 0
    }
    if ($env:MSRF_DEBUG) {
        $chain = @()
        $current = Get-ProcessRecord $PID
        for ($hop = 0; $hop -lt 6 -and $current; $hop++) {
            $chain += "$($current.ProcessId):$($current.Name)"
            $current = Get-ProcessRecord $current.ParentProcessId
        }
        Write-MsrfLog "chain $($chain -join ' > ')"
    }
    $owner = Find-HookOwnerProcessId $PID
    if (-not $owner -or -not (Test-LaunchedFromTab $owner)) {
        Write-MsrfLog "outside-tab $summary"
        exit 0
    }
    Set-TabSession $terminal $session
    Write-MsrfLog "recorded $summary"
} catch {
    try { Write-MsrfLog "error $($_.Exception.Message)" } catch { }
}
exit 0
