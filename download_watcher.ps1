Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
    [DllImport("user32.dll")] public static extern int ShowWindow(int h, int s);
    [DllImport("kernel32.dll")] public static extern int GetConsoleWindow();
}
"@
[W]::ShowWindow([W]::GetConsoleWindow(), 0) | Out-Null

$form = New-Object System.Windows.Forms.Form
$form.Text = "Steam Download Watcher"
$form.Size = New-Object System.Drawing.Size(1, 1)
$form.StartPosition = "Manual"
$form.Location = New-Object System.Drawing.Point(-32000, -32000)
$form.WindowState = "Minimized"
$form.BackColor = "#0d1117"
$form.TopMost = $false
$form.ShowInTaskbar = $false
$form.Opacity = 0
$form.Visible = $false

$status = New-Object System.Windows.Forms.Label
$status.Location = New-Object System.Drawing.Point(20, 8)
$status.Size = New-Object System.Drawing.Size(850, 22)
$status.Text = "Iniciando..."
$status.ForeColor = "#00d4ff"
$status.Font = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($status)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 34)
$progressBar.Size = New-Object System.Drawing.Size(650, 18)
$progressBar.Style = "Continuous"
$progressBar.ForeColor = "#00d4ff"
$progressBar.BackColor = "#0d1117"
$progressBar.Visible = $false
$form.Controls.Add($progressBar)

$speedLabel = New-Object System.Windows.Forms.Label
$speedLabel.Location = New-Object System.Drawing.Point(680, 34)
$speedLabel.Size = New-Object System.Drawing.Size(190, 18)
$speedLabel.Text = ""
$speedLabel.ForeColor = "#00ff88"
$speedLabel.Font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
$speedLabel.TextAlign = "MiddleRight"
$speedLabel.Visible = $false
$form.Controls.Add($speedLabel)

$log = New-Object System.Windows.Forms.TextBox
$log.Location = New-Object System.Drawing.Point(20, 58)
$log.Size = New-Object System.Drawing.Size(850, 492)
$log.Multiline = $true
$log.ReadOnly = $true
$log.BackColor = "#0d1117"
$log.ForeColor = "#c0c0c0"
$log.Font = New-Object System.Drawing.Font("Consolas", 9)
$log.BorderStyle = "None"
$form.Controls.Add($log)

$script:lg = { param([string]$t) $log.AppendText("$t`r`n"); [System.Windows.Forms.Application]::DoEvents(); try { Add-Content -Path (Join-Path $env:TEMP "bsmap_watcher.log") -Value $t -Encoding UTF8 -ErrorAction SilentlyContinue } catch {} }
$script:st = { param([string]$t, [string]$c="#00d4ff") $script:status.Text = $t; $script:status.ForeColor = $c; [System.Windows.Forms.Application]::DoEvents(); try { Add-Content -Path (Join-Path $env:TEMP "bsmap_watcher.log") -Value "[STATUS] $t" -Encoding UTF8 -ErrorAction SilentlyContinue } catch {} }

$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

function Get-SteamPath {
    $paths = @(
        (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name InstallPath -ErrorAction SilentlyContinue).InstallPath,
        (Get-ItemProperty -Path "HKLM:\SOFTWARE\Valve\Steam" -Name InstallPath -ErrorAction SilentlyContinue).InstallPath,
        (Get-ItemProperty -Path "HKCU:\SOFTWARE\Valve\Steam" -Name SteamPath -ErrorAction SilentlyContinue).SteamPath,
        "${env:ProgramFiles(x86)}\Steam",
        "${env:ProgramFiles(x86)}\Steamm",
        "$env:ProgramFiles\Steam"
    )
    foreach ($p in $paths) { if ($p -and (Test-Path $p) -and (Test-Path (Join-Path $p "steam.exe"))) { return $p } }
    foreach ($p in $paths) { if ($p -and (Test-Path $p)) { return $p } }
    return $null
}

