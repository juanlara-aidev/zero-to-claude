#!/usr/bin/env bash
set -uo pipefail
# NO usar set -e — queremos continuar y acumular errores

# ═══════════════════════════════════════════════════════════════
#  Variables Globales
# ═══════════════════════════════════════════════════════════════

ERRORS=()
INSTALLED=()
ALREADY_INSTALLED=()
NEED_NEW_TERMINAL=false

# Pre-flight detection results
HAS_VERSION_MANAGER=false
VERSION_MANAGER_NAME=""
USER_SHELL=""
USER_SHELL_PROFILE=""

# ═══════════════════════════════════════════════════════════════
#  Colores y Formato
# ═══════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}"
    cat << 'BANNER'
 ██████╗██╗      █████╗ ██╗   ██╗██████╗ ███████╗
██╔════╝██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝
██║     ██║     ███████║██║   ██║██║  ██║█████╗
██║     ██║     ██╔══██║██║   ██║██║  ██║██╔══╝
╚██████╗███████╗██║  ██║╚██████╔╝██████╔╝███████╗
 ╚═════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝
           ██████╗ ██████╗ ██████╗ ███████╗
          ██╔════╝██╔═══██╗██╔══██╗██╔════╝
          ██║     ██║   ██║██║  ██║█████╗
          ██║     ██║   ██║██║  ██║██╔══╝
          ╚██████╗╚██████╔╝██████╔╝███████╗
           ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝
     Instalador Automático — by Juan Lara
BANNER
    echo -e "${NC}"
}

print_system_info() {
    local os_version arch shell_version current_date
    os_version="$(sw_vers -productVersion 2>/dev/null || echo 'desconocido')"
    arch="$(uname -m)"
    shell_version="$(zsh --version 2>/dev/null | head -1 || bash --version | head -1)"
    current_date="$(date '+%Y-%m-%d')"

    local arch_label="Intel"
    if [[ "$arch" == "arm64" ]]; then
        arch_label="Apple Silicon"
    fi

    echo -e "  ${BOLD}Sistema:${NC}  macOS $os_version ($arch_label)"
    echo -e "  ${BOLD}Shell:${NC}    $shell_version"
    echo -e "  ${BOLD}Fecha:${NC}    $current_date"
    echo ""
}

print_separator() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

print_step() {
    echo -e "  ${YELLOW}⏳ $1${NC}"
}

print_success() {
    echo -e "  ${GREEN}✅ $1${NC}"
}

print_skip() {
    echo -e "  ${CYAN}⏭️  $1${NC}"
}

print_error() {
    echo -e "  ${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "  ${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "  ${BLUE}ℹ️  $1${NC}"
}

# ═══════════════════════════════════════════════════════════════
#  Utilidades
# ═══════════════════════════════════════════════════════════════

command_exists() {
    command -v "$1" &> /dev/null
}

detect_os() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "$OS" in
        Darwin) OS_TYPE="macos" ;;
        Linux)  OS_TYPE="linux" ;;
        *)
            print_error "Sistema operativo no soportado: $OS"
            print_error "Este script es para macOS. Para Windows usa setup.ps1"
            exit 1
            ;;
    esac

    if [[ "$ARCH" == "arm64" ]]; then
        IS_APPLE_SILICON=true
        HOMEBREW_PREFIX="/opt/homebrew"
    else
        IS_APPLE_SILICON=false
        HOMEBREW_PREFIX="/usr/local"
    fi
}

check_macos_version() {
    MACOS_VERSION=$(sw_vers -productVersion)
    MAJOR_VERSION=$(echo "$MACOS_VERSION" | cut -d. -f1)

    if [[ "$MAJOR_VERSION" -lt 13 ]]; then
        print_error "Se requiere macOS 13.0 (Ventura) o superior. Versión actual: $MACOS_VERSION"
        exit 1
    fi

    print_success "macOS $MACOS_VERSION detectado ($ARCH)"
}

# ═══════════════════════════════════════════════════════════════
#  Pre-flight Checks
# ═══════════════════════════════════════════════════════════════

