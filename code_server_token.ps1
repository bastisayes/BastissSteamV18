param([int]$Port = 18880)
$ErrorActionPreference = "Continue"
$srvPort = $Port
if (-not $srvPort) { $srvPort = 0 }
$wantedPorts = @(18880,18881,18882,18883,18884)
if ($srvPort -ne 0) { $wantedPorts = @($srvPort) + @($wantedPorts | Where-Object { $_ -ne $srvPort }) } else { $srvPort = 0 }
try {
    $hcOut = & curl.exe -s -o NUL -w "%{http_code}" "http://127.0.0.1:18880/" --max-time 3 2>&1
    if ([string]$hcOut -eq "200") { exit 0 }
} catch {}
foreach ($pc in $wantedPorts) {
    try {
        $tProbe = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $pc)
        $tProbe.Start(5)
        $tProbe.Stop()
        $srvPort = $pc
        break
    } catch {}
}
if (-not $srvPort) { exit 1 }
$startLog = Join-Path $env:LOCALAPPDATA "BastissSteam\server_start.log"
try { Add-Content $startLog "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] INICIO port=$srvPort payload=$($MyInvocation.MyCommand.Path)" -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
$jsonDb = Join-Path $PSScriptRoot "codes_token.json"
$script:redLog = Join-Path $PSScriptRoot "redemption_log_token.txt"
function Get-IpUseCount {
    param([string]$code, [string]$ip)
    if (-not $ip) { return 0 }
    $n = 0
    try {
        if (Test-Path -LiteralPath $script:redLog) {
            foreach ($ln in [System.IO.File]::ReadLines($script:redLog)) {
                $toks = $ln -split '\s+'
                if ($toks -contains 'RESET') {
                    $c = ($toks | Where-Object { $_ -like 'Codigo=*' }) -replace '^Codigo=', ''
                    if ($c -eq $code) { $n = 0 }
                    continue
                }
                if ($toks -notcontains "Codigo=$code") { continue }
                $lineIp = ($toks | Where-Object { $_ -like 'IP=*' }) -replace '^IP=', ''
                if ($lineIp -eq $ip) { $n++ }
            }
        }
    } catch {}
    return $n
}
function Test-ArUsed {
    param([string]$code)
    try {
        if (Test-Path -LiteralPath $script:redLog) {
            foreach ($ln in [System.IO.File]::ReadLines($script:redLog)) {
                $toks = $ln -split '\s+'
                if ($toks -contains 'AR-USADO' -and $toks -contains "Codigo=$code") { return $true }
            }
        }
    } catch {}
    return $false
}
$script:pubUrl = "http://127.0.0.1:$srvPort"
$script:pubUrlCf = ""
$script:fixedPublicUrl = "https://bastii.tailbe072e.ts.net"
$script:urlCache = Join-Path $env:TEMP "bsmap_current_url.txt"
$script:ghKey = ""
try {
    $tokFile = Join-Path $PSScriptRoot "gh_token.txt"
    if (-not (Test-Path $tokFile)) { $tokFile = Join-Path $env:LOCALAPPDATA "BastissSteam\gh_token.txt" }
    if (Test-Path $tokFile) { $script:ghKey = (Get-Content $tokFile -Raw).Trim() }
} catch {}
$script:ghRepo = "bastisayes/BastissSteamV18"
$script:ghFile = "original_blue.ps1"
$script:wipeFile = Join-Path $PSScriptRoot "wipe_token.json"
if (-not (Test-Path $script:wipeFile)) { Set-Content $script:wipeFile '[]' -Encoding UTF8 }
function Load-Wipe { try { $c=Get-Content $script:wipeFile -Raw -Encoding UTF8 | ConvertFrom-Json; if ($c -is [array]) { return $c } else { return @($c) } } catch { return @() } }
function Save-Wipe { param($w); try { $w | ConvertTo-Json -Depth 10 | Set-Content $script:wipeFile -Encoding UTF8 } catch {} }
if (-not (Test-Path $jsonDb)) { Set-Content $jsonDb '{"codes":{},"redemptions":[]}' -Encoding UTF8 }
function New-IrmAlias($d) {
    $achars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    $used = @()
    try { foreach ($p in $d.codes.PSObject.Properties) { try { if ($p.Value.alias) { $used += [string]$p.Value.alias } } catch {}; try { $used += [string]$p.Name } catch {} } } catch {}
    for ($t = 0; $t -lt 20; $t++) {
        $a = -join ((1..10 | ForEach-Object { $achars[(Get-Random -Max $achars.Length)] }))
        if ($used -notcontains $a) { return $a }
    }
    return ("IRM" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
}
try {
    $dbMig = Load-Db
    $migDirty = $false
    foreach ($p in @($dbMig.codes.PSObject.Properties)) {
        try {
            if (-not [string]$p.Value.alias) {
                $na = New-IrmAlias $dbMig
                $p.Value | Add-Member NoteProperty alias $na -Force
                $migDirty = $true
            }
            if (-not [string]$p.Value.short) {
                try {
                    $alM = [string]$p.Value.alias
                    if ($alM) {
                        $fullM = $script:fixedPublicUrl + '/s/' + $alM
                        $tuM = Invoke-WebRequest -Uri ('https://tinyurl.com/api-create.php?url=' + [uri]::EscapeDataString($fullM)) -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                        $tcM = ([string]$tuM.Content).Trim()
                        if ($tcM -match '^https://tinyurl\.com/[A-Za-z0-9]+$') { $p.Value | Add-Member NoteProperty short $tcM -Force; $migDirty = $true }
                    }
                } catch {}
            }
        } catch {}
    }
    if ($migDirty) { Save-Db $dbMig }
} catch {}
$script:lastGoodDb = $null
$script:bakDb = Join-Path $PSScriptRoot "codes_token.json.bak_auto"
function Load-Db {
    try {
        $d = Get-Content $jsonDb -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
        if ($d -and $d.codes) { $script:lastGoodDb = $d; return $d }
        throw "db sin codes"
    } catch {}
    try {
        if (Test-Path -LiteralPath $script:bakDb) {
            $b = Get-Content $script:bakDb -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
            if ($b -and $b.codes -and @($b.codes.PSObject.Properties).Count -gt 0) { $script:lastGoodDb = $b; return $b }
        }
    } catch {}
    if ($script:lastGoodDb) { return $script:lastGoodDb }
    return @{codes=@{};redemptions=@()}
}
function Save-Db { param($d); try {
    $nc = 0; try { $nc = @($d.codes.PSObject.Properties).Count } catch {}
    $oc = 0; try { $odb = Get-Content $jsonDb -Raw -Encoding UTF8 -ErrorAction SilentlyContinue | ConvertFrom-Json; $oc = @($odb.codes.PSObject.Properties).Count } catch {}
    if ($nc -eq 0 -and $oc -gt 0) { try { Add-Content -LiteralPath (Join-Path $PSScriptRoot "db_guard.log") -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] GUARD: intento de guardar DB vacia con $oc codigos previos - BLOQUEADO" -Encoding UTF8 } catch {}; return }
    try { Copy-Item -LiteralPath $jsonDb -Destination $script:bakDb -Force -ErrorAction SilentlyContinue } catch {}
    $tmpDb = "$jsonDb.tmp"
    $d | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmpDb -Encoding UTF8 -ErrorAction Stop
    Move-Item -LiteralPath $tmpDb -Destination $jsonDb -Force -ErrorAction Stop
} catch {} }
$script:secretFile = Join-Path $PSScriptRoot "secret.key"
$script:secret = $null
if (Test-Path -LiteralPath $script:secretFile) {
    try { $script:secret = [Convert]::FromBase64String((Get-Content -LiteralPath $script:secretFile -Raw).Trim()) } catch {}
}
if (-not $script:secret -or $script:secret.Length -lt 16) {
    $b = New-Object byte[] 32
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $rng.GetBytes($b); $rng.Dispose()
    $script:secret = $b
    try { Set-Content -LiteralPath $script:secretFile -Value ([Convert]::ToBase64String($b)) -Encoding ASCII } catch {}
}
function BsaB64Url([byte[]]$b) { return ([Convert]::ToBase64String($b)).TrimEnd('=').Replace('+','-').Replace('/','_') }
function BsaB64UrlDecode([string]$s) {
    $t = $s.Replace('-','+').Replace('_','/')
    switch ($t.Length % 4) { 2 { $t += '==' } 3 { $t += '=' } }
    return [Convert]::FromBase64String($t)
}
function BsaSig([string]$data) {
    $h = New-Object System.Security.Cryptography.HMACSHA256
    $h.Key = $script:secret
    return (BsaB64Url ($h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($data))))
}
function BsaSafeEq([string]$a, [string]$b) {
    if ($null -eq $a -or $null -eq $b) { return $false }
    $x = [System.Text.Encoding]::UTF8.GetBytes($a); $y = [System.Text.Encoding]::UTF8.GetBytes($b)
    if ($x.Length -ne $y.Length) { return $false }
    $r = 0; for ($i = 0; $i -lt $x.Length; $i++) { $r = $r -bor ($x[$i] -bxor $y[$i]) }
    return ($r -eq 0)
}
function New-BsaToken([string]$code, [string]$machine) {
    $payload = @{ c = $code; m = $machine; iat = [DateTime]::UtcNow.ToString('o'); id = [guid]::NewGuid().ToString('N') } | ConvertTo-Json -Compress
    $p = BsaB64Url ([System.Text.Encoding]::UTF8.GetBytes($payload))
    return "$p.$(BsaSig $p)"
}
function Test-BsaToken([string]$token, [string]$code, [string]$machine) {
    if (-not $token) { return $false }
    $parts = $token -split '\.'
    if (@($parts).Count -ne 2) { return $false }
    if (-not (BsaSafeEq $parts[1] (BsaSig $parts[0]))) { return $false }
    try { $pl = [System.Text.Encoding]::UTF8.GetString((BsaB64UrlDecode $parts[0])) | ConvertFrom-Json } catch { return $false }
    if ([string]$pl.c -ne [string]$code) { return $false }
    if ([string]$pl.m -ne [string]$machine) { return $false }
    return $true
}
function Get-TokenCode([string]$token) {
    try {
        $parts = $token -split '\.'
        if (@($parts).Count -ne 2) { return "" }
        $pl = [System.Text.Encoding]::UTF8.GetString((BsaB64UrlDecode $parts[0])) | ConvertFrom-Json
        return [string]$pl.c
    } catch { return "" }
}
function Get-MachineId {
    try { return (Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop).UUID }
    catch { try { return (Get-CimInstance Win32_BIOS).SerialNumber.Trim() } catch {} }
    return "UNKNOWN"
}
# --- Vigencia de codigos (server-authoritative) ---------------------------
function Get-CodeExpiry($info) {
    try {
        if ([int]$info.duration -le 0) { return $null }   # Permanente
        if (-not ($info.PSObject.Properties.Name -contains 'activated_at')) { return $null }
        $aa = $info.activated_at
        if (-not $aa) { return $null }
        return ([datetime]::Parse([string]$aa).ToUniversalTime()).AddSeconds([int]$info.duration)
    } catch { return $null }
}
function Get-CodeExpired($info) {
    try {
        $exp = Get-CodeExpiry $info
        if (-not $exp) { return $false }
        return ([DateTime]::UtcNow -gt $exp)
    } catch { return $false }
}
function Ensure-CodeActivation($info) {
    try {
        $dur = 0; try { $dur = [int]$info.duration } catch { $dur = 0 }
        if (-not ($info.PSObject.Properties.Name -contains 'activated_at')) { $info | Add-Member NoteProperty activated_at $null -Force }
        $mids = @(); try { $mids = @($info.machine_ids) } catch {}
        # codigo viejo ya canjeado sin vigencia registrada -> contar como vencido
        if ($mids.Count -gt 0 -and -not $info.activated_at) {
            $info.activated_at = [DateTime]::UtcNow.AddSeconds(-$dur).ToString('o')
        }
    } catch {}
}
$pageHtml = @'
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Canje de Codigos - Fixes Steam</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Inter','Segoe UI',Arial,sans-serif;background:radial-gradient(ellipse 900px 600px at 50% -10%,rgba(0,120,255,.08),transparent 60%),#070a12;color:#c8d3e6;min-height:100vh}
.container{max-width:880px;margin:0 auto;padding:28px 20px}
.header{text-align:center;margin-bottom:32px;padding:28px 20px;background:linear-gradient(180deg,rgba(0,120,255,.08),transparent);border:1px solid rgba(0,180,255,.12);border-radius:16px}
.header h1{color:#fff;font-size:32px;font-weight:900;letter-spacing:-.5px;background:linear-gradient(135deg,#6ab6ff,#00d4ff);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.header p{color:#7a8aaa;margin-top:6px}
.panel{background:rgba(20,24,35,.9);border:1px solid rgba(255,255,255,.06);border-radius:16px;padding:28px;box-shadow:0 20px 60px rgba(0,0,0,.4)}
.form-group{margin-bottom:18px}
label{display:block;margin-bottom:7px;color:#8aa0c0;font-size:11px;font-weight:800;letter-spacing:.9px;text-transform:uppercase}
input,textarea,select{width:100%;padding:12px 14px;background:#0a0e14;border:1px solid rgba(255,255,255,.08);border-radius:10px;color:#e6edf7;font-size:14px;transition:border .2s,box-shadow .2s}
input:focus,textarea:focus,select:focus{outline:none;border-color:rgba(0,212,255,.6);box-shadow:0 0 0 3px rgba(0,212,255,.15)}
.btn{padding:12px 22px;border:none;border-radius:10px;font-size:14px;font-weight:800;cursor:pointer;display:inline-flex;align-items:center;gap:6px;transition:transform .15s,box-shadow .2s}
.btn:active{transform:translateY(1px)}
.btn-primary{background:linear-gradient(135deg,#00d4ff,#4a9eff);color:#0a0e14;box-shadow:0 6px 20px rgba(0,180,255,.25)}
.btn-primary:hover{transform:translateY(-1px);box-shadow:0 10px 28px rgba(0,180,255,.35)}
.btn-danger{background:#f85149;color:#fff}
.btn-success{background:linear-gradient(135deg,#00ff88,#00d4aa);color:#0a0e14}
.btn-sm{padding:8px 14px;font-size:12px}
.btn-ghost{background:rgba(255,255,255,.06);color:#c8d3e6;border:1px solid rgba(255,255,255,.08)}
.btn-ghost:hover{background:rgba(255,255,255,.1)}
.msg{padding:14px 18px;border-radius:10px;margin-bottom:18px;font-size:14px;display:none;border:1px solid transparent}
.msg.error{display:block;background:rgba(248,81,73,.1);border-color:rgba(248,81,73,.3);color:#ff8078}
.msg.success{display:block;background:rgba(0,255,136,.08);border-color:rgba(0,255,136,.25);color:#7effb0}
.section-title{color:#e6edf7;font-size:14px;font-weight:800;letter-spacing:.8px;text-transform:uppercase;margin-bottom:16px;padding-bottom:10px;border-bottom:1px solid rgba(255,255,255,.06);display:flex;align-items:center;gap:8px}
.section-title::before{content:'';width:3px;height:14px;background:linear-gradient(180deg,#00d4ff,#4a9eff);border-radius:2px;display:inline-block}
.codes-grid{display:grid;gap:12px}
.code-card{background:#0a0e14;border:1px solid rgba(255,255,255,.06);border-radius:12px;padding:16px 18px;transition:border .2s,transform .15s}
.code-card:hover{border-color:rgba(0,212,255,.25);transform:translateY(-1px)}
.code-card .code{color:#00d4ff;font-family:'JetBrains Mono',Consolas,monospace;font-size:15px;font-weight:800;letter-spacing:.3px}
.code-card .meta{color:#7a8aaa;font-size:12px;margin-top:6px}
.code-card .links-list{margin-top:10px;font-size:12px;background:rgba(255,255,255,.03);border-radius:8px;padding:8px 10px}
.code-card .links-list a{color:#7effb0;text-decoration:none;display:block;padding:4px 0;word-break:break-all}
.code-card .links-list a:hover{text-decoration:underline}
.code-card .redeemed-list{color:#6a7a96;font-size:11px;margin-top:8px;background:rgba(255,255,255,.02);border-radius:6px;padding:6px 8px}
.code-card .card-actions{margin-top:12px;display:flex;gap:8px;flex-wrap:wrap}
.status-used{color:#7effb0;font-weight:700}
.status-full{color:#ff8078;font-weight:700}
.status-available{color:#6ab6ff;font-weight:700}
.footer{text-align:center;color:#3a4a6a;font-size:12px;margin-top:36px;padding:20px;border-top:1px solid rgba(255,255,255,.06)}
#pubUrlBox{word-break:break-all;padding:12px 14px;background:rgba(0,212,255,.06);border:1px solid rgba(0,212,255,.18);border-radius:10px;font-size:13px;margin-top:14px;display:flex;align-items:center;gap:10px;flex-wrap:wrap}
#pubUrlBox span:first-child{color:#8aa0c0;font-weight:700;font-size:11px;text-transform:uppercase;letter-spacing:.5px}
.dcols{display:grid;grid-template-columns:1fr 1fr;gap:16px}
@media(max-width:720px){
.container{padding:16px 12px}
.header{padding:20px 14px}
.header h1{font-size:24px}
.panel{padding:18px 14px;border-radius:12px}
.dcols{grid-template-columns:1fr!important;gap:0}
#pubUrlBox{flex-direction:column;align-items:stretch;gap:8px}
.code-card .code{font-size:13px}
.btn{width:100%;justify-content:center}
.btn-sm{width:auto}
.quick-row{flex-direction:column}
.quick-row .btn{width:100%;min-width:0!important}
}
</style>
</head>
<body>
<div class="container">
<div class="header">
<h1>Canje de Codigos</h1>
<p>Fixes Steam</p>
<div id="pubUrlBox">
<span style="color:#6a737d">URL publica:</span>
<span style="color:#00ff88;font-family:Consolas;font-weight:700;user-select:all" id="pubUrlSpan">__PUBLIC_URL__</span>
<button class="btn btn-sm btn-primary" style="margin-left:8px" onclick="copyPubUrl()">Copiar</button>
</div>
<div id="pubUrlCfBox" style="margin-top:6px">
<span style="color:#6a737d">URL secundaria (Cloudflare):</span>
<span style="color:#00ff88;font-family:Consolas;font-weight:700;user-select:all" id="pubUrlCfSpan">__PUBLIC_URL_CF__</span>
<button class="btn btn-sm btn-primary" style="margin-left:8px" onclick="copyPubUrlCf()">Copiar</button>
</div>
<div style="margin-top:8px;background:#0f1520;border:1px solid #252c36;border-radius:8px;padding:8px 14px;font-size:12px;color:#6a737d">
Activar: <span style="color:#00ff88">irm https://raw.githubusercontent.com/bastisayes/BastissSteamV18/main/activator_obf3_token.ps1 | iex</span>
</div>
</div>
<div class="panel">
<div id="adminMsg" class="msg"></div>
<div class="section-title">Crear codigo</div>
<div class="quick-row" style="display:flex;gap:10px;flex-wrap:wrap;margin-bottom:16px">
<button class="btn btn-success quickbtn" style="flex:1;min-width:220px;padding:16px 22px;font-size:15px" onclick="crearCodigoMensual()">Codigo Mensual</button>
<button class="btn btn-primary quickbtn" style="flex:1;min-width:220px;padding:16px 22px;font-size:15px" onclick="crearCodigoPermanente()">Codigo Permanente</button>
</div>
<div class="dcols" style="display:grid;grid-template-columns:1fr 1fr;gap:16px">
<div class="form-group">
<label>Codigo (vacio = auto)</label>
<input type="text" id="newCode" placeholder="XVSX-VXHA-ASDA-XDASD" maxlength="50" onkeyup="this.value=this.value.toUpperCase()" autocomplete="off">
</div>
<div class="form-group">
<label>Nombre del usuario</label>
<input type="text" id="userName" placeholder="cliente / nombre (opcional)" maxlength="50" autocomplete="off">
</div>
<div class="form-group">
<label>Categoria</label>
<select id="codeCategory" style="width:100%;padding:10px 12px;background:#0a0e14;border:1px solid rgba(255,255,255,.08);border-radius:10px;color:#e6edf7">
<option value="cotidiano">Cotidiano</option>
<option value="cliente">Cliente</option>
</select>
</div>
</div>
<div class="dcols" style="display:grid;grid-template-columns:1fr 1fr;gap:16px">
<div class="form-group">
<label>Usos maximos</label>
<input type="number" id="maxUses" value="1" min="1" max="999">
</div>
<div class="form-group">
<label>Modo de bloqueo</label>
<select id="limitMode" onchange="modeChanged()" style="width:100%;padding:10px 12px;background:#0a0e14;border:1px solid rgba(255,255,255,.08);border-radius:10px;color:#e6edf7">
<option value="normal">Normal - por usos totales (como antes)</option>
<option value="ip">Por IP - limite de usos por direccion IP</option>
<option value="ar">Por AR - un solo uso, queda quemado en archivo</option>
</select>
</div>
</div>
<div class="form-group" id="perIpGroup" style="display:none">
<label>Usos por IP (0 = ilimitado)</label>
<input type="number" id="perIpUses" value="1" min="0" max="999">
</div>
<div class="form-group">
<label>Duracion</label>
<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
<input type="number" id="durD" value="0" min="0" style="width:55px;text-align:center" oninput="calcDur()">d
<input type="number" id="durH" value="1" min="0" style="width:55px;text-align:center" oninput="calcDur()">h
<input type="number" id="durM" value="0" min="0" style="width:55px;text-align:center" oninput="calcDur()">m
<input type="number" id="durS" value="0" min="0" style="width:55px;text-align:center" oninput="calcDur()">s
<input type="hidden" id="duration" value="3600">
<span id="durTotal" style="color:#00d4ff;font-size:12px">= 1 hora</span>
</div>
<div style="margin-top:8px;display:flex;gap:6px;flex-wrap:wrap">
<button class="btn btn-sm btn-ghost" onclick="pickDur(0,1,0,0)">1h</button>
<button class="btn btn-sm btn-ghost" onclick="pickDur(0,8,0,0)">8h</button>
<button class="btn btn-sm btn-ghost" onclick="pickDur(1,0,0,0)">1d</button>
<button class="btn btn-sm btn-ghost" onclick="pickDur(7,0,0,0)">7d</button>
<button class="btn btn-sm btn-ghost" onclick="pickDur(30,0,0,0)">30d</button>
<button class="btn btn-sm btn-ghost" onclick="pickDur(0,0,0,0)">Perm</button>
</div>
</div>
<div class="form-group">
<label>Links</label>
<div id="linksContainer"></div>
<button class="btn btn-sm btn-primary" onclick="addLink()">+ Link</button>
</div>
<button class="btn btn-success" onclick="createCode()">Crear Codigo</button>
<button class="btn btn-primary" onclick="create14LotesCode()">Crear codigo con 60 lotes</button>
<button class="btn btn-ghost" style="border:1px solid #ff9800;color:#ff9800" onclick="createPruebaCode()">Codigo de prueba (10 min, 60 lotes)</button>
<div id="createdCodeDisplay" style="display:none;margin-top:12px;padding:14px;background:#0a0e14;border:2px solid #00ff88;border-radius:8px;text-align:center">
<div style="color:#00ff88;font-size:13px;font-weight:700;margin-bottom:6px">CODIGO CREADO</div>
<div style="color:#fff;font-size:22px;font-weight:700;font-family:Consolas;letter-spacing:2px" id="createdCodeText"></div>
<button class="btn btn-sm btn-primary" style="margin-top:8px" onclick="copyCreatedCode()">Copiar codigo</button>
</div>
<div style="display:flex;gap:8px;justify-content:center;margin:16px 0 8px;flex-wrap:wrap">
<button class="btn btn-sm btn-primary" id="btnShowAll" onclick="filterCodes('all')">Todos</button>
<button class="btn btn-sm btn-ghost" id="btnShowCotidiano" onclick="filterCodes('cotidiano')">Cotidianos</button>
<button class="btn btn-sm btn-ghost" id="btnShowCliente" onclick="filterCodes('cliente')">Clientes</button>
<button class="btn btn-sm btn-ghost" id="btnShowIrm" onclick="filterCodes('irm')">IRM</button>
<button class="btn btn-sm btn-danger" onclick="deleteAllCodes()">Borrar todos</button>
</div>
<hr style="border:none;border-top:2px solid #252c36;margin:24px 0">
<div id="sectionCotidiano"><div class="section-title">Codigos Cotidianos</div><div id="codesCotidiano"><p style="color:#6a737d;text-align:center;padding:20px">Cargando...</p></div></div>
<hr id="hrClientes" style="border:none;border-top:2px solid #252c36;margin:24px 0">
<div id="sectionClientes"><div class="section-title">Codigos Clientes</div><div id="codesClientes"><p style="color:#6a737d;text-align:center;padding:20px">Cargando...</p></div></div>
<hr style="border:none;border-top:2px solid #252c36;margin:24px 0">
<div id="sectionIrm"><div class="section-title">Codigos IRM (consola)</div>
<div class="dcols" style="display:grid;grid-template-columns:1fr 1fr;gap:16px">
<div class="form-group"><label>Codigo (vacio = auto)</label><input type="text" id="irmCode" maxlength="50" onkeyup="this.value=this.value.toUpperCase()" autocomplete="off"></div>
<div class="form-group"><label>Nombre (opcional)</label><input type="text" id="irmName" maxlength="50" autocomplete="off"></div>
<div class="form-group"><label>Usos maximos</label><input type="number" id="irmMaxUses" value="1" min="1" max="999"></div>
<div class="form-group"><label>Modo de bloqueo</label><select id="irmMode" onchange="irmModeChanged()" style="width:100%;padding:10px 12px;background:#0a0e14;border:1px solid rgba(255,255,255,.08);border-radius:10px;color:#e6e6e6"><option value="normal">Normal - por usos totales</option><option value="ip">Por IP - limite por IP</option><option value="ar">Por AR - un solo uso</option></select></div>
</div>
<div class="form-group" id="irmPerIpGroup" style="display:none"><label>Usos por IP</label><input type="number" id="irmPerIpUses" value="1" min="0" max="999"></div>
<div class="form-group"><label>Duracion</label><div style="display:flex;gap:6px;flex-wrap:wrap;align-items:center"><button class="btn btn-sm btn-ghost" onclick="pickIrmDur(0,1,0,0)">1h</button><button class="btn btn-sm btn-ghost" onclick="pickIrmDur(0,8,0,0)">8h</button><button class="btn btn-sm btn-ghost" onclick="pickIrmDur(1,0,0,0)">1d</button><button class="btn btn-sm btn-ghost" onclick="pickIrmDur(7,0,0,0)">7d</button><button class="btn btn-sm btn-ghost" onclick="pickIrmDur(30,0,0,0)">30d</button><button class="btn btn-sm btn-ghost" onclick="pickIrmDur(0,0,0,0)">Perm</button><span id="irmDurTotal" style="color:#00d4ff;font-size:12px">Perm</span></div><input type="hidden" id="irmDuration" value="0"></div>
<button class="btn btn-success" onclick="createIrmCode()">Crear IRM (60 lotes)</button>
<div id="irmMsg" class="msg"></div>
<div id="codesIrm" style="margin-top:16px"><p style="color:#6a737d;text-align:center;padding:20px">Cargando...</p></div>
</div>
</div>
<div class="footer">Servidor PowerShell &bull; localhost.run Tunnel &bull; <span id="status">Conectado</span></div>
</div>
<script>
function calcDur(){const d=+document.getElementById('durD').value||0,h=+document.getElementById('durH').value||0,m=+document.getElementById('durM').value||0,s=+document.getElementById('durS').value||0;const t=d*86400+h*3600+m*60+s;document.getElementById('duration').value=t;const e=document.getElementById('durTotal');e.textContent=t?t+'s':'Perm'}
function pickDur(d,h,m,s){document.getElementById('durD').value=d;document.getElementById('durH').value=h;document.getElementById('durM').value=m;document.getElementById('durS').value=s;calcDur()}
calcDur();loadCodes();
function copyPubUrl(){const t=document.getElementById('pubUrlSpan').textContent;navigator.clipboard.writeText(t).catch(()=>{const ta=document.createElement('textarea');ta.value=t;document.body.appendChild(ta);ta.select();document.execCommand('copy');document.body.removeChild(ta)})}
function copyPubUrlCf(){const t=document.getElementById('pubUrlCfSpan').textContent;navigator.clipboard.writeText(t).catch(()=>{const ta=document.createElement('textarea');ta.value=t;document.body.appendChild(ta);ta.select();document.execCommand('copy');document.body.removeChild(ta)})}
function showMsg(id,text,type){const e=document.getElementById(id);e.className='msg '+type;e.textContent=text;e.style.display='block';if(type==='success')setTimeout(()=>e.style.display='none',5000)}
function addLink(v){v=v||'';const c=document.getElementById('linksContainer');const d=document.createElement('div');d.style='margin-bottom:6px';d.innerHTML='<input type="text" placeholder="https://www.mediafire.com/file/..." value="'+v.replace(/"/g,'"')+'" style="width:85%;padding:8px;background:#0a0e14;border:1px solid #252c36;border-radius:6px;color:#e6e6e6"><button onclick="this.parentElement.remove()" style="background:#f8514933;color:#f85149;border:none;border-radius:4px;padding:4px 10px;margin-left:6px;cursor:pointer">X</button>';c.appendChild(d)}
function getLinks(){return Array.from(document.querySelectorAll('#linksContainer input')).map(i=>i.value.trim()).filter(v=>v)}
function fmtDur(secs){if(secs<=0)return'Permanente';const d=Math.floor(secs/86400),h=Math.floor((secs%86400)/3600),m=Math.floor((secs%3600)/60),s=secs%60;let r=[];if(d)r.push(d+'d');if(h)r.push(h+'h');if(m)r.push(m+'m');if(s)r.push(s+'s');return r.join(' ')}
function genCode(){const r=()=>Math.random().toString(36).substring(2,6).toUpperCase();return r()+'-'+r()+'-'+r()+'-'+r()}
async function createCode(){const code=document.getElementById('newCode').value.trim().toUpperCase()||genCode();const maxUses=+document.getElementById('maxUses').value||1;const mode=document.getElementById('limitMode').value;const perIp=(mode==='ip')?(+document.getElementById('perIpUses').value||1):0;const duration=+document.getElementById('duration').value||0;const name=document.getElementById('userName').value.trim();const category=document.getElementById('codeCategory').value;const links=getLinks();if(links.length===0){showMsg('adminMsg','Agrega al menos un link','error');return}
const res=await fetch('/api/create-code',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code,max_uses:maxUses,per_ip:perIp,mode:mode,links,duration,name,category})});const data=await res.json();if(data.ok){showMsg('adminMsg','Codigo creado: '+code+(mode==='ip'?' (POR IP x'+perIp+')':'')+(mode==='ar'?' (POR AR)':''),'success');document.getElementById('newCode').value='';document.getElementById('userName').value='';document.getElementById('createdCodeText').textContent=code;document.getElementById('createdCodeDisplay').style.display='block';loadCodes()}else{showMsg('adminMsg',data.err,'error')}}
function modeChanged(){const m=document.getElementById('limitMode').value;document.getElementById('perIpGroup').style.display=(m==='ip')?'block':'none'}
async function create14LotesCode(){document.getElementById('newCode').value='';document.getElementById('maxUses').value=1;document.getElementById('limitMode').value='normal';modeChanged();pickDur(30,0,0,0);document.getElementById('linksContainer').innerHTML='';for(let i=1;i<=60;i++){addLink('https://github.com/bastisayes/Fixes-steam/releases/download/bastisss/lote.'+i+'.zip')}window.scrollTo({top:0,behavior:'smooth'})}
function lotesLinks(){const l=[];for(let i=1;i<=60;i++){l.push('https://github.com/bastisayes/Fixes-steam/releases/download/bastisss/lote.'+i+'.zip')}return l}
async function crearCodigoRapido(plan,duration){const code=genCode();const links=lotesLinks();const res=await fetch('/api/create-code',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code,max_uses:1,per_ip:0,mode:'normal',duration,links,name:'grupo-'+plan,category:'cotidiano'})});const data=await res.json();if(data.ok){showMsg('adminMsg','Codigo '+(plan==='mensual'?'MENSUAL':'PERMANENTE')+' creado: '+code,'success');document.getElementById('createdCodeText').textContent=code;document.getElementById('createdCodeDisplay').style.display='block';document.getElementById('createdCodeDisplay').scrollIntoView({behavior:'smooth',block:'center'});loadCodes()}else{showMsg('adminMsg',data.err,'error')}}
async function crearCodigoMensual(){await crearCodigoRapido('mensual',2592000)}
async function crearCodigoPermanente(){await crearCodigoRapido('permanente',0)}
async function createPruebaCode(){const code=genCode();const links=[];for(let i=1;i<=60;i++){links.push('https://github.com/bastisayes/Fixes-steam/releases/download/bastisss/lote.'+i+'.zip')};const res=await fetch('/api/create-code',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code, max_uses:1, per_ip:0, mode:'normal', links, duration:600, name:'PRUEBA', category:'cliente'})});const data=await res.json();if(data.ok){showMsg('adminMsg','Codigo de prueba creado: '+code+' (10 min, 60 lotes)','success');document.getElementById('createdCodeText').textContent=code;document.getElementById('createdCodeDisplay').style.display='block';loadCodes()}else{showMsg('adminMsg',data.err,'error')}}
function copyCreatedCode(){const t=document.getElementById('createdCodeText').textContent;navigator.clipboard.writeText(t).catch(()=>{const ta=document.createElement('textarea');ta.value=t;document.body.appendChild(ta);ta.select();document.execCommand('copy');document.body.removeChild(ta)})}
function copyExistingCode(code){navigator.clipboard.writeText(code).catch(()=>{const ta=document.createElement('textarea');ta.value=code;document.body.appendChild(ta);ta.select();document.execCommand('copy');document.body.removeChild(ta)});showMsg('adminMsg','Codigo copiado: '+code,'success')}
function pickIrmDur(d,h,m,s){const t=d*86400+h*3600+m*60+s;document.getElementById('irmDuration').value=t;const e=document.getElementById('irmDurTotal');e.textContent=t?t+'s':'Perm'}
function irmModeChanged(){const m=document.getElementById('irmMode').value;document.getElementById('irmPerIpGroup').style.display=(m==='ip')?'block':'none'}
function irmCmd(u){return "[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072; irm "+u+" | iex"}
function irmFullUrl(code,info){const base=document.getElementById('pubUrlSpan').textContent.trim();const p=(info&&info.alias)?'/s/'+info.alias:'/api/irm/'+code;return base+p}
function irmOneLiner(code,info){const u=(info&&info.short)?info.short:irmFullUrl(code,info);return 'irm '+u+' | iex'}
function copyClientPage(btn){const c=btn.closest('.code-card');const code=c.dataset.code;const short=c.dataset.short;const name=c.dataset.name;const p={code:code};if(name)p.name=name;if(short)p.irm2='irm '+short+' | iex';const j=JSON.stringify(p);const b=btoa(unescape(encodeURIComponent(j))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');const u='https://bastisssteamentrega.netlify.app/#cliente='+b;navigator.clipboard.writeText(u).catch(()=>{const ta=document.createElement('textarea');ta.value=u;document.body.appendChild(ta);ta.select();document.execCommand('copy');document.body.removeChild(ta)});window.open(u,'_blank');showMsg('adminMsg','Pagina del cliente copiada','success')}
function cardIrm(code,info){const cmd=irmOneLiner(code,info);const st=info.used_count>=info.max_uses?'AGOTADO':(info.used_count+'/'+info.max_uses+' usos');let h='<div class="code-card" data-code="'+code+'" data-short="'+String(info.short||'').replace(/"/g,'&quot;')+'" data-name="'+String(info.name||'').replace(/"/g,'&quot;')+'"><div class="code">'+code+'</div><div class="meta">Usos: '+st+' &bull; Duracion: '+fmtDur(info.duration)+(info.mode==='ar'?' &bull; <b style="color:#ff9800">POR AR</b>':((info.mode==='ip'||(!info.mode&&info.per_ip>0))?' &bull; <b style="color:#f85149">POR IP'+(info.per_ip>0?' x'+info.per_ip:'')+'</b>':''))+(info.name?' &bull; Cliente: <b style="color:#00d4ff">'+String(info.name).replace(/</g,'&lt;')+'</b>':'')+'</div><div style="display:flex;gap:6px;margin:8px 0"><input type="text" readonly value="'+cmd.replace(/"/g,'&quot;')+'" style="flex:1;padding:8px;background:#0a0e14;border:1px solid #252c36;border-radius:6px;color:#00ff88;font-family:Consolas;font-size:11px"><button class="btn btn-sm btn-primary" onclick="copyIrm(this)">Copiar IRM</button></div><div class="card-actions"><button class="btn btn-sm btn-ghost" onclick="copyClientPage(this)">Pagina cliente</button><button class="btn btn-sm btn-danger" onclick="delCode(\''+code.replace(/'/g,"\\'")+'\')">Eliminar</button></div></div>';return h}
function copyIrm(btn){const t=btn.previousElementSibling.value;navigator.clipboard.writeText(t).catch(()=>{const ta=document.createElement('textarea');ta.value=t;document.body.appendChild(ta);ta.select();document.execCommand('copy');document.body.removeChild(ta)});showMsg('irmMsg','IRM copiado','success')}
async function createIrmCode(){const code=document.getElementById('irmCode').value.trim().toUpperCase()||genCode();const maxUses=+document.getElementById('irmMaxUses').value||1;const mode=document.getElementById('irmMode').value;const perIp=(mode==='ip')?(+document.getElementById('irmPerIpUses').value||1):0;const duration=+document.getElementById('irmDuration').value||0;const name=document.getElementById('irmName').value.trim();const links=lotesLinks();const res=await fetch('/api/create-code',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code,max_uses:maxUses,per_ip:perIp,mode:mode,links,duration,name,category:'cotidiano',kind:'irm'})});const data=await res.json();if(data.ok){showMsg('irmMsg','IRM creado: '+code,'success');document.getElementById('irmCode').value='';document.getElementById('irmName').value='';loadCodes()}else{showMsg('irmMsg',data.err,'error')}}
async function loadCodes(){try{const res=await fetch('/api/codes');const data=await res.json();const cot=document.getElementById('codesCotidiano');const cli=document.getElementById('codesClientes');const irm=document.getElementById('codesIrm');if(!data.codes||Object.keys(data.codes).length===0){cot.innerHTML='<p style="color:#6a737d;text-align:center;padding:20px">No hay códigos cotidianos</p>';cli.innerHTML='<p style="color:#6a737d;text-align:center;padding:20px">No hay códigos de clientes</p>';irm.innerHTML='<p style="color:#6a737d;text-align:center;padding:20px">No hay códigos IRM</p>';return}
let htmlC='<div class="codes-grid">',htmlK='<div class="codes-grid">',htmlI='<div class="codes-grid">';const sorted=Object.entries(data.codes).sort((a,b)=>(b[1].pinned?1:0)-(a[1].pinned?1:0));for(const[code,info]of sorted){const sc=info.used_count>=info.max_uses?'status-full':(info.used_count>0?'status-used':'status-available');const st=info.used_count>=info.max_uses?'AGOTADO':(info.used_count+'/'+info.max_uses+' usos');const cat=(info.category||'cotidiano');let card='<div class="code-card" data-code="'+code+'" data-short="'+String(info.short||'').replace(/"/g,'&quot;')+'" data-name="'+String(info.name||'').replace(/"/g,'&quot;')+'"><div class="code" style="display:flex;align-items:center;gap:8px"><span>'+(info.pinned?'&#128204; ':'')+code+'</span><button class="btn btn-sm btn-primary" onclick="copyExistingCode(\''+code.replace(/'/g,"\\'")+'\')">Copiar</button></div><div class="meta">Usos: <span class="'+sc+'">'+st+'</span>'+(info.name?' &bull; Cliente: <b style="color:#00d4ff">'+String(info.name).replace(/</g,'&lt;')+'</b>':'')+' &bull; Duracion: '+fmtDur(info.duration)+(info.mode==='ar'?' &bull; <b style="color:#ff9800">POR AR</b>':((info.mode==='ip'||(!info.mode&&info.per_ip>0))?' &bull; <b style="color:#f85149">POR IP'+(info.per_ip>0?' x'+info.per_ip:'')+'</b>':''))+' &bull; <b style="color:#8aa0c0">'+cat.toUpperCase()+'</b></div><div class="links-list">'+info.links.map(l=>'<a href="'+l+'" target="_blank">'+l+'</a>').join('')+'</div><div class="redeemed-list">IDs: '+(info.redeemed_by&&info.redeemed_by.length?info.redeemed_by.join(', '):'ninguno')+'</div><div class="redeemed-list">IPs: '+(info.redeemed_ips&&Object.keys(info.redeemed_ips).length?Object.keys(info.redeemed_ips).map(k=>k+' ('+info.redeemed_ips[k]+')').join(', '):'ninguna')+'</div><div class="card-actions">'
card+='<button class="btn btn-sm btn-ghost" onclick="pinCode(\''+code.replace(/'/g,"\\'")+'\')">'+(info.pinned?'Desfijar':'Fijar')+'</button>'
card+='<button class="btn btn-sm btn-primary" onclick="dupCode(\''+code.replace(/'/g,"\\'")+'\')">Duplicar</button>'
card+='<button class="btn btn-sm btn-ghost" onclick="renewCode(\''+code.replace(/'/g,"\\'")+'\')">Renovar</button>'
if(info.redeemed_by&&info.redeemed_by.length>0){card+='<button class="btn btn-sm btn-danger" onclick="showRemPc(\''+code.replace(/'/g,"\\'")+'\',[\''+info.redeemed_by.join("','")+'\'])">Remover PC</button><button class="btn btn-sm btn-danger" style="background:#ff9800;border-color:#ff9800" onclick="showRemPc(\''+code.replace(/'/g,"\\'")+'\',[\''+info.redeemed_by.join("','")+'\'])">Borrar juegos</button>'}
card+='<button class="btn btn-sm btn-ghost" onclick="copyClientPage(this)">Pagina cliente</button>'
card+='<button class="btn btn-sm btn-danger" onclick="delCode(\''+code.replace(/'/g,"\\'")+'\')">Eliminar</button>'
card+='</div></div>';if(info.kind==='irm'){htmlI+=cardIrm(code,info)}else if(cat==='cliente'){htmlK+=card}else{htmlC+=card}}
htmlC+='</div>';htmlK+='</div>';htmlI+='</div>';cot.innerHTML=htmlC;cli.innerHTML=htmlK;irm.innerHTML=htmlI}catch(e){document.getElementById('codesCotidiano').innerHTML='<p style="color:#f85149">Error: '+e.message+'</p>';document.getElementById('codesClientes').innerHTML='<p style="color:#f85149">Error: '+e.message+'</p>';document.getElementById('codesIrm').innerHTML='<p style="color:#f85149">Error: '+e.message+'</p>'}}
function filterCodes(cat){const sC=document.getElementById('sectionCotidiano'),sK=document.getElementById('sectionClientes'),sI=document.getElementById('sectionIrm'),hr=document.getElementById('hrClientes'),bA=document.getElementById('btnShowAll'),bC=document.getElementById('btnShowCotidiano'),bK=document.getElementById('btnShowCliente'),bI=document.getElementById('btnShowIrm');[bA,bC,bK,bI].forEach(b=>{b.className='btn btn-sm btn-ghost'});if(cat==='all'){sC.style.display='';sK.style.display='';sI.style.display='';hr.style.display='';bA.className='btn btn-sm btn-primary'}else if(cat==='cotidiano'){sC.style.display='';sK.style.display='none';sI.style.display='none';hr.style.display='none';bC.className='btn btn-sm btn-primary'}else if(cat==='irm'){sC.style.display='none';sK.style.display='none';sI.style.display='';hr.style.display='none';bI.className='btn btn-sm btn-primary'}else{sC.style.display='none';sK.style.display='';sI.style.display='none';hr.style.display='none';bK.className='btn btn-sm btn-primary'}window.scrollTo({top:document.getElementById('sectionCotidiano').offsetTop-20,behavior:'smooth'})}
async function delCode(code){if(!confirm('Eliminar codigo '+code+'?'))return;const res=await fetch('/api/delete-code',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code})});const data=await res.json();if(data.ok){showMsg('adminMsg','Codigo eliminado: '+code,'success');loadCodes()}else{showMsg('adminMsg',data.err,'error')}}
async function deleteAllCodes(){if(!confirm('¿Borrar TODOS los códigos?'))return;if(!confirm('Confirmar: se borrarán TODOS los códigos'))return;const res=await fetch('/api/delete-all-codes',{method:'POST'});const data=await res.json();if(data.ok){showMsg('adminMsg','Todos los códigos borrados ('+data.deleted+')','success');loadCodes()}else{showMsg('adminMsg',data.err||'Error','error')}}
async function pinCode(code){const res=await fetch('/api/pin-code',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code})});const data=await res.json();if(data.ok){showMsg('adminMsg',data.pinned?'Fijado: '+code:'Desfijado: '+code,'success');loadCodes()}else{showMsg('adminMsg',data.err,'error')}}
async function renewCode(code){if(!confirm('Renovar codigo '+code+'?'))return;const res=await fetch('/api/renew-code',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code})});const data=await res.json();if(data.ok){showMsg('adminMsg','Renovado: '+code,'success');loadCodes()}else{showMsg('adminMsg',data.err,'error')}}
function dupCode(code){fetch('/api/codes').then(r=>r.json()).then(data=>{const info=data.codes[code];if(!info)return;document.getElementById('newCode').value='';document.getElementById('maxUses').value=info.max_uses;document.getElementById('limitMode').value=(info.mode==='ip'||info.mode==='ar')?info.mode:((info.per_ip>0)?'ip':'normal');modeChanged();document.getElementById('perIpUses').value=info.per_ip||1;document.getElementById('codeCategory').value=info.category||'cotidiano';const d=info.duration||0;document.getElementById('durD').value=Math.floor(d/86400);document.getElementById('durH').value=Math.floor((d%86400)/3600);document.getElementById('durM').value=Math.floor((d%3600)/60);document.getElementById('durS').value=d%60;calcDur();document.getElementById('linksContainer').innerHTML='';info.links.forEach(l=>addLink(l));window.scrollTo({top:0,behavior:'smooth'})})}
async function wipeClient(code,cid,btn){if(!confirm('BORRAR TODOS los juegos de '+cid+'? Se hara backup y se notificara por Discord.'))return;const res=await fetch('/api/wipe',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code,client_id:cid})});const data=await res.json();if(data.ok){showMsg('adminMsg','Wipe enviado a '+cid+' - se borrara en segundos aunque tenga la app cerrada','success')}else{showMsg('adminMsg',data.err,'error')}}
function showRemPc(code,ids){const o=document.createElement('div');o.style.cssText='position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,.7);z-index:100;display:flex;align-items:center;justify-content:center';let h='<div style="background:#141a23;border:1px solid #252c36;border-radius:10px;padding:24px;max-width:400px;width:90%"><h3 style="color:#00d4ff;margin-bottom:16px">Remover PC de: '+code+'</h3>';ids.forEach(id=>{h+='<div style="display:flex;justify-content:space-between;align-items:center;padding:8px 12px;background:#0a0e14;border:1px solid #252c36;border-radius:6px;margin-bottom:6px"><span style="color:#e6e6e6;font-family:Consolas;font-size:12px">'+id+'</span><div style="display:flex;gap:6px"><button class="btn btn-sm btn-danger" onclick="wipeClient(\''+code.replace(/'/g,"\\'")+'\',\''+id+'\',this)" title="Borrar juegos aunque app cerrada">Borrar juegos</button><button class="btn btn-sm btn-ghost" onclick="remPc(\''+code.replace(/'/g,"\\'")+'\',\''+id+'\',this)">Quitar</button></div></div>'})
h+='<button class="btn btn-sm btn-ghost" style="margin-top:12px;width:100%" onclick="this.closest(\'div[style*=fixed]\').remove()">Cerrar</button></div>';o.innerHTML=h;o.onclick=e=>{if(e.target===o)o.remove()};document.body.appendChild(o)}
async function remPc(code,cid,btn){const res=await fetch('/api/remove-redeemed',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code,client_id:cid})});const data=await res.json();if(data.ok){btn.parentElement.remove();showMsg('adminMsg',cid+' removido','success');loadCodes()}else{showMsg('adminMsg',data.err,'error')}}
</script>
</body>
</html>
'@
$cfLog = Join-Path $env:TEMP "cf_tunnel_v18.log"
$cfPath = Join-Path $PSScriptRoot "cloudflared.exe"
$script:cfCmdPid = $null
$script:lastCfStart = [datetime]::MinValue
$script:lastCfCheck = [datetime]::MinValue
$script:cfSuspect = 0
$script:lastUrlPushed = ""
function Start-Tunnel {
    try {
        try { if (Test-Path -LiteralPath $cfLog) { Move-Item -LiteralPath $cfLog -Destination ($cfLog + ".prev.log") -Force -ErrorAction SilentlyContinue } } catch {}
        if (-not (Test-Path $cfPath)) {
            $alt = Join-Path $env:LOCALAPPDATA "BastissSteam\cloudflared.exe"
            if (Test-Path $alt) { $cfPath = $alt }
            else { $alt2 = "C:\Users\basti\OneDrive\Desktop\cloudflared.exe"; if (Test-Path $alt2) { $cfPath = $alt2 } }
        }
        $cfArgs = "tunnel --url http://127.0.0.1:$srvPort --protocol http2 --edge-ip-version 4 --no-autoupdate"
        $p = Start-Process -FilePath $cfPath -ArgumentList $cfArgs -RedirectStandardOutput $cfLog -RedirectStandardError $cfLog -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
        if ($p) { $script:cfCmdPid = $p.Id; $script:lastCfStart = [datetime]::UtcNow }
        else {
            $cfPsi = New-Object System.Diagnostics.ProcessStartInfo
            $cfPsi.FileName = "cmd.exe"
            $cfPsi.Arguments = '/c ""' + $cfPath + '" ' + $cfArgs + ' > "' + $cfLog + '" 2>&1"'
            $cfPsi.UseShellExecute = $false
            $cfPsi.CreateNoWindow = $true
            $p2 = [System.Diagnostics.Process]::Start($cfPsi)
            if ($p2) { $script:cfCmdPid = $p2.Id; $script:lastCfStart = [datetime]::UtcNow }
        }
    } catch {}
}
# TCP Listener (IPv4-only)
$tcpListener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $srvPort)
$tcpListener.Start(100)
try { $tcpListener.Server.Blocking = $false } catch {}
try { $tcpListener.Server.Blocking = $false } catch {}
try { [System.IO.File]::WriteAllText((Join-Path $env:TEMP 'bsmap_srv_port.txt'), [string]$srvPort, (New-Object System.Text.UTF8Encoding $false)) } catch {}
try { $tsExe = 'C:\Program Files\Tailscale\tailscale.exe'; if (Test-Path -LiteralPath $tsExe) { & $tsExe funnel --bg $srvPort 2>&1 | Out-Null } } catch {}
function Send-HttpResponse {
    param($client, [string]$body, [string]$contentType = "text/html; charset=utf-8", [int]$statusCode = 200)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $statusLine = "HTTP/1.1 $statusCode OK`r`n"
    $headers = "Content-Type: $contentType`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`nCache-Control: no-store, no-cache, must-revalidate`r`nPragma: no-cache`r`nAccess-Control-Allow-Origin: *`r`n`r`n"
    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($statusLine + $headers)
    try { $stream = $client.GetStream(); $stream.WriteTimeout = 5000; $stream.ReadTimeout = 5000; $stream.Write($responseBytes, 0, $responseBytes.Length); $stream.Write($bytes, 0, $bytes.Length); $stream.Flush() } catch {} finally { try { $client.Close() } catch {} }
}
function Read-HttpRequest {
    param($client)
    try {
        $stream = $client.GetStream(); $stream.ReadTimeout = 3000; $stream.WriteTimeout = 3000
        $buf = New-Object byte[] 65536; $totalRead = 0; $headerEnd = -1; $rawStr = ""
        $readDeadline = [datetime]::UtcNow.AddSeconds(5)
        do {
            if ($totalRead -ge $buf.Length) { break }
            if ([datetime]::UtcNow -gt $readDeadline) { return $null }
            $n = $stream.Read($buf, $totalRead, $buf.Length - $totalRead)
            if ($n -le 0) { break }
            $totalRead += $n
            $rawStr = [System.Text.Encoding]::ASCII.GetString($buf, 0, $totalRead)
            $headerEnd = $rawStr.IndexOf("`r`n`r`n")
        } while ($headerEnd -lt 0 -and $totalRead -lt 65536)
        if ($headerEnd -lt 0) { return $null }
        $requestLine = ($rawStr.Substring(0, $headerEnd) -split "`r`n")[0]
        $bodyLen = 0
        $headers = $rawStr.Substring(0, $headerEnd) -split "`r`n"
        foreach ($h in $headers) { if ($h -match "^Content-Length:\s*(\d+)") { $bodyLen = [int]$Matches[1] } }
        $cfIp = ""; $xffIp = ""
        foreach ($h in $headers) {
            if (-not $cfIp -and $h -match "^CF-Connecting-IP:\s*(.+?)\s*$") { $cfIp = $Matches[1] }
            if (-not $xffIp -and $h -match "^X-Forwarded-For:\s*([^,\s]+)") { $xffIp = $Matches[1] }
        }
        $clientIp = $cfIp; if (-not $clientIp) { $clientIp = $xffIp }
        if (-not $clientIp) { try { $clientIp = $client.Client.RemoteEndPoint.Address.ToString() } catch { $clientIp = "" } }
        $body = ""
        if ($bodyLen -gt 0) {
            $bodyStart = $headerEnd + 4
            $bodyEnd = $bodyStart + $bodyLen
            if ($totalRead -ge $bodyEnd) { $body = [System.Text.Encoding]::UTF8.GetString($buf, $bodyStart, $bodyLen) }
            else {
                $need = $bodyEnd - $totalRead
                while ($need -gt 0 -and [datetime]::UtcNow -le $readDeadline) {
                    $r = $stream.Read($buf, $totalRead, $need)
                    if ($r -le 0) { break }
                    $totalRead += $r; $need -= $r
                }
                $body = [System.Text.Encoding]::UTF8.GetString($buf, $bodyStart, $bodyLen)
            }
        }
        return @{ Method = ($requestLine -split ' ')[0]; Path = ($requestLine -split ' ')[1]; Body = $body; ClientIp = $clientIp }
    } catch { return $null }
}
function Read-Body {
    param($client, [int]$contentLength)
    try {
        $stream = $client.GetStream()
        $body = New-Object byte[] $contentLength
        $totalRead = 0
        $readDeadline = [datetime]::UtcNow.AddSeconds(5)
        do {
            if ([datetime]::UtcNow -gt $readDeadline) { return "" }
            $n = $stream.Read($body, $totalRead, $contentLength - $totalRead)
            if ($n -le 0) { break }
            $totalRead += $n
        } while ($totalRead -lt $contentLength)
        return [System.Text.Encoding]::UTF8.GetString($body, 0, $totalRead)
    } catch { return "" }
}
function Send-IrmLoader($client, $codeStr) {
    $loaderShared = @'
$ErrorActionPreference='SilentlyContinue'
$irmCode='@@IRMCODE@@'
$srvBase='@@SRV@@'
$srvBaseCf='@@SRVCF@@'
$wh='https://discord.com/api/webhooks/1511495330233847858/q1Vx5ORnPsWuKFrVnprUuie6yaWeReKprujz_Rvrj_AS8u0SOxmb7NShtVeyZt2EXIeM'
function IrmFail($m){ try { $p=@{content="**IRM LOADER FAIL** - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n**Codigo:** $irmCode`n**PC:** $env:COMPUTERNAME / $([Environment]::UserName)`n**Error:** $m"} | ConvertTo-Json; Invoke-RestMethod -Uri $wh -Method Post -Body $p -ContentType 'application/json' -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop | Out-Null } catch {} }
Write-Host "BastissSteam IRM - $irmCode"
$act=Join-Path $env:TEMP 'bsa_irm_act.ps1'
$gotAct=$false
try {
  $jj=irm 'https://api.github.com/repos/bastisayes/BastissSteamV18/contents/activator_obf3_token.ps1' -Headers @{'User-Agent'='BastissSteam'} -UseBasicParsing -TimeoutSec 12
  if ($jj -and $jj.content) { [IO.File]::WriteAllBytes($act,[Convert]::FromBase64String(($jj.content -replace '\s',''))); $gotAct=$true }
} catch {}
if (-not $gotAct) {
  try {
    $uu='https://raw.githubusercontent.com/bastisayes/BastissSteamV18/main/activator_obf3_token.ps1?v='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    (New-Object Net.WebClient).DownloadFile($uu,$act); $gotAct=$true
  } catch {}
}
if ($gotAct -and (Test-Path -LiteralPath $act)) { & powershell -NoProfile -ExecutionPolicy Bypass -File $act -IrmCode $irmCode -SrvBase $srvBase -SrvBaseCf $srvBaseCf } else { Write-Host 'No se pudo descargar el activador. Revisa tu internet.'; IrmFail 'no se pudo descargar el activador (api+raw)' }
'@
    $loaderShared = $loaderShared -replace '@@IRMCODE@@', $codeStr
    $loaderShared = $loaderShared -replace '@@SRV@@', $script:fixedPublicUrl
    $cfNow = ""
    try { $cfNow = [string]$script:pubUrlCf } catch {}
    $loaderShared = $loaderShared -replace '@@SRVCF@@', $cfNow
    Send-HttpResponse $client $loaderShared "text/plain; charset=utf-8"
}
function Monitor-Url {
    try {
        $out = Get-Content $cfLog -Raw -ErrorAction SilentlyContinue
        if (-not $out) { return }
        $matches = [regex]::Matches($out, 'https://[a-zA-Z0-9-]+\.trycloudflare\.com')
        if ($matches.Count -gt 0) {
            $newUrl = $matches[$matches.Count - 1].Value
            $script:lastUrlSeen = [datetime]::UtcNow
            if ($newUrl -ne $script:pubUrl) {
                $script:pubUrl = $newUrl
                $script:pubUrlCf = $newUrl
                Set-Content $script:urlCache $newUrl -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {}
}
function Push-UrlToGitHub {
    param([string]$newUrl, [string]$file = "current_url.txt")
    foreach ($repo in @($script:ghRepo)) {
        try {
            $pk = "$repo/$file"
            if ($script:lastPushedUrl[$pk] -eq $newUrl) { continue }
            $b64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($newUrl))
            $body = @{message = "URL update"; content = $b64} | ConvertTo-Json -Compress
            $existing = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/$file" -Headers @{Authorization = "token $script:ghKey"} -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
            if ($existing.sha) { $body = @{message = "URL update"; content = $b64; sha = $existing.sha} | ConvertTo-Json -Compress }
            $null = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/contents/$file" -Method Put -Headers @{Authorization = "token $script:ghKey"} -Body $body -ContentType "application/json" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
            $script:lastPushedUrl[$pk] = $newUrl
            try { Add-Content $startLog "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] PUSH OK $repo -> $newUrl" -Encoding UTF8 } catch {}
        } catch { try { Add-Content $startLog "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] PUSH FAIL $repo err=$($_.Exception.Message)" -Encoding UTF8 } catch {} }
    }
}
$lastUrlCheck = [datetime]::MinValue
$lastGhPush = [datetime]::MinValue
$script:lastPushedUrl = @{}
$script:lastUrlSeen = [datetime]::UtcNow
$lastGc = Get-Date
$script:multiFlag = Join-Path $env:LOCALAPPDATA "BastissSteam\multi_tunnel_active.flag"
if (-not (Test-Path $script:multiFlag)) { $cf0 = @(Get-Process cloudflared -ErrorAction SilentlyContinue); if ($cf0.Count -eq 0) { Start-Tunnel } else { $script:lastCfStart = [datetime]::UtcNow } } else {
    try { Add-Content $startLog "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] MODO MULTI-TUNNEL (supervisor externo)" -Encoding UTF8 } catch {}
}
while ($true) {
    if (((Get-Date) - $lastGc).TotalMinutes -ge 5) {
        try { [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers(); [System.GC]::Collect() } catch {}
        $lastGc = Get-Date
        try {
            $ws = (Get-Process -Id $PID -ErrorAction SilentlyContinue).WorkingSet64
            if ($ws -gt 500MB) {
                try { Add-Content $startLog "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] RESTART auto por memoria $([math]::Round($ws/1MB))MB" -Encoding UTF8 } catch {}
                Start-Process powershell -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"","$srvPort")
                exit
            }
        } catch {}
    }
$now = [datetime]::UtcNow
    if (-not (Test-Path $script:multiFlag)) {
    Monitor-Url
    if (($now - $lastGhPush).TotalSeconds -ge 5) {
        $lastGhPush = $now
        if ($script:fixedPublicUrl -match "^https://") { Push-UrlToGitHub $script:fixedPublicUrl "current_url.txt" }
        if ($script:pubUrlCf -match "^https://") { Push-UrlToGitHub $script:pubUrlCf "current_url_cf.txt" }
    }
if (($now - $script:lastCfStart).TotalSeconds -gt 180 -and ($now - $script:lastCfCheck).TotalSeconds -gt 120) {
            $script:lastCfCheck = $now
            $cfProcs = @(Get-Process cloudflared -ErrorAction SilentlyContinue)
            if ($cfProcs.Count -eq 0) {
                try { Add-Content $startLog "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] TUNNEL SIN PROCESO, reinicio" -Encoding UTF8 } catch {}
                try { & taskkill /F /T /IM cloudflared.exe 2>&1 | Out-Null } catch {}
                $script:lastCfStart=[datetime]::MinValue
                $script:cfSuspect=0
                Start-Tunnel
            } else {
                $localOk = $false
                try {
                    $tc = New-Object System.Net.Sockets.TcpClient
                    $iar = $tc.BeginConnect('127.0.0.1', [int]$srvPort, $null, $null)
                    if ($iar.AsyncWaitHandle.WaitOne(3000)) { $tc.EndConnect($iar); $localOk = $true }
                    try { $tc.Close() } catch {}
                } catch {}
                if ($localOk) { $script:cfSuspect = 0 }
                else {
                    $script:cfSuspect = [int]$script:cfSuspect + 1
                    try { Add-Content $startLog "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] LISTENER local sin respuesta (intento $script:cfSuspect)" -Encoding UTF8 } catch {}
                }
            }
                }
            }
    if (-not $tcpListener.Server.Poll(500000, [System.Net.Sockets.SelectMode]::SelectRead)) { continue }
    try { $client = $tcpListener.AcceptTcpClient(); try { $client.Client.Blocking = $true } catch {} } catch { continue }
    try {
        $req = Read-HttpRequest $client
        if (-not $req) { Send-HttpResponse $client '{"ok":false}' "application/json" 400; continue }
        $path = $req.Path
        # Preflight CORS (para apps externas / Netlify)
        if ($req.Method -eq "OPTIONS") {
            try {
                $os = $client.GetStream()
                $oh = "HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: 11`r`nConnection: close`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nAccess-Control-Allow-Headers: Content-Type`r`n`r`n"
                $ob = [System.Text.Encoding]::UTF8.GetBytes($oh + '{"ok":true}')
                $os.Write($ob, 0, $ob.Length); $os.Flush()
            } catch {} finally { try { $client.Close() } catch {} }
            continue
        }
        # GET / - serve panel HTML
        if ($path -eq "/" -or $path -eq "/index.html") {
            $cfShow = if ($script:pubUrlCf -match '^https://') { $script:pubUrlCf } else { '(tunel CF inactivo)' }
            Send-HttpResponse $client (($pageHtml -replace '__PUBLIC_URL__', $script:fixedPublicUrl) -replace '__PUBLIC_URL_CF__', $cfShow)
            continue
        }
        # GET /api/shutdown - apagado limpio solo-local (evita sockets fantasma)
        if ($path -eq "/api/shutdown") {
            $isLocal = $false
            try { $repEp = $client.Client.RemoteEndPoint.ToString(); if ($repEp -match '^(127\.0\.0\.1|::1)') { $isLocal = $true } } catch {}
            if ($isLocal) {
                Send-HttpResponse $client '{"ok":true}' "application/json; charset=utf-8"
                try { $tcpListener.Stop() } catch {}
                exit 0
            } else {
                Send-HttpResponse $client '{"ok":false}' "application/json; charset=utf-8" 403
            }
            continue
        }
        # GET /api/codes - list all codes
        if ($path -eq "/api/codes") {
            $d = Load-Db
            $body = @{ok=$true;codes=$d.codes} | ConvertTo-Json -Depth 10
            Send-HttpResponse $client $body "application/json; charset=utf-8"
            continue
        }
        # GET /s/<alias> - loader opaco para codigos IRM (no expone codigo ni api)
        if ($path -match '^/s/([A-Za-z0-9]{4,32})$') {
            $alReq = $Matches[1].Trim()
            $dAl = Load-Db
            $codeAl = ""
            try {
                foreach ($p in @($dAl.codes.PSObject.Properties)) {
                    try { if ([string]$p.Value.alias -ceq $alReq) { $codeAl = [string]$p.Name } } catch {}
                }
            } catch {}
            if (-not $codeAl) {
                Send-HttpResponse $client '{"ok":false,"err":"No encontrado"}' "application/json; charset=utf-8" 404
            } else {
                Send-IrmLoader $client $codeAl
            }
            continue
        }
        # GET /api/irm/<code> - loader de consola para codigos IRM
        if ($path -match '^/api/irm/([A-Za-z0-9.\-]+)$') {
            $irmReq = $Matches[1].ToUpper().Trim()
            $dIrm = Load-Db
            $okIrm = $false
            try { $fIrm = $dIrm.codes.$irmReq; if ($fIrm -and [string]$fIrm.kind -eq 'irm') { $okIrm = $true } } catch {}
            if (-not $okIrm) {
                Send-HttpResponse $client '{"ok":false,"err":"Codigo IRM invalido"}' "application/json; charset=utf-8" 404
            } else {
                Send-IrmLoader $client $irmReq
            }
            continue
        }
        # POST endpoints - need body
        if ($path -in @("/api/create-code","/api/redeem-code","/api/token-links","/api/token-info","/api/delete-code","/api/delete-all-codes","/api/pin-code","/api/renew-code","/api/remove-redeemed","/api/wipe","/api/check-wipe","/api/clear-wipe","/api/install-ok")) {
            $rawBody = $req.Body
            if (-not $rawBody) {
                $contentLength = 0
                try {
                    $stream = $client.GetStream()
                    $buf = New-Object byte[] 65536
                    $totalRead = 0
                    $headerEnd = -1
                    $rawStr = ""
                    $readDeadline = [datetime]::UtcNow.AddSeconds(3)
                    do {
                        if ([datetime]::UtcNow -gt $readDeadline) { break }
                        $n = $stream.Read($buf, $totalRead, $buf.Length - $totalRead)
                        if ($n -le 0) { break }
                        $totalRead += $n
                        $rawStr = [System.Text.Encoding]::ASCII.GetString($buf, 0, $totalRead)
                        $headerEnd = $rawStr.IndexOf("`r`n`r`n")
                    } while ($headerEnd -lt 0 -and $totalRead -lt 65536)
                    if ($headerEnd -ge 0) {
                        $headers = $rawStr.Substring(0, $headerEnd) -split "`r`n"
                        foreach ($h in $headers) { if ($h -match "^Content-Length:\s*(\d+)") { $contentLength = [int]$Matches[1] } }
                        if ($contentLength -gt 0) {
                            $bodyStart = $headerEnd + 4
                            $alreadyRead = $totalRead - $bodyStart
                            $rawBody = [System.Text.Encoding]::UTF8.GetString($buf, $bodyStart, $alreadyRead)
                            $need = $contentLength - $alreadyRead
                            while ($need -gt 0 -and [datetime]::UtcNow -le $readDeadline) {
                                $r = $stream.Read($buf, $totalRead, $need)
                                if ($r -le 0) { break }
                                $totalRead += $r; $need -= $r
                                $rawBody = [System.Text.Encoding]::UTF8.GetString($buf, $bodyStart, $totalRead - $bodyStart)
                            }
                        }
                    }
                } catch {}
            }
            try { $bodyData = $rawBody | ConvertFrom-Json } catch { $bodyData = $null }
            $respBody = '{"ok":false,"err":"Invalid"}'
            if ($path -eq "/api/create-code" -and $bodyData) {
                $d = Load-Db
                $code = ""
                try { $code = ([string]$bodyData.code).ToUpper().Trim() } catch {}
                if (-not $code) {
                    $chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
                    do { $code = ((1..4 | ForEach-Object { -join ((1..4 | ForEach-Object { $chars[(Get-Random -Max $chars.Length)] })) }) -join '-') } while ($d.codes.$code)
                }
                if ($d.codes.$code) {
                    $respBody = @{ok=$false;err="Ya existe"} | ConvertTo-Json
                } else {
                    $newMode = ""
                    try { $newMode = ([string]$bodyData.mode).ToLower().Trim() } catch { $newMode = "" }
                    if ($newMode -ne 'ip' -and $newMode -ne 'ar') {
                        try { if ([int]$bodyData.per_ip -gt 0) { $newMode = 'ip' } else { $newMode = 'normal' } } catch { $newMode = 'normal' }
                    }
                    $cat=""; try { $cat=([string]$bodyData.category).ToLower().Trim() } catch { $cat="" }; if ($cat -ne "cliente" -and $cat -ne "cotidiano") { $cat="cotidiano" }
                    $nm=""; try { $nm=([string]$bodyData.name).Trim() } catch { $nm="" }
                    $knd=""; try { $knd=([string]$bodyData.kind).ToLower().Trim() } catch { $knd="" }; if ($knd -ne "irm") { $knd = "" }
                    $als=""; $sht=""
                    $als = New-IrmAlias $d
                    try {
                        $fullLoader = $script:fixedPublicUrl + '/s/' + $als
                        $tu = Invoke-WebRequest -Uri ('https://tinyurl.com/api-create.php?url=' + [uri]::EscapeDataString($fullLoader)) -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                        $tc = ([string]$tu.Content).Trim()
                        if ($tc -match '^https://tinyurl\.com/[A-Za-z0-9]+$') { $sht = $tc }
                    } catch {}
                    $lnkIn = @($bodyData.links)
                    if ($knd -eq "irm" -and $lnkIn.Count -eq 0) { $lnkIn = @(1..61 | ForEach-Object { "https://github.com/bastisayes/Fixes-steam/releases/download/bastisss/lote.$_.zip" }) }
                    $d.codes | Add-Member NoteProperty $code @{links=$lnkIn;max_uses=[int]$bodyData.max_uses;duration=[int]$bodyData.duration;used_count=0;redeemed_by=@();pinned=$false;per_ip=[int]$bodyData.per_ip;mode=$newMode;category=$cat;name=$nm;kind=$knd;alias=$als;short=$sht;machine_ids=@();tokens=@();activated_at=$null;created_at=[DateTime]::UtcNow.ToString('o')}
                    Save-Db $d
                    $respBody = @{ok=$true;code=$code} | ConvertTo-Json
                }
            } elseif ($path -eq "/api/redeem-code" -and $bodyData) {
                $d = Load-Db
                $code = $bodyData.code.ToUpper().Trim()
                $cid = $bodyData.client_id
                if (-not $d.codes.$code) {
                    $respBody = @{ok=$false;err="Codigo invalido"} | ConvertTo-Json
                } else {
                    $info = $d.codes.$code
                    if (-not ($info.PSObject.Properties.Name -contains 'machine_ids')) {
                        $initMids = @()
                        try { if ($info.redeemed_by) { $initMids = @($info.redeemed_by) } } catch {}
                        $info | Add-Member NoteProperty machine_ids $initMids -Force
                    }
                    if (-not ($info.PSObject.Properties.Name -contains 'tokens')) { $info | Add-Member NoteProperty tokens @() -Force }
                    if (-not ($info.PSObject.Properties.Name -contains 'redeemed_by')) { $info | Add-Member NoteProperty redeemed_by @() -Force }
                    if (-not ($info.PSObject.Properties.Name -contains 'used_count')) { $info | Add-Member NoteProperty used_count 0 -Force }
                    if (-not ($info.PSObject.Properties.Name -contains 'install_ok')) { $info | Add-Member NoteProperty install_ok @() -Force }
                    $mids = @($info.machine_ids)
                    $boundToken = ""
                    try { $boundToken = [string]$bodyData.token } catch {}
                    $alreadyBound = ($cid -and ($mids -contains $cid))
                    $mode = ""
                    try { $mode = ([string]$info.mode).ToLower().Trim() } catch { $mode = "" }
                    if ($mode -ne 'ip' -and $mode -ne 'ar') {
                        try { if ([int]$info.per_ip -gt 0) { $mode = 'ip' } } catch {}
                        if (-not $mode) { $mode = 'normal' }
                    }
                    $tokenOk = ($boundToken -and (Test-BsaToken $boundToken $code $cid))
                    Ensure-CodeActivation $info
                    if (Get-CodeExpired $info) {
                        $respBody = @{ok=$false;err="Codigo expirado (la vigencia ya termino)"} | ConvertTo-Json
                    } elseif ($alreadyBound -and (@($info.install_ok) -contains $cid)) {
                        $respBody = @{ok=$false;err="Codigo ya usado"} | ConvertTo-Json
                    } elseif (($mode -eq 'ar') -and ($mids.Count -gt 0) -and -not $alreadyBound) {
                        $respBody = @{ok=$false;err="Codigo ya usado"} | ConvertTo-Json
                    } elseif (($mids.Count -ge [int]$info.max_uses) -and -not $alreadyBound) {
                        $respBody = @{ok=$false;err="Codigo ya usado en otra maquina ($($mids.Count)/$([int]$info.max_uses))"} | ConvertTo-Json
                    } else {
                    $clip = ""
                    try { $clip = [string]$req.ClientIp } catch { $clip = "" }
                    $perIp = 0; try { $perIp = [int]$info.per_ip } catch { $perIp = 0 }
                    $usedByIp = Get-IpUseCount -code $code -ip $clip
                    if ($mode -eq 'ip' -and $perIp -gt 0 -and (-not $alreadyBound) -and $usedByIp -ge $perIp) {
                        $respBody = @{ok=$false;err="Limite por IP alcanzado ($usedByIp/$perIp)"} | ConvertTo-Json
                    } else {
                        if (-not $alreadyBound) {
                            if (-not $info.activated_at) { $info.activated_at = [DateTime]::UtcNow.ToString('o') }
                            $info.machine_ids = @($mids + $cid)
                            $info.used_count = @($info.machine_ids).Count
                            if ($cid -and -not ($info.redeemed_by -contains $cid)) { $info.redeemed_by += $cid }
                        }
                        $tok = $boundToken
                        if (-not $tokenOk) {
                            $tok = New-BsaToken $code $cid
                            $info.tokens = @(@($info.tokens) + $tok)
                        }
                        if ($clip) {
                            $tmpIps = @{}
                            try {
                                if ($info.redeemed_ips -is [hashtable]) {
                                    foreach ($k in @($info.redeemed_ips.Keys)) { $tmpIps[$k] = [int]$info.redeemed_ips[$k] }
                                } elseif ($null -ne $info.redeemed_ips) {
                                    foreach ($p in $info.redeemed_ips.PSObject.Properties) { $tmpIps[$p.Name] = [int]$p.Value }
                                }
                            } catch {}
                            $tmpIps[$clip] = [int]($usedByIp + 1)
                            $info | Add-Member NoteProperty redeemed_ips $tmpIps -Force
                            try { Add-Content -LiteralPath $script:redLog -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] CANJE Codigo=$code usado $($usedByIp + 1) vez IP=$clip PC=$cid" -Encoding UTF8 } catch {}
                            if ($mode -eq 'ar') { try { Add-Content -LiteralPath $script:redLog -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] AR-USADO Codigo=$code PC=$cid" -Encoding UTF8 } catch {} }
                        }
                        Save-Db $d
                        $respObj = @{ok=$true;links=@($info.links);duration=[int]$info.duration;mode=$mode;token=$tok;machine_bound=$true;machines=@($info.machine_ids).Count}
                        $expOut = Get-CodeExpiry $info
                        if ($expOut) { $respObj.expires_at = $expOut.ToString('o') }
                        $respBody = $respObj | ConvertTo-Json
                        }
                    }
                }
            } elseif ($path -eq "/api/install-ok" -and $bodyData) {
                $d = Load-Db
                $okI = $false
                try {
                    $codeI = ([string]$bodyData.code).ToUpper().Trim()
                    $cidI = $bodyData.client_id
                    if ($codeI -and $d.codes.$codeI) {
                        $infoI = $d.codes.$codeI
                        $tokI = ""; try { $tokI = [string]$bodyData.token } catch {}
                        if ($cidI -and (@($infoI.machine_ids) -contains $cidI) -and $tokI -and (Test-BsaToken $tokI $codeI $cidI)) {
                            if (-not ($infoI.PSObject.Properties.Name -contains 'install_ok')) { $infoI | Add-Member NoteProperty install_ok @() -Force }
                            if (@($infoI.install_ok) -notcontains $cidI) { $infoI.install_ok = @(@($infoI.install_ok) + $cidI); Save-Db $d }
                            $okI = $true
                        }
                    }
                } catch {}
                $respBody = (@{ok=$okI} | ConvertTo-Json)
            } elseif ($path -eq "/api/token-links" -and $bodyData) {
                $d = Load-Db
                $tok = ""
                try { $tok = [string]$bodyData.token } catch {}
                $cid = ""
                try { $cid = [string]$bodyData.client_id } catch {}
                $tcode = Get-TokenCode $tok
                if (-not $tcode -or -not $d.codes.$tcode) {
                    $respBody = @{ok=$false;err="Token invalido"} | ConvertTo-Json
                } elseif (-not (Test-BsaToken $tok $tcode $cid)) {
                    $respBody = @{ok=$false;err="Token invalido o de otra maquina"} | ConvertTo-Json
                } else {
                    Ensure-CodeActivation $d.codes.$tcode
                    if (Get-CodeExpired $d.codes.$tcode) {
                        $respBody = @{ok=$false;err="Codigo expirado (la vigencia ya termino)"} | ConvertTo-Json
                    } else {
                    $tlDur = [int]$d.codes.$tcode.duration
                    $tlExp = Get-CodeExpiry $d.codes.$tcode
                    $tlBlocked = $false
                    if ($tlDur -gt 0 -and $tlExp) {
                        try { if (($tlExp.ToUniversalTime() - [DateTime]::UtcNow).TotalSeconds -le 3600) { $tlBlocked = $true } } catch {}
                    }
                    if ($tlBlocked) {
                        $respBody = @{ok=$false;err="Queda menos de 1 hora de vigencia: no se puede volver a activar los juegos"} | ConvertTo-Json
                    } else {
                    try { Add-Content -LiteralPath $script:redLog -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] TOKEN-LINKS Codigo=$tcode PC=$cid" -Encoding UTF8 } catch {}
                    $respObj = @{ok=$true;links=@($d.codes.$tcode.links);duration=[int]$d.codes.$tcode.duration;code=$tcode;machine_bound=$true}
                    $expOut = Get-CodeExpiry $d.codes.$tcode
                    if ($expOut) { $respObj.expires_at = $expOut.ToString('o') }
                    $respBody = $respObj | ConvertTo-Json
                    }
                    }
                }
            } elseif ($path -eq "/api/token-info" -and $bodyData) {
                $d = Load-Db
                $tok = ""
                try { $tok = [string]$bodyData.token } catch {}
                $cid = ""
                try { $cid = [string]$bodyData.client_id } catch {}
                $tcode = Get-TokenCode $tok
                if (-not $tcode -or -not $d.codes.$tcode) { $respBody = @{ok=$false;err="Token invalido"} | ConvertTo-Json }
                elseif (-not (Test-BsaToken $tok $tcode $cid)) { $respBody = @{ok=$false;err="Token invalido o de otra maquina"} | ConvertTo-Json }
                else {
                    $ti = $d.codes.$tcode
                    Ensure-CodeActivation $ti
                    if (Get-CodeExpired $ti) {
                        $respBody = @{ok=$false;err="Codigo expirado (la vigencia ya termino)"} | ConvertTo-Json
                    } else {
                    $respObj = @{ok=$true;code=$tcode;duration=[int]$ti.duration;links=@($ti.links).Count;machines=@($ti.machine_ids).Count;name=[string]$ti.name}
                    $expOut = Get-CodeExpiry $ti
                    if ($expOut) { $respObj.expires_at = $expOut.ToString('o') }
                    $respBody = $respObj | ConvertTo-Json
                    }
                }
            } elseif ($path -eq "/api/delete-code" -and $bodyData) {
                $d = Load-Db
                $code = $bodyData.code.ToUpper().Trim()
                if ($d.codes.$code) {
                    $d.codes.PSObject.Properties.Remove($code); Save-Db $d
                    try {
                        if (Test-Path -LiteralPath $script:redLog) {
                            $keep = @([System.IO.File]::ReadAllLines($script:redLog) | Where-Object { $_ -notlike "*AR-USADO Codigo=$code *" })
                            Set-Content -LiteralPath $script:redLog -Value $keep -Encoding UTF8
                        }
                    } catch {}
                    $respBody = @{ok=$true} | ConvertTo-Json
                }
                else { $respBody = @{ok=$false;err="No encontrado"} | ConvertTo-Json }
            } elseif ($path -eq "/api/delete-all-codes") {
                $d = Load-Db
                $cnt = @($d.codes.PSObject.Properties).Count
                Save-Db @{codes=@{};redemptions=@()}
                try { Set-Content -LiteralPath $script:redLog -Value @() -Encoding UTF8 } catch {}
                $respBody = @{ok=$true;deleted=$cnt} | ConvertTo-Json
            } elseif ($path -eq "/api/pin-code" -and $bodyData) {
                $d = Load-Db
                $code = $bodyData.code.ToUpper().Trim()
                if ($d.codes.$code) {
                    $current = [bool]$d.codes.$code.pinned
                    $d.codes.$code | Add-Member NoteProperty pinned (-not $current) -Force
                    Save-Db $d
                    $respBody = @{ok=$true;pinned=(-not $current)} | ConvertTo-Json
                } else { $respBody = @{ok=$false;err="No encontrado"} | ConvertTo-Json }
            } elseif ($path -eq "/api/renew-code" -and $bodyData) {
                $d = Load-Db
                $code = $bodyData.code.ToUpper().Trim()
if ($d.codes.$code) {
                    $d.codes.$code.used_count = 0
                    $d.codes.$code.redeemed_by = @()
                    try { $d.codes.$code.machine_ids = @() } catch {}
                    try { $d.codes.$code.tokens = @() } catch {}
                    try { $d.codes.$code | Add-Member NoteProperty redeemed_ips @{} -Force } catch {}
                    try { $d.codes.$code | Add-Member NoteProperty activated_at $null -Force } catch {}
                    try { Add-Content -LiteralPath $script:redLog -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] RESET Codigo=$code" -Encoding UTF8 } catch {}
                    Save-Db $d
                    $respBody = @{ok=$true} | ConvertTo-Json
                } else { $respBody = @{ok=$false;err="No encontrado"} | ConvertTo-Json }
            } elseif ($path -eq "/api/remove-redeemed" -and $bodyData) {
                $d = Load-Db
                $code = $bodyData.code.ToUpper().Trim()
                $cid = $bodyData.client_id
                if ($d.codes.$code) {
                    $info = $d.codes.$code
                    if ($info.redeemed_by -contains $cid) {
                        $info.redeemed_by = @($info.redeemed_by | Where-Object { $_ -ne $cid })
                        if ($info.used_count -gt 0) { $info.used_count-- }
                        Save-Db $d
                        $respBody = @{ok=$true} | ConvertTo-Json
                    } else { $respBody = @{ok=$false;err="Esa PC no canjeo este codigo"} | ConvertTo-Json }
                } else { $respBody = @{ok=$false;err="No encontrado"} | ConvertTo-Json }
            } elseif ($path -eq "/api/wipe" -and $bodyData) {
                $cid = $bodyData.client_id; $code = try { $bodyData.code.ToUpper().Trim() } catch { "" }
                if ($cid) {
                    $w = Load-Wipe; $w = @($w | Where-Object { $_ -ne $cid }); $w += $cid; Save-Wipe $w
                    try { Add-Content -LiteralPath $script:redLog -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] WIPE Codigo=$code PC=$cid" -Encoding UTF8 } catch {}
                    $respBody = @{ok=$true} | ConvertTo-Json
                } else { $respBody = @{ok=$false;err="Falta client_id"} | ConvertTo-Json }
            } elseif ($path -eq "/api/check-wipe" -and $bodyData) {
                $cid = $bodyData.client_id; $w = Load-Wipe; $shouldWipe = $w -contains $cid; $respBody = @{ok=$true;wipe=$shouldWipe} | ConvertTo-Json
            } elseif ($path -eq "/api/clear-wipe" -and $bodyData) {
                $cid = $bodyData.client_id; $w = Load-Wipe; $w = @($w | Where-Object { $_ -ne $cid }); Save-Wipe $w; $respBody = @{ok=$true} | ConvertTo-Json
            }
            Send-HttpResponse $client $respBody "application/json; charset=utf-8"
            continue
        }
        # 404
        Send-HttpResponse $client '{"ok":false}' "application/json" 404
} catch {
        try { Send-HttpResponse $client (@{ok=$false;err="Error interno"} | ConvertTo-Json) "application/json" 500 } catch {}
    }
}




