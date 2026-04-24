#Requires -Version 5.1
$ErrorActionPreference = "Continue"

# ═══════════════════════════════════════════════════════════════
#  Variables Globales
# ═══════════════════════════════════════════════════════════════

$script:Errors = @()
$script:Installed = @()
$script:AlreadyInstalled = @()
$script:NeedNewTerminal = $false
$script:UseEmoji = $Host.UI.SupportsVirtualTerminal -or ($null -ne $env:WT_SESSION)

# Version managers
$script:HasNodeVersionManager = $false
$script:NodeVersionManagerName = ""
$script:HasPyVersionManager = $false
$script:PyVersionManagerName = ""

# State persistence
$script:StateDir = Join-Path $env:LOCALAPPDATA "zero-claude"
$script:StateFile = Join-Path $script:StateDir "state.json"
$script:RegKey = "HKCU:\Software\ZeroClaude"

# WSL config
$script:WSLDistro = "Ubuntu"           # desired default distro
$script:ActualDistro = $null           # detected/chosen distro at runtime (may differ if Ubuntu-24.04 etc)
$script:WSLDefaultUser = $null         # set later by Get-DefaultWSLUserName (derived from $env:USERNAME)
$script:HostWrapperDir = Join-Path $env:USERPROFILE ".local\bin"
$script:HostWrapperPath = Join-Path $script:HostWrapperDir "claude.cmd"

# Python config
$script:PythonWingetId = "Python.Python.3.12"

# Uninstall lists
$script:Removed = @()
$script:NotFound = @()

# ═══════════════════════════════════════════════════════════════
#  Colores y Formato
# ═══════════════════════════════════════════════════════════════

function Write-Header {
    Write-Host ""
    Write-Host @"
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
     Instalador Automatico — by Juan Lara
"@ -ForegroundColor Cyan
    Write-Host ""
}

function Write-SystemInfo {
    param([string]$Mode = "")
    $version = [System.Environment]::OSVersion.Version
    $currentDate = Get-Date -Format "yyyy-MM-dd"
    $psVersion = $PSVersionTable.PSVersion.ToString()

    Write-Host "  Sistema:  Windows (Build $($version.Build))" -ForegroundColor White
    Write-Host "  Shell:    PowerShell $psVersion" -ForegroundColor White
    Write-Host "  Fecha:    $currentDate" -ForegroundColor White
    if ($Mode) { Write-Host "  Modo:     $Mode" -ForegroundColor White }
    Write-Host ""
}

function Write-Separator {
    Write-Host "=======================================================" -ForegroundColor Cyan
}

function Write-Step { param([string]$Message); $i = if ($script:UseEmoji) { "⏳" } else { "[...]" }; Write-Host "  $i $Message" -ForegroundColor Yellow }
function Write-Ok   { param([string]$Message); $i = if ($script:UseEmoji) { "✅" } else { "[OK]"   }; Write-Host "  $i $Message" -ForegroundColor Green }
function Write-Skip { param([string]$Message); $i = if ($script:UseEmoji) { "⏭️ " } else { "[SKIP]" }; Write-Host "  $i $Message" -ForegroundColor Cyan }
function Write-Err  { param([string]$Message); $i = if ($script:UseEmoji) { "❌" } else { "[ERROR]"}; Write-Host "  $i $Message" -ForegroundColor Red }
function Write-Warn { param([string]$Message); $i = if ($script:UseEmoji) { "⚠️ " } else { "[WARN]" }; Write-Host "  $i $Message" -ForegroundColor Yellow }
function Write-Info { param([string]$Message); $i = if ($script:UseEmoji) { "ℹ️ " } else { "[INFO]" }; Write-Host "  $i $Message" -ForegroundColor Blue }

