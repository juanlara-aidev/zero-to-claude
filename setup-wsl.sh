#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  setup-wsl.sh — Instalador dentro de WSL Ubuntu
#  Invocado por setup.ps1 en modo WSL (default).
#  Instala: git, node.js LTS, python3+pip+venv, claude code
# ═══════════════════════════════════════════════════════════════
set -uo pipefail
# NO usar set -e — queremos continuar y acumular errores

ERRORS=()
INSTALLED=()
ALREADY_INSTALLED=()

HAS_NODE_VM=false
NODE_VM_NAME=""
HAS_PY_VM=false
PY_VM_NAME=""

# ═══════════════════════════════════════════════════════════════
#  Colores y Formato
# ═══════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}"
    cat << 'BANNER'
  ┌─────────────────────────────────────────────────┐
  │  zero-claude — instalador intra-WSL             │
  │  git  |  node.js  |  python3  |  claude code    │
  └─────────────────────────────────────────────────┘
BANNER
    echo -e "${NC}"
}

print_step()    { echo -e "  ${YELLOW}⏳ $1${NC}"; }
print_success() { echo -e "  ${GREEN}✅ $1${NC}"; }
print_skip()    { echo -e "  ${CYAN}⏭️  $1${NC}"; }
print_error()   { echo -e "  ${RED}❌ $1${NC}"; }
print_warning() { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
print_info()    { echo -e "  ${BLUE}ℹ️  $1${NC}"; }
print_separator() { echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"; }

# ═══════════════════════════════════════════════════════════════
#  Utilidades
# ═══════════════════════════════════════════════════════════════

command_exists() { command -v "$1" &>/dev/null; }

is_wsl() {
    [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qiE "microsoft|wsl" /proc/version 2>/dev/null
}

ensure_profile_line() {
    # Append $2 to $1 (profile file) only if not already present
    local profile="$1"
    local line="$2"
    local marker="$3"
    if ! grep -qF "$line" "$profile" 2>/dev/null; then
        echo "" >> "$profile"
        echo "# $marker" >> "$profile"
        echo "$line" >> "$profile"
    fi
}

# ═══════════════════════════════════════════════════════════════
#  Pre-flight
# ═══════════════════════════════════════════════════════════════

check_wsl() {
    print_step "Verificando que corremos dentro de WSL..."
    if ! is_wsl; then
        print_error "Este script esta pensado para correr dentro de WSL Ubuntu."
        print_info "Si estas en Linux nativo puede funcionar igual (usa apt), pero no esta probado."
    else
        print_success "WSL detectado: ${WSL_DISTRO_NAME:-unknown}"
    fi
}

check_internet() {
    print_step "Verificando conexion a internet..."
    if curl --max-time 10 -fsS -o /dev/null https://github.com 2>/dev/null; then
        print_success "Internet OK"
    else
        print_error "Sin conexion a internet."
        exit 1
    fi
}

detect_node_vm() {
    if [[ -n "${NVM_DIR:-}" ]] || [[ -f "$HOME/.nvm/nvm.sh" ]]; then
        HAS_NODE_VM=true; NODE_VM_NAME="nvm"
        print_skip "Node.js gestionado por nvm — respeto tu instalacion"; return
    fi
    if command_exists fnm; then
        HAS_NODE_VM=true; NODE_VM_NAME="fnm"
        print_skip "Node.js gestionado por fnm — respeto tu instalacion"; return
    fi
    if command_exists volta || [[ -d "$HOME/.volta" ]]; then
        HAS_NODE_VM=true; NODE_VM_NAME="volta"
        print_skip "Node.js gestionado por volta — respeto tu instalacion"; return
    fi
    if command_exists asdf || [[ -d "$HOME/.asdf" ]]; then
        HAS_NODE_VM=true; NODE_VM_NAME="asdf"
        print_skip "Node.js gestionado por asdf — respeto tu instalacion"; return
    fi
    if command_exists mise; then
        HAS_NODE_VM=true; NODE_VM_NAME="mise"
        print_skip "Node.js gestionado por mise — respeto tu instalacion"; return
    fi
}

detect_py_vm() {
    if command_exists pyenv || [[ -d "$HOME/.pyenv" ]]; then
        HAS_PY_VM=true; PY_VM_NAME="pyenv"
        print_skip "Python gestionado por pyenv — respeto tu instalacion"; return
    fi
    if command_exists uv; then
        HAS_PY_VM=true; PY_VM_NAME="uv"
        print_skip "Python gestionado por uv — respeto tu instalacion"; return
    fi
    if command_exists conda || command_exists mamba; then
        HAS_PY_VM=true; PY_VM_NAME="conda"
        print_skip "Python gestionado por conda/mamba — respeto tu instalacion"; return
    fi
    if command_exists rye; then
        HAS_PY_VM=true; PY_VM_NAME="rye"
        print_skip "Python gestionado por rye — respeto tu instalacion"; return
    fi
}

preflight() {
    echo ""
    print_info "Verificaciones previas (intra-WSL)..."
    echo ""
    check_wsl
    check_internet
    detect_node_vm
    detect_py_vm
    echo ""
}

# ═══════════════════════════════════════════════════════════════
#  Instaladores
# ═══════════════════════════════════════════════════════════════

apt_install() {
    # $@ = paquetes a instalar
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" < /dev/null
}

ensure_apt_updated() {
    # Cache de apt cada 24h
    local stamp="/var/cache/apt/pkgcache.bin"
    if [[ -f "$stamp" ]]; then
        local age=$(( $(date +%s) - $(stat -c %Y "$stamp" 2>/dev/null || echo 0) ))
        if [[ $age -lt 86400 ]]; then
            return 0
        fi
    fi
    print_step "Actualizando lista de paquetes (apt-get update)..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq < /dev/null || true
}

install_git() {
    print_step "Verificando Git..."
    if command_exists git; then
        print_skip "Git ya instalado ($(git --version))"
        ALREADY_INSTALLED+=("Git")
        return 0
    fi
    print_step "Instalando Git (apt)..."
    if apt_install git; then
        print_success "Git instalado ($(git --version))"
        INSTALLED+=("Git")
    else
        print_error "No se pudo instalar Git"
        ERRORS+=("Git")
    fi
}

install_node() {
    print_step "Verificando Node.js..."

    if [[ "$HAS_NODE_VM" == true ]]; then
        if command_exists node; then
            print_skip "Node.js $(node --version) (via $NODE_VM_NAME) — respeto tu instalacion"
        else
            print_skip "Node.js gestionado por $NODE_VM_NAME (no activo en esta sesion)"
        fi
        ALREADY_INSTALLED+=("Node.js ($NODE_VM_NAME)")
        return 0
    fi

    if command_exists node; then
        print_skip "Node.js ya instalado ($(node --version))"
        ALREADY_INSTALLED+=("Node.js")
        return 0
    fi

    print_step "Instalando Node.js LTS via NodeSource..."
    # NodeSource 20.x (LTS "Iron") setup script — idempotent
    if curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - < /dev/null 2>/dev/null; then
        if apt_install nodejs; then
            if command_exists node; then
                print_success "Node.js instalado ($(node --version), npm $(npm --version 2>/dev/null || echo 'n/a'))"
                INSTALLED+=("Node.js")
                return 0
            fi
        fi
    fi

    # Fallback: apt package (older but present in Ubuntu main)
    print_warning "NodeSource fallo — intentando con el paquete de apt (puede ser una version mas vieja)"
    if apt_install nodejs npm; then
        if command_exists node; then
            print_success "Node.js instalado ($(node --version))"
            INSTALLED+=("Node.js")
            return 0
        fi
    fi

    print_error "No se pudo instalar Node.js"
    print_info "Si la descarga fallo, verifica conexion o configura HTTP_PROXY/HTTPS_PROXY."
    ERRORS+=("Node.js")
}

install_python() {
    print_step "Verificando Python..."

    if [[ "$HAS_PY_VM" == true ]]; then
        print_skip "Python gestionado por $PY_VM_NAME — respeto tu instalacion"
        ALREADY_INSTALLED+=("Python ($PY_VM_NAME)")
        return 0
    fi

    local need_install=false

    if command_exists python3 && python3 -c "import sys; sys.exit(0 if sys.version_info[:2] >= (3,10) else 1)" 2>/dev/null; then
        print_skip "Python ya instalado ($(python3 --version))"
    else
        need_install=true
    fi

    # Ensure pip and venv are present, even if python3 is there
    if ! python3 -m pip --version &>/dev/null; then need_install=true; fi
    if ! python3 -c "import venv" &>/dev/null;  then need_install=true; fi

    if [[ "$need_install" == false ]]; then
        ALREADY_INSTALLED+=("Python")
        return 0
    fi

    print_step "Instalando Python3 + pip + venv (apt)..."
    if apt_install python3 python3-pip python3-venv; then
        if command_exists python3 && python3 -m pip --version &>/dev/null && python3 -c "import venv" &>/dev/null; then
            print_success "Python instalado ($(python3 --version))"
            print_info "pip: $(python3 -m pip --version 2>/dev/null | awk '{print $1, $2}')"
            INSTALLED+=("Python")
            return 0
        fi
    fi

    print_error "No se pudo instalar Python3 / pip / venv"
    ERRORS+=("Python")
}

configure_claude_path() {
    # Persist ~/.local/bin in .bashrc so claude is in PATH on new shells
    local bashrc="$HOME/.bashrc"
    local line='export PATH="$HOME/.local/bin:$PATH"'
    ensure_profile_line "$bashrc" "$line" "Claude Code"
}

install_claude_code() {
    print_step "Verificando Claude Code..."

    if command_exists claude; then
        local v; v="$(claude --version 2>/dev/null || echo 'OK')"
        print_skip "Claude Code ya instalado ($v)"
        ALREADY_INSTALLED+=("Claude Code")
        configure_claude_path
        return 0
    fi

    if [[ -f "$HOME/.local/bin/claude" ]]; then
        export PATH="$HOME/.local/bin:$PATH"
        print_skip "Claude Code encontrado en ~/.local/bin (PATH ajustado)"
        ALREADY_INSTALLED+=("Claude Code")
        configure_claude_path
        return 0
    fi

    print_step "Instalando Claude Code (instalador nativo Linux)..."
    if curl -fsSL https://claude.ai/install.sh | bash; then
        if [[ -f "$HOME/.local/bin/claude" ]]; then
            export PATH="$HOME/.local/bin:$PATH"
            if command_exists claude; then
                print_success "Claude Code instalado ($(claude --version 2>/dev/null || echo 'OK'))"
                INSTALLED+=("Claude Code")
                configure_claude_path
                return 0
            fi
        fi
    fi

    print_error "No se pudo instalar Claude Code"
    print_info "Intenta manual dentro de WSL: curl -fsSL https://claude.ai/install.sh | bash"
    ERRORS+=("Claude Code")
}

# ═══════════════════════════════════════════════════════════════
#  Resumen
# ═══════════════════════════════════════════════════════════════

print_summary() {
    echo ""
    print_separator

    if [[ ${#ERRORS[@]} -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}✅ setup-wsl.sh completado${NC}"
    else
        echo -e "  ${YELLOW}${BOLD}⚠️  setup-wsl.sh completado con errores${NC}"
    fi
    print_separator
    echo ""

    if [[ ${#INSTALLED[@]} -gt 0 ]]; then
        echo -e "  ${BOLD}📦 Instalado ahora:${NC}"
        for item in "${INSTALLED[@]}"; do echo -e "     ${GREEN}✅ $item${NC}"; done
        echo ""
    fi
    if [[ ${#ALREADY_INSTALLED[@]} -gt 0 ]]; then
        echo -e "  ${BOLD}⏭️  Ya estaba instalado:${NC}"
        for item in "${ALREADY_INSTALLED[@]}"; do echo -e "     ${GREEN}✅ $item${NC}"; done
        echo ""
    fi
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo -e "  ${BOLD}❌ No se pudo instalar:${NC}"
        for item in "${ERRORS[@]}"; do echo -e "     ${RED}❌ $item${NC}"; done
        echo ""
    fi

    echo -e "  ${BOLD}📋 Versiones finales (dentro de WSL):${NC}"
    echo "  ─────────────────────────────────"
    command_exists git     && echo "     Git:         $(git --version | sed 's/git version //')"
    command_exists node    && echo "     Node.js:     $(node --version)"
    command_exists npm     && echo "     npm:         $(npm --version 2>/dev/null || echo 'n/a')"
    command_exists python3 && echo "     Python:      $(python3 --version 2>&1)"
    python3 -m pip --version &>/dev/null && echo "     pip:         $(python3 -m pip --version 2>&1 | awk '{print $1, $2}')"
    command_exists claude  && echo "     Claude Code: $(claude --version 2>/dev/null || echo 'OK')"
    echo "  ─────────────────────────────────"
    echo ""

    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════

main() {
    print_header
    preflight
    ensure_apt_updated

    echo ""
    print_info "Iniciando instalacion..."
    echo ""

    install_git
    install_node
    install_python
    install_claude_code

    print_summary
}

main "$@"
