"""Modo Foco checklist: choose which apps survive focus mode, then run it.

Launched by double-clicking Modo-Foco.bat. Reads and writes lista_blanca.txt and
runs Modo-Foco.ps1 (simulate / apply / restore), showing its output.
"""
import ctypes
import json
import subprocess
import threading
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, ttk

HERE = Path(__file__).resolve().parent
WHITELIST = HERE / "lista_blanca.txt"
PROFILES = HERE / "perfiles.json"
FOCUS_SCRIPT = HERE / "Modo-Foco.ps1"
LIST_SCRIPT = HERE / "listar_apps.ps1"

# Always kept: without a console, focus mode could close the window running it.
CONSOLES = {
    "powershell": "Windows PowerShell",
    "pwsh": "PowerShell 7",
    "WindowsTerminal": "Terminal de Windows",
    "cmd": "Símbolo del sistema",
}
CONSOLE_KEYS = {c.lower() for c in CONSOLES}


def run_powershell(script, *args):
    """Runs a .ps1 hidden and returns (stdout, stderr) decoded as UTF-8."""
    command = f"[Console]::OutputEncoding = [Text.Encoding]::UTF8; & '{script}' {' '.join(args)}"
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command],
        capture_output=True,
        creationflags=subprocess.CREATE_NO_WINDOW,
    )
    return result.stdout.decode("utf-8", "replace"), result.stderr.decode("utf-8", "replace")


def read_whitelist():
    """Returns {lowercase exe: (exe, description)} from lista_blanca.txt."""
    entries = {}
    if WHITELIST.exists():
        for line in WHITELIST.read_text(encoding="utf-8-sig").splitlines():
            name, _, comment = line.partition("#")
            name = name.strip()
            if name.lower().endswith(".exe"):
                name = name[:-4]
            if name:
                entries[name.lower()] = (name, comment.strip())
    return entries


def write_whitelist(selected):
    """selected: list of (exe, description), already sorted."""
    width = max(len(exe) for exe, _ in selected) + 2
    lines = [
        "# LISTA BLANCA DEL MODO FOCO - la escribe la checklist (Modo-Foco.bat).",
        "# Un nombre de proceso por línea, sin .exe. Lo que va detrás de # no cuenta.",
        "# Nunca se cierran los procesos de Windows ni los hijos de estas apps.",
        "",
    ]
    lines += [f"{exe:<{width}}# {description}" for exe, description in selected]
    WHITELIST.write_text("\n".join(lines) + "\n", encoding="utf-8")


def load_profiles():
    try:
        return json.loads(PROFILES.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError):
        return {}


