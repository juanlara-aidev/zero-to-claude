# Zero to Claude

Instala [Claude Code](https://docs.anthropic.com/en/docs/claude-code) en una computadora desde cero con un solo comando. Funciona en macOS y Windows.

## Instalación

Abre tu terminal y pega **un solo comando**:

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/juanlara-aidev/zero-to-claude/main/install.sh | bash
```

### Windows

Abre **PowerShell como Administrador** (clic derecho -> "Ejecutar como administrador"):

```powershell
irm https://raw.githubusercontent.com/juanlara-aidev/zero-to-claude/main/install.ps1 | iex
```

## Después de instalar

1. Cierra tu terminal
2. Abre una nueva terminal
3. Escribe `claude`
4. Inicia sesión con tu cuenta de Claude (Pro, Max, Team o Enterprise)
5. ¡Listo!

## Qué se instala

| Herramienta | macOS | Windows |
|-------------|-------|---------|
| Xcode Command Line Tools | Sí | — |
| Homebrew | Sí | — |
| Git | Sí (brew) | Sí (winget) |
| Node.js LTS | Sí (brew) | Sí (winget) |
| Claude Code | Sí (nativo) | Sí (nativo) |

> Si ya tienes **nvm**, **fnm**, **volta** u otro version manager de Node.js, el script lo detecta y no instala Node.js de nuevo.

## Desinstalación

Elimina **todo** lo que instaló el script — como si nunca se hubiera ejecutado.

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/juanlara-aidev/zero-to-claude/main/install.sh | bash -s -- --uninstall
```

### Windows

Abre **PowerShell como Administrador**:

```powershell
$env:CLAUDE_SETUP_UNINSTALL="1"; irm https://raw.githubusercontent.com/juanlara-aidev/zero-to-claude/main/install.ps1 | iex
```

> Se pide confirmación antes de eliminar cualquier cosa.

## Requisitos

- **Cuenta de Claude**: Pro, Max, Team o Enterprise. También se puede usar con API key desde [console.anthropic.com](https://console.anthropic.com).
- **Espacio en disco**: mínimo 5 GB libres.
- **macOS**: el usuario debe ser Administrador (requerido por Homebrew). No ejecutar como root.
- **Windows**: ejecutar PowerShell como Administrador para que la desinstalación funcione completamente.

## Bueno saberlo

- **Se puede ejecutar varias veces** — solo instala lo que falta (idempotente).
- **Respeta version managers** — si usas nvm, fnm, volta, asdf o mise, no se instala Node.js de nuevo.
- **Desinstalación completa** — elimina binarios, configuraciones, entradas de PATH y residuos del sistema.

---

*by Juan Lara para la comunidad de Vibe-Coders ⚡*
