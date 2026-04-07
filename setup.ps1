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

# Pre-flight detection results
$script:HasVersionManager = $false
$script:VersionManagerName = ""

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
    $version = [System.Environment]::OSVersion.Version
    $currentDate = Get-Date -Format "yyyy-MM-dd"
    $psVersion = $PSVersionTable.PSVersion.ToString()

    Write-Host "  Sistema:  Windows (Build $($version.Build))" -ForegroundColor White
    Write-Host "  Shell:    PowerShell $psVersion" -ForegroundColor White
    Write-Host "  Fecha:    $currentDate" -ForegroundColor White
    Write-Host ""
}

function Write-Separator {
    Write-Host "=======================================================" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message)
    $icon = if ($script:UseEmoji) { "⏳" } else { "[...]" }
    Write-Host "  $icon $Message" -ForegroundColor Yellow
}

function Write-Ok {
    param([string]$Message)
    $icon = if ($script:UseEmoji) { "✅" } else { "[OK]" }
    Write-Host "  $icon $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    $icon = if ($script:UseEmoji) { "⏭️ " } else { "[SKIP]" }
    Write-Host "  $icon $Message" -ForegroundColor Cyan
}

function Write-Err {
    param([string]$Message)
    $icon = if ($script:UseEmoji) { "❌" } else { "[ERROR]" }
    Write-Host "  $icon $Message" -ForegroundColor Red
}

function Write-Warn {
    param([string]$Message)
    $icon = if ($script:UseEmoji) { "⚠️ " } else { "[WARN]" }
    Write-Host "  $icon $Message" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    $icon = if ($script:UseEmoji) { "ℹ️ " } else { "[INFO]" }
    Write-Host "  $icon $Message" -ForegroundColor Blue
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

function Test-WindowsVersion {
    $version = [System.Environment]::OSVersion.Version
    if ($version.Major -lt 10) {
        Write-Err "Se requiere Windows 10+"; exit 1
    }
    if ($version.Major -eq 10 -and $version.Build -lt 17763) {
        Write-Err "Se requiere Windows 10 1809+ (Build 17763+). Build actual: $($version.Build)"
        exit 1
    }
    Write-Ok "Windows (Build $($version.Build)) detectado"
}

function Test-Winget {
    if (-not (Test-CommandExists "winget")) {
        Write-Err "winget no encontrado."
        Write-Info "Instala 'App Installer' desde Microsoft Store: https://aka.ms/getwinget"
        exit 1
    }
    Write-Ok "winget disponible"
}

# ═══════════════════════════════════════════════════════════════
#  Pre-flight Checks
# ═══════════════════════════════════════════════════════════════

function Test-Internet {
    Write-Step "Verificando conexion a internet..."
    try {
        $response = Invoke-WebRequest -Uri "https://github.com" -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        Write-Ok "Conexion a internet verificada"
    } catch {
        Write-Err "No se detecto conexion a internet."
        Write-Info "Verifica tu conexion y ejecuta el script de nuevo."
        Write-Info "Si estas detras de un proxy, configura HTTP_PROXY y HTTPS_PROXY."
        exit 1
    }
}

function Test-DiskSpace {
    Write-Step "Verificando espacio en disco..."
    $freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
    if ($freeGB -lt 5) {
        Write-Err "Espacio en disco insuficiente."
        Write-Info "Disponible: $freeGB GB — Se requieren al menos 5 GB."
        Write-Info "Libera espacio y ejecuta el script de nuevo."
        exit 1
    }
    Write-Ok "Espacio en disco suficiente ($freeGB GB disponibles)"
}

function Test-WingetHealth {
    Write-Step "Verificando que winget funciona correctamente..."
    if (-not (Test-CommandExists "winget")) {
        Write-Err "winget no encontrado."
        Write-Info "Instala 'App Installer' desde Microsoft Store: https://aka.ms/getwinget"
        exit 1
    }

    # Verify winget sources are healthy
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
            Write-Warn "No se pudieron reparar winget sources (puede requerir admin)."
            Write-Info "Si la instalacion falla, ejecuta como admin: winget source reset --force"
        }
    }
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

