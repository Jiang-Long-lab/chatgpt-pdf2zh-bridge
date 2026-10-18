param([switch]$Notify)
$ErrorActionPreference = 'Stop'
try {
    $DataDir = Join-Path $PSScriptRoot '.local-data'
    $configPath = Join-Path $PSScriptRoot 'config.local.ps1'
    if (-not (Test-Path -LiteralPath $configPath)) { throw 'config.local.ps1 was not found.' }
    . $configPath
    $DataDir = [IO.Path]::GetFullPath($DataDir)
    $services = @(
        @{Name='bridge'; Port=8766; Executable=$NodePath; Script='server.mjs'},
        @{Name='pdf2zh'; Port=8767; Executable=$PythonPath; Script='pdf_server.py'}
    )
    $running = @{}
    foreach ($service in $services) {
        $listeners = @(Get-NetTCPConnection -LocalPort $service.Port -State Listen -ErrorAction SilentlyContinue)
        if (-not $listeners) { continue }
        $pidFile = Join-Path $DataDir ($service.Name + '.pid')
        if (-not (Test-Path -LiteralPath $pidFile)) { throw "Missing PID file for $($service.Name); refusing to stop an unknown process." }
        $serviceId = [int](Get-Content -LiteralPath $pidFile -Raw).Trim()
        if (@($listeners | Where-Object OwningProcess -ne $serviceId).Count) { throw 'Port owner differs from the recorded process. No unknown process will be stopped.' }
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$serviceId"
        $expectedExe = (Get-Command $service.Executable -ErrorAction Stop).Source
        if (-not $process -or $process.ExecutablePath -ine $expectedExe -or $process.CommandLine -notmatch ('(?:^|[\s"\\/])' + [regex]::Escape($service.Script) + '(?:["\s]|$)')) {
            throw 'Process identity does not match this installation. Refusing shutdown.'
        }
        $running[$service.Name] = $serviceId
    }
    if ($running.Count) {
        $settings = Get-Content -LiteralPath (Join-Path $DataDir 'bridge.json') -Raw | ConvertFrom-Json
        $headers = @{Authorization=('Bearer ' + $settings.apiKey)}
        if ($running.ContainsKey('bridge')) {
            $status = Invoke-RestMethod http://127.0.0.1:8766/status -TimeoutSec 5
            if ($status.app -ne 'zotero-pdf2zh-chatgpt-bridge' -or $status.dataDir -ine $DataDir) { throw 'The bridge uses another data directory.' }
            if ($status.inFlight -gt 0 -or $status.loginExpiresAt) { throw 'Translation or login is running. Wait until it finishes, then stop again.' }
        }
        # Backend refuses shutdown during an entire PDF request, including layout.
        if ($running.ContainsKey('pdf2zh')) {
            Invoke-RestMethod http://127.0.0.1:8767/bridge/shutdown -Method Post -Headers $headers -TimeoutSec 5 | Out-Null
        }
        if ($running.ContainsKey('bridge')) {
            Invoke-RestMethod http://127.0.0.1:8766/v1/shutdown -Method Post -Headers $headers -TimeoutSec 5 | Out-Null
        }
        foreach ($service in $services) {
            if (-not $running.ContainsKey($service.Name)) { continue }
            $serviceProcess = Get-Process -Id $running[$service.Name] -ErrorAction SilentlyContinue
            if ($serviceProcess -and -not $serviceProcess.WaitForExit(10000)) { throw 'A service has not exited. Check its log; no forced termination was performed.' }
            Remove-Item -LiteralPath (Join-Path $DataDir ($service.Name + '.pid')) -ErrorAction SilentlyContinue
        }
    }
    $message = 'Translation services are stopped. Login and settings are preserved.'
    Write-Output $message
    if ($Notify) { (New-Object -ComObject WScript.Shell).Popup($message, 0, 'ChatGPT PDF2zh', 64) | Out-Null }
} catch {
    $message = 'Could not stop services: ' + $_.Exception.Message
    if ($Notify) { (New-Object -ComObject WScript.Shell).Popup($message, 0, 'ChatGPT PDF2zh', 48) | Out-Null }
    Write-Error $message
    exit 1
}
