function Get-BridgeCandidates {
    param([string]$Root)
    $bases = @($env:USERPROFILE, $env:ProgramData, $env:ProgramFiles, (Split-Path $Root), $Root)
    $bases += @(Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Root -match '^[A-Za-z]:\\$'} | ForEach-Object Root)
    $bases += @('Desktop','Documents','Downloads') | ForEach-Object { Join-Path $env:USERPROFILE $_ }
    $bases = @($bases | Where-Object {$_} | Select-Object -Unique)
    $nodes = @((Get-Command node.exe -ErrorAction SilentlyContinue).Source)
    $pythons = @(); $backends = @()
    foreach ($base in $bases) {
        $nodes += Join-Path $base 'nodejs\node.exe'
        foreach ($suffix in @('zotero-pdf2zh\server','zotero-pdf2zh-main\server','server')) {
            $backends += Join-Path $base $suffix
        }
        foreach ($distribution in @('anaconda3','miniconda3','miniforge3')) {
            $pythons += Join-Path $base "$distribution\envs\zotero-pdf2zh-server\python.exe"
        }
    }
    # Conda records custom environment locations here, without running activation scripts.
    $condaList = Join-Path $env:USERPROFILE '.conda\environments.txt'
    if (Test-Path -LiteralPath $condaList) {
        $pythons += Get-Content -LiteralPath $condaList | Where-Object {$_ -match 'zotero-pdf2zh-server[\\/]?$'} | ForEach-Object {Join-Path $_ 'python.exe'}
    }
    $backends = @($backends | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'server.py') } | Select-Object -Unique)
    foreach ($backend in $backends) {
        foreach ($suffix in @('.venv\Scripts\python.exe','venv\Scripts\python.exe','..\.venv\Scripts\python.exe')) { $pythons += Join-Path $backend $suffix }
    }
    return @{
        Node = @($nodes | Where-Object {$_ -and (Test-Path -LiteralPath $_)} | Select-Object -Unique)
        Python = @($pythons | Where-Object {Test-Path -LiteralPath $_} | Select-Object -Unique)
        Backend = $backends
    }
}

function Select-BridgePath {
    param([string]$Label, [string[]]$Candidates, [string]$FileName, [switch]$NonInteractive)
    if ($Candidates.Count -eq 1) { return [IO.Path]::GetFullPath($Candidates[0]) }
    if ($NonInteractive) { throw "$Label was not uniquely detected. Configure it in config.local.ps1." }
    if ($Candidates.Count -gt 1) { Write-Host "$Label candidates:"; $Candidates | ForEach-Object {Write-Host "  $_"} }
    Write-Host "Select $Label ($FileName) in the file picker."
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select $Label ($FileName)"
    $dialog.Filter = "$FileName|$FileName"
    $dialog.CheckFileExists = $true
    try {
        if ($dialog.ShowDialog() -ne 'OK') { throw "Selection cancelled: $Label" }
        if ($FileName -eq 'server.py') { return Split-Path $dialog.FileName }
        return $dialog.FileName
    } finally { $dialog.Dispose() }
}

function ConvertTo-PSLiteral([string]$Value) { return "'" + $Value.Replace("'", "''") + "'" }
