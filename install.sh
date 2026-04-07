#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Bootstrap — Instalador de Claude Code + Entorno de Desarrollo
#  Instalar:      curl -fsSL https://raw.githubusercontent.com/juanlara-aidev/zero-to-claude/main/install.sh | bash
#  Desinstalar:   curl -fsSL https://raw.githubusercontent.com/juanlara-aidev/zero-to-claude/main/install.sh | bash -s -- --uninstall
# ═══════════════════════════════════════════════════════════════
set -uo pipefail

REPO_URL="https://raw.githubusercontent.com/juanlara-aidev/zero-to-claude/main"
TMPDIR="${TMPDIR:-/tmp}"
SETUP_FILE="$TMPDIR/claude-code-setup-$$.sh"

cleanup() {
    rm -f "$SETUP_FILE"
}
trap cleanup EXIT

echo ""
echo "  Descargando instalador de Claude Code..."
echo ""

if ! curl -fsSL "$REPO_URL/setup.sh" -o "$SETUP_FILE"; then
    echo "  ❌ Error descargando el instalador."
    echo "  Verifica tu conexión a internet e intenta de nuevo."
    exit 1
fi

chmod +x "$SETUP_FILE"

# Redirect stdin to /dev/tty so sudo and read prompts work
# (when running via curl | bash, stdin is the pipe, not the terminal)
if [[ -t 0 ]]; then
    # Already have a terminal on stdin (user ran: bash install.sh)
    exec bash "$SETUP_FILE" "$@"
else
    # stdin is a pipe (user ran: curl ... | bash)
    exec bash "$SETUP_FILE" "$@" < /dev/tty
fi