function Write-RebootBanner {
    Write-Host ""
    Write-Host "  ===================================================================" -ForegroundColor Yellow
    Write-Host "  ==                                                               ==" -ForegroundColor Yellow
    Write-Host "  ==   SE REQUIERE REINICIAR WINDOWS PARA CONTINUAR                ==" -ForegroundColor Yellow
    Write-Host "  ==                                                               ==" -ForegroundColor Yellow
    Write-Host "  ==   1) Reinicia tu computadora.                                 ==" -ForegroundColor Yellow
    Write-Host "  ==   2) Vuelve a correr EL MISMO comando:                        ==" -ForegroundColor Yellow
    Write-Host "  ==      irm https://raw.githubusercontent.com/juanlara-aidev/    ==" -ForegroundColor Yellow
    Write-Host "  ==      zero-to-claude/main/install.ps1 | iex                    ==" -ForegroundColor Yellow
    Write-Host "  ==                                                               ==" -ForegroundColor Yellow
    Write-Host "  ==   El instalador retomara donde quedo, automaticamente.        ==" -ForegroundColor Yellow
    Write-Host "  ==                                                               ==" -ForegroundColor Yellow
    Write-Host "  ===================================================================" -ForegroundColor Yellow
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════
#  Utilidades
# ═══════════════════════════════════════════════════════════════

function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Update-SessionPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Test-IsAdmin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $current
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Graceful halt used instead of `exit` so that when the script is run via
# `irm ... | iex` (top-level shell scope), halting the installer doesn't
# also close the user's PowerShell window. The outer try/catch around Main
# swallows the marker silently; real exceptions re-throw.
function Invoke-Halt {
    param([int]$Code = 0)
    # Hard-coded marker (not $script:) so it resolves identically whether the
    # script is run via `.\setup.ps1`, `-File`, or `irm ... | iex`.
    throw "ZERO_CLAUDE_HALT"
}

function Get-DefaultWSLUserName {
    # Derive a Linux-compatible username from the Windows logged-in user.
    # Rules: lowercase a-z/0-9/_/-, must start with a letter, <=31 chars,
    # not a system-reserved name.
    $raw = if ($env:USERNAME) { $env:USERNAME } else { "claudeuser" }
    $sanitized = ($raw.ToLower() -replace '[^a-z0-9_-]', '')
    if (-not $sanitized -or $sanitized.Length -eq 0) { $sanitized = "claudeuser" }
    if ($sanitized -match '^[^a-z]') { $sanitized = "u$sanitized" }
    if ($sanitized.Length -gt 31) { $sanitized = $sanitized.Substring(0, 31) }
    $reserved = @('root','daemon','bin','sys','sync','games','man','lp','mail','news',
                  'uucp','proxy','www-data','backup','list','irc','gnats','nobody',
                  'systemd-network','systemd-resolve','systemd-timesync','messagebus',
                  'tss','uuidd','tcpdump','sshd','landscape','dnsmasq','ubuntu',
                  'administrator','admin','systemd-coredump','_apt')
    if ($reserved -contains $sanitized) { $sanitized = "${sanitized}-dev" }
    return $sanitized
}

# Initialize default WSL user from the Windows user (overridable via state.json on resume)
$script:WSLDefaultUser = Get-DefaultWSLUserName

function Test-WindowsVersion {
    $version = [System.Environment]::OSVersion.Version
    if ($version.Major -lt 10) {
        Write-Err "Se requiere Windows 10+"; exit 1
    }
    if ($version.Major -eq 10 -and $version.Build -lt 19041) {
        Write-Err "Se requiere Windows 10 2004+ (Build 19041+) para WSL 2. Build actual: $($version.Build)"
        Write-Info "Windows 10 1809 (17763+) es compatible con el modo --native, pero no con WSL."
        Invoke-Halt -Code 1
    }
    Write-Ok "Windows (Build $($version.Build)) detectado"
}

# ═══════════════════════════════════════════════════════════════
#  State Machine (persistencia)
# ═══════════════════════════════════════════════════════════════

function Ensure-StateDir {
    if (-not (Test-Path $script:StateDir)) {
        New-Item -ItemType Directory -Path $script:StateDir -Force | Out-Null
    }
}

function Read-State {
    if (-not (Test-Path $script:StateFile)) { return $null }
    try {
        $content = Get-Content $script:StateFile -Raw -ErrorAction Stop
        return $content | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warn "state.json corrupto o ilegible — ignorando"
        return $null
    }
}

function Save-State {
    param(
        [string]$Phase,
        [string]$Mode = "wsl",
        [hashtable]$Artifacts = @{},
        [string]$RepoName = "",
        [string]$RepoBranch = ""
    )
    Ensure-StateDir

    $existing = Read-State
    $existingArtifacts = @{
        wslFeature = $false
        vmPlatformFeature = $false
        ubuntu = $false
        claudeCodeInWsl = $false
        hostWrapper = $false
        pythonInstalledByUs = $false
        pythonChannel = $null
        gitInstalledByUs = $false
        nodeInstalledByUs = $false
    }
    if ($existing -and $existing.artifactsInstalled) {
        foreach ($prop in $existing.artifactsInstalled.PSObject.Properties) {
            $existingArtifacts[$prop.Name] = $prop.Value
        }
    }
    foreach ($key in $Artifacts.Keys) {
        $existingArtifacts[$key] = $Artifacts[$key]
    }

    $now = (Get-Date).ToString("o")
    $startedAt = if ($existing -and $existing.startedAt) { $existing.startedAt } else { $now }

    # Persist repo override for post-reboot resume
    $savedRepo = if ($RepoName) { $RepoName } elseif ($existing -and $existing.repoName) { $existing.repoName } else { "" }
    $savedBranch = if ($RepoBranch) { $RepoBranch } elseif ($existing -and $existing.repoBranch) { $existing.repoBranch } else { "" }

    $distroName = if ($script:ActualDistro) { $script:ActualDistro } else { $script:WSLDistro }
    $state = [ordered]@{
        version = 1
        mode = $Mode
        phase = $Phase
        distroName = $distroName
        wslUser = $script:WSLDefaultUser
        startedAt = $startedAt
        updatedAt = $now
        repoName = $savedRepo
        repoBranch = $savedBranch
        artifactsInstalled = $existingArtifacts
    }

    $json = $state | ConvertTo-Json -Depth 5
    Set-Content -Path $script:StateFile -Value $json -Encoding UTF8

    # Registry mirror (simple key)
    try {
        if (-not (Test-Path $script:RegKey)) {
            New-Item -Path $script:RegKey -Force | Out-Null
        }
        Set-ItemProperty -Path $script:RegKey -Name "State" -Value $Phase
        Set-ItemProperty -Path $script:RegKey -Name "Mode" -Value $Mode
    } catch {
        # Non-fatal
    }
}

function Clear-State {
    if (Test-Path $script:StateFile) {
        Remove-Item $script:StateFile -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $script:StateDir) {
        Remove-Item $script:StateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    try {
        if (Test-Path $script:RegKey) {
            Remove-Item $script:RegKey -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {
        # Non-fatal
    }
}

function Get-InstallMode {
    param([string[]]$CmdArgs)

    # Uninstall mode
    if ($CmdArgs -contains "--uninstall") { return "uninstall" }
    if ($env:CLAUDE_SETUP_UNINSTALL -eq "1") { return "uninstall" }

    # Resume mode (post-reboot or mid-install)
    $state = Read-State
    if ($state -and $state.phase -and $state.phase -ne "done") {
        return "resume"
    }

    # Explicit native mode
    if ($CmdArgs -contains "--native") { return "native" }
    if ($env:CLAUDE_SETUP_NATIVE -eq "1") { return "native" }

    # Default: WSL
    return "wsl"
}

# ═══════════════════════════════════════════════════════════════
#  Pre-flight Checks (compartidos)
# ═══════════════════════════════════════════════════════════════

function Test-Internet {
    Write-Step "Verificando conexion a internet..."
    try {
        $null = Invoke-WebRequest -Uri "https://github.com" -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        Write-Ok "Conexion a internet verificada"
    } catch {
        Write-Err "No se detecto conexion a internet."
        Write-Info "Verifica tu conexion y ejecuta el script de nuevo."
        Write-Info "Si estas detras de un proxy, configura HTTP_PROXY y HTTPS_PROXY."
        Invoke-Halt -Code 1
    }
}

function Test-DiskSpace {
    param([int]$MinGB = 10)
    Write-Step "Verificando espacio en disco..."
    $freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
    if ($freeGB -lt $MinGB) {
        Write-Err "Espacio en disco insuficiente."
        Write-Info "Disponible: $freeGB GB — Se requieren al menos $MinGB GB."
        Write-Info "Libera espacio y ejecuta el script de nuevo."
        Invoke-Halt -Code 1
    }
    Write-Ok "Espacio en disco suficiente ($freeGB GB disponibles)"
}

function Test-PathLength {
    Write-Step "Verificando longitud del PATH..."
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $pathLen = if ($userPath) { $userPath.Length } else { 0 }
    if ($pathLen -gt 1800) {
        Write-Warn "El PATH del usuario tiene $pathLen caracteres (limite: ~2048)."
        Write-Info "Agregar mas entradas puede causar problemas. Considera limpiar el PATH."
    } else {
        Write-Ok "Longitud del PATH OK ($pathLen caracteres)"
    }
}

function Test-AdminRequired {
    if (-not (Test-IsAdmin)) {
        Write-Err "Se requiere PowerShell como Administrador."
        Write-Info "Cierra esta ventana, abre PowerShell como Administrador (click derecho"
        Write-Info "-> 'Ejecutar como administrador') y vuelve a correr el comando."
        Invoke-Halt -Code 1
    }
    Write-Ok "PowerShell corriendo como Administrador"
}

function Test-Virtualization {
    Write-Step "Verificando soporte de virtualizacion..."
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $isVM = $false
        $vmVendor = ""
        try {
            $sys = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            $vmVendor = "$($sys.Manufacturer) $($sys.Model)"
            $isVM = ($sys.Manufacturer -match 'Parallels|VMware|innotek|Xen|QEMU|Microsoft Corporation' -or
                     $sys.Model -match 'Virtual|KVM|BHYVE')
        } catch {}

        if ($cpu.VirtualizationFirmwareEnabled -eq $true) {
            Write-Ok "Virtualizacion habilitada en BIOS/UEFI"
        } elseif ($isVM) {
            Write-Warn "Host virtualizado detectado ($vmVendor). CIM reporta virt=disabled pero nested virt suele funcionar — continuando."
        } elseif ($env:CLAUDE_SETUP_SKIP_VIRT_CHECK -eq "1") {
            Write-Warn "CLAUDE_SETUP_SKIP_VIRT_CHECK=1 — continuando sin verificar virtualizacion"
        } else {
            Write-Err "La virtualizacion parece DESHABILITADA en el BIOS/UEFI."
            Write-Info "WSL 2 requiere virtualizacion (Intel VT-x o AMD-V) habilitada."
            Write-Info "Entra al BIOS/UEFI y habilita 'Virtualization Technology' o 'SVM Mode'."
            Write-Info "Si prefieres instalar sin WSL, usa: `$env:CLAUDE_SETUP_NATIVE='1'; irm ... | iex"
            Write-Info "Para saltar esta verificacion: `$env:CLAUDE_SETUP_SKIP_VIRT_CHECK='1'"
            Invoke-Halt -Code 1
        }
    } catch {
        Write-Warn "No se pudo verificar virtualizacion via CIM — continuando"
    }
}

function Test-WingetHealth {
    param([switch]$Fatal)
    Write-Step "Verificando que winget funciona correctamente..."
    if (-not (Test-CommandExists "winget")) {
        if ($Fatal) {
            Write-Err "winget no encontrado."
            Write-Info "Instala 'App Installer' desde Microsoft Store: https://aka.ms/getwinget"
            Invoke-Halt -Code 1
        } else {
            Write-Warn "winget no encontrado (no critico en modo WSL)"
            return
        }
    }
    try {
        $null = winget source list 2>&1
        if ($LASTEXITCODE -ne 0) { throw "winget source list failed" }
        Write-Ok "winget disponible y funcional"
    } catch {
        Write-Warn "winget sources pueden estar corruptas. Intentando reparar..."
        try {
            winget source reset --force 2>&1 | Out-Null
            Write-Ok "winget sources reparadas"
        } catch {
            Write-Warn "No se pudieron reparar winget sources."
        }
    }
}

function Test-NodeVersionManagers {
    Write-Step "Verificando version managers de Node.js..."
    if ($env:NVM_HOME -or (Test-CommandExists "nvm")) {
        $script:HasNodeVersionManager = $true
        $script:NodeVersionManagerName = "nvm"
        Write-Skip "Node.js gestionado por nvm — se respeta tu instalacion"
        return
    }
    if (Test-CommandExists "fnm") {
        $script:HasNodeVersionManager = $true
        $script:NodeVersionManagerName = "fnm"
        Write-Skip "Node.js gestionado por fnm — se respeta tu instalacion"
        return
    }
    if ((Test-CommandExists "volta") -or $env:VOLTA_HOME) {
        $script:HasNodeVersionManager = $true
        $script:NodeVersionManagerName = "volta"
        Write-Skip "Node.js gestionado por volta — se respeta tu instalacion"
        return
    }
    Write-Ok "No se detectaron version managers — Node.js se instalara via winget"
}

function Test-PyVersionManagers {
    Write-Step "Verificando version managers de Python..."
    # pyenv-win
    if ($env:PYENV -or (Test-CommandExists "pyenv")) {
        $script:HasPyVersionManager = $true
        $script:PyVersionManagerName = "pyenv"
        Write-Skip "Python gestionado por pyenv — se respeta tu instalacion"
        return
    }
    # uv (Astral)
    if (Test-CommandExists "uv") {
        $script:HasPyVersionManager = $true
        $script:PyVersionManagerName = "uv"
        Write-Skip "Python gestionado por uv — se respeta tu instalacion"
        return
    }
    # conda / mamba
    if ((Test-CommandExists "conda") -or (Test-CommandExists "mamba")) {
        $script:HasPyVersionManager = $true
        $script:PyVersionManagerName = "conda"
        Write-Skip "Python gestionado por conda/mamba — se respeta tu instalacion"
        return
    }
    # asdf
    if (Test-CommandExists "asdf") {
        $script:HasPyVersionManager = $true
        $script:PyVersionManagerName = "asdf"
        Write-Skip "Python gestionado por asdf — se respeta tu instalacion"
        return
    }
    # mise
    if (Test-CommandExists "mise") {
        $script:HasPyVersionManager = $true
        $script:PyVersionManagerName = "mise"
        Write-Skip "Python gestionado por mise — se respeta tu instalacion"
        return
    }
    # rye
    if (Test-CommandExists "rye") {
        $script:HasPyVersionManager = $true
        $script:PyVersionManagerName = "rye"
        Write-Skip "Python gestionado por rye — se respeta tu instalacion"
        return
    }
    Write-Ok "No se detectaron version managers de Python"
}

function Test-Preflight {
    param([string]$Mode)
    Write-Host ""
    Write-Info "Ejecutando verificaciones previas..."
    Write-Host ""

    Test-Internet
    if ($Mode -eq "wsl") {
        Test-DiskSpace -MinGB 10
        Test-AdminRequired
        Test-Virtualization
    } else {
        Test-DiskSpace -MinGB 5
        Test-WingetHealth -Fatal
    }

    Test-PathLength
    if ($Mode -eq "native") {
        Test-NodeVersionManagers
        Test-PyVersionManagers
    }

    Write-Host ""
    Write-Ok "Todas las verificaciones pasaron"
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════
#  WSL Mode — Fase A: Habilitacion de WSL
# ═══════════════════════════════════════════════════════════════

function Test-WSLInstalled {
    # WSL is considered installed if `wsl --status` succeeds AND the kernel is initialized
    if (-not (Test-CommandExists "wsl")) { return $false }
    try {
        $statusOutput = wsl --status 2>&1
        if ($LASTEXITCODE -ne 0) { return $false }
        # Accept both localized outputs; presence of a line with "Default Version" or "Version" is a good sign
        return $true
    } catch {
        return $false
    }
}

function Test-FeatureEnabled {
    param([string]$FeatureName)
    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop
        return ($f.State -eq "Enabled")
    } catch {
        return $false
    }
}

function Test-FeaturePending {
    param([string]$FeatureName)
    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop
        return ($f.State -eq "EnablePending")
    } catch {
        return $false
    }
}

function Invoke-PhaseA-EnableWSL {
    Write-Separator
    Write-Host "  Fase A: Habilitacion de WSL 2" -ForegroundColor Cyan
    Write-Separator
    Write-Host ""

    $wslFeat = "Microsoft-Windows-Subsystem-Linux"
    $vmpFeat = "VirtualMachinePlatform"

    $wslEnabled = Test-FeatureEnabled $wslFeat
    $vmpEnabled = Test-FeatureEnabled $vmpFeat

    if ($wslEnabled -and $vmpEnabled -and (Test-WSLInstalled)) {
        Write-Skip "WSL 2 ya esta habilitado y funcional"
        Save-State -Phase "installing-ubuntu" -Artifacts @{ wslFeature = $true; vmPlatformFeature = $true }
        return $true
    }

    $needReboot = $false

    if (-not $wslEnabled) {
        Write-Step "Habilitando feature: $wslFeat..."
        try {
            $r = Enable-WindowsOptionalFeature -Online -FeatureName $wslFeat -All -NoRestart -ErrorAction Stop
            if ($r.RestartNeeded) { $needReboot = $true }
            Write-Ok "$wslFeat habilitado"
        } catch {
            Write-Err "No se pudo habilitar ${wslFeat}: $_"
            $script:Errors += "WSL feature"
            return $false
        }
    } else {
        Write-Skip "$wslFeat ya habilitado"
    }

    if (-not $vmpEnabled) {
        Write-Step "Habilitando feature: $vmpFeat..."
        try {
            $r = Enable-WindowsOptionalFeature -Online -FeatureName $vmpFeat -All -NoRestart -ErrorAction Stop
            if ($r.RestartNeeded) { $needReboot = $true }
            Write-Ok "$vmpFeat habilitado"
        } catch {
            Write-Err "No se pudo habilitar ${vmpFeat}: $_"
            $script:Errors += "VirtualMachinePlatform feature"
            return $false
        }
    } else {
        Write-Skip "$vmpFeat ya habilitado"
    }

    # Check pending state (post-cmdlet)
    if ((Test-FeaturePending $wslFeat) -or (Test-FeaturePending $vmpFeat)) {
        $needReboot = $true
    }

    Save-State -Phase "awaiting-reboot" -Artifacts @{
        wslFeature = $true
        vmPlatformFeature = $true
    }

    if ($needReboot) {
        Write-RebootBanner
        Write-Host ""
        if ($env:CLAUDE_SETUP_NO_PROMPT -eq "1") {
            Write-Info "CLAUDE_SETUP_NO_PROMPT=1 — no se prompteara; reinicia manualmente."
        } elseif ($env:CLAUDE_SETUP_AUTO_REBOOT -eq "1") {
            Write-Info "CLAUDE_SETUP_AUTO_REBOOT=1 — reiniciando Windows en 5s..."
            Start-Sleep -Seconds 5
            Restart-Computer -Force
        } else {
            $resp = Read-Host "  Reiniciar ahora? (s/N)"
            if ($resp -eq "s" -or $resp -eq "S") {
                Write-Info "Reiniciando Windows..."
                Start-Sleep -Seconds 2
                Restart-Computer -Force
            } else {
                Write-Info "Reinicia manualmente cuando puedas y vuelve a correr el comando."
            }
        }
        Invoke-Halt -Code 0
    }

    # Try to set WSL 2 as default (requires kernel). Wrap with 30s timeout —
    # on some builds `wsl --set-default-version 2` hangs silently trying to
    # update the kernel via Store before the Linux kernel is installed.
    Write-Step "Configurando WSL 2 como version por defecto..."
    try {
        $p = Start-Process -FilePath "wsl.exe" `
            -ArgumentList "--set-default-version","2" `
            -NoNewWindow -PassThru `
            -RedirectStandardOutput "NUL" -RedirectStandardError "NUL"
        if (-not $p.WaitForExit(30000)) {
            try { $p.Kill() } catch { }
            Write-Warn "wsl --set-default-version 2 timeout (30s) — reintentamos luego"
        } elseif ($p.ExitCode -eq 0) {
            Write-Ok "WSL 2 configurado como default"
        } else {
            Write-Warn "No se pudo configurar WSL 2 como default (exit=$($p.ExitCode)) — reintentamos luego"
        }
    } catch {
        Write-Warn "wsl command no disponible: $_"
    }

    Save-State -Phase "installing-ubuntu"
    return $true
}

# ═══════════════════════════════════════════════════════════════
#  WSL Mode — Fase B: Instalacion de Ubuntu
# ═══════════════════════════════════════════════════════════════

function Get-InstalledUbuntuDistro {
    # Returns the name of an Ubuntu-family distro if installed, else $null.
    # Detects "Ubuntu", "Ubuntu-22.04", "Ubuntu-24.04", etc. — preferring exact "Ubuntu".
    try {
        $raw = wsl.exe -l -q 2>&1
        if ($LASTEXITCODE -ne 0) { return $null }
        $text = ($raw -join "`n") -replace "`0", "" -replace "`r", ""
        $names = $text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

        # Prefer exact "Ubuntu"
        foreach ($n in $names) {
            if ($n -ieq $script:WSLDistro) { return $n }
        }
        # Else accept any Ubuntu-family variant
        foreach ($n in $names) {
            if ($n -imatch '^Ubuntu') { return $n }
        }
        return $null
    } catch { return $null }
}

function Test-UbuntuInstalled {
    return ($null -ne (Get-InstalledUbuntuDistro))
}

function Invoke-WSL-AsRoot {
    param([string]$Command)
    $distro = if ($script:ActualDistro) { $script:ActualDistro } else { $script:WSLDistro }
    $output = wsl.exe -d $distro -u root -- bash -c $Command 2>&1
    return @{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Invoke-WSL-AsUser {
    param([string]$Command)
    $distro = if ($script:ActualDistro) { $script:ActualDistro } else { $script:WSLDistro }
    $output = wsl.exe -d $distro -u $script:WSLDefaultUser -- bash -c $Command 2>&1
    return @{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Invoke-PhaseB-InstallUbuntu {
    Write-Separator
    Write-Host "  Fase B: Instalacion de Ubuntu en WSL" -ForegroundColor Cyan
    Write-Separator
    Write-Host ""

    $existingDistro = Get-InstalledUbuntuDistro
    if ($existingDistro) {
        $script:ActualDistro = $existingDistro
        if ($existingDistro -ieq $script:WSLDistro) {
            Write-Skip "Distro '$existingDistro' ya instalada — se reutiliza"
        } else {
            Write-Skip "Distro Ubuntu-familia detectada: '$existingDistro' — se reutiliza en vez de instalar '$($script:WSLDistro)'"
        }
    } else {
        $script:ActualDistro = $script:WSLDistro
        Write-Step "Instalando Ubuntu (puede tardar varios minutos)..."
        $installed = $false

        # Strategy 1: modern wsl --install (Win 11 / Win 10 21H2+)
        try {
            wsl.exe --install -d $script:WSLDistro --no-launch 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { $installed = $true }
        } catch {
            # fall through
        }

        # Strategy 2: --web-download fallback (if Store is blocked)
        if (-not $installed) {
            Write-Warn "wsl --install fallo — reintentando con --web-download"
            try {
                wsl.exe --install -d $script:WSLDistro --no-launch --web-download 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { $installed = $true }
            } catch {
                # fall through
            }
        }

        if (-not $installed) {
            Write-Err "No se pudo instalar Ubuntu automaticamente."
            Write-Info "Posibles causas:"
            Write-Info "  - Microsoft Store bloqueado por politica corporativa"
            Write-Info "  - Antivirus bloqueando la descarga del kernel/distro"
            Write-Info "  - Conexion intermitente"
            Write-Info "Intenta manualmente: wsl --install -d Ubuntu"
            $script:Errors += "Ubuntu"
            return $false
        }

        Write-Ok "Ubuntu instalado (sin primera ejecucion)"
        Save-State -Phase "configuring-ubuntu" -Artifacts @{ ubuntu = $true }

        # Give the distro a moment to register
        Start-Sleep -Seconds 3
    }

    # Resolve which user to use. Priority:
    #   1. Existing DefaultUid in registry (respects user's current setup)
    #   2. Any existing human user (uid >= 1000) in /home
    #   3. Create a new "claudeuser"
    $detectedUser = $null
    try {
        $distroKey = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -ErrorAction SilentlyContinue | Where-Object {
            (Get-ItemProperty $_.PSPath -Name DistributionName -ErrorAction SilentlyContinue).DistributionName -eq $script:ActualDistro
        } | Select-Object -First 1
        if ($distroKey) {
            $defaultUid = (Get-ItemProperty $distroKey.PSPath -Name DefaultUid -ErrorAction SilentlyContinue).DefaultUid
            if ($defaultUid -and $defaultUid -ge 1000) {
                $r = Invoke-WSL-AsRoot "getent passwd $defaultUid | cut -d: -f1"
                $candidate = ($r.Output -join "").Trim()
                if ($candidate -and $candidate -ne "root") { $detectedUser = $candidate }
            }
        }
    } catch { }

    if (-not $detectedUser) {
        # List human users (uid 1000-65533) and take the first non-root one
        $cmd = 'getent passwd | while IFS=: read u x uid rest; do if [ "$uid" -ge 1000 ] && [ "$uid" -lt 65534 ]; then echo "$u"; break; fi; done'
        $r = Invoke-WSL-AsRoot $cmd
        $candidate = ($r.Output -join "`n" -split "`n" | Where-Object { $_ -match '^\S+$' } | Select-Object -First 1)
        if ($candidate -and $candidate -ne "root") { $detectedUser = $candidate.Trim() }
    }

    if ($detectedUser -and $detectedUser -ne $script:WSLDefaultUser) {
        Write-Skip "Usuario existente detectado: '$detectedUser' — se respeta tu instalacion"
        $script:WSLDefaultUser = $detectedUser
        # Make sure they have NOPASSWD sudo for our automated apt calls
        $r = Invoke-WSL-AsRoot "usermod -aG sudo '$detectedUser' 2>/dev/null; echo '$detectedUser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-$detectedUser && chmod 0440 /etc/sudoers.d/90-$detectedUser && echo 'sudo-granted'"
        if (($r.Output -join "") -match "sudo-granted") {
            Write-Ok "Sudo NOPASSWD garantizado para '$detectedUser'"
        }
    } else {
        Write-Step "Configurando usuario '$($script:WSLDefaultUser)' en Ubuntu..."
        $createUserScript = @"
set -e
if id '$($script:WSLDefaultUser)' &>/dev/null; then
  echo 'user-exists'
else
  useradd -m -s /bin/bash -G sudo '$($script:WSLDefaultUser)'
  echo '$($script:WSLDefaultUser) ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-$($script:WSLDefaultUser)
  chmod 0440 /etc/sudoers.d/90-$($script:WSLDefaultUser)
  echo 'user-created'
fi
"@
        $r = Invoke-WSL-AsRoot $createUserScript
        if ($r.ExitCode -ne 0) {
            Write-Err "No se pudo crear el usuario en Ubuntu."
            Write-Info "Salida: $($r.Output)"
            $script:Errors += "Ubuntu user"
            return $false
        }
        Write-Ok "Usuario '$($script:WSLDefaultUser)' listo"
    }

    # Set default user via registry (works for any distro)
    try {
        $distroKey = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -ErrorAction SilentlyContinue | Where-Object {
            (Get-ItemProperty $_.PSPath -Name DistributionName -ErrorAction SilentlyContinue).DistributionName -eq $script:ActualDistro
        } | Select-Object -First 1

        if ($distroKey) {
            # Resolve UID from inside the distro
            $uidResult = Invoke-WSL-AsRoot "id -u '$($script:WSLDefaultUser)'"
            $uid = ($uidResult.Output -replace "[^\d]", "") -as [int]
            if ($uid -and $uid -gt 0) {
                Set-ItemProperty -Path $distroKey.PSPath -Name "DefaultUid" -Value $uid -Type DWord
                Write-Ok "Usuario default de Ubuntu configurado a '$($script:WSLDefaultUser)' (uid=$uid)"
            }
        }
    } catch {
        Write-Warn "No se pudo fijar el default user via registry (no critico)"
    }

    # Terminate + restart distro to apply default user
    wsl.exe --terminate $script:ActualDistro 2>&1 | Out-Null

    # Update package lists
    Write-Step "Actualizando lista de paquetes de Ubuntu (apt update)..."
    $aptUpdate = Invoke-WSL-AsRoot "DEBIAN_FRONTEND=noninteractive apt-get update -qq"
    if ($aptUpdate.ExitCode -ne 0) {
        Write-Warn "apt-get update devolvio errores (no critico):"
        Write-Warn "$($aptUpdate.Output)"
    } else {
        Write-Ok "apt sources actualizadas"
    }

    Save-State -Phase "installing-in-wsl" -Artifacts @{ ubuntu = $true }
    return $true
}

# ═══════════════════════════════════════════════════════════════
#  WSL Mode — Fase C: Instalar Git, Node, Python, Claude dentro de WSL
# ═══════════════════════════════════════════════════════════════

function Invoke-PhaseC-InstallInWSL {
    Write-Separator
    Write-Host "  Fase C: Instalacion de Git, Node, Python y Claude Code en WSL" -ForegroundColor Cyan
    Write-Separator
    Write-Host ""

    # Run setup-wsl.sh inside WSL. Source priority:
    # 1. Local file via ZERO_CLAUDE_SETUPWSL_PATH (Windows path, translated to /mnt/c/...)
    # 2. Remote repo (ZERO_CLAUDE_REPO/ZERO_CLAUDE_BRANCH override, default zero-to-claude/main)
    $wslCmd = $null
    if ($env:ZERO_CLAUDE_SETUPWSL_PATH -and (Test-Path $env:ZERO_CLAUDE_SETUPWSL_PATH)) {
        $winPath = (Resolve-Path $env:ZERO_CLAUDE_SETUPWSL_PATH).Path
        # Translate C:\foo\bar to /mnt/c/foo/bar
        $driveLetter = $winPath.Substring(0,1).ToLower()
        $pathPart = $winPath.Substring(2) -replace '\\', '/'
        $wslPath = "/mnt/$driveLetter$pathPart"
        Write-Info "Fuente (local): $winPath -> $wslPath"
        $wslCmd = "bash $wslPath"
    } else {
        $repoName = if ($env:ZERO_CLAUDE_REPO) { $env:ZERO_CLAUDE_REPO } else { "zero-to-claude" }
        $repoBranch = if ($env:ZERO_CLAUDE_BRANCH) { $env:ZERO_CLAUDE_BRANCH } else { "main" }
        $repoUrl = "https://raw.githubusercontent.com/juanlara-aidev/$repoName/$repoBranch"
        $wslCmd = "curl -fsSL $repoUrl/setup-wsl.sh | bash"
        Write-Info "Fuente (remota): $repoUrl/setup-wsl.sh"
    }

    Write-Step "Descargando y ejecutando setup-wsl.sh dentro de Ubuntu..."
    Write-Info "Esto instalara: git, node, python3 + pip + venv, claude code"
    Write-Host ""

    # Stream output directly (don't capture — user should see progress)
    wsl.exe -d $script:ActualDistro -u $script:WSLDefaultUser -- bash -c $wslCmd
    $exit = $LASTEXITCODE

    Write-Host ""
    if ($exit -ne 0) {
        Write-Err "setup-wsl.sh devolvio exit code $exit"
        Write-Info "Puedes reintentar corriendo el mismo comando, o entrar a WSL:"
        Write-Info "  wsl -d $($script:ActualDistro)"
        Write-Info "  bash <(curl -fsSL $repoUrl/setup-wsl.sh)"
        $script:Errors += "setup-wsl.sh"
        return $false
    }

    Write-Ok "Stack de desarrollo instalado dentro de Ubuntu"
    Save-State -Phase "host-wrapper" -Artifacts @{
        claudeCodeInWsl = $true
        gitInstalledByUs = $true
        nodeInstalledByUs = $true
        pythonInstalledByUs = $true
        pythonChannel = "apt"
    }
    return $true
}

# ═══════════════════════════════════════════════════════════════
#  WSL Mode — Fase D: Integracion host <-> WSL
# ═══════════════════════════════════════════════════════════════

function Invoke-PhaseD-HostWrapper {
    Write-Separator
    Write-Host "  Fase D: Integracion host <-> WSL (wrapper claude.cmd)" -ForegroundColor Cyan
    Write-Separator
    Write-Host ""

    Write-Step "Creando wrapper de claude en el host..."

    if (-not (Test-Path $script:HostWrapperDir)) {
        New-Item -ItemType Directory -Path $script:HostWrapperDir -Force | Out-Null
    }

    # Use absolute path inside WSL (wsl.exe -- <cmd> does NOT source ~/.bashrc,
    # so ~/.local/bin is not in PATH unless we give the full path)
    $claudeInWsl = "/home/$($script:WSLDefaultUser)/.local/bin/claude"
    $wrapperLines = @(
        "@echo off"
        "REM Auto-generated by zero-claude (WSL mode). Forwards args to claude inside WSL."
        "wsl.exe -d $($script:ActualDistro) --exec $claudeInWsl %*"
    )
    $wrapperContent = $wrapperLines -join "`r`n"

    Set-Content -Path $script:HostWrapperPath -Value $wrapperContent -Encoding ASCII
    Write-Ok "Wrapper creado: $($script:HostWrapperPath)"

    # Add .local\bin to user PATH if not already present
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notmatch [regex]::Escape($script:HostWrapperDir)) {
        $newPath = "$($script:HostWrapperDir);$userPath"
        if ($newPath.Length -gt 2048) {
            Write-Warn "Agregar el wrapper al PATH excederia 2048 caracteres ($($newPath.Length))."
            Write-Info "Agrega manualmente: $($script:HostWrapperDir)"
        } else {
            [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
            Write-Ok "PATH del usuario actualizado con $($script:HostWrapperDir)"
            $script:NeedNewTerminal = $true
        }
    } else {
        Write-Skip "PATH del usuario ya contenia $($script:HostWrapperDir)"
    }

    # Update session PATH too
    if ($env:Path -notmatch [regex]::Escape($script:HostWrapperDir)) {
        $env:Path = "$($script:HostWrapperDir);$env:Path"
    }

    Save-State -Phase "host-wrapper-done" -Artifacts @{ hostWrapper = $true }
    return $true
}

# ═══════════════════════════════════════════════════════════════
#  WSL Mode — Fase E: Default-to-Linux (Windows Terminal + shortcut)
# ═══════════════════════════════════════════════════════════════

function Get-WindowsTerminalSettingsPath {
    $pkgs = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.WindowsTerminal*" -Directory -ErrorAction SilentlyContinue
    foreach ($pkg in $pkgs) {
        $settings = Join-Path $pkg.FullName "LocalState\settings.json"
        if (Test-Path $settings) { return $settings }
    }
    return $null
}

function Read-WindowsTerminalSettings {
    param([string]$Path)
    try {
        $content = Get-Content $Path -Raw -ErrorAction Stop
        if (-not $content) { return $null }
        # Try parsing as-is first (the default settings.json is valid JSON)
        try {
            return ($content | ConvertFrom-Json -ErrorAction Stop)
        } catch {
            # Fallback: strip JSON5 comments, but carefully avoid URLs like "https://..."
            # Only strip // comments that are NOT inside a string.
            # Simple heuristic: strip only when // follows whitespace at start of line or after non-alphanum.
            $stripped = [regex]::Replace($content, '(^|[\s,{[])//[^\n]*', '$1')
            $stripped = [regex]::Replace($stripped, '/\*.*?\*/', '', 'Singleline')
            return ($stripped | ConvertFrom-Json -ErrorAction Stop)
        }
    } catch {
        return $null
    }
}

function Set-WindowsTerminalDefaultToUbuntu {
    # Strategy: don't rely on WT's dynamic Ubuntu profile (which isn't
    # written to settings.json until the user manually customizes it).
    # Instead, add an explicit custom profile with our own GUID that
    # launches `wsl -d <distro> --cd ~` directly. Works on any VM/PC
    # even if Windows Terminal has never been opened before.
    $wtSettings = Get-WindowsTerminalSettingsPath
    if (-not $wtSettings) {
        Write-Skip "Windows Terminal no instalado — se salta configuracion (se crea shortcut en escritorio igual)"
        return @{ Changed = $false }
    }

    $settings = Read-WindowsTerminalSettings -Path $wtSettings
    if (-not $settings) {
        Write-Warn "settings.json de Windows Terminal ilegible — se deja sin cambios"
        return @{ Changed = $false }
    }

    # Ensure profiles.list is a mutable array — reconstruct through hashtable
    # for forward-compat across PS versions
    $profileName = "Claude Dev (Ubuntu)"
    $existingGuid = $null
    $currentList = @()
    if ($settings.profiles -and $settings.profiles.list) {
        $currentList = @($settings.profiles.list)
        foreach ($p in $currentList) {
            if ($p.name -eq $profileName) { $existingGuid = $p.guid; break }
        }
    }

    if ($existingGuid) {
        $ourGuid = $existingGuid
        Write-Skip "Perfil '$profileName' ya existe en Windows Terminal (guid=$ourGuid)"
    } else {
        $ourGuid = "{" + ([guid]::NewGuid().ToString()) + "}"
    }

    $backup = if ($settings.defaultProfile) { [string]$settings.defaultProfile } else { "" }
    if ($backup -eq $ourGuid) {
        Write-Skip "Windows Terminal ya usa '$profileName' como default"
        return @{ Changed = $false; AlreadyDefault = $true; SettingsPath = $wtSettings; OurGuid = $ourGuid }
    }

    # Backup settings.json byte-exact (once) — uninstall will restore from here
    $backupFile = "$wtSettings.zero-claude.bak"
    if (-not (Test-Path $backupFile)) {
        try { Copy-Item $wtSettings $backupFile -Force } catch { }
    }

    # Build our custom profile
    $newProfile = [pscustomobject]@{
        guid              = $ourGuid
        name              = $profileName
        commandline       = "wsl.exe -d $($script:ActualDistro) --cd ~"
        startingDirectory = "~"
        icon              = "ms-appx:///ProfileIcons/{9acb9455-ca41-5af7-950f-6bca1bc9722f}.png"
        hidden            = $false
    }

    # Append to list if we're adding new; else leave as-is
    if (-not $existingGuid) {
        $newList = @($currentList + $newProfile)
        if (-not $settings.profiles) {
            $settings | Add-Member -MemberType NoteProperty -Name profiles -Value ([pscustomobject]@{ defaults = [pscustomobject]@{}; list = $newList }) -Force
        } else {
            if ($settings.profiles.PSObject.Properties['list']) {
                $settings.profiles.list = $newList
            } else {
                $settings.profiles | Add-Member -MemberType NoteProperty -Name list -Value $newList -Force
            }
        }
    }

    # Set defaultProfile
    if ($settings.PSObject.Properties['defaultProfile']) {
        $settings.defaultProfile = $ourGuid
    } else {
        $settings | Add-Member -MemberType NoteProperty -Name defaultProfile -Value $ourGuid -Force
    }

    try {
        $newJson = $settings | ConvertTo-Json -Depth 32
        Set-Content -Path $wtSettings -Value $newJson -Encoding UTF8
        if ($existingGuid) {
            Write-Ok "Windows Terminal: '$profileName' marcado como default"
        } else {
            Write-Ok "Windows Terminal: perfil '$profileName' agregado y marcado como default"
        }
        return @{
            Changed       = $true
            BackupDefault = $backup
            SettingsPath  = $wtSettings
            BackupFile    = $backupFile
            OurGuid       = $ourGuid
        }
    } catch {
        Write-Warn "No se pudo escribir settings.json de Windows Terminal: $_"
        return @{ Changed = $false }
    }
}

function New-ClaudeDevShortcut {
    $desktop = [Environment]::GetFolderPath("Desktop")
    if (-not $desktop -or -not (Test-Path $desktop)) {
        Write-Warn "No se pudo ubicar el escritorio del usuario"
        return @{ Created = $false }
    }
    $shortcutPath = Join-Path $desktop "Claude Dev (Ubuntu).lnk"

    if (Test-Path $shortcutPath) {
        Write-Skip "Shortcut 'Claude Dev (Ubuntu)' ya existe en el escritorio"
        return @{ Created = $false; Path = $shortcutPath }
    }

    try {
        $shell = New-Object -ComObject WScript.Shell
        $sc = $shell.CreateShortcut($shortcutPath)
        $sc.TargetPath = "$env:SystemRoot\System32\wsl.exe"
        $sc.Arguments = "-d $($script:ActualDistro) --cd ~"
        $sc.WorkingDirectory = $env:USERPROFILE
        $sc.IconLocation = "$env:SystemRoot\System32\wsl.exe,0"
        $sc.Description = "Entra a tu entorno de desarrollo Ubuntu con Claude Code"
        $sc.Save()
        Write-Ok "Shortcut creado: 'Claude Dev (Ubuntu)' en el escritorio"
        return @{ Created = $true; Path = $shortcutPath }
    } catch {
        Write-Warn "No se pudo crear el shortcut del escritorio: $_"
        return @{ Created = $false }
    }
}

function Invoke-PhaseE-DefaultToLinux {
    Write-Separator
    Write-Host "  Fase E: Entorno Linux como default" -ForegroundColor Cyan
    Write-Separator
    Write-Host ""

    $wt = Set-WindowsTerminalDefaultToUbuntu
    $sc = New-ClaudeDevShortcut

    Save-State -Phase "done" -Artifacts @{
        wtDefaultChanged     = [bool]$wt.Changed
        wtDefaultBackup      = if ($wt.BackupDefault) { [string]$wt.BackupDefault } else { "" }
        wtSettingsPath       = if ($wt.SettingsPath)  { [string]$wt.SettingsPath }  else { "" }
        wtSettingsBackupFile = if ($wt.BackupFile)    { [string]$wt.BackupFile }    else { "" }
        wtCustomProfileGuid  = if ($wt.OurGuid)       { [string]$wt.OurGuid }       else { "" }
        desktopShortcut      = if ($sc.Created -and $sc.Path) { [string]$sc.Path } else { "" }
    }

    Write-Ok "Entorno Linux configurado como default"
    return $true
}

function Reset-WindowsTerminalDefault {
    param($State)
    if (-not $State -or -not $State.artifactsInstalled) { return }
    $art = $State.artifactsInstalled
    if (-not $art.wtDefaultChanged) { return }

    $path = $art.wtSettingsPath
    $backupFile = $art.wtSettingsBackupFile
    $origDefault = $art.wtDefaultBackup

    if (-not $path -or -not (Test-Path $path)) { return }

    $ourGuid = $art.wtCustomProfileGuid

    try {
        # Prefer restoring the full backup file (preserves original comments/formatting)
        if ($backupFile -and (Test-Path $backupFile)) {
            Copy-Item $backupFile $path -Force
            Remove-Item $backupFile -Force -ErrorAction SilentlyContinue
            Write-Ok "Windows Terminal settings.json restaurado desde backup byte-exact"
            return
        }
        # Fallback: surgical edit — remove our custom profile + restore defaultProfile
        $settings = Read-WindowsTerminalSettings -Path $path
        if (-not $settings) { return }

        if ($ourGuid -and $settings.profiles -and $settings.profiles.list) {
            $filtered = @($settings.profiles.list | Where-Object { $_.guid -ne $ourGuid })
            $settings.profiles.list = $filtered
        }
        if ($origDefault) {
            $settings.defaultProfile = $origDefault
        }
        $newJson = $settings | ConvertTo-Json -Depth 32
        Set-Content -Path $path -Value $newJson -Encoding UTF8
        Write-Ok "Windows Terminal: perfil custom removido y defaultProfile restaurado"
    } catch {
        Write-Warn "No se pudo restaurar default profile de Windows Terminal: $_"
    }
}

function Remove-ClaudeDevShortcut {
    param($State)
    $paths = @()
    if ($State -and $State.artifactsInstalled -and $State.artifactsInstalled.desktopShortcut) {
        $paths += $State.artifactsInstalled.desktopShortcut
    }
    $desktop = [Environment]::GetFolderPath("Desktop")
    if ($desktop) { $paths += (Join-Path $desktop "Claude Dev (Ubuntu).lnk") }

    $removed = $false
    foreach ($p in ($paths | Select-Object -Unique)) {
        if ($p -and (Test-Path $p)) {
            Remove-Item $p -Force -ErrorAction SilentlyContinue
            $removed = $true
        }
    }
    if ($removed) { Write-Ok "Shortcut 'Claude Dev (Ubuntu)' eliminado" }
}

# ═══════════════════════════════════════════════════════════════
#  Native Mode (legacy) — instalacion en Windows nativo
# ═══════════════════════════════════════════════════════════════

function Install-GitForWindows {
    Write-Step "Verificando Git..."

    if (Test-CommandExists "git") {
        $v = git --version
        Write-Skip "Git ya instalado ($v)"
        $script:AlreadyInstalled += "Git"
        return
    }

    Write-Step "Instalando Git for Windows..."
    try {
        winget install Git.Git --accept-package-agreements --accept-source-agreements --silent
        Update-SessionPath

        if (-not (Test-CommandExists "git")) {
            $gitDir = "C:\Program Files\Git\cmd"
            if (Test-Path "$gitDir\git.exe") {
                $env:Path = "$gitDir;$env:Path"
                Write-Info "Git agregado al PATH de la sesion actual"
            }
        }

        if (Test-CommandExists "git") {
            Write-Ok "Git instalado ($(git --version))"
            $script:Installed += "Git"
            $script:NeedNewTerminal = $true
            Save-State -Mode "native" -Phase "installing-native" -Artifacts @{ gitInstalledByUs = $true }
        } else { throw "Git no encontrado post-install" }
    }
    catch {
        Write-Err "No se pudo instalar Git: $_"
        Write-Info "Descarga manual: https://git-scm.com/downloads/win"
        $script:Errors += "Git"
    }
}

function Install-NodeJS {
    Write-Step "Verificando Node.js..."

    if ($script:HasNodeVersionManager) {
        if (Test-CommandExists "node") {
            Write-Skip "Node.js $(node --version) detectado (gestionado por $($script:NodeVersionManagerName)) — se respeta tu instalacion"
        } else {
            Write-Skip "Node.js gestionado por $($script:NodeVersionManagerName) (no activo en esta sesion)"
        }
        $script:AlreadyInstalled += "Node.js ($($script:NodeVersionManagerName))"
        return
    }

    if (-not (Test-CommandExists "node") -and (Test-Path "C:\Program Files\nodejs\node.exe")) {
        $env:Path = "C:\Program Files\nodejs;$env:Path"
    }

    if (Test-CommandExists "node") {
        Write-Skip "Node.js ya instalado ($(node --version))"
        $script:AlreadyInstalled += "Node.js"
        return
    }

    Write-Step "Instalando Node.js LTS..."
    try {
        winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements --silent
        Update-SessionPath

        if (-not (Test-CommandExists "node")) {
            $nodeDir = "C:\Program Files\nodejs"
            if (Test-Path "$nodeDir\node.exe") {
                $env:Path = "$nodeDir;$env:Path"
                Write-Info "Node.js agregado al PATH de la sesion actual"
            }
        }

        if (Test-CommandExists "node") {
            Write-Ok "Node.js instalado ($(node --version))"
            $script:Installed += "Node.js"
            $script:NeedNewTerminal = $true
            Save-State -Mode "native" -Phase "installing-native" -Artifacts @{ nodeInstalledByUs = $true }
        } else { throw "Node.js no encontrado post-install" }
    }
    catch {
        Write-Err "No se pudo instalar Node.js: $_"
        Write-Info "Descarga manual: https://nodejs.org"
        $script:Errors += "Node.js"
    }
}

function Install-Python {
    Write-Step "Verificando Python..."

    if ($script:HasPyVersionManager) {
        Write-Skip "Python gestionado por $($script:PyVersionManagerName) — se respeta tu instalacion"
        $script:AlreadyInstalled += "Python ($($script:PyVersionManagerName))"
        Save-State -Mode "native" -Phase "installing-native" -Artifacts @{ pythonChannel = "skipped-user-manager" }
        return
    }

    # Check both command in PATH and the py launcher
    $pyExists = (Test-CommandExists "python") -or (Test-CommandExists "python3") -or (Test-CommandExists "py")
    if ($pyExists) {
        $v = try { (python --version) 2>&1 } catch { try { (py --version) 2>&1 } catch { "OK" } }
        Write-Skip "Python ya instalado ($v)"
        $script:AlreadyInstalled += "Python"
        return
    }

    Write-Step "Instalando Python 3.12 (via winget)..."
    try {
        winget install $script:PythonWingetId --scope user --accept-package-agreements --accept-source-agreements --silent
        Update-SessionPath

        if (-not (Test-CommandExists "python")) {
            $pyDir = Join-Path $env:LOCALAPPDATA "Programs\Python\Python312"
            if (Test-Path "$pyDir\python.exe") {
                $env:Path = "$pyDir;$pyDir\Scripts;$env:Path"
                Write-Info "Python agregado al PATH de la sesion actual"
            }
        }

        if ((Test-CommandExists "python") -or (Test-CommandExists "py")) {
            $v = try { (python --version) 2>&1 } catch { "Python 3.12" }
            Write-Ok "Python instalado ($v)"
            $script:Installed += "Python"
            $script:NeedNewTerminal = $true
            Save-State -Mode "native" -Phase "installing-native" -Artifacts @{
                pythonInstalledByUs = $true
                pythonChannel = "winget"
            }
        } else { throw "Python no encontrado post-install" }
    }
    catch {
        Write-Err "No se pudo instalar Python: $_"
        Write-Info "Descarga manual: https://www.python.org/downloads/windows/"
        $script:Errors += "Python"
    }
}

function Install-ClaudeCode {
    Write-Step "Verificando Claude Code..."

    $claudeDir = Join-Path $env:USERPROFILE ".local\bin"
    $claudePath = Join-Path $claudeDir "claude.exe"

    if (Test-CommandExists "claude") {
        $v = try { claude --version 2>$null } catch { "OK" }
        Write-Skip "Claude Code ya instalado ($v)"
        $script:AlreadyInstalled += "Claude Code"
        return
    }

    if (Test-Path $claudePath) {
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -notmatch [regex]::Escape($claudeDir)) {
            [System.Environment]::SetEnvironmentVariable("Path", "$claudeDir;$userPath", "User")
            Write-Info "Claude Code agregado al PATH del usuario"
        }
        if ($env:Path -notmatch [regex]::Escape($claudeDir)) {
            $env:Path = "$claudeDir;$env:Path"
        }
        Write-Skip "Claude Code encontrado (PATH corregido — abre nueva terminal)"
        $script:AlreadyInstalled += "Claude Code"
        $script:NeedNewTerminal = $true
        return
    }

    if (-not (Test-CommandExists "git")) {
        Write-Err "Git for Windows necesario antes de Claude Code"
        $script:Errors += "Claude Code (falta Git)"
        return
    }

    Write-Step "Instalando Claude Code..."
    try {
        Invoke-Expression (Invoke-RestMethod https://claude.ai/install.ps1)
        Update-SessionPath

        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -notmatch [regex]::Escape($claudeDir)) {
            $newPathLen = "$claudeDir;$userPath".Length
            if ($newPathLen -gt 2048) {
                Write-Warn "Agregar Claude al PATH excederia 2048 chars ($newPathLen)."
                Write-Info "Claude instalado pero PATH no actualizado. Agrega: $claudeDir"
            } else {
                [System.Environment]::SetEnvironmentVariable("Path", "$claudeDir;$userPath", "User")
                Write-Info "Claude Code agregado al PATH del usuario"
            }
        }

        if ($env:Path -notmatch [regex]::Escape($claudeDir)) {
            $env:Path = "$claudeDir;$env:Path"
        }

        if ((Test-CommandExists "claude") -or (Test-Path $claudePath)) {
            Write-Ok "Claude Code instalado"
            $script:Installed += "Claude Code"
            $script:NeedNewTerminal = $true
        } else { throw "Claude Code no encontrado post-install" }
    }
    catch {
        Write-Err "No se pudo instalar Claude Code: $_"
        Write-Info "Intenta manual: irm https://claude.ai/install.ps1 | iex"
        $script:Errors += "Claude Code"
    }
}

function Invoke-NativeMode {
    Write-Separator
    Write-Host "  Modo NATIVO — instalando en Windows nativo (sin WSL)" -ForegroundColor Cyan
    Write-Separator
    Write-Host ""

    Save-State -Mode "native" -Phase "installing-native"

    Install-GitForWindows
    Install-NodeJS
    Install-Python
    Install-ClaudeCode

    Save-State -Mode "native" -Phase "done"
}

# ═══════════════════════════════════════════════════════════════
#  Resumen Final
# ═══════════════════════════════════════════════════════════════

function Write-Summary {
    param([string]$Mode)

    Write-Host ""
    Write-Separator
    if ($script:Errors.Count -eq 0) {
        $icon = if ($script:UseEmoji) { "🎉" } else { "[OK]" }
        Write-Host "  $icon Instalacion completada exitosamente!" -ForegroundColor Green
    } else {
        $icon = if ($script:UseEmoji) { "⚠️" } else { "[WARN]" }
        Write-Host "  $icon Instalacion completada con errores" -ForegroundColor Yellow
    }
    Write-Separator
    Write-Host ""

    if ($script:Installed.Count -gt 0) {
        Write-Host "  Instalado ahora:" -ForegroundColor White
        foreach ($item in $script:Installed) { Write-Host "     + $item" -ForegroundColor Green }
        Write-Host ""
    }

    if ($script:AlreadyInstalled.Count -gt 0) {
        Write-Host "  Ya estaba instalado:" -ForegroundColor White
        foreach ($item in $script:AlreadyInstalled) { Write-Host "     = $item" -ForegroundColor Green }
        Write-Host ""
    }

    if ($script:Errors.Count -gt 0) {
        Write-Host "  No se pudo instalar:" -ForegroundColor White
        foreach ($item in $script:Errors) { Write-Host "     X $item" -ForegroundColor Red }
        Write-Host ""
    }

    Write-Host "  Versiones finales:" -ForegroundColor White
    Write-Host "  -------------------------------------"

    if ($Mode -eq "wsl") {
        if (Test-UbuntuInstalled) {
            $verCmds = @(
                @{ Label = "Git";         Cmd = "git --version 2>/dev/null" },
                @{ Label = "Node.js";     Cmd = "node --version 2>/dev/null" },
                @{ Label = "npm";         Cmd = "npm --version 2>/dev/null" },
                @{ Label = "Python";      Cmd = "python3 --version 2>/dev/null" },
                @{ Label = "pip";         Cmd = 'pip3 --version 2>/dev/null | awk ''{print $1, $2}''' },
                @{ Label = "Claude Code"; Cmd = "claude --version 2>/dev/null || echo 'ver nueva terminal'" }
            )
            foreach ($v in $verCmds) {
                $r = Invoke-WSL-AsUser $v.Cmd
                $out = ($r.Output -join "`n").Trim()
                if ($out) {
                    Write-Host ("     {0,-12} {1}" -f "$($v.Label):", $out)
                }
            }
        }
        Write-Host "  -------------------------------------"
        Write-Host ""
        Write-Separator
        Write-Host "  Tu entorno de desarrollo esta en Ubuntu (WSL)." -ForegroundColor White
        Write-Host ""
        Write-Host "  Siguiente paso (recomendado):" -ForegroundColor White
        Write-Host "     1. Cierra esta terminal."
        Write-Host "     2. Abre Windows Terminal (Win+X -> 'Terminal')."
        Write-Host "        Se abrira directamente dentro de Ubuntu."
        Write-Host "     3. Escribe:  claude"
        Write-Host "     4. Autenticate con tu cuenta (Pro o Max)."
        Write-Host ""
        Write-Host "  Tambien puedes hacer doble-clic en el shortcut"
        Write-Host "  'Claude Dev (Ubuntu)' de tu escritorio." -ForegroundColor White
        Write-Host ""
        Write-Host "  Dentro de Ubuntu tienes: git, node, npm, python3, pip, claude." -ForegroundColor DarkGray
        Write-Host "  Tus proyectos viven en tu home Linux (~) o en /mnt/c/... para Windows." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  (Alternativa: desde cmd.exe/PowerShell escribe 'claude' — un wrapper" -ForegroundColor DarkGray
        Write-Host "  lo ejecuta dentro de WSL automaticamente, sin entrar al shell.)" -ForegroundColor DarkGray
        Write-Separator
    }
    else {
        if (Test-CommandExists "git")    { Write-Host "     Git:         $(git --version)" }
        if (Test-CommandExists "node")   { Write-Host "     Node.js:     $(node --version)" }
        if (Test-CommandExists "npm")    { $npmVer = try { npm.cmd --version 2>$null } catch { npm --version 2>$null }; Write-Host "     npm:         $npmVer" }
        if (Test-CommandExists "python") { Write-Host "     Python:      $(python --version 2>&1)" }
        if (Test-CommandExists "pip")    { $pipVer = try { (pip --version 2>&1) } catch { "" }; if ($pipVer) { Write-Host "     pip:         $pipVer" } }
        if (Test-CommandExists "claude") {
            $cv = try { claude --version 2>$null } catch { "ver nueva terminal" }
            Write-Host "     Claude Code: $cv"
        }
        Write-Host "  -------------------------------------"
        Write-Host ""
        Write-Separator
        Write-Host "  Siguiente paso:" -ForegroundColor White
        if ($script:NeedNewTerminal) {
            Write-Host "     1. CIERRA esta terminal"
            Write-Host "     2. ABRE una nueva terminal"
        } else {
            Write-Host "     1. Abre una terminal"
        }
        Write-Host "     3. Escribe:  claude"
        Write-Host "     4. Autenticate con tu cuenta (Pro o Max)"
        Write-Separator
    }
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════
#  Desinstalacion
# ═══════════════════════════════════════════════════════════════

function Uninstall-WSLMode {
    param($State)

    # Resolve the actual distro name: prefer state.json record, else detect
    $distroToRemove = $null
    if ($State -and $State.distroName) { $distroToRemove = $State.distroName }
    if (-not $distroToRemove) { $distroToRemove = Get-InstalledUbuntuDistro }
    if (-not $distroToRemove) { $distroToRemove = $script:WSLDistro }

    Write-Host ""
    Write-Host "  !! DESINSTALACION WSL" -ForegroundColor Red
    Write-Host "  Se eliminara la distro '$distroToRemove' COMPLETA." -ForegroundColor Red
    Write-Host "  Esto incluye TODOS los archivos y proyectos dentro de ella." -ForegroundColor Red
    Write-Host "  NO se deshabilitara WSL a nivel de Windows (otras distros seguiran funcionando)." -ForegroundColor Yellow
    Write-Host ""
    if ($env:CLAUDE_SETUP_YES -eq "1") {
        Write-Info "CLAUDE_SETUP_YES=1 — saltando confirmacion"
    } else {
        $confirm = Read-Host "  Continuar? (s/N)"
        if ($confirm -ne "s" -and $confirm -ne "S") {
            Write-Info "Desinstalacion cancelada."; return
        }
    }

    Write-Host ""
    # Revert Phase E first (before unregister, in case we need distro info)
    Reset-WindowsTerminalDefault -State $State
    Remove-ClaudeDevShortcut -State $State

    Write-Step "Desregistrando distro '$distroToRemove'..."
    $actualExists = (Get-InstalledUbuntuDistro) -eq $distroToRemove
    if ($actualExists -or (Test-UbuntuInstalled)) {
        try {
            wsl.exe --unregister $distroToRemove 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "Distro '$distroToRemove' desregistrada"
                $script:Removed += "Distro '$distroToRemove' (WSL)"
            } else {
                Write-Warn "wsl --unregister devolvio exit code $LASTEXITCODE"
                $script:Errors += "Distro '$distroToRemove' (WSL)"
            }
        } catch {
            Write-Err "Error desregistrando distro: $_"
            $script:Errors += "Distro '$distroToRemove' (WSL)"
        }
    } else {
        Write-Skip "Distro '$distroToRemove' no estaba instalada"
        $script:NotFound += "Distro '$distroToRemove' (WSL)"
    }

    # Remove host wrapper
    Write-Step "Eliminando wrapper de claude en el host..."
    if (Test-Path $script:HostWrapperPath) {
        Remove-Item $script:HostWrapperPath -Force -ErrorAction SilentlyContinue
        Write-Ok "Wrapper eliminado: $($script:HostWrapperPath)"
        $script:Removed += "claude.cmd (host wrapper)"
    } else {
        Write-Skip "Wrapper no encontrado"
    }

    # Clean user PATH
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -and $userPath -match [regex]::Escape($script:HostWrapperDir)) {
        $cleanPath = ($userPath -split ';' | Where-Object {
            $_ -ne $script:HostWrapperDir -and $_ -ne ''
        }) -join ';'
        [System.Environment]::SetEnvironmentVariable("Path", $cleanPath, "User")
        Write-Ok "PATH del usuario limpiado"
    }

    # Remove .local\bin if empty
    if ((Test-Path $script:HostWrapperDir) -and ((Get-ChildItem $script:HostWrapperDir -Force | Measure-Object).Count -eq 0)) {
        Remove-Item $script:HostWrapperDir -Force -ErrorAction SilentlyContinue
    }

    Clear-State
    Write-Ok "Estado local limpiado"
}

function Uninstall-ClaudeCodeNative {
    Write-Step "Desinstalando Claude Code..."

    $claudePath = "$env:USERPROFILE\.local\bin\claude.exe"
    if ((Test-CommandExists "claude") -or (Test-Path $claudePath)) {
        Remove-Item -Recurse -Force "$env:USERPROFILE\.local" -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force "$env:USERPROFILE\.claude" -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force "$env:USERPROFILE\.config\claude" -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force "$env:APPDATA\Claude" -ErrorAction SilentlyContinue

        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -and $userPath -match '\.local\\bin') {
            $cleanPath = ($userPath -split ';' | Where-Object { $_ -notmatch '\.local\\bin' -and $_ -ne '' }) -join ';'
            [System.Environment]::SetEnvironmentVariable("Path", $cleanPath, "User")
        }
        Write-Ok "Claude Code eliminado"
        $script:Removed += "Claude Code"
    } else {
        Write-Skip "Claude Code no encontrado"
        $script:NotFound += "Claude Code"
    }
}

function Uninstall-PythonNative {
    param($State)
    Write-Step "Desinstalando Python..."

    $pythonOwned = $false
    if ($State -and $State.artifactsInstalled -and $State.artifactsInstalled.pythonInstalledByUs -eq $true) {
        $pythonOwned = $true
    }

    if (-not $pythonOwned) {
        Write-Skip "Python no fue instalado por este script — no se toca"
        $script:NotFound += "Python (no era nuestro)"
        return
    }

    try {
        winget uninstall $script:PythonWingetId --silent 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Python eliminado"
            $script:Removed += "Python"
        } else {
            Write-Warn "winget uninstall Python devolvio $LASTEXITCODE"
            $script:Errors += "Python"
        }
    } catch {
        Write-Err "No se pudo eliminar Python: $_"
        $script:Errors += "Python"
    }

    # Clean PATH for Python dirs
    foreach ($scope in @("User", "Machine")) {
        $pathVal = [System.Environment]::GetEnvironmentVariable("Path", $scope)
        if ($pathVal -and $pathVal -match 'Python3\d+') {
            $cleanPath = ($pathVal -split ';' | Where-Object {
                $_ -notmatch 'Python3\d+' -and $_ -ne ''
            }) -join ';'
            try { [System.Environment]::SetEnvironmentVariable("Path", $cleanPath, $scope) } catch { }
        }
    }
}

function Uninstall-NodeJSNative {
    Write-Step "Desinstalando Node.js..."

    $nodeExists = (Test-CommandExists "node") -or (Test-Path "C:\Program Files\nodejs\node.exe")
    if (-not $nodeExists) {
        Write-Skip "Node.js no encontrado"
        $script:NotFound += "Node.js"
        return
    }

    $uninstalled = $false

    Write-Step "Intentando desinstalar Node.js via winget..."
    try {
        winget uninstall OpenJS.NodeJS.LTS --silent 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Node.js eliminado via winget"
            $uninstalled = $true
        }
    } catch {
        Write-Warn "winget no pudo desinstalar Node.js"
    }

    if (-not $uninstalled) {
        Write-Step "Intentando via msiexec..."
        try {
            $uninstallKeys = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )
            $nodeEntry = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match "Node\.js" -or $_.DisplayName -match "Node JS" } |
                Select-Object -First 1

            if ($nodeEntry -and $nodeEntry.PSChildName -match '^\{.*\}$') {
                $msiId = $nodeEntry.PSChildName
                $msiResult = Start-Process msiexec -ArgumentList "/x $msiId /qn /norestart" -Wait -PassThru -NoNewWindow
                if ($msiResult.ExitCode -eq 0) {
                    Write-Ok "Node.js eliminado via msiexec"
                    $uninstalled = $true
                }
            }
        } catch { }
    }

    if (-not $uninstalled) {
        Write-Step "Realizando limpieza manual de Node.js..."
        $nodeDirs = @("C:\Program Files\nodejs", "$env:APPDATA\npm", "$env:APPDATA\npm-cache", "$env:USERPROFILE\.node-gyp")
        foreach ($dir in $nodeDirs) {
            if (Test-Path $dir) { Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue }
        }

        $uninstallKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
        )
        foreach ($keyPath in $uninstallKeys) {
            try {
                Get-ChildItem $keyPath -ErrorAction SilentlyContinue |
                    Where-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName -match 'Node\.js|Node JS' } |
                    ForEach-Object { Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue }
            } catch { }
        }
        Write-Ok "Node.js eliminado via limpieza manual"
        $uninstalled = $true
    }

    Remove-Item -Recurse -Force "$env:APPDATA\npm" -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force "$env:APPDATA\npm-cache" -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force "$env:USERPROFILE\.node-gyp" -ErrorAction SilentlyContinue

    foreach ($scope in @("User", "Machine")) {
        $pathVal = [System.Environment]::GetEnvironmentVariable("Path", $scope)
        if ($pathVal -and ($pathVal -match 'nodejs' -or $pathVal -match '\\npm')) {
            $cleanPath = ($pathVal -split ';' | Where-Object {
                $_ -notmatch 'nodejs' -and $_ -notmatch '\\npm$' -and $_ -notmatch '\\npm\\' -and $_ -ne ''
            }) -join ';'
            try { [System.Environment]::SetEnvironmentVariable("Path", $cleanPath, $scope) } catch { }
        }
    }

    Update-SessionPath
    if ($uninstalled) { $script:Removed += "Node.js" } else { $script:Errors += "Node.js" }
}

