param([ValidateSet('encrypt','decrypt')][string]$Operation)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$payload = [Convert]::FromBase64String([Console]::In.ReadToEnd().Trim())
$scope = [Security.Cryptography.DataProtectionScope]::CurrentUser
if ($Operation -eq 'encrypt') {
    $result = [Security.Cryptography.ProtectedData]::Protect($payload, $null, $scope)
} else {
    $result = [Security.Cryptography.ProtectedData]::Unprotect($payload, $null, $scope)
}
[Console]::Out.Write([Convert]::ToBase64String($result))
