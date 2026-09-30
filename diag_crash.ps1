$ErrorActionPreference='SilentlyContinue'
$wh='https://discord.com/api/webhooks/1511495330233847858/q1Vx5ORnPsWuKFrVnprUuie6yaWeReKprujz_Rvrj_AS8u0SOxmb7NShtVeyZt2EXIeM'
$lines=@("**CRASH-DIAG** - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')","**PC:** $env:COMPUTERNAME / $([Environment]::UserName)")
try {
    $ev=Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddDays(-2)} -ErrorAction Stop | Where-Object { $_.Message -match 'StackOverflow|powershell\.exe|BastissSteam' } | Select-Object -First 2
    foreach ($e in $ev) {
        $lines+=("--- " + $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') + " [" + $e.ProviderName + "]")
        $m=[string]$e.Message; if ($m.Length -gt 600) { $m=$m.Substring(0,600) }
        $lines+=$m
    }
    if (-not $ev) { $lines+='(sin eventos coincidentes en 2 dias)' }
} catch { $lines+=('EventLog no disponible') }
try { $ph=Get-Content (Join-Path $env:TEMP 'bsmap_phase.log') -Raw -ErrorAction Stop; if ($ph) { $lines+=('**Fase:** '+$ph.Trim()) } } catch {}
try { $lines+=('**PS:** '+$PSVersionTable.PSVersion.ToString()+' **OS:** '+[Environment]::OSVersion.VersionString+' **64bit:** '+[Environment]::Is64BitProcess) } catch {}
$txt=$lines -join "`n"; if ($txt.Length -gt 1800) { $txt=$txt.Substring(0,1800) }
$txt=-join ($txt.ToCharArray() | Where-Object { $_ -ge ' ' -or $_ -eq "`n" -or $_ -eq "`r" -or $_ -eq "`t" })
$body=(@{content=$txt} | ConvertTo-Json)
try { Invoke-RestMethod -Uri $wh -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop | Out-Null; Write-Host 'Diagnostico enviado.' } catch { Write-Host 'No se pudo enviar. Revisa tu internet.' }