function Test-VersionManagers {
    Write-Step "Verificando version managers de Node.js..."

    # nvm-windows
    if ($env:NVM_HOME -or (Test-CommandExists "nvm")) {
        $script:HasVersionManager = $true
        $script:VersionManagerName = "nvm"
        Write-Skip "Node.js gestionado por nvm — se respeta tu instalacion"
        return
    }

    # fnm
    if (Test-CommandExists "fnm") {
        $script:HasVersionManager = $true
        $script:VersionManagerName = "fnm"
        Write-Skip "Node.js gestionado por fnm — se respeta tu instalacion"
        return
    }

    # volta
    if ((Test-CommandExists "volta") -or $env:VOLTA_HOME) {
        $script:HasVersionManager = $true
        $script:VersionManagerName = "volta"
        Write-Skip "Node.js gestionado por volta — se respeta tu instalacion"
        return
    }

    Write-Ok "No se detectaron version managers — Node.js se instalara via winget"
}

function Test-Preflight {
    Write-Host ""
    Write-Info "Ejecutando verificaciones previas..."
    Write-Host ""

    # Critical checks (abort on failure)
    Test-Internet
    Test-DiskSpace
    Test-WingetHealth

    # Non-critical checks (warn and continue)
    Test-PathLength
    Test-VersionManagers

    Write-Host ""
    Write-Ok "Todas las verificaciones pasaron"
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════
#  Funciones de Instalación
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

        # Si git no esta en PATH despues de instalar, agregarlo manualmente
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
        } else { throw "Git no encontrado post-install" }
    }
    catch {
        Write-Err "No se pudo instalar Git: $_"
        Write-Info "Si la descarga fallo, verifica tu conexion o configura HTTP_PROXY/HTTPS_PROXY."
        Write-Info "Si winget fallo, intenta: winget source reset --force"
        Write-Info "Descarga manual: https://git-scm.com/downloads/win"
        Write-Info "IMPORTANTE: Marca 'Add Git to PATH' durante instalacion"
        $script:Errors += "Git"
    }
}