class FocusChecklist:
    def __init__(self, root):
        self.root = root
        self.apps = {}   # lowercase exe -> {"exe", "name", "ram", "running"}
        self.vars = {}   # lowercase exe -> BooleanVar
        self.rows = []   # (search text, row frame), in display order

        root.title("Modo Foco")
        root.geometry("640x760")
        root.minsize(540, 600)

        header = ttk.Frame(root, padding=(12, 12, 12, 4))
        header.pack(fill="x")
        ttk.Label(header, text="Apps que pueden seguir abiertas en Modo Foco",
                  font=("Segoe UI", 12, "bold")).pack(anchor="w")
        ttk.Label(header, text="Lo de Windows nunca se cierra. Las abiertas ahora salen arriba, con su RAM.",
                  foreground="#555").pack(anchor="w")
        search_row = ttk.Frame(header)
        search_row.pack(fill="x", pady=(8, 0))
        ttk.Label(search_row, text="Buscar:").pack(side="left")
        self.search = tk.StringVar()
        self.search.trace_add("write", lambda *_: self.filter_rows())
        ttk.Entry(search_row, textvariable=self.search).pack(side="left", fill="x", expand=True, padx=(6, 0))

        presets = ttk.Frame(root, padding=(12, 4))
        presets.pack(fill="x")
        ttk.Button(presets, text="Todas", command=lambda: self.select(lambda key: True)).pack(side="left")
        ttk.Button(presets, text="Ninguna", command=lambda: self.select(lambda key: False)).pack(side="left", padx=6)
        for profile, members in load_profiles().items():
            wanted = {m.lower() for m in members}
            ttk.Button(presets, text=profile,
                       command=lambda w=wanted: self.select(lambda key: key in w)).pack(side="left", padx=(0, 6))

        box = ttk.Frame(root, padding=(12, 4))
        box.pack(fill="both", expand=True)
        self.canvas = tk.Canvas(box, highlightthickness=1, highlightbackground="#ccc", background="white")
        scrollbar = ttk.Scrollbar(box, orient="vertical", command=self.canvas.yview)
        self.inner = tk.Frame(self.canvas, background="white")
        self.inner.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        window = self.canvas.create_window((0, 0), window=self.inner, anchor="nw")
        self.canvas.bind("<Configure>", lambda e: self.canvas.itemconfigure(window, width=e.width))
        self.canvas.configure(yscrollcommand=scrollbar.set)
        self.canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        wheel = lambda e: self.canvas.yview_scroll(int(-e.delta / 120), "units")
        self.canvas.bind("<Enter>", lambda e: self.canvas.bind_all("<MouseWheel>", wheel))
        self.canvas.bind("<Leave>", lambda e: self.canvas.unbind_all("<MouseWheel>"))

        self.status = ttk.Label(root, padding=(12, 4), foreground="#1a5")
        self.status.pack(fill="x")

        actions = ttk.Frame(root, padding=(12, 4))
        actions.pack(fill="x")
        self.buttons = [
            ttk.Button(actions, text="Guardar lista", command=self.save),
            ttk.Button(actions, text="Simular", command=lambda: self.run_focus("simular")),
            ttk.Button(actions, text="Activar foco", command=lambda: self.run_focus("aplicar")),
            ttk.Button(actions, text="Restaurar", command=lambda: self.run_focus("restaurar")),
            ttk.Button(actions, text="Actualizar", command=self.reload),
        ]
        for button in self.buttons:
            button.pack(side="left", padx=(0, 6))

        self.output = tk.Text(root, height=11, font=("Consolas", 9), wrap="none", state="disabled",
                              background="#f6f6f6", relief="flat")
        self.output.pack(fill="both", padx=12, pady=(4, 12))

        self.reload()

    # --- list -------------------------------------------------------------

    def reload(self):
        self.set_busy(True, "Buscando apps instaladas y abiertas…")
        threading.Thread(target=self._load_apps, daemon=True).start()

    def _load_apps(self):
        stdout, _ = run_powershell(LIST_SCRIPT)
        try:
            data = json.loads(stdout or "[]")
        except json.JSONDecodeError:
            data = []
        self.root.after(0, self.build_list, data)

    def build_list(self, data):
        saved = read_whitelist()
        first_load = not self.vars
        previous = {key: var.get() for key, var in self.vars.items()}

        self.apps = {a["exe"].lower(): a for a in data}
        for exe, name in CONSOLES.items():
            self.apps.setdefault(exe.lower(), {"exe": exe, "name": name, "ram": 0, "running": False})
        for key, (exe, description) in saved.items():   # whitelisted but not installed/open now
            self.apps.setdefault(key, {"exe": exe, "name": description or exe, "ram": 0, "running": False})

        for _, row in self.rows:
            row.destroy()
        self.rows, self.vars = [], {}

        order = sorted(self.apps.items(),
                       key=lambda kv: (not kv[1]["running"], -kv[1]["ram"], kv[1]["name"].lower()))
        for key, app in order:
            is_console = key in CONSOLE_KEYS
            checked = True if is_console else (key in saved if first_load else previous.get(key, key in saved))
            var = tk.BooleanVar(value=checked)
            var.trace_add("write", lambda *_: self.update_status())
            self.vars[key] = var

            row = tk.Frame(self.inner, background="white")
            label = app["name"] if app["name"].lower() == key else f"{app['name']}   ({app['exe']})"
            check = tk.Checkbutton(row, text=label, variable=var, background="white", anchor="w",
                                   activebackground="white", font=("Segoe UI", 10))
            if is_console:
                check.configure(state="disabled", text=f"{label}   · siempre")
            check.pack(side="left", fill="x", expand=True)
            if app["running"]:
                tk.Label(row, text=f"● {app['ram']:,} MB".replace(",", "."), background="white",
                         foreground="#666").pack(side="right", padx=8)
            self.rows.append((f"{app['name']} {app['exe']}".lower(), row))

        self.filter_rows()
        self.set_busy(False)
        self.update_status()

    def filter_rows(self):
        query = self.search.get().strip().lower()
        for _, row in self.rows:
            row.pack_forget()
        for text, row in self.rows:
            if query in text:
                row.pack(fill="x", padx=4, pady=1)
        self.canvas.yview_moveto(0)

    def select(self, predicate):
        for key, var in self.vars.items():
            if key not in CONSOLE_KEYS:
                var.set(predicate(key))

    def update_status(self):
        if not self.vars:
            return
        marked = sum(var.get() for var in self.vars.values())
        freeable = sum(a["ram"] for key, a in self.apps.items() if a["running"] and not self.vars[key].get())
        self.status.configure(text=f"Marcadas: {marked}   ·   Al activar el foco se liberarían hasta ~{freeable:,} MB"
                              .replace(",", "."))

    # --- actions ----------------------------------------------------------

    def save(self):
        selected = [(a["exe"], a["name"]) for key, a in self.apps.items() if self.vars[key].get()]
        selected.sort(key=lambda item: (item[0].lower() not in CONSOLE_KEYS, item[1].lower()))
        write_whitelist(selected)
        self.log(f"Lista guardada: {len(selected)} apps en {WHITELIST.name}\n")

    def run_focus(self, mode):
        self.clear_log()
        if mode != "restaurar":
            self.save()
        # "Activar foco" always simulates first and asks before closing anything.
        args = ["-Restaurar"] if mode == "restaurar" else []
        self.set_busy(True, "Trabajando…")

        def work():
            stdout, stderr = run_powershell(FOCUS_SCRIPT, *args)
            self.root.after(0, self.after_run, mode, stdout + stderr)

        threading.Thread(target=work, daemon=True).start()

    def after_run(self, mode, output):
        self.log(output.strip() + "\n")
        if mode == "aplicar" and "SIMULACIÓN" in output:
            self.set_busy(False)
            if messagebox.askyesno("Activar foco",
                                   "En el panel de abajo tienes lo que se va a cerrar.\n\n"
                                   "Las ventanas que pidan guardar se quedan abiertas.\n¿Las cierro?"):
                self.clear_log()
                self.set_busy(True, "Cerrando apps…")

                def work():
                    stdout, stderr = run_powershell(FOCUS_SCRIPT, "-Aplicar")
                    self.root.after(0, self.after_run, "hecho", stdout + stderr)

                threading.Thread(target=work, daemon=True).start()
            return
        self.reload()

    # --- helpers ----------------------------------------------------------

    def set_busy(self, busy, message=""):
        for button in self.buttons:
            button.configure(state="disabled" if busy else "normal")
        if busy:
            self.status.configure(text=message)

    def clear_log(self):
        self.output.configure(state="normal")
        self.output.delete("1.0", "end")
        self.output.configure(state="disabled")

    def log(self, text):
        self.output.configure(state="normal")
        self.output.insert("end", text)
        self.output.see("end")
        self.output.configure(state="disabled")


if __name__ == "__main__":
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(1)   # sharp text on high-DPI screens
    except (AttributeError, OSError):
        pass
    root = tk.Tk()
    FocusChecklist(root)
    root.mainloop()