check_not_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        print_error "No ejecutes este script como root (sudo)."
        print_info "Homebrew se niega a instalar como root por seguridad."
        print_info "Ejecuta sin sudo: bash setup.sh"
        exit 1
    fi
}

check_admin() {
    print_step "Verificando permisos de administrador..."
    if groups "$USER" 2>/dev/null | grep -qw admin; then
        print_success "Usuario '$USER' tiene permisos de administrador"
    else
        print_error "Tu usuario '$USER' no es Administrador."
        print_info "Homebrew requiere un usuario con permisos de admin."
        print_info "Ve a: Ajustes del Sistema → Usuarios y Grupos → Haz tu cuenta Administrador"
        exit 1
    fi
}

ensure_sudo() {
    # Pre-cache sudo credentials so Homebrew doesn't fail
    # This shows our own clean prompt instead of Homebrew's cryptic error

    # Check if sudo is already cached (NOPASSWD or recently authenticated)
    if sudo -n true 2>/dev/null; then
        return 0
    fi

    print_step "Se necesitan permisos de administrador para instalar Homebrew..."
    print_info "Introduce tu contraseña de macOS cuando se te pida:"
    echo ""
    if ! sudo -v; then
        echo ""
        print_error "No se pudo obtener acceso sudo."
        print_info "Verifica tu contraseña e intenta de nuevo."
        exit 1
    fi
    echo ""
    print_success "Permisos de administrador verificados"
}

check_internet() {
    print_step "Verificando conexión a internet..."
    if curl --max-time 10 -fsS -o /dev/null https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh 2>/dev/null; then
        print_success "Conexión a internet verificada"
    else
        print_error "No se detectó conexión a internet."
        print_info "Verifica tu conexión y ejecuta el script de nuevo."
        print_info "Si estás detrás de un proxy, configura HTTP_PROXY y HTTPS_PROXY."
        exit 1
    fi
}

check_disk_space() {
    print_step "Verificando espacio en disco..."
    local available_gb
    available_gb=$(df -g / | awk 'NR==2 {print $4}')

    if [[ "$available_gb" -lt 5 ]]; then
        print_error "Espacio en disco insuficiente."
        print_info "Disponible: ${available_gb} GB — Se requieren al menos 5 GB."
        print_info "Libera espacio y ejecuta el script de nuevo."
        exit 1
    fi

    print_success "Espacio en disco suficiente (${available_gb} GB disponibles)"
}

detect_user_shell() {
    print_step "Detectando shell del usuario..."
    local login_shell
    login_shell="$(basename "$SHELL")"

    case "$login_shell" in
        zsh)
            USER_SHELL="zsh"
            USER_SHELL_PROFILE="$HOME/.zprofile"
            ;;
        bash)
            USER_SHELL="bash"
            if [[ -f "$HOME/.bash_profile" ]]; then
                USER_SHELL_PROFILE="$HOME/.bash_profile"
            else
                USER_SHELL_PROFILE="$HOME/.profile"
            fi
            ;;
        fish)
            USER_SHELL="fish"
            USER_SHELL_PROFILE="$HOME/.config/fish/conf.d/homebrew.fish"
            ;;
        *)
            USER_SHELL="zsh"
            USER_SHELL_PROFILE="$HOME/.zprofile"
            print_warning "Shell '$login_shell' no reconocido — usando zsh como fallback"
            ;;
    esac

    print_success "Shell detectado: $USER_SHELL (profile: $USER_SHELL_PROFILE)"
}