function Install-NodeJS {
    Write-Step "Verificando Node.js..."

    # Skip if a version manager is managing Node.js
    if ($script:HasVersionManager) {
        if (Test-CommandExists "node") {
            Write-Skip "Node.js $(node --version) detectado (gestionado por $($script:VersionManagerName)) — se respeta tu instalacion"
        } else {
            Write-Skip "Node.js gestionado por $($script:VersionManagerName) (no activo en esta sesion) — se respeta tu instalacion"
            Write-Info "Asegurate de activar una version de Node.js con $($script:VersionManagerName) antes de usar npm"
        }
        $script:AlreadyInstalled += "Node.js ($($script:VersionManagerName))"
        return
    }

    # Check both command in PATH and file on disk
    if (-not (Test-CommandExists "node") -and (Test-Path "C:\Program Files\nodejs\node.exe")) {
        # Node exists but not in session PATH — add it
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

        # Si node no esta en PATH despues de instalar, agregarlo manualmente
        if (-not (Test-CommandExists "node")) {
            $nodeDir = "C:\Program Files\nodejs"
            if (Test-Path "$nodeDir\node.exe") {
                # Agregar a sesion actual
                $env:Path = "$nodeDir;$env:Path"
                Write-Info "Node.js agregado al PATH de la sesion actual"
            }
        }

        if (Test-CommandExists "node") {
            Write-Ok "Node.js instalado ($(node --version))"
            $script:Installed += "Node.js"
            $script:NeedNewTerminal = $true
        } else { throw "Node.js no encontrado post-install" }
    }
    catch {
        Write-Err "No se pudo instalar Node.js: $_"
        Write-Info "Si la descarga fallo, verifica tu conexion o configura HTTP_PROXY/HTTPS_PROXY."
        Write-Info "Descarga manual: https://nodejs.org"
        $script:Errors += "Node.js"
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
        # Existe pero no está en PATH — agregarlo permanentemente
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

        # Agregar .local\bin al PATH del usuario permanentemente si no está
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        if ($userPath -notmatch [regex]::Escape($claudeDir)) {
            $newPathLen = "$claudeDir;$userPath".Length
            if ($newPathLen -gt 2048) {
                Write-Warn "Agregar Claude al PATH excederia el limite de 2048 caracteres ($newPathLen)."
                Write-Info "Claude se instalo pero el PATH no se actualizo. Agrega manualmente: $claudeDir"
            } else {
                [System.Environment]::SetEnvironmentVariable("Path", "$claudeDir;$userPath", "User")
                Write-Info "Claude Code agregado al PATH del usuario"
            }
        }

        # Agregar al PATH de la sesion actual tambien
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

# ═══════════════════════════════════════════════════════════════
#  Resumen Final
# ═══════════════════════════════════════════════════════════════

function Write-Summary {
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
        $pkgIcon = if ($script:UseEmoji) { "📦" } else { "[NEW]" }
        $okIcon = if ($script:UseEmoji) { "✅" } else { "[OK]" }
        Write-Host "  $pkgIcon Instalado ahora:" -ForegroundColor White
        foreach ($item in $script:Installed) {
            Write-Host "     $okIcon $item" -ForegroundColor Green
        }
        Write-Host ""
    }

    if ($script:AlreadyInstalled.Count -gt 0) {
        $skipIcon = if ($script:UseEmoji) { "⏭️" } else { "[SKIP]" }
        $okIcon = if ($script:UseEmoji) { "✅" } else { "[OK]" }
        Write-Host "  $skipIcon Ya estaba instalado:" -ForegroundColor White
        foreach ($item in $script:AlreadyInstalled) {
            Write-Host "     $okIcon $item" -ForegroundColor Green
        }
        Write-Host ""
    }

    if ($script:Errors.Count -gt 0) {
        $errIcon = if ($script:UseEmoji) { "❌" } else { "[ERROR]" }
        Write-Host "  $errIcon No se pudo instalar:" -ForegroundColor White
        foreach ($item in $script:Errors) {
            Write-Host "     $errIcon $item" -ForegroundColor Red
        }
        Write-Host ""
    }

    $listIcon = if ($script:UseEmoji) { "📋" } else { "[VER]" }
    Write-Host "  $listIcon Versiones finales:" -ForegroundColor White
    Write-Host "  -------------------------------------"
    if (Test-CommandExists "git")    { Write-Host "     Git:         $(git --version)" }
    if (Test-CommandExists "node")   { Write-Host "     Node.js:     $(node --version)" }
    if (Test-CommandExists "npm")    { $npmVer = try { npm.cmd --version 2>$null } catch { npm --version 2>$null }; Write-Host "     npm:         $npmVer" }
    if (Test-CommandExists "claude") {
        $cv = try { claude --version 2>$null } catch { "ver nueva terminal" }
        Write-Host "     Claude Code: $cv"
    }
    Write-Host "  -------------------------------------"

    Write-Host ""
    Write-Separator
    $pinIcon = if ($script:UseEmoji) { "📌" } else { "[>>]" }
    $rocketIcon = if ($script:UseEmoji) { "🚀" } else { "" }
    Write-Host "  $pinIcon Siguiente paso:" -ForegroundColor White
    if ($script:NeedNewTerminal) {
        Write-Host "     1. CIERRA esta terminal"
        Write-Host "     2. ABRE una nueva terminal"
    } else {
        Write-Host "     1. Abre una terminal"
    }
    Write-Host "     3. Escribe:  claude"
    Write-Host "     4. Autenticate con tu cuenta (Pro o Max)"
    Write-Host "     5. Listo! Ya puedes usar Claude Code $rocketIcon"
    Write-Separator
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════
#  Funciones de Desinstalación
# ═══════════════════════════════════════════════════════════════

$script:Removed = @()
$script:NotFound = @()

function Uninstall-ClaudeCode {
    Write-Step "Desinstalando Claude Code..."

    $claudePath = "$env:USERPROFILE\.local\bin\claude.exe"
    if ((Test-CommandExists "claude") -or (Test-Path $claudePath)) {
        Remove-Item -Recurse -Force "$env:USERPROFILE\.local" -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force "$env:USERPROFILE\.claude" -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force "$env:USERPROFILE\.config\claude" -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force "$env:APPDATA\Claude" -ErrorAction SilentlyContinue

        # Limpiar PATH del usuario
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

function Uninstall-NodeJS {
    Write-Step "Desinstalando Node.js..."

    $nodeExists = (Test-CommandExists "node") -or (Test-Path "C:\Program Files\nodejs\node.exe")
    if (-not $nodeExists) {
        Write-Skip "Node.js no encontrado"
        $script:NotFound += "Node.js"
        return
    }

    $uninstalled = $false

    # Nivel 1: winget
    Write-Step "Intentando desinstalar Node.js via winget..."
    try {
        $wingetResult = winget uninstall OpenJS.NodeJS.LTS --silent 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Node.js eliminado via winget"
            $uninstalled = $true
        } else {
            throw "winget exit code: $LASTEXITCODE"
        }
    } catch {
        Write-Warn "winget no pudo desinstalar Node.js ($($_.Exception.Message))"
    }

    # Nivel 2: msiexec via registro
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
                } else {
                    throw "msiexec exit code: $($msiResult.ExitCode)"
                }
            } else {
                throw "No se encontro MSI ID de Node.js en el registro"
            }
        } catch {
            Write-Warn "msiexec no pudo desinstalar Node.js ($($_.Exception.Message))"
        }
    }

    # Nivel 3: limpieza manual
    if (-not $uninstalled) {
        Write-Step "Realizando limpieza manual de Node.js..."
        $nodeDirs = @(
            "C:\Program Files\nodejs",
            "$env:APPDATA\npm",
            "$env:APPDATA\npm-cache",
            "$env:USERPROFILE\.node-gyp"
        )
        foreach ($dir in $nodeDirs) {
            if (Test-Path $dir) {
                Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
            }
        }

        # Limpiar entradas del registro para que winget no crea que sigue instalado
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
            } catch {
                # Registry cleanup may need admin — not critical
            }
        }

        Write-Ok "Node.js eliminado via limpieza manual"
        $uninstalled = $true
    }

    # Limpiar carpetas residuales (en todos los casos)
    Remove-Item -Recurse -Force "$env:APPDATA\npm" -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force "$env:APPDATA\npm-cache" -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force "$env:USERPROFILE\.node-gyp" -ErrorAction SilentlyContinue

    # Limpiar PATH de entradas de nodejs y npm
    foreach ($scope in @("User", "Machine")) {
        $pathVal = [System.Environment]::GetEnvironmentVariable("Path", $scope)
        if ($pathVal -and ($pathVal -match 'nodejs' -or $pathVal -match '\\npm')) {
            $cleanPath = ($pathVal -split ';' | Where-Object {
                $_ -notmatch 'nodejs' -and $_ -notmatch '\\npm$' -and $_ -notmatch '\\npm\\' -and $_ -ne ''
            }) -join ';'
            try {
                [System.Environment]::SetEnvironmentVariable("Path", $cleanPath, $scope)
            } catch {
                if ($scope -eq "Machine") {
                    Write-Warn "No se pudo limpiar el PATH de Machine (requiere admin)."
                    Write-Info "Ejecuta como admin para limpiar completamente."
                }
            }
        }
    }

    Update-SessionPath

    if ($uninstalled) {
        $script:Removed += "Node.js"
    } else {
        Write-Err "No se pudo eliminar Node.js completamente"
        $script:Errors += "Node.js"
    }
}

