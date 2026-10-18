$ErrorActionPreference = 'Stop'
$sdk = Join-Path $PSScriptRoot 'vendor\sign-in-with-chatgpt-devkit'
$revision = '0a36fefeb913055c8c7a1a29b63d82b96b2e841a'
if (-not (Test-Path -LiteralPath $sdk)) {
    New-Item -ItemType Directory -Force (Split-Path $sdk) | Out-Null
    git clone https://github.com/openai/sign-in-with-chatgpt-devkit.git $sdk
    if ($LASTEXITCODE -ne 0) { throw 'SDK clone failed. Check the network; no existing directory was deleted.' }
    git -C $sdk checkout --detach $revision
    if ($LASTEXITCODE -ne 0) { throw 'Pinned SDK checkout failed.' }
}
$head = git -C $sdk rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $head -ne $revision) { throw 'Existing SDK is not the pinned revision. It was not overwritten.' }
$patch = Join-Path $PSScriptRoot 'patches\sdk-usage-effort.patch'
$savedPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    git -C $sdk apply --reverse --check $patch 2>$null
    $alreadyPatched = $LASTEXITCODE -eq 0
} finally { $ErrorActionPreference = $savedPreference }
if (-not $alreadyPatched) {
    git -C $sdk diff --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Existing SDK has custom or partial modifications. It was not overwritten.' }
    git -C $sdk apply --check $patch
    if ($LASTEXITCODE -ne 0) { throw 'SDK patch check failed.' }
    git -C $sdk apply $patch
    if ($LASTEXITCODE -ne 0) { throw 'SDK patch failed.' }
}
Push-Location $sdk
try {
    npm.cmd ci
    if ($LASTEXITCODE -ne 0) { throw 'SDK dependency installation failed.' }
    npm.cmd run build --workspace @siwc/local
    if ($LASTEXITCODE -ne 0) { throw 'SDK build failed.' }
} finally { Pop-Location }
Write-Host 'SDK ready. Run install.ps1 to detect paths, or start.ps1 if already configured.'