detect_version_managers() {
    print_step "Verificando version managers de Node.js..."

    # nvm
    if [[ -n "${NVM_DIR:-}" ]] || [[ -f "$HOME/.nvm/nvm.sh" ]]; then
        HAS_VERSION_MANAGER=true
        VERSION_MANAGER_NAME="nvm"
        print_skip "Node.js gestionado por nvm — se respeta tu instalación"
        return
    fi

    # fnm
    if command_exists fnm; then
        HAS_VERSION_MANAGER=true
        VERSION_MANAGER_NAME="fnm"
        print_skip "Node.js gestionado por fnm — se respeta tu instalación"
        return
    fi

    # volta
    if command_exists volta || [[ -d "$HOME/.volta" ]]; then
        HAS_VERSION_MANAGER=true
        VERSION_MANAGER_NAME="volta"
        print_skip "Node.js gestionado por volta — se respeta tu instalación"
        return
    fi

    # asdf
    if command_exists asdf || [[ -d "$HOME/.asdf" ]]; then
        HAS_VERSION_MANAGER=true
        VERSION_MANAGER_NAME="asdf"
        print_skip "Node.js gestionado por asdf — se respeta tu instalación"
        return
    fi

    # mise
    if command_exists mise; then
        HAS_VERSION_MANAGER=true
        VERSION_MANAGER_NAME="mise"
        print_skip "Node.js gestionado por mise — se respeta tu instalación"
        return
    fi

    print_success "No se detectaron version managers — Node.js se instalará vía Homebrew"
}

preflight_checks() {
    echo ""
    print_info "Ejecutando verificaciones previas..."
    echo ""

    # Critical checks (abort on failure)
    check_not_root
    check_admin
    check_internet
    check_disk_space

    # Non-critical checks (warn and continue)
    detect_user_shell
    detect_version_managers

    echo ""
    print_success "Todas las verificaciones pasaron"
    echo ""
}

# ═══════════════════════════════════════════════════════════════
#  Funciones de Instalación
# ═══════════════════════════════════════════════════════════════

install_xcode_clt() {
    print_step "Verificando Xcode Command Line Tools..."

    if xcode-select -p &>/dev/null; then
        print_skip "Xcode CLT ya instaladas"
        ALREADY_INSTALLED+=("Xcode CLT")

        # Verify Xcode license is accepted (only when full Xcode.app is installed, not just CLT)
        if [[ -d "/Applications/Xcode.app" ]] && command_exists xcodebuild; then
            if ! xcodebuild -license check &>/dev/null; then
                print_info "Aceptando licencia de Xcode..."
                sudo xcodebuild -license accept 2>/dev/null || print_warning "No se pudo aceptar la licencia de Xcode. Ejecuta: sudo xcodebuild -license accept"
            fi
        fi
        return 0
    fi

    print_step "Instalando Xcode Command Line Tools..."

    # Strategy 1: Try headless install via softwareupdate (works in SSH, CI, scripts)
    print_info "Buscando Xcode CLT via softwareupdate..."
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress 2>/dev/null
    local clt_label
    clt_label=$(softwareupdate --list 2>&1 | grep -o 'Label: Command Line Tools.*' | sed 's/Label: //' | head -1)

    if [[ -n "$clt_label" ]]; then
        print_info "Encontrado: $clt_label — instalando..."
        sudo softwareupdate --install "$clt_label" --agree-to-license 2>/dev/null
        rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress 2>/dev/null
    else
        rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress 2>/dev/null
    fi

    # Check if softwareupdate succeeded
    if xcode-select -p &>/dev/null; then
        print_success "Xcode Command Line Tools instaladas"
        INSTALLED+=("Xcode CLT")
        return 0
    fi

    # Strategy 2: GUI dialog (works in interactive terminal with display)
    print_info "Intentando instalación via diálogo del sistema..."
    xcode-select --install 2>/dev/null || true
    print_warning "Puede aparecer un diálogo del sistema. Haz clic en 'Instalar'."
    print_info "Esperando a que se complete la instalación de Xcode CLT..."

    SECONDS=0
    TIMEOUT=900
    while ! xcode-select -p &>/dev/null; do
        if [[ $SECONDS -ge $TIMEOUT ]]; then
            print_error "Timeout esperando Xcode CLT."
            print_info "Instálalas manualmente con: xcode-select --install"
            ERRORS+=("Xcode CLT")
            return 1
        fi
        sleep 5
    done

    # Verify Xcode license is accepted (only when full Xcode.app is installed, not just CLT)
    if [[ -d "/Applications/Xcode.app" ]] && command_exists xcodebuild; then
        if ! xcodebuild -license check &>/dev/null; then
            print_info "Aceptando licencia de Xcode..."
            sudo xcodebuild -license accept 2>/dev/null || print_warning "No se pudo aceptar la licencia de Xcode. Ejecuta: sudo xcodebuild -license accept"
        fi
    fi

    print_success "Xcode Command Line Tools instaladas"
    INSTALLED+=("Xcode CLT")
}

