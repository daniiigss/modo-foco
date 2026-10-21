# Compares this PC right now with its own baseline. The first run saves the baseline
# in linea_base.json; -NuevaLineaBase saves it again (e.g. after a clean Windows install).
param([switch]$NuevaLineaBase)

$baseFile = Join-Path $PSScriptRoot 'linea_base.json'
$os       = Get-CimInstance Win32_OperatingSystem
$uptime   = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalMinutes)
$now = [ordered]@{
    Fecha      = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    UptimeMin  = $uptime
    RamFreeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    CommitGB   = [math]::Round(($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / 1MB, 1)
    Processes  = (Get-Process).Count
    DiskFreeGB = [math]::Round((Get-Volume ($env:SystemDrive.TrimEnd(':'))).SizeRemaining / 1GB, 1)
}

if ($NuevaLineaBase -or -not (Test-Path $baseFile)) {
    [pscustomobject]$now | ConvertTo-Json | Set-Content $baseFile -Encoding UTF8
    Write-Host ''
    Write-Host '  Linea base guardada: es la foto de este PC hoy.' -ForegroundColor Cyan
    Write-Host ('  RAM libre {0} GB | memoria usada {1} GB | {2} procesos | disco libre {3} GB' -f $now.RamFreeGB, $now.CommitGB, $now.Processes, $now.DiskFreeGB)
    if ($uptime -lt 15) { Write-Host ('  Ojo: el PC lleva {0} min encendido. Para una foto justa, repitela a los 20 min con -NuevaLineaBase.' -f $uptime) -ForegroundColor Yellow }
    Write-Host '  Las proximas veces te compara con ella.'
    Write-Host ''
    Read-Host '  Pulsa Enter para cerrar'
    return
}

$baseline = Get-Content $baseFile -Raw -Encoding UTF8 | ConvertFrom-Json

function Row($label, $before, $after, $better) {
    $ok = if ($better -eq 'up') { $after -ge $before } else { $after -le $before }
    Write-Host ('  {0,-22} {1,10} {2,10}' -f $label, $before, $after) -ForegroundColor $(if ($ok) { 'Green' } else { 'Yellow' })
}

Write-Host ''
Write-Host ('  RENDIMIENTO: AHORA vs LINEA BASE ({0})' -f $baseline.Fecha) -ForegroundColor Cyan
Write-Host ('  {0,-22} {1,10} {2,10}' -f '', 'Base', 'Ahora')
Row 'RAM libre (GB)'     $baseline.RamFreeGB  $now.RamFreeGB  'up'
Row 'Memoria usada (GB)' $baseline.CommitGB   $now.CommitGB   'down'
Row 'Procesos'           $baseline.Processes  $now.Processes  'down'
Row 'Disco libre (GB)'   $baseline.DiskFreeGB $now.DiskFreeGB 'up'
Write-Host ''
Write-Host ('  Encendido hace {0} min. La linea base se tomo a los {1} min.' -f $uptime, $baseline.UptimeMin)
if ($uptime -lt 15) { Write-Host '  Aun es pronto: Windows sigue cargando cosas. Vuelve a medir pasados 20 min.' -ForegroundColor Yellow }

Write-Host ''
Write-Host '  Lo que mas RAM usa ahora:' -ForegroundColor Cyan
Get-Process | Group-Object ProcessName | ForEach-Object {
    [pscustomobject]@{ Name = $_.Name; MB = [math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB) }
} | Sort-Object MB -Descending | Select-Object -First 8 | ForEach-Object { Write-Host ('  {0,-28} {1,6} MB' -f $_.Name, $_.MB) }
Write-Host ''
Read-Host '  Pulsa Enter para cerrar'