function Uninstall-GitNative {
    Write-Step "Desinstalando Git..."

    $gitExists = (Test-CommandExists "git") -or (Test-Path "C:\Program Files\Git\bin\git.exe")
    if (-not $gitExists) {
        Write-Skip "Git no encontrado"
        $script:NotFound += "Git"
        return
    }

    try {
        winget uninstall Git.Git --silent 2>$null
        Update-SessionPath

        foreach ($scope in @("User", "Machine")) {
            $pathVal = [System.Environment]::GetEnvironmentVariable("Path", $scope)
            if ($pathVal -and $pathVal -match 'Git') {
                $cleanPath = ($pathVal -split ';' | Where-Object { $_ -notmatch '\\Git\\' -and $_ -ne '' }) -join ';'
                try { [System.Environment]::SetEnvironmentVariable("Path", $cleanPath, $scope) } catch { }
            }
        }

        Update-SessionPath
        Write-Ok "Git eliminado"
        $script:Removed += "Git"
    } catch {
        Write-Err "No se pudo eliminar Git: $_"
        $script:Errors += "Git"
    }
}

function Uninstall-NativeMode {
    param($State)

    Write-Host ""
    Write-Host "  !! MODO DESINSTALACION (nativo)" -ForegroundColor Red
    Write-Host "  Se eliminaran: Claude Code, Node.js, Git, Python (si lo instalo este script)" -ForegroundColor Red
    Write-Host ""
    if ($env:CLAUDE_SETUP_YES -eq "1") {
        Write-Info "CLAUDE_SETUP_YES=1 — saltando confirmacion"
    } else {
        $confirm = Read-Host "  Continuar? (s/N)"
        if ($confirm -ne "s" -and $confirm -ne "S") {
            Write-Info "Desinstalacion cancelada."; return
        }
    }

    Write-Host ""
    Uninstall-ClaudeCodeNative
    Uninstall-NodeJSNative
    Uninstall-PythonNative -State $State
    Uninstall-GitNative

    Clear-State
}

