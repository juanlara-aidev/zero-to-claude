# Zero to Claude

Instala [Claude Code](https://docs.anthropic.com/en/docs/claude-code) en una computadora desde cero con un solo comando. Funciona en macOS y Windows.

## Instalación

Abre tu terminal y pega **un solo comando**:

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/juanlara-aidev/zero-to-claude/main/install.sh | bash
```

### Windows

Abre **PowerShell como Administrador** (clic derecho → "Ejecutar como administrador"):

```powershell
irm https://raw.githubusercontent.com/juanlara-aidev/zero-to-claude/main/install.ps1 | iex
```

El instalador habilita **WSL 2 + Ubuntu** y te pedirá **reiniciar la primera vez**. Después del reinicio, vuelve a correr el mismo comando y retoma donde quedó automáticamente.

## Después de instalar

1. Cierra tu terminal
2. Abre una nueva terminal
3. Escribe `claude`
4. Inicia sesión con tu cuenta de Claude (Pro, Max, Team o Enterprise)
5. ¡Listo!

## Qué se instala

| Herramienta | macOS | Windows (WSL por defecto) | Windows (`--native`, legacy) |
|-------------|-------|---------------------------|-----------------------------|
| Xcode Command Line Tools | Sí | — | — |
| Homebrew | Sí | — | — |
| WSL 2 + Ubuntu | — | Sí | — |
| Git | Sí (brew) | Sí (apt, dentro de Ubuntu) | Sí (winget) |
| Node.js LTS | Sí (brew) | Sí (apt, dentro de Ubuntu) | Sí (winget) |
| **Python 3 + pip + venv** | **Sí (brew)** | **Sí (apt, dentro de Ubuntu)** | **Sí (winget)** |
| Claude Code | Sí (nativo) | Sí (dentro de Ubuntu) + wrapper en host | Sí (nativo) |

> Si ya tienes **nvm / fnm / volta / asdf / mise** (Node) o **pyenv / uv / conda / mamba / asdf / mise / rye** (Python), el script los detecta y no reinstala nada.

### ¿Modo nativo sin WSL?

Si prefieres instalar todo directamente en Windows nativo (sin WSL), antes de correr el comando:

```powershell
$env:CLAUDE_SETUP_NATIVE="1"; irm https://raw.githubusercontent.com/juanlara-aidev/zero-to-claude/main/install.ps1 | iex
```

## Desinstalación

Elimina **todo** lo que instaló el script — como si nunca se hubiera ejecutado. Si instalaste Python antes, tu instalación previa NO se toca (el script solo remueve lo que él mismo instaló).

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/juanlara-aidev/zero-to-claude/main/install.sh | bash -s -- --uninstall
```

### Windows

Abre **PowerShell como Administrador**:

```powershell
$env:CLAUDE_SETUP_UNINSTALL="1"; irm https://raw.githubusercontent.com/juanlara-aidev/zero-to-claude/main/install.ps1 | iex
```

> Se pide confirmación antes de eliminar cualquier cosa. En modo WSL, se desregistra la distro Ubuntu (¡perderás archivos y proyectos dentro de ella! — haz respaldo primero).

## Requisitos

- **Cuenta de Claude**: Pro, Max, Team o Enterprise. También se puede usar con API key desde [console.anthropic.com](https://console.anthropic.com).
- **Espacio en disco**: mínimo 10 GB libres en modo WSL, 5 GB en modo nativo.
- **macOS**: el usuario debe ser Administrador (requerido por Homebrew). No ejecutar como root.
- **Windows**: PowerShell como Administrador. Windows 10 Build 19041+ o Windows 11.
- **Windows + VM Parallels/VMware en Apple Silicon**: habilitar nested virtualization en la config de la VM (`prlctl set "<VM>" --nested-virt on` con la VM parada).

## Bueno saberlo

- **Se puede ejecutar varias veces** — solo instala lo que falta (idempotente).
- **Respeta version managers** — Node (nvm/fnm/volta/asdf/mise) y Python (pyenv/uv/conda/mamba/asdf/mise/rye). Si detecta uno activo, no duplica nada.
- **Respeta tu Ubuntu si ya existe** — si ya tienes una distro Ubuntu registrada en WSL, la reusa y reusa tu usuario existente.
- **Reinicio automático manejado** — después del reinicio obligatorio de WSL, vuelve a correr el comando y el instalador retoma donde quedó via `%LOCALAPPDATA%\zero-claude\state.json`.
- **Desinstalación completa y respetuosa** — elimina binarios, configuraciones, entradas de PATH y residuos del sistema, pero no toca Python/Node que tenías antes de correr el script.

---

*by Juan Lara para la comunidad de Vibe-Coders ⚡*
