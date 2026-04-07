# ═══════════════════════════════════════════════════════════════
#  Bootstrap — Instalador de Claude Code + Entorno de Desarrollo
#  Instalar:      irm https://raw.githubusercontent.com/juanlara-aidev/zero-to-claude/main/install.ps1 | iex
#  Desinstalar:   $env:CLAUDE_SETUP_UNINSTALL="1"; irm https://raw.githubusercontent.com/juanlara-aidev/zero-to-claude/main/install.ps1 | iex
# ═══════════════════════════════════════════════════════════════

$repoUrl = "https://raw.githubusercontent.com/juanlara-aidev/zero-to-claude/main"

try {
    Write-Host ""
    Write-Host "  Descargando instalador de Claude Code..." -ForegroundColor Cyan
    Write-Host ""

    $setupContent = Invoke-RestMethod "$repoUrl/setup.ps1"
    Invoke-Expression $setupContent
}
catch {
    Write-Host "  [ERROR] Error descargando el instalador: $_" -ForegroundColor Red
    Write-Host "  Verifica tu conexion a internet e intenta de nuevo." -ForegroundColor Yellow
    exit 1
}