function Get-SteamLibraries {
    $steamRoot = Get-SteamPath
    if (-not $steamRoot) { return @() }
    $libs = @($steamRoot)
    $vdf = Join-Path $steamRoot "steamapps\libraryfolders.vdf"
    if (Test-Path $vdf) {
        $v = Get-Content $vdf -Raw -ErrorAction SilentlyContinue
        [regex]::Matches($v, '"path"\s+"([^"]+)"') | ForEach-Object { $p = $_.Groups[1].Value -replace '\\\\', '\'; if (Test-Path $p) { $libs += $p } }
    }
    return ($libs | Select-Object -Unique)
}

function Get-AppName {
    param([string]$appid, [string[]]$libs)
    foreach ($sl in $libs) {
        $acf = Join-Path (Join-Path $sl "steamapps") "appmanifest_$appid.acf"
        if (-not (Test-Path $acf)) { continue }
        try {
            $raw = [System.IO.File]::ReadAllText($acf)
            if ($raw -match '"name"\s+"([^"]+)"') { return $Matches[1].Trim() }
            if ($raw -match '"installdir"\s+"([^"]+)"') { return $Matches[1].Trim() }
        } catch {}
    }
    try {
        $r = Invoke-RestMethod -Uri "https://store.steampowered.com/api/appdetails?appids=$appid" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        if ($r.$appid.success -eq $true -and $r.$appid.data.name) { return ($r.$appid.data.name).Trim() }
    } catch {}
    return $null
}

function Find-Fix {
    param([string]$name)
    if ($fixesCache.Count -eq 0) { return $null }
    if ($fixesCache.ContainsKey($name)) { return $fixesCache[$name] }
    $n2 = ($name -replace '[^a-zA-Z0-9]', '').ToLower()
    foreach ($key in $fixesCache.Keys) {
        if (($key -replace '[^a-zA-Z0-9]', '').ToLower() -eq $n2) { return $fixesCache[$key] }
    }
    $clean = $name -replace '\s*\([^)]*\)', '' -replace '\s+', ' '
    $nc = ($clean -replace '[^a-zA-Z0-9]', '').ToLower()
    foreach ($key in $fixesCache.Keys) {
        $kb = $key -replace '\s*\([^)]*\)', '' -replace '\s+', ' '
        if (($kb -replace '[^a-zA-Z0-9]', '').ToLower() -eq $nc) { return $fixesCache[$key] }
    }
    # Fallback: fuzzy matching por si los nombres no coinciden exactamente
    $bestKey = $null; $bestPct = 0
    foreach ($key in $fixesCache.Keys) {
        $pct = Get-Similarity $name $key
        if ($pct -gt $bestPct) { $bestPct = $pct; $bestKey = $key }
    }
    if ($bestPct -ge 50) { return $fixesCache[$bestKey] }
    return $null
}

function Get-Similarity {
    param([string]$a, [string]$b)
    $a = (($a -replace '[^a-zA-Z0-9\s]', ' ') -replace '\s+', ' ').Trim().ToLower()
    $b = (($b -replace '[^a-zA-Z0-9\s]', ' ') -replace '\s+', ' ').Trim().ToLower()
    $la = $a.Length; $lb = $b.Length
    if ($la -eq 0 -or $lb -eq 0) { return 0 }
    $m = New-Object 'int[,]' ($la + 1), ($lb + 1)
    for ($i = 0; $i -le $la; $i++) { $m[$i,0] = $i }
    for ($j = 0; $j -le $lb; $j++) { $m[0,$j] = $j }
    for ($i = 1; $i -le $la; $i++) {
        for ($j = 1; $j -le $lb; $j++) {
            $i1 = $i - 1; $j1 = $j - 1
            $c = if ($a[$i1] -eq $b[$j1]) { 0 } else { 1 }
            $del = $m[$i1,$j] + 1; $ins = $m[$i,$j1] + 1; $sub = $m[$i1,$j1] + $c
            $m[$i,$j] = [math]::Min([math]::Min($del, $ins), $sub)
        }
    }
    $maxLen = [math]::Max($la, $lb)
    return [math]::Round((1 - $m[$la,$lb] / $maxLen) * 100)
}

function Normalize-Name {
    param([string]$n)
    return ($n -replace ':', '' -replace '\s+', ' ').Trim()
}

function Find-CommonFolder {
    param([string]$name, [string[]]$libs)
    $best = $null; $bestPct = 0
    $nNorm = (($name -replace '[^a-zA-Z0-9\s]', ' ') -replace '\s+', ' ').Trim().ToLower()
    foreach ($sl in $libs) {
        $cp = Join-Path $sl "steamapps\common"
        if (-not (Test-Path -LiteralPath $cp)) { continue }
        try {
            foreach ($d in [System.IO.Directory]::GetDirectories($cp)) {
                $fn = [System.IO.Path]::GetFileName($d)
                $fnNorm = (($fn -replace '[^a-zA-Z0-9\s]', ' ') -replace '\s+', ' ').Trim().ToLower()
                if ($fnNorm.Contains($nNorm) -or $nNorm.Contains($fnNorm)) { return $d }
                $pct = Get-Similarity $name $fn
                if ($pct -gt $bestPct) { $bestPct = $pct; $best = $d }
            }
        } catch { }
    }
    if ($bestPct -ge 50) { return $best }
    return $null
}

function Start-GitHubDownload {
    param(
        [string]$Url,
        [string]$OutFile,
        [string]$UserAgent,
        [int]$Connections = 0,
        [long]$KnownSize = 0,
        $ProgressInfo = $null
    )
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls
        [System.Net.ServicePointManager]::DefaultConnectionLimit = 256
        $totalSize = $KnownSize
        if ($totalSize -le 0) {
            $hReq = [System.Net.HttpWebRequest]::Create($Url)
            $hReq.Method = "HEAD"; $hReq.UserAgent = $UserAgent
            $hReq.AllowAutoRedirect = $true;             $hReq.Timeout = 5000
            try {
                $hResp = $hReq.GetResponse()
                $totalSize = $hResp.ContentLength; $hResp.Close()
            } catch {}
            if ($totalSize -le 0) {
                $gReq = [System.Net.HttpWebRequest]::Create($Url)
                $gReq.Method = "GET"; $gReq.UserAgent = $UserAgent
                $gReq.AllowAutoRedirect = $true;                 $gReq.Timeout = 5000
                $gReq.AddRange(0, 0)
                try {
                    $gResp = $gReq.GetResponse()
                    $cr = $gResp.Headers["Content-Range"]
                    if ($cr -and $cr -match '/(\d+)') { $totalSize = [long]$Matches[1] }
                    $gResp.Close()
                } catch {}
            }
            if ($totalSize -le 0) { return @{ok=$false;err="Invalid size: $totalSize"} }
        }
        if ($Connections -le 0) {
            if ($totalSize -lt 5MB) { $Connections = 1 }
            elseif ($totalSize -lt 50MB) { $Connections = 4 }
            elseif ($totalSize -lt 500MB) { $Connections = 8 }
            else { $Connections = 16 }
        }
        if ($ProgressInfo) { $ProgressInfo.Total = $totalSize }
        $tempDir = [System.IO.Path]::GetTempPath()
        $randomTag = [System.IO.Path]::GetRandomFileName().Replace('.', '')
        $fileBase = [System.IO.Path]::GetFileNameWithoutExtension($OutFile) + "_${randomTag}_ghd"
        $bufSize = 262144; $maxRetries = 3; $chunkSize = [math]::Ceiling($totalSize / $Connections)
        if ($Connections -le 1 -or $chunkSize -lt 65536) {
            $req = [System.Net.HttpWebRequest]::Create($Url)
            $req.Method = "GET"; $req.UserAgent = $UserAgent
            $req.AllowAutoRedirect = $true;             $req.Timeout = 60000; $req.ReadWriteTimeout = 60000
            $req.KeepAlive = $true; $req.Pipelined = $true
            $resp = $req.GetResponse(); $st = $resp.GetResponseStream()
            $fs = [System.IO.File]::Create($OutFile)
            $buf = [System.Array]::CreateInstance([System.Byte], $bufSize)
            $totalRead = 0; $sw = [System.Diagnostics.Stopwatch]::StartNew(); $lastRead = 0
            while (($n = $st.Read($buf, 0, $buf.Length)) -gt 0) {
                $fs.Write($buf, 0, $n); $totalRead += $n
                if ($ProgressInfo -and $totalSize -gt 0) {
                    $ProgressInfo.Percent = [math]::Min(99, [math]::Round($totalRead / $totalSize * 100))
                    $ProgressInfo.Current = $totalRead
                    if ($sw.Elapsed.TotalSeconds -ge 1) {
                        $ProgressInfo.Speed = [long](($totalRead - $lastRead) / $sw.Elapsed.TotalSeconds)
                        $lastRead = $totalRead; $sw.Restart()
                    }
                }
            }
            $sw.Stop(); $st.Close(); $resp.Close(); $fs.Close()
            $fi = [System.IO.File]::OpenRead($OutFile); $actualSize = $fi.Length; $fi.Close()
            if ($totalSize -gt 0 -and $actualSize -ne $totalSize) { return @{ok=$false;err="Size mismatch: $actualSize vs $totalSize"} }
            if ($ProgressInfo) { $ProgressInfo.Percent = 100; $ProgressInfo.Speed = 0 }
            return @{ok=$true;path=$OutFile;size=$actualSize}
        }

        $chunkCount = [math]::Ceiling([double]$totalSize / $chunkSize)
        $chunkFiles = @(); $runspaces = @()
        if ($ProgressInfo) { $ProgressInfo.LogMsg = "Iniciando $Connections conexiones ($chunkCount chunks)" }
        $csText = @'
param($u, $s, $e, $o, $ua2, $bs, $mr)
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls
$le = $null
for ($a = 1; $a -le $mr; $a++) {
    try {
        $r = [System.Net.HttpWebRequest]::Create($u)
        $r.Method = "GET"; $r.UserAgent = $ua2
        $r.AllowAutoRedirect = $true; $r.Timeout = 60000; $r.ReadWriteTimeout = 60000
        $r.KeepAlive = $true; $r.Pipelined = $true
        $r.AddRange($s, $e)
        $rp = $r.GetResponse(); $f = [System.IO.File]::Create($o)
        $st = $rp.GetResponseStream(); $b = [System.Array]::CreateInstance([System.Byte], $bs)
        while (($nr = $st.Read($b, 0, $bs)) -gt 0) { $f.Write($b, 0, $nr) }
        $f.Close(); $st.Close(); $rp.Close(); return
    } catch { $le = $_; try { [System.IO.File]::Delete($o) } catch {}; Start-Sleep -Milliseconds (500 * $a) }
}
throw "Chunk failed after $mr attempts: $le"
'@
        for ($i = 0; $i -lt $chunkCount; $i++) {
            $start = $i * $chunkSize
            if ($start -ge $totalSize) { break }
            $end = [math]::Min($start + $chunkSize - 1, $totalSize - 1)
            $chunkFile = [System.IO.Path]::Combine($tempDir, "${fileBase}_${i}.tmp")
            if (Test-Path $chunkFile) { Remove-Item $chunkFile -Force -ErrorAction SilentlyContinue }
            $chunkFiles += $chunkFile
            $ps = [powershell]::Create()
            $rs = [RunspaceFactory]::CreateRunspace()
            $ps.Runspace = $rs; $rs.Open()
            [void]$ps.AddScript($csText).AddArgument($Url).AddArgument([long]$start).AddArgument([long]$end).AddArgument($chunkFile).AddArgument($UserAgent).AddArgument($bufSize).AddArgument($maxRetries)
            $runspaces += @{ps=$ps;handle=$ps.BeginInvoke();file=$chunkFile;rs=$rs;start=$start;end=$end}
        }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $chunkErrors = @(); $completed = 0; $totalChunks = $runspaces.Count
        $doneMap = @{}
        $lastBytes = 0; $lastSw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($completed -lt $totalChunks) {
            $found = $false
            for ($i = 0; $i -lt $totalChunks; $i++) {
                if ($doneMap.ContainsKey($i)) { continue }
                if ($runspaces[$i].handle.IsCompleted) {
                    try {
                        $runspaces[$i].ps.EndInvoke($runspaces[$i].handle)
                        $cFileInfo = New-Object System.IO.FileInfo $runspaces[$i].file
                        if (-not (Test-Path $runspaces[$i].file) -or $cFileInfo.Length -ne ($runspaces[$i].end - $runspaces[$i].start + 1)) {
                            throw "Chunk size mismatch"
                        }
                        $completed++
                    }
                    catch { $chunkErrors += "[$($runspaces[$i].file)] $($_.Exception.Message)"; $completed++ }
                    $runspaces[$i].ps.Dispose(); $runspaces[$i].rs.Dispose()
                    $doneMap[$i] = $true; $found = $true
                    break
                }
            }
            if ($ProgressInfo) {
                $bytesNow = 0
                foreach ($cf in $chunkFiles) {
                    try {
                        $fi3 = New-Object System.IO.FileInfo $cf
                        if ($fi3.Exists) { $bytesNow += $fi3.Length }
                    } catch {}
                }
                $ProgressInfo.Current = $bytesNow
                if ($totalSize -gt 0) { $ProgressInfo.Percent = [math]::Min(99, [math]::Round($bytesNow / $totalSize * 100)) }
                if ($lastSw.ElapsedMilliseconds -ge 1000) {
                    $delta = $bytesNow - $lastBytes
                    $secs = $lastSw.ElapsedMilliseconds / 1000
                    if ($secs -gt 0 -and $delta -ge 0) { $ProgressInfo.Speed = [long]($delta / $secs) }
                    $lastBytes = $bytesNow; $lastSw.Restart()
                }
            }
            if (-not $found) { Start-Sleep -Milliseconds 500 }
        }
        $sw.Stop()
        if ($chunkErrors.Count -gt 0) {
            foreach ($cf in $chunkFiles) { try { [System.IO.File]::Delete($cf) } catch {} }
            return @{ok=$false;err="Chunk errors: $($chunkErrors -join '; ')"}
        }
        $fs2 = [System.IO.File]::Create($OutFile)
        $mergeBuf = [System.Array]::CreateInstance([System.Byte], 1048576)
        foreach ($cf in $chunkFiles) {
            $fsIn = [System.IO.File]::OpenRead($cf)
            while (($nm = $fsIn.Read($mergeBuf, 0, $mergeBuf.Length)) -gt 0) { $fs2.Write($mergeBuf, 0, $nm) }
            $fsIn.Close()
        }
        $fs2.Close()
        foreach ($cf in $chunkFiles) { try { [System.IO.File]::Delete($cf) } catch {} }
        $fi2 = [System.IO.File]::OpenRead($OutFile); $actualSize = $fi2.Length; $fi2.Close()
        if ($actualSize -ne $totalSize) {
            try { [System.IO.File]::Delete($OutFile) } catch {}
            return @{ok=$false;err="Merged size mismatch: got $actualSize expected $totalSize"}
        }
        if ($ProgressInfo) { $ProgressInfo.Percent = 100; $ProgressInfo.Speed = 0 }
        return @{ok=$true;path=$OutFile;size=$totalSize}
    } catch { return @{ok=$false;err=$_.Exception.Message} }
}

