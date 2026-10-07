# BastissSteam - Activador (v1)
$ErrorActionPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072
Write-Host 'BastissSteam - Activador'
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $admin){
  Write-Host 'Solicitando permisos de administrador...'
  try { Start-Process powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command','irm https://raw.githubusercontent.com/bastisayes/BastissSteamV18/main/activar.ps1 | iex') -Verb RunAs } catch { Write-Host 'Se necesitan permisos de administrador para continuar.' }
  return
}
function Stop-SteamQ { for($i=0;$i -lt 3;$i++){ try { Get-Process steam,steamwebhelper,steamservice,gameoverlayui -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}; Start-Sleep -Milliseconds 800 } }
Stop-SteamQ
Write-Host 'Paso 1/3: buscando instalacion...'
function Get-SteamRoots {
  $r=@()
  foreach($h in @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam')){
    try { $p=(Get-ItemProperty -Path $h -Name InstallPath -ErrorAction Stop).InstallPath; if($p -and (Test-Path -LiteralPath $p) -and $r -notcontains $p){ $r+=$p } } catch {}
  }
  try { $p=(Get-ItemProperty -Path 'HKCU:\SOFTWARE\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath; if($p -and (Test-Path -LiteralPath $p) -and $r -notcontains $p){ $r+=$p } } catch {}
  foreach($p in @("${env:ProgramFiles(x86)}\Steam","$env:ProgramFiles\Steam")){ if($p -and (Test-Path -LiteralPath $p) -and $r -notcontains $p){ $r+=$p } }
  foreach($d in 'C','D','E','F','G'){ foreach($s in @('\Steam','\SteamLibrary')){ $p="${d}:$s"; if((Test-Path -LiteralPath $p) -and $r -notcontains $p){ $r+=$p } } }
  try {
    foreach($root in @($r)){
      foreach($lf in @((Join-Path $root 'steamapps\libraryfolders.vdf'),(Join-Path $root 'config\libraryfolders.vdf'))){
        if(Test-Path -LiteralPath $lf){
          $c=Get-Content -LiteralPath $lf -Raw -ErrorAction Stop
          foreach($m in [regex]::Matches($c,'"path"\s+"([^"]+)"')){
            $p=$m.Groups[1].Value.Replace('\\','\')
            if($p -and (Test-Path -LiteralPath $p) -and $r -notcontains $p){ $r+=$p }
          }
        }
      }
    }
  } catch {}
  return @($r | Select-Object -Unique)
}
$roots=Get-SteamRoots
if(-not $roots -or $roots.Count -eq 0){ Write-Host 'No se encontro Steam instalado en esta PC.'; return }
Write-Host ("Instalaciones encontradas: " + $roots.Count)
Write-Host 'Paso 2/3: descargando componentes...'
$zipUrl=[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('aHR0cHM6Ly9naXRodWIuY29tL2Jhc3Rpc2F5ZXMvRml4ZXMtc3RlYW0vcmVsZWFzZXMvZG93bmxvYWQvYmFzdGlzc3MvcGFyY2hlX251ZXZvLnppcA=='))
$zip=Join-Path $env:TEMP ("act_" + (Get-Random) + ".zip")
$dlOk=$false
try { (New-Object System.Net.WebClient).DownloadFile($zipUrl,$zip); $dlOk=$true } catch {}
if(-not $dlOk){ try { Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop; $dlOk=$true } catch {} }
if(-not $dlOk -or -not (Test-Path -LiteralPath $zip) -or (Get-Item -LiteralPath $zip).Length -lt 1000){ Write-Host 'No se pudo descargar. Revisa tu internet e intenta de nuevo.'; return }
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
try { $zx=[System.IO.Compression.ZipFile]::OpenRead($zip); $nTest=@($zx.Entries).Count; $zx.Dispose() } catch { $nTest=0 }
if($nTest -le 0){ Write-Host 'Descarga incompleta. Intenta de nuevo.'; Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue; return }
Write-Host 'aplicando activacion...'
$totOk=0; $totBad=0; $badFiles=@()
foreach($sr in $roots){
  Stop-SteamQ
  Start-Sleep -Milliseconds 1500
  $arch=[System.IO.Compression.ZipFile]::OpenRead($zip)
  try {
    $entries=@($arch.Entries | Where-Object { $rel=$_.FullName.TrimStart('/','\'); -not [string]::IsNullOrWhiteSpace($rel) -and -not ($_.FullName.EndsWith('/') -or $_.FullName.EndsWith('\')) })
    foreach($e in $entries){
      $rel=$e.FullName.TrimStart('/','\')
      $full=Join-Path $sr $rel
      $dir=[System.IO.Path]::GetDirectoryName($full)
      if($dir -and -not (Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Path $dir -Force | Out-Null }
      $done=$false
      for($t=1;$t -le 4 -and -not $done;$t++){
        try { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e,$full,$true); $done=$true }
        catch {
          if($t -lt 4){
            Stop-SteamQ
            Start-Sleep -Milliseconds 1500
          }
        }
      }
    }
  } finally { $arch.Dispose() }
  try { $wm=Join-Path $sr 'winmm.dll'; if(Test-Path -LiteralPath $wm){ Remove-Item -LiteralPath $wm -Force -ErrorAction SilentlyContinue } } catch {}
  $arch2=[System.IO.Compression.ZipFile]::OpenRead($zip)
  try {
    $entries2=@($arch2.Entries | Where-Object { $rel=$_.FullName.TrimStart('/','\'); -not [string]::IsNullOrWhiteSpace($rel) -and -not ($_.FullName.EndsWith('/') -or $_.FullName.EndsWith('\')) })
    foreach($e in $entries2){
      $rel=$e.FullName.TrimStart('/','\')
      if($rel -ieq 'winmm.dll'){ continue }
      $full=Join-Path $sr $rel
      $ok=$false
      try { $it=Get-Item -LiteralPath $full -ErrorAction Stop; if(-not $it.PSIsContainer -and $it.Length -eq $e.Length){ $ok=$true } } catch {}
      if($ok){ $totOk++ } else { $totBad++; if($badFiles.Count -lt 8){ $badFiles+=$rel } }
    }
  } finally { $arch2.Dispose() }
}
Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
if($totBad -gt 0){
  Write-Host ("No se pudo completar (" + $totOk + " verificados, " + $totBad + " pendientes).")
  Write-Host 'Cierra Steam y los juegos, luego ejecuta de nuevo.'
  foreach($b in $badFiles){ Write-Host (" - " + $b) }
  return
}
Write-Host ("activacion completada: " + $totOk + " de " + $totOk + " archivos verificados.")
try { Start-Process -FilePath (Join-Path $roots[0] 'steam.exe') -ErrorAction Stop } catch { Write-Host 'Abre Steam manualmente.' }
