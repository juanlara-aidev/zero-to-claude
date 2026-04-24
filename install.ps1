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

    # CRITICAL: strip UTF-8 BOM (U+FEFF) if present before Invoke-Expression.
    # The BOM is required so PS 5.1 can correctly parse setup.ps1 when run
    # via `-File` (emojis etc.), but when that same file is fetched as a
    # string and piped into `iex`, the BOM becomes a literal character at
    # the start of the string. iex then can't parse it and throws a
    # TerminatingError. That error used to be caught below and `exit 1`
    # killed the whole terminal session (since this bootstrap runs via
    # `irm | iex` in the user's shell scope).
    if ($setupContent -is [string] -and $setupContent.Length -gt 0) {
        if ([int][char]$setupContent[0] -eq 0xFEFF) {
            $setupContent = $setupContent.Substring(1)
        }
    }

    Invoke-Expression $setupContent
}
catch {
    Write-Host ""
    Write-Host "  [ERROR] Error durante la instalacion:" -ForegroundColor Red
    Write-Host "    $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Verifica tu conexion a internet e intenta de nuevo." -ForegroundColor Yellow
    Write-Host "  Si persiste, reporta el issue en:" -ForegroundColor Yellow
    Write-Host "    https://github.com/juanlara-aidev/zero-to-claude/issues" -ForegroundColor Yellow
    Write-Host ""
    # DO NOT use `exit 1` here — this bootstrap runs via `irm | iex` which
    # evaluates the content in the user's PowerShell session. `exit` would
    # close their whole terminal window. Let the script end naturally; the
    # prompt returns, the user reads the error, tries again.
}
