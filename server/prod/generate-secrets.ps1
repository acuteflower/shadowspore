param(
    [string]$ServerKey = "shadowspore_live_client_v1",
    [switch]$RandomServerKey,
    [switch]$Arm64
)

$ErrorActionPreference = "Stop"

function New-RandomHex([int]$Bytes = 24) {
    $buf = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($buf)
    } finally {
        $rng.Dispose()
    }
    return ($buf | ForEach-Object { $_.ToString("x2") }) -join ""
}

$Dir = $PSScriptRoot
$EnvFile = Join-Path $Dir ".env"
$Template = Join-Path $Dir "prod.yml.template"
$ProdYml = Join-Path $Dir "prod.yml"

if ((Test-Path $EnvFile) -or (Test-Path $ProdYml)) {
    throw "'.env' oder 'prod.yml' existieren bereits in '$Dir'. Loesche oder sichere sie vor einer Neugenerierung."
}

$pgPass = New-RandomHex 24
$sessKey = New-RandomHex 32
$refreshKey = New-RandomHex 32
$effectiveServerKey = if ($RandomServerKey) { "ssp_live_" + (New-RandomHex 18) } else { $ServerKey.Trim() }
if (-not $effectiveServerKey) {
    throw "ServerKey darf nicht leer sein."
}
$consolePass = New-RandomHex 20
$httpKey = New-RandomHex 24

$nakamaTag = if ($Arm64) { "3.24.2-arm" } else { "3.24.2" }
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($EnvFile, "POSTGRES_PASSWORD=$pgPass`nNAKAMA_TAG=$nakamaTag`n", $utf8NoBom)

$yml = (Get-Content -Path $Template -Raw).Replace("`r`n", "`n")
$yml = $yml.Replace("__SESSION_ENCRYPTION_KEY__", $sessKey)
$yml = $yml.Replace("__REFRESH_ENCRYPTION_KEY__", $refreshKey)
$yml = $yml.Replace("__SOCKET_SERVER_KEY__", $effectiveServerKey)
$yml = $yml.Replace("__CONSOLE_PASSWORD__", $consolePass)
$yml = $yml.Replace("__RUNTIME_HTTP_KEY__", $httpKey)
[System.IO.File]::WriteAllText($ProdYml, $yml, $utf8NoBom)

Write-Host "Produktions-Secrets erzeugt in:" -ForegroundColor Green
Write-Host "  - $EnvFile"
Write-Host "  - $ProdYml"
Write-Host ""
Write-Host "socket.server_key = $effectiveServerKey" -ForegroundColor Cyan
if ($RandomServerKey -or $effectiveServerKey -ne "shadowspore_live_client_v1") {
    Write-Host "HINWEIS: Bei abweichendem Server-Key Release bauen mit:" -ForegroundColor Yellow
    Write-Host "  ./tools/build_release.ps1 -ServerKey `"$effectiveServerKey`"" -ForegroundColor Yellow
}
