param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$bridgeRoot = $PSScriptRoot
$configPath = Join-Path $bridgeRoot 'config.local.ps1'
if (-not (Test-Path -LiteralPath $configPath)) { throw 'Copy config.example.ps1 to config.local.ps1 and configure your paths first.' }
$DataDir = Join-Path $bridgeRoot '.local-data'
. $configPath
if (-not $NodePath -or -not $PythonPath -or -not $BackendPath) { throw 'NodePath, PythonPath and BackendPath are required.' }
if (-not (Test-Path -LiteralPath (Join-Path $BackendPath 'server.py'))) { throw 'BackendPath must contain the installed PDF2zh server.py.' }
if (-not (Test-Path -LiteralPath (Join-Path $bridgeRoot 'vendor\sign-in-with-chatgpt-devkit\packages\local\dist\index.js'))) { throw 'Run setup.ps1 first to build the SDK.' }
$env:PDF2ZH_BACKEND_PATH = $BackendPath
if (-not [IO.Path]::IsPathRooted($DataDir)) { throw 'DataDir must be an absolute path.' }
$logDir = [IO.Path]::GetFullPath($DataDir)
$env:ZOTERO_CHATGPT_DATA_DIR = $logDir
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$bridgeReady = $false
$existingBridge = $null
try { $existingBridge = Invoke-RestMethod 'http://127.0.0.1:8766/status' -TimeoutSec 2 } catch {}
if ($existingBridge -and $existingBridge.app -eq 'zotero-pdf2zh-chatgpt-bridge') {
    if (-not $existingBridge.dataDir -or $existingBridge.dataDir.TrimEnd('\') -ine $logDir.TrimEnd('\')) {
        throw 'The running bridge uses a different or legacy data directory. Stop that bridge before restarting.'
    }
    $bridgeReady = $true
}
if (-not $bridgeReady) {
    if (Get-NetTCPConnection -State Listen -LocalPort 8766 -ErrorAction SilentlyContinue) { throw 'Port 8766 is occupied by another application.' }
    $bridgeProcess = Start-Process -FilePath $NodePath -ArgumentList 'server.mjs' -WorkingDirectory $bridgeRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logDir 'bridge.log') -RedirectStandardError (Join-Path $logDir 'bridge-error.log')
    Set-Content -LiteralPath (Join-Path $logDir 'bridge.pid') -Value $bridgeProcess.Id
}
# The backend shutdown control needs the local key created by the bridge.
for ($attempt=0; $attempt -lt 30; $attempt++) {
    try {
        $readyStatus = Invoke-RestMethod 'http://127.0.0.1:8766/status' -TimeoutSec 2
        $bridgeReady = $readyStatus.app -eq 'zotero-pdf2zh-chatgpt-bridge' -and $readyStatus.dataDir -ieq $logDir
        if ($bridgeReady) { break }
    } catch {}
    Start-Sleep -Milliseconds 500
}
if (-not $bridgeReady) { throw "Bridge did not become ready. Check logs in $logDir" }
$pdfReady = $false
try { $pdfReady = (Invoke-RestMethod 'http://127.0.0.1:8767/health' -TimeoutSec 2).status -eq 'ok' } catch {}
if (-not $pdfReady) {
    if (Get-NetTCPConnection -State Listen -LocalPort 8767 -ErrorAction SilentlyContinue) { throw 'Port 8767 is occupied by another application.' }
    $env:PYTHONUTF8 = '1'
    $env:PYTHONIOENCODING = 'utf-8'
    $pdfProcess = Start-Process -FilePath $PythonPath -ArgumentList '-u','pdf_server.py' -WorkingDirectory $bridgeRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logDir 'pdf2zh.log') -RedirectStandardError (Join-Path $logDir 'pdf2zh-error.log')
    Set-Content -LiteralPath (Join-Path $logDir 'pdf2zh.pid') -Value $pdfProcess.Id
}
for ($attempt=0; $attempt -lt 30; $attempt++) {
    try {
        $readyStatus = Invoke-RestMethod 'http://127.0.0.1:8766/status' -TimeoutSec 2
        $bridgeReady = $readyStatus.app -eq 'zotero-pdf2zh-chatgpt-bridge' -and $readyStatus.dataDir -ieq $logDir
        $pdfReady = (Invoke-RestMethod 'http://127.0.0.1:8767/health' -TimeoutSec 2).status -eq 'ok'
        if ($bridgeReady -and $pdfReady) { break }
    } catch {}
    Start-Sleep -Milliseconds 500
}
if (-not ($bridgeReady -and $pdfReady)) { throw "Services did not become ready. Check logs in $logDir" }
if (-not $NoBrowser) { Start-Process 'http://127.0.0.1:8766/' }