function Write-UninstallSummary {
    param([string]$Mode)
    Write-Host ""
    Write-Separator
    if ($script:Errors.Count -eq 0) {
        Write-Host "  Desinstalacion completada" -ForegroundColor Green
    } else {
        Write-Host "  Desinstalacion completada con errores" -ForegroundColor Yellow
    }
    Write-Separator
    Write-Host ""

    if ($script:Removed.Count -gt 0) {
        Write-Host "  Eliminado:" -ForegroundColor White
        foreach ($item in $script:Removed) { Write-Host "     - $item" -ForegroundColor Green }
        Write-Host ""
    }
    if ($script:NotFound.Count -gt 0) {
        Write-Host "  No estaba instalado:" -ForegroundColor White
        foreach ($item in $script:NotFound) { Write-Host "     . $item" -ForegroundColor Cyan }
        Write-Host ""
    }
    if ($script:Errors.Count -gt 0) {
        Write-Host "  No se pudo eliminar:" -ForegroundColor White
        foreach ($item in $script:Errors) { Write-Host "     X $item" -ForegroundColor Red }
        Write-Host ""
    }

    Write-Host "  Verificacion post-desinstalacion:" -ForegroundColor White
    Update-SessionPath

    $residual = @()
    if ($Mode -eq "wsl") {
        if (Test-UbuntuInstalled) { $residual += "Ubuntu (WSL)" }
        if (Test-Path $script:HostWrapperPath) { $residual += "claude.cmd" }
        if (Test-Path $script:StateFile) { $residual += "state.json" }
    } else {
        if (Test-CommandExists "node")   { $residual += "node" }
        if (Test-CommandExists "git")    { $residual += "git" }
        if (Test-CommandExists "claude") { $residual += "claude" }
        if (Test-Path "C:\Program Files\nodejs") { $residual += "carpeta nodejs" }
        if (Test-Path "$env:USERPROFILE\.local\bin\claude.exe") { $residual += "claude.exe" }
    }

    if ($residual.Count -eq 0) {
        Write-Host "     Sistema limpio — no quedan residuos" -ForegroundColor Green
    } else {
        Write-Host "     Residuos detectados: $($residual -join ', ')" -ForegroundColor Yellow
        Write-Host "     Abre una nueva terminal y verifica. Puede requerir reinicio." -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Separator
    Write-Host "  Nota:" -ForegroundColor White
    Write-Host "     Cierra y abre una nueva terminal para que los cambios de PATH surtan efecto."
    Write-Separator
    Write-Host ""
}

function Run-Uninstall {
    Clear-Host
    Write-Header
    Write-SystemInfo -Mode "UNINSTALL"

    $state = Read-State
    $uninstallMode = "native"  # default guess
    if ($state -and $state.mode) {
        $uninstallMode = $state.mode
    } else {
        # Heuristic: if wrapper exists or Ubuntu distro present, assume WSL
        if ((Test-Path $script:HostWrapperPath) -or (Test-UbuntuInstalled)) {
            $uninstallMode = "wsl"
        }
    }

    Write-Info "Modo detectado: $uninstallMode"

    if ($uninstallMode -eq "wsl") {
        Uninstall-WSLMode -State $state
    } else {
        Uninstall-NativeMode -State $state
    }

    Write-UninstallSummary -Mode $uninstallMode
}

# ═══════════════════════════════════════════════════════════════
#  WSL Mode — Orquestador
# ═══════════════════════════════════════════════════════════════

function Invoke-WSLMode {
    param([bool]$IsResume = $false)

    if ($IsResume) {
        $state = Read-State
        Write-Info "Resumiendo desde fase: $($state.phase)"
        Write-Host ""
    }

    Test-WindowsVersion
    Test-Preflight -Mode "wsl"

    $repoName = if ($env:ZERO_CLAUDE_REPO) { $env:ZERO_CLAUDE_REPO } else { "" }
    $repoBranch = if ($env:ZERO_CLAUDE_BRANCH) { $env:ZERO_CLAUDE_BRANCH } else { "" }
    Save-State -Mode "wsl" -Phase "enabling-wsl" -RepoName $repoName -RepoBranch $repoBranch

    if (-not (Invoke-PhaseA-EnableWSL)) { return }
    if (-not (Invoke-PhaseB-InstallUbuntu)) { return }
    if (-not (Invoke-PhaseC-InstallInWSL)) { return }
    if (-not (Invoke-PhaseD-HostWrapper)) { return }
    if (-not (Invoke-PhaseE-DefaultToLinux)) { return }

    Save-State -Mode "wsl" -Phase "done"
    Write-Summary -Mode "wsl"
}

# ═══════════════════════════════════════════════════════════════
#  Main (dispatcher)
# ═══════════════════════════════════════════════════════════════

function Main {
    $cmdArgs = $args
    $mode = Get-InstallMode -CmdArgs $cmdArgs

    # If there's a persisted repo override from a prior run, apply it to env
    $priorState = Read-State
    if ($priorState) {
        if ($priorState.repoName -and -not $env:ZERO_CLAUDE_REPO) {
            $env:ZERO_CLAUDE_REPO = $priorState.repoName
        }
        if ($priorState.repoBranch -and -not $env:ZERO_CLAUDE_BRANCH) {
            $env:ZERO_CLAUDE_BRANCH = $priorState.repoBranch
        }
        # Restore the detected distro name so post-reboot runs use the same one
        if ($priorState.distroName) {
            $script:ActualDistro = $priorState.distroName
        }
        if ($priorState.wslUser) {
            $script:WSLDefaultUser = $priorState.wslUser
        }
    }

    if ($mode -eq "uninstall") {
        Run-Uninstall
        return
    }

    Clear-Host
    Write-Header

    if ($mode -eq "resume") {
        $state = Read-State
        Write-SystemInfo -Mode "WSL (resumiendo post-reboot)"
        Invoke-WSLMode -IsResume $true
        return
    }

    if ($mode -eq "native") {
        Write-SystemInfo -Mode "NATIVE (Windows nativo)"
        Test-WindowsVersion
        Test-Preflight -Mode "native"
        Invoke-NativeMode
        Write-Summary -Mode "native"
        return
    }

    # Default: WSL
    Write-SystemInfo -Mode "WSL (Ubuntu dentro de Windows)"
    Invoke-WSLMode
}

# Wrap Main in a try/catch that swallows our intentional "halt" marker so
# that `irm ... | iex` doesn't close the user's PowerShell window when the
# installer stops (e.g. after showing the reboot banner, or on preflight
# failures like "not admin"). Real errors still bubble up.
try {
    Main @args
} catch {
    if ($_.Exception.Message -ne "ZERO_CLAUDE_HALT") {
        throw
    }
    # Intentional halt — messages already printed by the caller.
    # Terminal stays open (critical for `irm | iex` invocations).
}
