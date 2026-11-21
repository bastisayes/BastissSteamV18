[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    $installDir = Join-Path $env:LOCALAPPDATA 'BastissSteam'
    $appPath = Join-Path $installDir 'BastissSteamActivator4.exe'
    if (-not (Test-Path -LiteralPath $appPath -PathType Leaf)) {
        throw 'BastissSteam todavía no está instalado. Instalá primero la versión firmada.'
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $appPath
    if ($signature.Status -ne 'Valid') {
        throw 'No se pudo verificar la firma de BastissSteam. Instalá la versión firmada antes de abrirlo.'
    }

    Start-Process -FilePath $appPath -WorkingDirectory $installDir
} catch {
    Write-Host ('No se pudo abrir BastissSteam. ' + $_.Exception.Message)
    exit 1
}