$watcherLog = Join-Path $env:TEMP "bsmap_watcher.log"
try { Add-Content -Path $watcherLog -Value "[$(Get-Date -Format 'HH:mm:ss')] [WATCHER] Watcher iniciado" -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
$steamLibs = Get-SteamLibraries
if ($steamLibs.Count -eq 0) { try { Add-Content -Path $watcherLog -Value "[$(Get-Date -Format 'HH:mm:ss')] [WATCHER] ERROR: No se encontro Steam" -Encoding UTF8 } catch {}; return }

$log.AppendText("Librerias: $($steamLibs -join ', ')`r`n"); [System.Windows.Forms.Application]::DoEvents()
foreach ($sl in $steamLibs) { $cp = Join-Path $sl "steamapps\common"; $log.AppendText("  common en: $cp ($(if (Test-Path -LiteralPath $cp) { 'EXISTE' } else { 'NO EXISTE' }))`r`n"); [System.Windows.Forms.Application]::DoEvents() }

$watcher = New-Object System.Windows.Forms.Timer
$watcher.Interval = 3000

$knownDirs = @{}
$pendingJobs = @{}
$pendingExtract = @{}
$fixesCache = @{}
$fixesLoaded = $false
$apiRetryTick = 0
$tickCount = 0
$downloadProgress = $null
$downloadName = $null

$fixesFallback = @(
    @{fn="ACOrigins.zip";sz=301244266},
    @{fn="Assasin.Creed.2.zip";sz=15279290},
    @{fn="bin.Watch.dog.legion.zip";sz=420834764},
    @{fn="BlackMithWukong.zip";sz=311804015},
    @{fn="Call.of.Duty.-.Black.Ops.zip";sz=14055409},
    @{fn="Call.of.duty.2.MW.remaster.zip";sz=91368153},
    @{fn="Call.of.Duty.4.Modern.Warfare.zip";sz=1452244},
    @{fn="Call.Of.Duty.Black.Ops.2.2.fix.zip";sz=4462719},
    @{fn="Call.of.Duty.Black.Ops.Cold.War.zip";sz=32091},
    @{fn="Call.of.Duty.Black.Ops.II.zip";sz=4463647},
    @{fn="Call.of.Duty.Black.Ops.III.zip";sz=1368154},
    @{fn="Call.of.Duty.Infinite.Warfare.zip";sz=5122830},
    @{fn="Call.of.Duty.Modern.Warfare.2.2009.2.zip";sz=2106367},
    @{fn="Call.Of.Duty.Modern.Warfare.2019.zip";sz=29201831},
    @{fn="Call.of.Duty.Modern.Warfare.3.2011.zip";sz=10936761},
    @{fn="Call.of.Duty.Vanguard.zip";sz=25647327},
    @{fn="F1.2021.zip";sz=309920736},
    @{fn="F1.22.zip";sz=28392809},
    @{fn="Far.Cry.3.zip";sz=33310094},
    @{fn="Far.Cry.4.zip";sz=50742467},
    @{fn="Far.cry.5.zip";sz=143957511},
    @{fn="Far.Cry.New.Down.zip";sz=262675288},
    @{fn="Far.Cry.Primal.zip";sz=21985},
    @{fn="Fifa.22.zip";sz=364368021},
    @{fn="God.of.War.Ragnarok.zip";sz=13940837},
    @{fn="GTA.San.Andreas.The.Definitive.Edition.zip";sz=56912096},
    @{fn="Gtaiv.zip";sz=11224486},
    @{fn="GTAV.ENHANCED.zip";sz=70748898},
    @{fn="Hitman.Absolution.zip";sz=16734971},
    @{fn="Hitman.World.Of.Asassin.zip";sz=123515400},
    @{fn="LEGO.Batman.-.Legacy.of.the.Dark.Knight.zip";sz=216146404},
    @{fn="Metal.gear.5.zip";sz=89768960},
    @{fn="Mortal.Kombat.X.zip";sz=19185352},
    @{fn="Need.For.Speed.Heat.zip";sz=207521431},
    @{fn="Need.For.Speed.Most.Wanted.zip";sz=5702979},
    @{fn="pragmata.zip";sz=6158895},
    @{fn="Red.Dead.Redemption.1.Bypass.zip";sz=21234364},
    @{fn="Red.Dead.Redemption.2.zip";sz=84793516},
    @{fn="Resident.evil.requiem.zip";sz=297674333},
    @{fn="Sniper.Elite.4.zip";sz=124207965},
    @{fn="stellar.blade.zip";sz=200177998},
    @{fn="The.Crew.2.zip";sz=52472429},
    @{fn="Watch.Dogs.2.zip";sz=23187383},
    @{fn="Watch.Dogs.zip";sz=45401226}
)

$watcher.Add_Tick({
    $script:tickCount++
    try {
        if ($tickCount % 40 -eq 0) { $script:steamLibs = Get-SteamLibraries }
        # ── cargar catalogo (max 1 vez cada 3 minutos) ──
        if (-not $script:fixesLoaded -and $script:tickCount -gt $script:apiRetryTick) {
            $script:apiRetryTick = $script:tickCount + 60
            $ok = $false
            try {
                $jsonUrl = "https://raw.githubusercontent.com/bastisayes/Fixes-steam/main/fixes_list.json"
                $wc = New-Object System.Net.WebClient; $jsonText = $wc.DownloadString($jsonUrl); $wc.Dispose()
                $parsed = $jsonText | ConvertFrom-Json
                foreach ($f in $parsed) {
                    $name = $f.filename -replace '\.zip$', ''
                    $script:fixesCache[$name] = @{url="https://github.com/bastisayes/Fixes-steam/releases/download/bastisss/$($f.filename)"; size=$f.size}
                }
                $ok = $true
                & $script:lg "Catalogo fixes_list.json: $($fixesCache.Count) fixes"
                try { [System.IO.File]::WriteAllText([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "bsmap_fixlist.cache"), $jsonText) } catch {}
            } catch { & $script:lg "ERROR fixes_list.json: $($_.Exception.Message)" }
            if (-not $ok) {
                try {
                    $cacheFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "bsmap_fixlist.cache")
                    if (Test-Path $cacheFile) {
                        $cached = Get-Content $cacheFile -Raw | ConvertFrom-Json
                        foreach ($f in $cached) {
                            $name = $f.filename -replace '\.zip$', ''
                            $script:fixesCache[$name] = @{url="https://github.com/bastisayes/Fixes-steam/releases/download/bastisss/$($f.filename)"; size=$f.size}
                        }
                        & $script:lg "Catalogo cache: $($fixesCache.Count) fixes"
                        $ok = $true
                    }
                } catch {}
            }
            if (-not $ok) {
                foreach ($f in $script:fixesFallback) {
                    $name = $f.fn -replace '\.zip$', ''
                    $script:fixesCache[$name] = @{url="https://github.com/bastisayes/Fixes-steam/releases/download/bastisss/$($f.fn)"; size=$f.sz}
                }
                & $script:lg "Catalogo fallback: $($fixesCache.Count) fixes"
            }
            if ($fixesCache.Count -gt 0) { $script:fixesLoaded = $true; $script:apiRetryTick = $script:tickCount + 999999 }
        }

        # ── detectar descargas ──
        $activeCount = 0
        $activeNames = @()
        foreach ($lib in $steamLibs) {
            $dlDir = Join-Path (Join-Path $lib "steamapps") "downloading"
            if (-not (Test-Path $dlDir)) { continue }
            foreach ($sub in Get-ChildItem $dlDir -Directory -ErrorAction SilentlyContinue) {
                $appid = $sub.Name
                if ($sub.CreationTime -lt (Get-Date).AddDays(-1)) { continue }
                $activeCount++
                $gn = Get-AppName $appid $steamLibs
                if ($gn) { $activeNames += "$gn ($appid)" }
                if ($knownDirs.ContainsKey($appid) -or $pendingJobs.ContainsKey($appid)) { continue }
                if (-not $gn) { $knownDirs[$appid] = $true; continue }
                & $script:lg "Buscando fix para: $gn ... "
                $fixInfo = Find-Fix $gn
                if (-not $fixInfo) { & $script:lg "NO ENCONTRADO"; continue }
                $gameFolder = Find-CommonFolder $gn $steamLibs
                if (-not $gameFolder) {
                    foreach ($fk in $fixesCache.Keys) {
                        $gameFolder = Find-CommonFolder $fk $steamLibs
                        if ($gameFolder) { break }
                    }
                }
                if (-not $gameFolder) { & $script:lg "ENCONTRADO, esperando carpeta..."; continue }
                $knownDirs[$appid] = $true
                $zipPath = Join-Path $gameFolder "$(Normalize-Name $gn).predl.zip"
                & $script:lg "ENCONTRADO! descargando a: $gameFolder"
                & $script:st "Descargando fix para $gn..."
                # Iniciar job en segundo plano (runspace with inline function)
                $ps = [powershell]::Create()
                $rs = [RunspaceFactory]::CreateRunspace()
                $ps.Runspace = $rs
                $rs.Open()
                $progressInfo = [hashtable]::Synchronized(@{Percent=0;Speed=0;Current=0;Total=0;DlHost="";RetryCount=0;LogMsg=$null})
                $script:downloadProgress = $progressInfo
                $script:downloadName = $gn
                & $script:lg "  URL: $($fixInfo.url)"
                $funcSrc = (Get-Command Start-GitHubDownload).Definition
                $sb = {
                    param($url, $zip, $ua, $sz, $pi, $fsrc)
                    Invoke-Expression ('function Start-GitHubDownload { ' + $fsrc + ' }')
                    Start-GitHubDownload -Url $url -OutFile $zip -UserAgent $ua -KnownSize $sz -ProgressInfo $pi
                }
                [void]$ps.AddScript($sb).AddArgument($fixInfo.url).AddArgument($zipPath).AddArgument($ua).AddArgument([long]$fixInfo.size).AddArgument($progressInfo).AddArgument($funcSrc)
                $handle = $ps.BeginInvoke()
                $pendingJobs[$appid] = @{ps=$ps;handle=$handle;gn=$gn;zip=$zipPath;dest=$gameFolder;rs=$rs;progress=$progressInfo;dlPath=(Join-Path $dlDir $appid)}
            }
        }

        # ── verificar jobs completados ──
        $doneJobs = @()
        foreach ($appid in $pendingJobs.Keys) {
            $info = $pendingJobs[$appid]
            if (-not $info.handle.IsCompleted) { continue }
            try {
                $result = $info.ps.EndInvoke($info.handle)
            } catch { $result = @{ok=$false;err=$_.Exception.Message} }
            $info.ps.Dispose()
            $info.rs.Dispose()
            if ($result -and $result.ok) {
                $sz = $result.size
                & $script:lg "  Descarga OK ($([math]::Round($sz/1KB,0)) KB)"
                $script:pendingExtract[$appid] = @{zip=$info.zip;dest=$info.dest;gn=$info.gn;readyTick=-1;done=$false;dlPath=$info.dlPath}
            } else {
                $err = if ($result -and $result.err) { $result.err } else { "desconocido" }
                & $script:st "Error descargando fix para $($info.gn)" "#f85149"
                & $script:lg "ERROR descarga: $($info.gn) - $err"
            }
            $doneJobs += $appid
        }
        foreach ($appid in $doneJobs) { $pendingJobs.Remove($appid) }

        # ── extraer fixes cuando el juego ya este instalado en common ──
        $doneExtract = @()
        foreach ($appid in $pendingExtract.Keys) {
            $ex = $script:pendingExtract[$appid]
            if ($ex.done) { $doneExtract += $appid; continue }
            # 1) Verificar que la carpeta del juego exista y tenga archivos
            $hasFiles = $false
            try { $hasFiles = ([System.IO.Directory]::GetFiles($ex.dest, "*", [System.IO.SearchOption]::TopDirectoryOnly).Length -gt 0) } catch {}
            if (-not $hasFiles) {
                if ($ex.readyTick -ge 0) { & $script:lg "  Esperando archivos en: $($ex.dest)" }
                $ex.readyTick = -1
                continue
            }
            # 2) Verificar que Steam ya no este descargando el juego (carpeta downloading/APPID vacia o eliminada)
            $steamStillDownloading = $false
            if ($ex.dlPath -and (Test-Path $ex.dlPath)) {
                try {
                    $dlFiles = [System.IO.Directory]::GetFiles($ex.dlPath, "*", [System.IO.SearchOption]::AllDirectories)
                    $dlSize = 0; foreach ($f in $dlFiles) { $dlSize += (New-Object System.IO.FileInfo $f).Length }
                    if ($dlSize -gt 10MB) { $steamStillDownloading = $true }
                } catch { $steamStillDownloading = $false }
            }
            if ($steamStillDownloading) {
                if ($ex.readyTick -ge 0) { & $script:lg "  Steam aun descargando, esperando..." }
                $ex.readyTick = -1
                continue
            }
            # 3) Marcar tick de listo y esperar estabilidad (2 ticks = ~6s)
            if ($ex.readyTick -lt 0) {
                $ex.readyTick = $script:tickCount
                & $script:lg "  Juego detectado en common, esperando estabilidad..."
                continue
            }
            $elapsedTicks = $script:tickCount - $ex.readyTick
            if ($elapsedTicks -lt 2) { continue }
            # 4) Extraer
            try {
                & $script:st "Extrayendo fix para $($ex.gn)..." "#ffaa00"
                Expand-Archive -Path $ex.zip -DestinationPath $ex.dest -Force
                & $script:st "Fix aplicado a $($ex.gn)!" "#00ff88"
                & $script:lg "FIX APLICADO: $($ex.gn) -> $($ex.dest)"
            } catch {
                & $script:st "Error extrayendo fix en $($ex.gn)" "#f85149"
                & $script:lg "ERROR extrayendo fix: $($_.Exception.Message)"
            }
            Remove-Item $ex.zip -Force -ErrorAction SilentlyContinue
            $ex.done = $true
            $doneExtract += $appid
        }
        foreach ($appid in $doneExtract) { $script:pendingExtract.Remove($appid) }

        # ── progreso de descarga (antes de limpiar downloadProgress) ──
        if ($script:downloadProgress -and $script:downloadProgress.Percent -ge 0) {
            $pi = $script:downloadProgress
            $pct = $pi.Percent
            $speed = $pi.Speed
            $cur = $pi.Current
            $tot = $pi.Total
            $dlHost = $pi.DlHost
            $retry = $pi.RetryCount
            $logMsg = $pi.LogMsg
            if ($logMsg) { & $script:lg "  $logMsg"; $pi.LogMsg = $null }
            if ($script:progressBar.Visible -eq $false) { $script:progressBar.Visible = $true; $script:speedLabel.Visible = $true }
            if ($pct -le 99) {
                $script:progressBar.Value = $pct
                $speedText = if ($speed -ge 1MB) { "$([math]::Round($speed/1MB,1)) MB/s" } elseif ($speed -ge 1KB) { "$([math]::Round($speed/1KB,0)) KB/s" } else { "0 B/s" }
                $hostText = if ($dlHost) { "$dlHost " } else { "" }
                $retryText = if ($retry -gt 0) { " (reintento $retry)" } else { "" }
                $script:speedLabel.Text = "$hostText$speedText  $pct%$retryText"
                $script:speedLabel.ForeColor = "#00ff88"
            } else {
                $script:progressBar.Value = 100
                $script:speedLabel.Text = "Completado!"
                $script:speedLabel.ForeColor = "#00ff88"
            }
        } elseif ($script:pendingJobs.Count -eq 0 -and $script:progressBar.Visible) {
            $script:progressBar.Visible = $false
            $script:speedLabel.Visible = $false
        }
        if ($doneJobs.Count -gt 0 -and $pendingJobs.Count -eq 0) { $script:downloadProgress = $null; $script:downloadName = $null }

        $names = if ($activeNames.Count -gt 0) { $activeNames -join ', ' } else { "ninguna" }
        & $script:st "$activeCount descarga(s): $names  |  Pendientes: $($pendingJobs.Count)"
    } catch { & $script:st "Watcher error: $($_.Exception.Message.Trim())" "#f85149"; & $script:lg "ERROR interno: $($_.Exception.GetType().Name): $($_.Exception.Message.Trim())" }
})

$watcher.Start()
$running = $true
while ($running) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 200 }
$watcher.Stop()
$watcher.Dispose()
foreach ($kv in $pendingJobs.Keys) {
    $j = $pendingJobs[$kv]
    if (-not $j.handle.IsCompleted) { $j.ps.Stop() }
    $j.ps.Dispose()
    $j.rs.Dispose()
}
$pendingJobs.Clear()

