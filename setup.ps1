$ErrorActionPreference = 'Stop'
$sdk = Join-Path $PSScriptRoot 'vendor\sign-in-with-chatgpt-devkit'
$revision = '0a36fefeb913055c8c7a1a29b63d82b96b2e841a'
if (Test-Path -LiteralPath $sdk) { throw 'SDK directory already exists. Setup will not overwrite it.' }
New-Item -ItemType Directory -Force (Split-Path $sdk) | Out-Null
git clone https://github.com/openai/sign-in-with-chatgpt-devkit.git $sdk
if ($LASTEXITCODE -ne 0) { throw 'SDK clone failed.' }
git -C $sdk checkout --detach $revision
if ($LASTEXITCODE -ne 0) { throw 'Pinned SDK checkout failed.' }
git -C $sdk apply --check (Join-Path $PSScriptRoot 'patches\sdk-usage-effort.patch')
if ($LASTEXITCODE -ne 0) { throw 'SDK patch check failed.' }
git -C $sdk apply (Join-Path $PSScriptRoot 'patches\sdk-usage-effort.patch')
if ($LASTEXITCODE -ne 0) { throw 'SDK patch failed.' }
Push-Location $sdk
try {
    npm.cmd ci
    if ($LASTEXITCODE -ne 0) { throw 'SDK dependency installation failed.' }
    npm.cmd run build --workspace @siwc/local
    if ($LASTEXITCODE -ne 0) { throw 'SDK build failed.' }
} finally { Pop-Location }
Write-Host 'SDK ready. Copy config.example.ps1 to config.local.ps1 and configure your backend paths.'