configure_homebrew_path() {
    if [[ "$IS_APPLE_SILICON" == true ]]; then
        if [[ "$USER_SHELL" == "fish" ]]; then
            # Fish uses different syntax
            local fish_conf_dir="$HOME/.config/fish/conf.d"
            local fish_conf="$fish_conf_dir/homebrew.fish"
            if ! grep -q 'homebrew' "$fish_conf" 2>/dev/null; then
                mkdir -p "$fish_conf_dir"
                echo '# Homebrew' > "$fish_conf"
                echo 'eval (/opt/homebrew/bin/brew shellenv)' >> "$fish_conf"
                print_info "Homebrew agregado al PATH en $fish_conf"
                NEED_NEW_TERMINAL=true
            fi
        else
            # bash and zsh use the same eval syntax
            local shell_profile="$USER_SHELL_PROFILE"
            local brew_shellenv='eval "$(/opt/homebrew/bin/brew shellenv)"'

            if ! grep -q 'brew shellenv' "$shell_profile" 2>/dev/null; then
                echo '' >> "$shell_profile"
                echo '# Homebrew' >> "$shell_profile"
                echo "$brew_shellenv" >> "$shell_profile"
                print_info "Homebrew agregado al PATH en $shell_profile"
                NEED_NEW_TERMINAL=true
            fi
        fi
    fi
}

check_homebrew_health() {
    # Quick health check: verify brew can actually operate (not just exist)
    print_step "Verificando estado de Homebrew..."

    if brew config &>/dev/null; then
        print_success "Homebrew funciona correctamente"
        return 0
    fi

    # Homebrew exists but is broken — attempt auto-repair
    print_warning "Homebrew detectado pero tiene problemas — intentando reparar..."

    # Repair 1: Fix common permission issues
    if [[ -d "$HOMEBREW_PREFIX" ]]; then
        sudo chown -R "$(whoami):admin" "$HOMEBREW_PREFIX" 2>/dev/null
        sudo chmod -R u+rwX "$HOMEBREW_PREFIX" 2>/dev/null
    fi

    # Repair 2: Remove stale lock files
    rm -f "$HOMEBREW_PREFIX/.git/index.lock" 2>/dev/null
    rm -f "$HOMEBREW_PREFIX/Library/Taps/*/*/.git/index.lock" 2>/dev/null

    # Repair 3: Force update to fix git/formula corruption
    brew update --force 2>/dev/null

    # Re-check after repairs
    if brew config &>/dev/null; then
        print_success "Homebrew reparado y funcionando"
        return 0
    fi

    # Still broken — offer to reinstall
    print_warning "No se pudo reparar automáticamente."
    echo ""
    read -rp "  ¿Reinstalar Homebrew? Se perderán los paquetes instalados (s/N): " confirm
    if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
        print_info "Continuando con Homebrew en su estado actual (puede fallar)."
        return 0
    fi

    print_step "Reinstalando Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" 2>/dev/null
    rm -rf "$HOMEBREW_PREFIX" 2>/dev/null
    sudo rm -rf "$HOMEBREW_PREFIX" 2>/dev/null

    ensure_sudo
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [[ $? -ne 0 ]]; then
        print_error "No se pudo reinstalar Homebrew"
        ERRORS+=("Homebrew")
        return 1
    fi

    configure_homebrew_path
    eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"
    print_success "Homebrew reinstalado y funcionando"
    return 0
}

