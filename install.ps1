param([switch]$CheckOnly, [switch]$NonInteractive, [switch]$NoStart, [switch]$NoShortcuts)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'install-paths.ps1')
    $configPath = Join-Path $PSScriptRoot 'config.local.ps1'
    $DataDir = Join-Path $PSScriptRoot '.local-data'
    $NodePath = $null; $PythonPath = $null; $BackendPath = $null
    $existing = Test-Path -LiteralPath $configPath
    if ($existing) { . $configPath }
    $candidates = Get-BridgeCandidates $PSScriptRoot
    if ($CheckOnly) { $candidates | ConvertTo-Json -Depth 3; return }
    if (-not $NodePath -and -not $candidates.Node.Count) {
        if (-not $NonInteractive -and (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
            $answer = Read-Host 'Node.js not found. Install Node.js LTS using winget? [y/N]'
            if ($answer -eq 'y') {
                winget.exe install --id OpenJS.NodeJS.LTS --exact --source winget --accept-package-agreements --accept-source-agreements
                if ($LASTEXITCODE -ne 0) { throw 'Node.js installation failed.' }
                $env:PATH = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
                $candidates = Get-BridgeCandidates $PSScriptRoot
            }
        }
    }
    if (-not $NodePath) { $NodePath = Select-BridgePath 'Node.js' $candidates.Node 'node.exe' -NonInteractive:$NonInteractive }
    if (-not $BackendPath) { $BackendPath = Select-BridgePath 'PDF2zh backend' $candidates.Backend 'server.py' -NonInteractive:$NonInteractive }
    if (-not $PythonPath) { $PythonPath = Select-BridgePath 'PDF2zh backend Python' $candidates.Python 'python.exe' -NonInteractive:$NonInteractive }
    $NodePath = (Get-Command $NodePath -ErrorAction Stop).Source
    $PythonPath = (Get-Command $PythonPath -ErrorAction Stop).Source
    $versionText = & $NodePath --version
    if ($LASTEXITCODE -ne 0 -or [version]($versionText.Trim().TrimStart('v')) -lt [version]'22.12.0') { throw 'Node.js 22.12 or newer is required.' }
    $env:PATH = (Split-Path $NodePath) + ';' + $env:PATH
    if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) { throw 'npm.cmd is missing. Install Node.js including npm.' }
    if (-not (Test-Path -LiteralPath (Join-Path $BackendPath 'utils\task_manager.py'))) { throw 'Select the supported PDF2zh server folder, containing server.py and utils/task_manager.py.' }
    & $PythonPath -c 'import sys; sys.path.insert(0, sys.argv[1]); import server' $BackendPath
    if ($LASTEXITCODE -ne 0) { throw 'Selected Python lacks backend dependencies. Select the environment that already runs your PDF2zh server.' }
    if (-not [IO.Path]::IsPathRooted($DataDir)) { throw 'DataDir must be an absolute path.' }
    Write-Host "Node: $NodePath`nPython: $PythonPath`nBackend: $BackendPath`nData: $DataDir"
    & (Join-Path $PSScriptRoot 'setup.ps1')
    if (-not $existing) {
        $lines = @(
            ('$NodePath = ' + (ConvertTo-PSLiteral $NodePath))
            ('$PythonPath = ' + (ConvertTo-PSLiteral $PythonPath))
            ('$BackendPath = ' + (ConvertTo-PSLiteral $BackendPath))
        )
        $lines += '$DataDir = Join-Path $PSScriptRoot ''.local-data'''
        # Windows PowerShell 5.1 needs BOM for non-ASCII installation paths.
        [IO.File]::WriteAllLines($configPath, $lines, (New-Object Text.UTF8Encoding($true)))
    }
    if (-not $NoShortcuts) {
        $shell = New-Object -ComObject WScript.Shell
        $desktop = [Environment]::GetFolderPath('Desktop')
        foreach ($entry in @(@{Name='ChatGPT PDF Translation';File='启动ChatGPT翻译.vbs'},@{Name='Stop ChatGPT PDF Translation';File='停止ChatGPT翻译.vbs'})) {
            $shortcut = $shell.CreateShortcut((Join-Path $desktop ($entry.Name + '.lnk')))
            $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
            $shortcut.Arguments = '"' + (Join-Path $PSScriptRoot $entry.File) + '"'
            $shortcut.WorkingDirectory = $PSScriptRoot
            $shortcut.Save()
        }
    }
    if (-not $NoStart) { & (Join-Path $PSScriptRoot 'start.ps1') }
    Write-Host 'Ready. Sign in on the local page and finish the Zotero settings in README.'
} catch {
    Write-Host ('Installation stopped: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Your existing config and login data have not been replaced. See README for manual path setup.'
    if (-not $NonInteractive) { Read-Host 'Press Enter to close' | Out-Null }
    exit 1
}
