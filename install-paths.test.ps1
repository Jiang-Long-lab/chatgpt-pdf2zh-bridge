$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'install-paths.ps1')
$fixture = Join-Path $PSScriptRoot 'setup.ps1'
if ((Select-BridgePath 'fixture' @($fixture) 'setup.ps1' -NonInteractive) -ne $fixture) { throw 'Unique path not selected' }
foreach ($paths in @(@(), @($fixture, (Join-Path $PSScriptRoot 'start.ps1')))) {
    $rejected = $false
    try { Select-BridgePath 'fixture' $paths 'setup.ps1' -NonInteractive | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Missing or ambiguous paths must not be silently selected' }
}
$value = "D:\Test Folder\O'Brien\" + [char]0x4e2d + '\python.exe'
$literal = ConvertTo-PSLiteral $value
if ((& ([scriptblock]::Create($literal))) -cne $value) { throw 'Configuration escaping failed' }
$errors = $null
foreach ($name in @('install.ps1','install-paths.ps1','setup.ps1')) {
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name), [ref]$null, [ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
}
Write-Host 'Installer path tests passed.'