install_homebrew() {
    print_step "Verificando Homebrew..."

    if command_exists brew; then
        BREW_VERSION=$(brew --version | head -1)
        print_skip "Homebrew ya instalado ($BREW_VERSION)"
        ALREADY_INSTALLED+=("Homebrew")
        check_homebrew_health
        return $?
    fi

    if [[ -f "$HOMEBREW_PREFIX/bin/brew" ]]; then
        eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"
        print_skip "Homebrew encontrado en $HOMEBREW_PREFIX (agregado al PATH)"
        ALREADY_INSTALLED+=("Homebrew")
        configure_homebrew_path
        check_homebrew_health
        return $?
    fi

    # Pre-cache sudo before Homebrew installation
    ensure_sudo

    print_step "Instalando Homebrew... (esto puede tomar unos minutos)"

    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [[ $? -ne 0 ]]; then
        print_error "No se pudo instalar Homebrew"
        print_info "Causas posibles:"
        print_info "  - Sin conexión a internet o detrás de un proxy (configura HTTP_PROXY/HTTPS_PROXY)"
        print_info "  - Permisos insuficientes (tu usuario debe ser Administrador)"
        print_info "  - Firewall bloqueando github.com o ghcr.io"
        ERRORS+=("Homebrew")
        return 1
    fi

    configure_homebrew_path
    eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"

    print_success "Homebrew instalado"
    INSTALLED+=("Homebrew")
}

install_git() {
    print_step "Verificando Git..."

    if command_exists git; then
        GIT_VERSION=$(git --version)
        print_skip "Git ya instalado ($GIT_VERSION)"
        ALREADY_INSTALLED+=("Git")
        return 0
    fi

    print_step "Instalando Git..."
    brew install git

    if command_exists git; then
        print_success "Git instalado ($(git --version))"
        INSTALLED+=("Git")
    else
        print_error "No se pudo instalar Git"
        ERRORS+=("Git")
    fi
}

install_node() {
    print_step "Verificando Node.js..."

    # Skip if a version manager is managing Node.js
    if [[ "$HAS_VERSION_MANAGER" == true ]]; then
        if command_exists node; then
            print_skip "Node.js $(node --version) detectado (gestionado por $VERSION_MANAGER_NAME) — se respeta tu instalación"
        else
            print_skip "Node.js gestionado por $VERSION_MANAGER_NAME (no activo en esta sesión) — se respeta tu instalación"
            print_info "Asegúrate de activar una versión de Node.js con $VERSION_MANAGER_NAME antes de usar npm"
        fi
        ALREADY_INSTALLED+=("Node.js ($VERSION_MANAGER_NAME)")
        return 0
    fi

    if command_exists node; then
        print_skip "Node.js ya instalado ($(node --version))"
        ALREADY_INSTALLED+=("Node.js")
        return 0
    fi

    print_step "Instalando Node.js..."
    brew install node

    if command_exists node; then
        print_success "Node.js instalado ($(node --version), npm $(npm --version))"
        INSTALLED+=("Node.js")
    else
        print_error "No se pudo instalar Node.js"
        print_info "Si la descarga falló, verifica tu conexión o configura HTTP_PROXY/HTTPS_PROXY."
        ERRORS+=("Node.js")
    fi
}

configure_claude_path() {
    # Persist ~/.local/bin in the user's shell profile so claude is available in new terminals
    local claude_path_line='export PATH="$HOME/.local/bin:$PATH"'

    if [[ "$USER_SHELL" == "fish" ]]; then
        local fish_conf_dir="$HOME/.config/fish/conf.d"
        local fish_conf="$fish_conf_dir/claude.fish"
        if ! grep -q '.local/bin' "$fish_conf" 2>/dev/null; then
            mkdir -p "$fish_conf_dir"
            echo '# Claude Code' > "$fish_conf"
            echo 'set -gx PATH $HOME/.local/bin $PATH' >> "$fish_conf"
            print_info "Claude Code agregado al PATH en $fish_conf"
        fi
    else
        local shell_profile="$USER_SHELL_PROFILE"
        if ! grep -q '.local/bin' "$shell_profile" 2>/dev/null; then
            echo '' >> "$shell_profile"
            echo '# Claude Code' >> "$shell_profile"
            echo "$claude_path_line" >> "$shell_profile"
            print_info "Claude Code agregado al PATH en $shell_profile"
        fi
    fi
}

