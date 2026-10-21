@echo off
rem Opens the Modo Foco checklist without a console window.
rem Without Python it falls back to the console version (simulation mode).
where pyw >nul 2>nul && (start "" pyw "%~dp0modo_foco_gui.py" & exit /b)
where pythonw >nul 2>nul && (start "" pythonw "%~dp0modo_foco_gui.py" & exit /b)
echo No se encontro Python: abro el Modo Foco en consola, en modo simulacion.
echo Para tener la ventana con casillas instala Python, sin admin:
echo     winget install --id Python.Python.3.12 --scope user
echo.
powershell -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0Modo-Foco.ps1"
