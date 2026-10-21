# Prints, as JSON, the apps the Modo Foco checklist can offer:
# Start Menu shortcuts (installed apps) + processes running in this session.
# Windows' own processes are left out: Modo-Foco.ps1 never closes them anyway.
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$apps  = @{}
$shell = New-Object -ComObject WScript.Shell
$menus = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"

foreach ($lnk in Get-ChildItem $menus -Recurse -Filter *.lnk) {
    $target = $shell.CreateShortcut($lnk.FullName).TargetPath
    if (-not $target -or $target -notlike '*.exe' -or $target -like "$env:windir\*") { continue }
    $exe = [IO.Path]::GetFileNameWithoutExtension($target)
    if ($exe -match '^(unins|uninst|setup|installer|updater)$|^unins') { continue }
    if ($lnk.BaseName -match 'activate|uninstall|desinstalar|update|actualiz|telemetr|manual|preferencias') { continue }
    if (-not $apps.ContainsKey($exe)) { $apps[$exe] = [ordered]@{ exe = $exe; name = $lnk.BaseName; ram = 0; running = $false } }
}

$session = (Get-Process -Id $PID).SessionId
foreach ($p in Get-CimInstance Win32_Process) {
    if ($p.SessionId -ne $session -or -not $p.ExecutablePath) { continue }
    if (($p.ExecutablePath -replace '^\\\\\?\\', '') -like "$env:windir\*") { continue }
    $exe = [IO.Path]::GetFileNameWithoutExtension($p.Name)
    if (-not $apps.ContainsKey($exe)) { $apps[$exe] = [ordered]@{ exe = $exe; name = $exe; ram = 0; running = $false } }
    $apps[$exe].ram += [math]::Round($p.WorkingSetSize / 1MB)
    $apps[$exe].running = $true
}

ConvertTo-Json @($apps.Values) -Compress