install_claude_code() {
    print_step "Verificando Claude Code..."

    # Check both PATH and file existence (binary may exist but not be in PATH yet)
    if command_exists claude; then
        CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "versión desconocida")
        print_skip "Claude Code ya instalado ($CLAUDE_VERSION)"
        ALREADY_INSTALLED+=("Claude Code")
        return 0
    fi

    if [[ -f "$HOME/.local/bin/claude" ]]; then
        export PATH="$HOME/.local/bin:$PATH"
        CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "versión desconocida")
        print_skip "Claude Code ya instalado ($CLAUDE_VERSION)"
        ALREADY_INSTALLED+=("Claude Code")
        configure_claude_path
        NEED_NEW_TERMINAL=true
        return 0
    fi

    print_step "Instalando Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash

    if [[ -f "$HOME/.local/bin/claude" ]] && ! command_exists claude; then
        export PATH="$HOME/.local/bin:$PATH"
    fi

    if command_exists claude; then
        print_success "Claude Code instalado ($(claude --version 2>/dev/null || echo 'OK'))"
        INSTALLED+=("Claude Code")
        configure_claude_path
        NEED_NEW_TERMINAL=true
    else
        print_error "No se pudo instalar Claude Code"
        print_info "Intenta manualmente: curl -fsSL https://claude.ai/install.sh | bash"
        ERRORS+=("Claude Code")
    fi
}

# ═══════════════════════════════════════════════════════════════
#  Resumen Final
# ═══════════════════════════════════════════════════════════════

