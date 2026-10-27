if ($env:MAESTRI_TERMINAL_ID) {
    function claude { & (Join-Path $PSScriptRoot 'msrf-claude-tab.ps1') @args }
}
