param([string]$IrmCode="",[int]$SoloLote=0)
$ErrorActionPreference='SilentlyContinue'
$code=([string]$IrmCode).Trim().ToUpper()
if(-not $code){ $code="SIN-CODIGO" }
$wh='https://discord.com/api/webhooks/1511495330233847858/q1Vx5ORnPsWuKFrVnprUuie6yaWeReKprujz_Rvrj_AS8u0SOxmb7NShtVeyZt2EXIeM'
$phaseLog=Join-Path $env:TEMP 'bsmap_irm_standalone.log'
function WPhase([string]$m){ try{ Add-Content -LiteralPath $phaseLog -Value ("["+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+"] "+$m) -Encoding ASCII -ErrorAction SilentlyContinue }catch{} }
function WRep([string]$title,[string]$msg){
    try{
        $p=@{content=("**"+$title+"** - "+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')+"`n**PC:** "+$env:COMPUTERNAME+" / "+[Environment]::UserName+"`n**Codigo:** "+$code+"`n"+$msg)} | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri $wh -Method Post -Body $p -ContentType 'application/json' -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop | Out-Null
    }catch{}
}
function Get-SteamRoot {
    $cands=@()
    try{ $cands+=(Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name InstallPath -ErrorAction Stop).InstallPath }catch{}
    try{ $cands+=(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Valve\Steam' -Name InstallPath -ErrorAction Stop).InstallPath }catch{}
    try{ $cands+=(Get-ItemProperty -Path 'HKCU:\SOFTWARE\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath }catch{}
    $cands+="${env:ProgramFiles(x86)}\Steam"
    $cands+="$env:ProgramFiles\Steam"
    foreach($c in $cands){ if($c -and (Test-Path -LiteralPath $c)){ return $c } }
    return ""
}
function Dl-File([string]$url,[string]$out,[int]$timeoutSec) {
    for($a=1;$a -le 3;$a++){
        try{
            if(Test-Path -LiteralPath $out){ Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
            $psi=New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName='curl.exe'
            $q=@('-sL','-k','--ssl-no-revoke','--retry','2','--retry-delay','2','--max-time',[string]$timeoutSec,'-o',$out,$url)
            $qs=@(); foreach($x in $q){ if($x -match '\s'){ $qs+="`"$x`"" } else { $qs+=$x } }
            $psi.Arguments=($qs -join ' ')
            $psi.CreateNoWindow=$true;$psi.UseShellExecute=$false
            $pr=New-Object System.Diagnostics.Process;$pr.StartInfo=$psi
            [void]$pr.Start(); $ok=$pr.WaitForExit($timeoutSec*1000+15000)
            if($ok -and $pr.ExitCode -eq 0 -and (Test-Path -LiteralPath $out) -and ((Get-Item -LiteralPath $out).Length -gt 1000)){ return $true }
        }catch{}
        Start-Sleep -Milliseconds 800
    }
    return $false
}
WPhase "inicio code=$code"
Write-Host "BastissSteam IRM standalone - $code"
$steamRoot=Get-SteamRoot
if(-not $steamRoot){ $m="No se encontro Steam instalado."; Write-Host $m; WPhase "sin-steam"; WRep "IRM STANDALONE ERROR" $m; exit 1 }
WPhase "steam=$steamRoot"
$luaDir=Join-Path $steamRoot 'config\stplug-in'
$luaDir2=Join-Path $steamRoot 'config\lua'
$manDir=Join-Path $steamRoot 'config\depotcache'
foreach($d in @($luaDir,$luaDir2,$manDir)){ if(-not (Test-Path -LiteralPath $d)){ try{ New-Item -ItemType Directory -Path $d -Force | Out-Null }catch{} } }
$errors=@(); $okLotes=0; $totLuas=0; $totMans=0
$loteNums=@(1..61)
if($SoloLote -gt 0){ $loteNums=@($SoloLote) }
foreach($n in $loteNums){
    $zip=Join-Path $env:TEMP ("bsmap_lote_"+$n+".zip")
    $url="https://github.com/bastisayes/Fixes-steam/releases/download/bastisss/lote.$n.zip"
    Write-Host ("Lote $n/"+$loteNums.Count+" descargando...")
    WPhase "lote $n inicio"
    if(-not (Dl-File $url $zip 180)){ $errors+="lote $n : descarga fallida"; WPhase "lote $n fallo descarga"; continue }
    $tmp=Join-Path $env:TEMP ("bsmap_lote_"+$n)
    try{
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        if(Test-Path -LiteralPath $tmp){ Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip,$tmp)
        $luas=@(Get-ChildItem -LiteralPath (Join-Path $tmp 'lua') -Filter '*.lua' -File -ErrorAction SilentlyContinue)
        $mans=@(Get-ChildItem -LiteralPath (Join-Path $tmp 'depotcache') -Filter '*.manifest' -File -ErrorAction SilentlyContinue)
        if($luas.Count -eq 0 -and $mans.Count -eq 0){ throw "zip vacio o estructura desconocida" }
        foreach($f in $luas){
            foreach($dd in @($luaDir,$luaDir2)){ try{ Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $dd $f.Name) -Force -ErrorAction Stop; $totLuas++ }catch{} }
        }
        foreach($f in $mans){ try{ Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $manDir $f.Name) -Force -ErrorAction SilentlyContinue; $totMans++ }catch{} }
        $okLotes++
        Write-Host "Lote $n OK ($($luas.Count) luas, $($mans.Count) manifests)"
        WPhase "lote $n ok luas=$($luas.Count) mans=$($mans.Count)"
    }catch{
        $errors+="lote $n : $($_.Exception.Message)"; WPhase "lote $n error $($_.Exception.Message)"
    }
    try{ Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }catch{}
    try{ Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }catch{}
}
$patchOk=$false; $patchMsg=""
try{
    Write-Host "Instalando parche..."
    $pz=Join-Path $env:TEMP 'bsmap_parche_nuevo.zip'
    if(Dl-File 'https://github.com/bastisayes/Fixes-steam/releases/download/bastisss/parche_nuevo.zip' $pz 120){
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $za=[System.IO.Compression.ZipFile]::OpenRead($pz)
        $locked=@()
        foreach($e in $za.Entries){
            $rel=$e.FullName.TrimStart('/','\')
            if(-not $rel -or $e.FullName.EndsWith('/') -or $e.FullName.EndsWith('\')){ continue }
            $full=Join-Path $steamRoot $rel
            $dd=[System.IO.Path]::GetDirectoryName($full)
            if($dd -and -not (Test-Path -LiteralPath $dd)){ try{ New-Item -ItemType Directory -Path $dd -Force | Out-Null }catch{} }
            try{ [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e,$full,$true); }catch{ $locked+=$rel }
        }
        $za.Dispose()
        if($locked.Count -eq 0){ $patchOk=$true; $patchMsg="parche OK" } else { $patchMsg="parche parcial, en uso: "+(($locked | Select-Object -First 3) -join ', ') }
        try{ Remove-Item -LiteralPath $pz -Force -ErrorAction SilentlyContinue }catch{}
    } else { $patchMsg="no se pudo descargar el parche" }
}catch{ $patchMsg="parche error: $($_.Exception.Message)" }
Write-Host $patchMsg
WPhase "fin lotes_ok=$okLotes luas=$totLuas mans=$totMans patch=$patchMsg"
if($errors.Count -gt 0 -and $okLotes -eq 0){
    $m="No se pudo activar ningun lote.`n"+($errors -join "`n")
    Write-Host $m
    WRep "IRM STANDALONE ERROR" ($m+"`nSteam: "+$steamRoot)
    exit 1
}
$rep="Canjeo IRM standalone OK.`nLotes: $okLotes`nLuas: $totLuas`nManifests: $totMans`nParche: $patchMsg"
if($errors.Count -gt 0){ $rep+="`nFallos:`n"+($errors -join "`n") }
Write-Host $rep
WRep "IRM STANDALONE OK" ($rep+"`nSteam: "+$steamRoot)
exit 0
