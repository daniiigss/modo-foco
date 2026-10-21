<#
Installs (or updates) Modo Foco on this PC. No administrator rights needed.

  From GitHub, in PowerShell:
    irm https://raw.githubusercontent.com/daniiigss/modo-foco/main/instalar.ps1 | iex

  From a downloaded copy:
    powershell -ExecutionPolicy Bypass -File instalar.ps1

Everything goes to %LOCALAPPDATA%\ModoFoco plus two desktop shortcuts.
Your whitelist, profiles and baseline are never overwritten on update.
#>
$ErrorActionPreference = 'Stop'
$repo = 'daniiigss/modo-foco'
$dest = Join-Path $env:LOCALAPPDATA 'ModoFoco'
$personal = 'lista_blanca.txt', 'perfiles.json', 'linea_base.json'

Write-Host ''
Write-Host '  Instalando Modo Foco (sin permisos de administrador)...' -ForegroundColor Cyan

# 1. Source: this folder when run from a copy, the GitHub zip when run through irm | iex
$here = if ($PSCommandPath) { Split-Path $PSCommandPath } else { $null }
if ($here -and (Test-Path (Join-Path $here 'Modo-Foco.ps1'))) {
    $src = $here
} else {
    $zip = Join-Path $env:TEMP 'modo-foco.zip'
    $tmp = Join-Path $env:TEMP 'modo-foco-src'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest "https://github.com/$repo/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive $zip $tmp -Force
    $src = (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName
}

# 2. Copy, keeping the user's own files
New-Item -ItemType Directory $dest -Force | Out-Null
Get-ChildItem $src -File | Where-Object { $_.Name -notin $personal -or -not (Test-Path (Join-Path $dest $_.Name)) } |
    Copy-Item -Destination $dest -Force
if (-not (Test-Path (Join-Path $dest 'lista_blanca.txt'))) {
    Copy-Item (Join-Path $dest 'lista_blanca.ejemplo.txt') (Join-Path $dest 'lista_blanca.txt')
}
Get-ChildItem $dest -File | Unblock-File   # downloaded files carry a "from the internet" mark

# 3. Desktop shortcuts
$desk = [Environment]::GetFolderPath('Desktop')
$sh = New-Object -ComObject WScript.Shell
$lnk = $sh.CreateShortcut((Join-Path $desk 'Modo Foco.lnk'))
$lnk.TargetPath = Join-Path $dest 'Modo-Foco.bat'; $lnk.WorkingDirectory = $dest
$lnk.IconLocation = "$env:windir\System32\shell32.dll,43"; $lnk.WindowStyle = 7; $lnk.Save()
$lnk = $sh.CreateShortcut((Join-Path $desk 'Medir rendimiento.lnk'))
$lnk.TargetPath = 'powershell.exe'; $lnk.WorkingDirectory = $dest
$lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $dest 'Medir-Rendimiento.ps1')`""
$lnk.IconLocation = "$env:windir\System32\shell32.dll,21"; $lnk.Save()

# 4. Python (only the checklist window needs it)
$py = Get-Command pyw, pythonw -ErrorAction SilentlyContinue | Select-Object -First 1
Write-Host ''
Write-Host "  Listo en $dest" -ForegroundColor Green
Write-Host '  En el escritorio: "Modo Foco" y "Medir rendimiento".'
if ($py) {
    Write-Host "  Python encontrado ($($py.Source)): la checklist abre con casillas."
} else {
    Write-Host '  No hay Python: "Modo Foco" abrira en consola. Para la ventana con casillas, sin admin:' -ForegroundColor Yellow
    Write-Host '      winget install --id Python.Python.3.12 --scope user' -ForegroundColor Yellow
}
Write-Host '  Consejo: abre "Medir rendimiento" ahora para guardar la linea base de este PC.'
Write-Host ''
