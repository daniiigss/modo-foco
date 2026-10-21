# Modo Foco

Cierra de golpe todas tus apps salvo las que tú elijas, para que el PC dedique la RAM a lo que estás haciendo. Y luego las vuelve a abrir.

- **No necesita permisos de administrador**: solo cierra procesos de tu propio usuario.
- **Nunca toca Windows**: lo que vive en `C:\Windows` no se cierra nunca, ni los procesos hijos de una app permitida (las pestañas de Chrome, por ejemplo).
- **No pierde trabajo**: una ventana que no se cierra sola (Word preguntando si guardar) se queda abierta; jamás se fuerza.

## Instalar

En **PowerShell** (no hace falta abrirlo como administrador):

```powershell
irm https://raw.githubusercontent.com/daniiigss/modo-foco/main/instalar.ps1 | iex
```

Se instala en `%LOCALAPPDATA%\ModoFoco` y crea dos accesos directos en el escritorio. El mismo comando sirve para **actualizar**: tu lista de apps, tus perfiles y tu línea base no se pisan.

¿Prefieres revisar el código antes? Descarga el ZIP (**Code → Download ZIP**), descomprímelo y ejecuta:

```powershell
powershell -ExecutionPolicy Bypass -File instalar.ps1
```

## Usar

| Acceso directo | Qué hace |
|---|---|
| **Modo Foco** | Abre la checklist con todas tus apps (las abiertas arriba, con su RAM). Marca las que se quedan y pulsa **Activar foco**: primero simula, te enseña qué cerraría y te pregunta. **Restaurar** las vuelve a abrir. |
| **Medir rendimiento** | La primera vez guarda una foto del PC (línea base). Las siguientes te compara RAM, procesos y disco con ella. |

Sin la ventana, desde la consola, en `%LOCALAPPDATA%\ModoFoco`:

```powershell
.\Modo-Foco.ps1             # simulación: no cierra nada
.\Modo-Foco.ps1 -Aplicar    # cierra lo que no está en la lista
.\Modo-Foco.ps1 -Restaurar  # vuelve a abrir lo que cerró
```

## Requisitos

- Windows 10 u 11, con PowerShell 5.1 (viene de serie).
- **Python 3** solo para la ventana con casillas. Sin él, Modo Foco funciona en consola. Para instalarlo sin admin:
  `winget install --id Python.Python.3.12 --scope user`
- En PCs de empresa con AppLocker o *Constrained Language Mode*, el administrador puede tener bloqueados los scripts.

## Archivos

| Archivo | Para qué |
|---|---|
| `Modo-Foco.ps1` | El motor: simula, cierra y restaura. |
| `modo_foco_gui.py` + `Modo-Foco.bat` | La checklist (tkinter) y su lanzador sin consola. |
| `listar_apps.ps1` | Lista las apps del menú Inicio y las abiertas, para la checklist. |
| `lista_blanca.ejemplo.txt` | Lista de partida; tu lista real es `lista_blanca.txt` y no se sube al repo. |
| `perfiles.json` | Botones de la checklist (p. ej. «Básicos»). Añade los tuyos. |
| `Medir-Rendimiento.ps1` | Comparación con la línea base de cada PC. |
| `instalar.ps1` | Instalación y actualización sin admin. |

## Desinstalar

Borra la carpeta `%LOCALAPPDATA%\ModoFoco` y los dos accesos directos del escritorio. No deja nada más.