print_summary() {
    echo ""
    print_separator

    if [[ ${#ERRORS[@]} -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}🎉 ¡Instalación completada exitosamente!${NC}"
    else
        echo -e "  ${YELLOW}${BOLD}⚠️  Instalación completada con errores${NC}"
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

    echo -e "  ${BOLD}📋 Versiones finales:${NC}"
    echo "  ─────────────────────────────────"
    command_exists git    && echo "     Git:         $(git --version | sed 's/git version //')"
    command_exists node   && echo "     Node.js:     $(node --version)"
    command_exists npm    && echo "     npm:         $(npm --version)"
    command_exists claude && echo "     Claude Code: $(claude --version 2>/dev/null || echo 'ver nueva terminal')"
    echo "  ─────────────────────────────────"

    echo ""
    print_separator
    echo -e "  ${BOLD}📌 Siguiente paso:${NC}"
    if [[ "$NEED_NEW_TERMINAL" == true ]]; then
        echo "     1. CIERRA esta terminal"
        echo "     2. ABRE una nueva terminal"
    else
        echo "     1. Abre una terminal"
    fi
    echo "     3. Escribe:  claude"
    echo "     4. Autentícate con tu cuenta (Pro o Max)"
    echo "     5. ¡Listo! Ya puedes usar Claude Code 🚀"
    print_separator
    echo ""
}

# ═══════════════════════════════════════════════════════════════
#  Funciones de Desinstalación
# ═══════════════════════════════════════════════════════════════

REMOVED=()
NOT_FOUND=()

uninstall_claude_code() {
    print_step "Desinstalando Claude Code..."

    if command_exists claude || [[ -f "$HOME/.local/bin/claude" ]]; then
        rm -rf "$HOME/.local/bin/claude"
        rm -rf "$HOME/.claude"
        rm -rf "$HOME/.config/claude"
        rm -rf "$HOME/.local/state/claude"
        rm -rf "$HOME/.local/share/claude"

        # Clean Claude Code PATH from all shell profiles
        local profiles_to_clean=(
            "$HOME/.zprofile"
            "$HOME/.bash_profile"
            "$HOME/.profile"
        )
        for profile in "${profiles_to_clean[@]}"; do
            if [[ -f "$profile" ]]; then
                sed -i '' '/# Claude Code/d' "$profile" 2>/dev/null
                sed -i '' '/\.local\/bin/d' "$profile" 2>/dev/null
            fi
        done
        # Clean fish config
        local fish_conf="$HOME/.config/fish/conf.d/claude.fish"
        if [[ -f "$fish_conf" ]]; then
            rm -f "$fish_conf"
        fi

        print_success "Claude Code eliminado"
        REMOVED+=("Claude Code")
    else
        print_skip "Claude Code no encontrado"
        NOT_FOUND+=("Claude Code")
    fi
}

uninstall_node() {
    print_step "Desinstalando Node.js..."

    # Detect Node.js via command, brew list, or binary path
    local node_found=false
    if command_exists node; then
        node_found=true
    elif command_exists brew && brew list node &>/dev/null; then
        node_found=true
    elif [[ -f "$HOMEBREW_PREFIX/bin/node" ]]; then
        node_found=true
    fi

    if [[ "$node_found" == true ]]; then
        if command_exists brew; then
            brew uninstall node 2>/dev/null || true
        elif [[ -f "$HOMEBREW_PREFIX/bin/brew" ]]; then
            "$HOMEBREW_PREFIX/bin/brew" uninstall node 2>/dev/null || true
        fi

        # Always clean npm/node artifacts
        rm -rf "$HOME/.npm"
        rm -rf "$HOME/.node-gyp"
        rm -rf "$HOME/.node_repl_history"

        # Verify actual removal
        if command_exists node || [[ -f "$HOMEBREW_PREFIX/bin/node" ]]; then
            print_warning "Node.js aún presente después de brew uninstall (puede ser de un version manager)"
            print_info "Si usas nvm/fnm/volta, Node.js no se elimina — es gestionado por tu version manager"
        else
            print_success "Node.js eliminado"
        fi
        REMOVED+=("Node.js")
    else
        # Still clean npm artifacts even if node binary wasn't found
        rm -rf "$HOME/.npm"
        rm -rf "$HOME/.node-gyp"
        rm -rf "$HOME/.node_repl_history"
        print_skip "Node.js no encontrado"
        NOT_FOUND+=("Node.js")
    fi
}

uninstall_git() {
    print_step "Desinstalando Git (brew)..."

    local brew_cmd=""
    if command_exists brew; then
        brew_cmd="brew"
    elif [[ -f "$HOMEBREW_PREFIX/bin/brew" ]]; then
        brew_cmd="$HOMEBREW_PREFIX/bin/brew"
    fi

    if [[ -n "$brew_cmd" ]] && $brew_cmd list git &>/dev/null; then
        $brew_cmd uninstall git 2>/dev/null || true
        print_success "Git (brew) eliminado"
        REMOVED+=("Git")
    else
        print_skip "Git (brew) no encontrado — probablemente es el de Xcode CLT"
        NOT_FOUND+=("Git")
    fi
}

uninstall_homebrew() {
    print_step "Desinstalando Homebrew..."

    if command_exists brew || [[ -f "$HOMEBREW_PREFIX/bin/brew" ]]; then
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"

        # Clean residual Homebrew files the official uninstaller misses
        if [[ -d "$HOMEBREW_PREFIX" ]]; then
            rm -rf "$HOMEBREW_PREFIX" 2>/dev/null
            if [[ -d "$HOMEBREW_PREFIX" ]]; then
                # Needs sudo to fully remove
                sudo rm -rf "$HOMEBREW_PREFIX" 2>/dev/null || print_warning "No se pudo eliminar $HOMEBREW_PREFIX (requiere sudo)"
            fi
        fi

        # Clean /etc/paths.d/homebrew (requires sudo, created by Homebrew installer)
        if [[ -f /etc/paths.d/homebrew ]]; then
            sudo rm -f /etc/paths.d/homebrew 2>/dev/null || print_warning "No se pudo eliminar /etc/paths.d/homebrew (requiere sudo)"
        fi

        # Limpiar profile del shell real del usuario (no solo zsh)
        local profiles_to_clean=(
            "$HOME/.zprofile"
            "$HOME/.bash_profile"
            "$HOME/.profile"
        )
        for profile in "${profiles_to_clean[@]}"; do
            if [[ -f "$profile" ]]; then
                sed -i '' '/# Homebrew/d' "$profile" 2>/dev/null
                sed -i '' '/brew shellenv/d' "$profile" 2>/dev/null
            fi
        done

        # Limpiar fish config si existe
        local fish_conf="$HOME/.config/fish/conf.d/homebrew.fish"
        if [[ -f "$fish_conf" ]]; then
            rm -f "$fish_conf"
        fi

        print_success "Homebrew eliminado"
        REMOVED+=("Homebrew")
    else
        print_skip "Homebrew no encontrado"
        NOT_FOUND+=("Homebrew")
    fi
}

print_uninstall_summary() {
    echo ""
    print_separator

    if [[ ${#ERRORS[@]} -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}🧹 Desinstalación completada${NC}"
    else
        echo -e "  ${YELLOW}${BOLD}⚠️  Desinstalación completada con errores${NC}"
    fi

    print_separator
    echo ""

    if [[ ${#REMOVED[@]} -gt 0 ]]; then
        echo -e "  ${BOLD}🗑️  Eliminado:${NC}"
        for item in "${REMOVED[@]}"; do echo -e "     ${GREEN}✅ $item${NC}"; done
        echo ""
    fi

    if [[ ${#NOT_FOUND[@]} -gt 0 ]]; then
        echo -e "  ${BOLD}⏭️  No estaba instalado:${NC}"
        for item in "${NOT_FOUND[@]}"; do echo -e "     ${CYAN}— $item${NC}"; done
        echo ""
    fi

    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        echo -e "  ${BOLD}❌ No se pudo eliminar:${NC}"
        for item in "${ERRORS[@]}"; do echo -e "     ${RED}❌ $item${NC}"; done
        echo ""
    fi

    print_separator
    echo -e "  ${BOLD}📌 Nota:${NC}"
    echo "     Xcode CLT NO se desinstala (es parte del sistema base)."
    echo "     Para eliminarlas manualmente: sudo rm -rf /Library/Developer/CommandLineTools"
    print_separator
    echo ""
}

run_uninstall() {
    clear
    print_header
    detect_os
    print_system_info
    detect_user_shell

    echo ""
    echo -e "  ${RED}${BOLD}⚠️  MODO DESINSTALACIÓN${NC}"
    echo -e "  ${RED}Se eliminarán: Claude Code, Node.js, Git (brew), Homebrew${NC}"
    echo -e "  ${YELLOW}Xcode CLT NO se tocará (es parte del sistema base)${NC}"
    echo ""
    read -rp "  ¿Continuar? (s/N): " confirm
    if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
        echo ""
        print_info "Desinstalación cancelada."
        exit 0
    fi

    echo ""
    print_info "Iniciando desinstalación..."
    echo ""

    # Ensure Homebrew is in PATH for uninstall operations (brew uninstall node/git)
    if ! command_exists brew && [[ -f "$HOMEBREW_PREFIX/bin/brew" ]]; then
        eval "$($HOMEBREW_PREFIX/bin/brew shellenv)"
    fi

    uninstall_claude_code
    uninstall_node
    uninstall_git
    uninstall_homebrew

    print_uninstall_summary
}

# ═══════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════

main() {
    clear
    print_header
    detect_os
    print_system_info
    check_macos_version

    preflight_checks

    echo ""
    print_info "Iniciando instalación..."
    echo ""

    install_xcode_clt
    install_homebrew

    print_step "Actualizando Homebrew..."
    # Run brew update with a 120-second timeout (macOS has no `timeout` command)
    brew update --quiet 2>/dev/null &
    local brew_update_pid=$!
    local brew_update_wait=0
    while kill -0 "$brew_update_pid" 2>/dev/null; do
        if [[ $brew_update_wait -ge 120 ]]; then
            kill "$brew_update_pid" 2>/dev/null
            wait "$brew_update_pid" 2>/dev/null
            print_warning "Timeout actualizando Homebrew (no bloqueante — se usarán las fórmulas disponibles)"
            brew_update_pid=""
            break
        fi
        sleep 2
        brew_update_wait=$((brew_update_wait + 2))
    done
    if [[ -n "${brew_update_pid:-}" ]]; then
        if wait "$brew_update_pid" 2>/dev/null; then
            print_success "Homebrew actualizado"
        else
            print_warning "No se pudo actualizar Homebrew (no bloqueante)"
        fi
    fi

    install_git
    install_node
    install_claude_code

    print_summary
}

if [[ "${1:-}" == "--uninstall" ]]; then
    run_uninstall
else
    main "$@"
fi
