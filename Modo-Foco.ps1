<#
Modo Foco: cierra tus apps que no estén en lista_blanca.txt.

  .\Modo-Foco.ps1             -> SIMULACIÓN: solo enseña qué cerraría
  .\Modo-Foco.ps1 -Aplicar    -> las cierra y apunta cuáles
  .\Modo-Foco.ps1 -Restaurar  -> vuelve a abrir lo que cerró el último -Aplicar

Never touches Windows processes (anything under C:\Windows), processes of other
sessions, this console, or children of a whitelisted app. Windows that don't close
gracefully (e.g. Word asking to save) are left open, never force-killed.
#>
param([switch]$Aplicar, [switch]$Restaurar)

$dir        = $PSScriptRoot
$listFile   = Join-Path $dir 'lista_blanca.txt'
$closedFile = Join-Path $dir 'cerradas_ultima_vez.csv'

function Split-CommandLine($cmd, $exe) {
    if (-not $cmd) { return '' }
    if ($cmd.StartsWith('"')) { $end = $cmd.IndexOf('"', 1) } else { $end = $cmd.IndexOf(' ') }
    if ($end -lt 0) { return '' }
    return $cmd.Substring($end + 1).Trim()
}

if ($Restaurar) {
    if (-not (Test-Path $closedFile)) { 'No hay nada que restaurar.'; return }
    $roots = Import-Csv $closedFile | Where-Object { $_.Root -eq 'True' } | Sort-Object CommandLine -Unique
    foreach ($r in $roots) {
        if ($r.Path -like '*\WindowsApps\*') { "Tienda      $($r.Name): se reabre sola al iniciar sesión, o ábrela desde Inicio"; continue }
        try {
            $argLine = Split-CommandLine $r.CommandLine $r.Path
            if ($argLine) { Start-Process -FilePath $r.Path -ArgumentList $argLine -WorkingDirectory (Split-Path $r.Path) -ErrorAction Stop }
            else       { Start-Process -FilePath $r.Path -WorkingDirectory (Split-Path $r.Path) -ErrorAction Stop }
            "Abierta     $($r.Name)"
        } catch { "NO abierta  $($r.Name) (ábrela a mano): $($_.Exception.Message)" }
    }
    Remove-Item $closedFile
    return
}

if (-not (Test-Path $listFile)) { "Falta $listFile"; exit 1 }
$whitelist = Get-Content $listFile -Encoding UTF8 |
    ForEach-Object { ($_ -split '#')[0].Trim() -replace '\.exe$', '' } |
    Where-Object { $_ }
$whitelist = [System.Collections.Generic.HashSet[string]]::new([string[]]$whitelist, [StringComparer]::OrdinalIgnoreCase)

$session = (Get-Process -Id $PID).SessionId
$all  = Get-CimInstance Win32_Process
$byId = @{}
foreach ($p in $all) { $byId[[int]$p.ProcessId] = $p }

function Get-ExePath($p) { if ($p.ExecutablePath) { $p.ExecutablePath -replace '^\\\\\?\\', '' } }
function Get-ShortName($p) { [IO.Path]::GetFileNameWithoutExtension($p.Name) }

# Real parent only: a recycled PID is newer than its "child".
function Get-Parent($p) {
    $parent = $byId[[int]$p.ParentProcessId]
    if ($parent -and $parent.CreationDate -le $p.CreationDate -and $parent.ProcessId -ne $p.ProcessId) { $parent }
}

# This console and everything above it stays alive.
$keep = [System.Collections.Generic.HashSet[int]]::new()
$cur = $byId[$PID]
while ($cur -and $keep.Add([int]$cur.ProcessId)) { $cur = Get-Parent $cur }

function Test-Protected($p) {
    $path = Get-ExePath $p
    if (-not $path) { return $true }                       # unreadable: elevated or protected
    if ($path -like "$env:windir\*") { return $true }      # Windows itself
    if ($keep.Contains([int]$p.ProcessId)) { return $true }
    $node = $p
    while ($node) {                                        # itself or a whitelisted ancestor
        if ($whitelist.Contains((Get-ShortName $node)) -and -not ((Get-ExePath $node) -like "$env:windir\*")) { return $true }
        $node = Get-Parent $node
    }
    return $false
}

$targets = $all | Where-Object { $_.SessionId -eq $session -and -not (Test-Protected $_) }
if (-not $targets) { 'Nada que cerrar: todo lo que corre está en la lista blanca.'; return }

$targetIds = [System.Collections.Generic.HashSet[int]]::new([int[]]@($targets | ForEach-Object { [int]$_.ProcessId }))
$rows = foreach ($t in $targets) {
    $parent = Get-Parent $t
    $gp = Get-Process -Id $t.ProcessId -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Name        = Get-ShortName $t
        Id          = [int]$t.ProcessId
        MB          = [math]::Round($t.WorkingSetSize / 1MB)
        Window      = [bool]($gp -and $gp.MainWindowHandle -ne 0)
        Parent      = if ($parent) { Get-ShortName $parent } else { '-' }
        # Only what you or Windows startup launched is reopened; helpers are recreated by their parent app.
        Root        = (-not $parent) -or ($parent.Name -in 'explorer.exe', 'svchost.exe', 'userinit.exe')
        Path        = Get-ExePath $t
        CommandLine = $t.CommandLine
    }
}

$rows | Group-Object Name | ForEach-Object {
    [pscustomobject]@{
        App        = $_.Name
        Procesos   = $_.Count
        RAM_MB     = ($_.Group | Measure-Object MB -Sum).Sum
        Ventana    = if ($_.Group.Window -contains $true) { 'sí' } else { '' }
        LanzadaPor = ($_.Group.Parent | Sort-Object -Unique) -join ', '
    }
} | Sort-Object RAM_MB -Descending | Format-Table -AutoSize | Out-String -Width 200
'RAM a liberar: ~{0:N0} MB' -f ($rows | Measure-Object MB -Sum).Sum

if (-not $Aplicar) {
    ''
    'SIMULACIÓN: no se ha cerrado nada.'
    'Si te falta algo, añádelo a lista_blanca.txt. Para cerrar de verdad: .\Modo-Foco.ps1 -Aplicar'
    return
}

$rows | Select-Object Name, Path, CommandLine, Root | Export-Csv $closedFile -NoTypeInformation -Encoding UTF8

# Windows first, gracefully, so apps can save; background processes after.
foreach ($r in $rows | Where-Object Window) {
    $gp = Get-Process -Id $r.Id -ErrorAction SilentlyContinue
    if ($gp) { [void]$gp.CloseMainWindow() }
}
Start-Sleep -Seconds 5
foreach ($r in $rows) {
    $gp = Get-Process -Id $r.Id -ErrorAction SilentlyContinue
    if (-not $gp) { continue }
    if ($r.Window) { "Sigue abierta $($r.Name): quizá te pide guardar. Ciérrala tú."; continue }
    try { Stop-Process -Id $r.Id -Force -ErrorAction Stop }
    catch { if ($_.FullyQualifiedErrorId -notlike 'NoProcessFoundForGivenId*') { "No se pudo cerrar $($r.Name): $($_.Exception.Message)" } }   # already gone with its parent
}
''
'Modo Foco activo. Para volver: .\Modo-Foco.ps1 -Restaurar'
