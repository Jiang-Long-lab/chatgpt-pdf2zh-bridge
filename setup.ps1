$ErrorActionPreference = 'Stop'
$vendor = Join-Path $PSScriptRoot 'vendor'
$sdk = Join-Path $vendor 'sign-in-with-chatgpt-devkit'
$revision = '0a36fefeb913055c8c7a1a29b63d82b96b2e841a'
$archiveHash = '3B97910855BA85D4214AC42A2E65BFE660AC3FF3475C81EB157AC27EE6F31C63'
$stage = Join-Path $vendor ('.sdk-install-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $stage | Out-Null
try {
    $archive = Join-Path $stage 'sdk.zip'
    Write-Host 'Downloading pinned SDK archive...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri "https://codeload.github.com/openai/sign-in-with-chatgpt-devkit/zip/$revision" -OutFile $archive
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $archiveHash) { throw 'SDK archive checksum mismatch. Existing files were not changed.' }
    # Strip the archive's long commit-named parent to stay within Windows PS 5.1 path limits.
    $source = Join-Path $stage 'source'
    New-Item -ItemType Directory $source | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $prefix = "sign-in-with-chatgpt-devkit-$revision/"
        foreach ($entry in $zip.Entries) {
            if (-not $entry.FullName.StartsWith($prefix)) { throw 'Unexpected SDK archive entry.' }
            $relative = $entry.FullName.Substring($prefix.Length)
            if (-not $relative) { continue }
            $destination = [IO.Path]::GetFullPath((Join-Path $source $relative))
            if (-not $destination.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid SDK archive path.' }
            if ($entry.FullName.EndsWith('/')) { New-Item -ItemType Directory -Force $destination | Out-Null }
            else {
                New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination)
            }
        }
    } finally { $zip.Dispose() }
    node.exe (Join-Path $PSScriptRoot 'sdk-archive.mjs') patch $source (Join-Path $PSScriptRoot 'patches\sdk-usage-effort.patch')
    if ($LASTEXITCODE -ne 0) { throw 'SDK patch failed. Existing files were not changed.' }
    if (Test-Path -LiteralPath $sdk) {
        node.exe (Join-Path $PSScriptRoot 'sdk-archive.mjs') verify $source $sdk
        if ($LASTEXITCODE -ne 0) { throw 'Existing SDK differs from the pinned, patched source. It was not overwritten.' }
    } else {
        Move-Item -LiteralPath $source -Destination $sdk
    }
} finally {
    # Only remove the uniquely named staging directory created by this invocation.
    $stageFull = [IO.Path]::GetFullPath($stage)
    $vendorFull = [IO.Path]::GetFullPath($vendor).TrimEnd('\') + '\'
    if (-not $stageFull.StartsWith($vendorFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid SDK staging path.' }
    if (Test-Path -LiteralPath $stageFull) { Remove-Item -LiteralPath $stageFull -Recurse -Force }
}
Push-Location $sdk
try {
    npm.cmd ci
    if ($LASTEXITCODE -ne 0) { throw 'SDK dependency installation failed.' }
    npm.cmd run build --workspace @siwc/local
    if ($LASTEXITCODE -ne 0) { throw 'SDK build failed.' }
} finally { Pop-Location }
Write-Host 'SDK ready. Run install.ps1 to detect paths, or start.ps1 if already configured.'
