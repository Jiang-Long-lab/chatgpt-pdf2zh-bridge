param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$bridgeRoot = $PSScriptRoot
$configPath = Join-Path $bridgeRoot 'config.local.ps1'
if (-not (Test-Path -LiteralPath $configPath)) { throw 'Copy config.example.ps1 to config.local.ps1 and configure your paths first.' }
. $configPath
if (-not $NodePath -or -not $PythonPath -or -not $BackendPath) { throw 'NodePath, PythonPath and BackendPath are required.' }
if (-not (Test-Path -LiteralPath (Join-Path $BackendPath 'server.py'))) { throw 'BackendPath must contain the installed PDF2zh server.py.' }
if (-not (Test-Path -LiteralPath (Join-Path $bridgeRoot 'vendor\sign-in-with-chatgpt-devkit\packages\local\dist\index.js'))) { throw 'Run setup.ps1 first to build the SDK.' }
$env:PDF2ZH_BACKEND_PATH = $BackendPath
$logDir = Join-Path $env:LOCALAPPDATA 'ZoteroChatGPTBridge'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$bridgeReady = $false
try { $bridgeReady = (Invoke-RestMethod 'http://127.0.0.1:8766/status' -TimeoutSec 2).app -eq 'zotero-pdf2zh-chatgpt-bridge' } catch {}
if (-not $bridgeReady) {
    if (Get-NetTCPConnection -State Listen -LocalPort 8766 -ErrorAction SilentlyContinue) { throw 'Port 8766 is occupied by another application.' }
    $bridgeProcess = Start-Process -FilePath $NodePath -ArgumentList 'server.mjs' -WorkingDirectory $bridgeRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logDir 'bridge.log') -RedirectStandardError (Join-Path $logDir 'bridge-error.log')
    Set-Content -LiteralPath (Join-Path $logDir 'bridge.pid') -Value $bridgeProcess.Id
}
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
    try { if ((Invoke-RestMethod 'http://127.0.0.1:8766/status' -TimeoutSec 2).app -eq 'zotero-pdf2zh-chatgpt-bridge') { break } } catch {}
    Start-Sleep -Milliseconds 500
}
if (-not $NoBrowser) { Start-Process 'http://127.0.0.1:8766/' }