function Uninstall-Git {
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

        # Limpiar PATH residual de Git
        foreach ($scope in @("User", "Machine")) {
            $pathVal = [System.Environment]::GetEnvironmentVariable("Path", $scope)
            if ($pathVal -and $pathVal -match 'Git') {
                $cleanPath = ($pathVal -split ';' | Where-Object {
                    $_ -notmatch '\\Git\\' -and $_ -ne ''
                }) -join ';'
                try {
                    [System.Environment]::SetEnvironmentVariable("Path", $cleanPath, $scope)
                } catch {
                    # Machine PATH requires admin — skip silently
                }
            }
        }

        Update-SessionPath
        Write-Ok "Git eliminado"
        $script:Removed += "Git"
    } catch {
        Write-Err "No se pudo eliminar Git: $_"
        Write-Info "Causa probable: winget fallo durante la desinstalacion."
        Write-Info "Intenta manualmente: winget uninstall Git.Git"
        $script:Errors += "Git"
    }
}

function Write-UninstallSummary {
    Write-Host ""
    Write-Separator

    $cleanIcon = if ($script:UseEmoji) { "🧹" } else { "[OK]" }
    if ($script:Errors.Count -eq 0) {
        Write-Host "  $cleanIcon Desinstalacion completada" -ForegroundColor Green
    } else {
        $warnIcon = if ($script:UseEmoji) { "⚠️" } else { "[WARN]" }
        Write-Host "  $warnIcon Desinstalacion completada con errores" -ForegroundColor Yellow
    }

    Write-Separator
    Write-Host ""

    if ($script:Removed.Count -gt 0) {
        $trashIcon = if ($script:UseEmoji) { "🗑️" } else { "[DEL]" }
        $okIcon = if ($script:UseEmoji) { "✅" } else { "[OK]" }
        Write-Host "  $trashIcon Eliminado:" -ForegroundColor White
        foreach ($item in $script:Removed) {
            Write-Host "     $okIcon $item" -ForegroundColor Green
        }
        Write-Host ""
    }

    if ($script:NotFound.Count -gt 0) {
        $skipIcon = if ($script:UseEmoji) { "⏭️" } else { "[SKIP]" }
        Write-Host "  $skipIcon No estaba instalado:" -ForegroundColor White
        foreach ($item in $script:NotFound) {
            Write-Host "     - $item" -ForegroundColor Cyan
        }
        Write-Host ""
    }

    if ($script:Errors.Count -gt 0) {
        $errIcon = if ($script:UseEmoji) { "❌" } else { "[ERROR]" }
        Write-Host "  $errIcon No se pudo eliminar:" -ForegroundColor White
        foreach ($item in $script:Errors) {
            Write-Host "     $errIcon $item" -ForegroundColor Red
        }
        Write-Host ""
    }

    # Verificación post-desinstalación
    Write-Host ""
    $checkIcon = if ($script:UseEmoji) { "🔍" } else { "[CHK]" }
    Write-Host "  $checkIcon Verificacion post-desinstalacion:" -ForegroundColor White
    Update-SessionPath

    $residualItems = @()
    if (Test-CommandExists "node")   { $residualItems += "node" }
    if (Test-CommandExists "git")    { $residualItems += "git" }
    if (Test-CommandExists "claude") { $residualItems += "claude" }
    if (Test-Path "C:\Program Files\nodejs") { $residualItems += "carpeta nodejs" }
    if (Test-Path "$env:USERPROFILE\.local\bin\claude.exe") { $residualItems += "claude.exe" }

    if ($residualItems.Count -eq 0) {
        $okIcon = if ($script:UseEmoji) { "✅" } else { "[OK]" }
        Write-Host "     $okIcon Sistema limpio — no quedan residuos" -ForegroundColor Green
    } else {
        $warnIcon = if ($script:UseEmoji) { "⚠️" } else { "[WARN]" }
        Write-Host "     $warnIcon Residuos detectados: $($residualItems -join ', ')" -ForegroundColor Yellow
        Write-Host "     Abre una nueva terminal y verifica. Puede requerir reinicio." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Separator
    $pinIcon = if ($script:UseEmoji) { "📌" } else { "[>>]" }
    Write-Host "  $pinIcon Nota:" -ForegroundColor White
    Write-Host "     Cierra y abre una nueva terminal para que los cambios de PATH surtan efecto."
    Write-Separator
    Write-Host ""
}

function Run-Uninstall {
    Clear-Host
    Write-Header
    Write-SystemInfo

    Write-Host ""
    Write-Host "  !! MODO DESINSTALACION" -ForegroundColor Red
    Write-Host "  Se eliminaran: Claude Code, Node.js, Git" -ForegroundColor Red
    Write-Host ""
    $confirm = Read-Host "  Continuar? (s/N)"
    if ($confirm -ne "s" -and $confirm -ne "S") {
        Write-Host ""
        Write-Info "Desinstalacion cancelada."
        return
    }

    Write-Host ""
    Write-Info "Iniciando desinstalacion..."
    Write-Host ""

    Uninstall-ClaudeCode
    Uninstall-NodeJS
    Uninstall-Git

    Write-UninstallSummary
}

# ═══════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════

function Main {
    Clear-Host
    Write-Header
    Test-WindowsVersion
    Write-SystemInfo

    Test-Preflight

    Write-Host ""
    Write-Info "Iniciando instalacion..."
    Write-Host ""

    Install-GitForWindows
    Install-NodeJS
    Install-ClaudeCode

    Write-Summary
}

# Detectar modo: --uninstall o instalacion normal
$isUninstall = $false
if ($args -contains "--uninstall") {
    $isUninstall = $true
} elseif ($env:CLAUDE_SETUP_UNINSTALL -eq "1") {
    $isUninstall = $true
}

if ($isUninstall) {
    Run-Uninstall
} else {
    Main
}
