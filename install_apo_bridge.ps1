# ============================================================
#  APO Remote Studio — Instalador Automático
#  Instala y configura todo lo necesario para usar la app móvil
#  con Equalizer APO como ecualizador de sistema en Windows.
#
#  Ejecutar como Administrador:
#    Right-click → "Run with PowerShell" (as admin)
# ============================================================

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

function Write-Header {
    param([string]$text)
    Write-Host "`n╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host   "  $text" -ForegroundColor White
    Write-Host   "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$step, [string]$status = "INFO", [string]$detail = "")
    $color = switch ($status) {
        "OK"   { "Green" }
        "WARN" { "Yellow" }
        "ERR"  { "Red" }
        default { "Cyan" }
    }
    Write-Host "  [$status] $step" -ForegroundColor $color
    if ($detail) { Write-Host "         $detail" -ForegroundColor DarkGray }
}

function Test-Command { param([string]$cmd); return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

Clear-Host
Write-Header "APO Remote Studio — Instalador v1.0"
Write-Host "  Configura Python, bridge de red y Equalizer APO" -ForegroundColor Gray
Write-Host "  Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n" -ForegroundColor DarkGray

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$BridgeDir   = Join-Path $ScriptDir "apo_bridge"
$ApoBridgeMain = Join-Path $BridgeDir "qr_launcher.py"

# ── 1. COMPROBAR PYTHON ──────────────────────────────────────────────────────
Write-Header "1. Python"

$pythonCmd = $null
foreach ($cmd in @("python", "python3", "py")) {
    if (Test-Command $cmd) {
        $ver = & $cmd --version 2>&1
        if ($ver -match "Python 3\.(\d+)") {
            $minor = [int]$matches[1]
            if ($minor -ge 9) {
                $pythonCmd = $cmd
                Write-Step "Python encontrado: $ver" "OK"
                break
            }
        }
    }
}

if (-not $pythonCmd) {
    Write-Step "Python 3.9+ no encontrado. Descargando..." "WARN"
    $pyInstaller = "$env:TEMP\python_installer.exe"
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.12.7/python-3.12.7-amd64.exe" `
        -OutFile $pyInstaller -UseBasicParsing
    Write-Step "Instalando Python 3.12 (silencioso)..." "INFO"
    Start-Process -FilePath $pyInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_pip=1" -Wait
    Remove-Item $pyInstaller -Force

    # Refresh PATH
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")

    $pythonCmd = "python"
    Write-Step "Python instalado correctamente" "OK"
}

# ── 2. INSTALAR PAQUETES PIP ─────────────────────────────────────────────────
Write-Header "2. Paquetes de Python"

$packages = @(
    "aiohttp",
    "websockets",
    "pyaudiowpatch",
    "PyQt6",
    "qrcode[pil]",
    "Pillow",
    "pywin32"
)

foreach ($pkg in $packages) {
    try {
        Write-Step "Instalando $pkg..." "INFO"
        & $pythonCmd -m pip install --quiet --upgrade $pkg 2>&1 | Out-Null
        Write-Step "$pkg listo" "OK"
    } catch {
        Write-Step "Error instalando $pkg" "WARN" "$_"
    }
}

# ── 3. VERIFICAR EQUALIZER APO ───────────────────────────────────────────────
Write-Header "3. Equalizer APO"

$apoReg = @(
    "HKLM:\SOFTWARE\EqualizerAPO",
    "HKLM:\SOFTWARE\WOW6432Node\EqualizerAPO"
)

$apoInstalled = $false
$apoPath = $null

foreach ($reg in $apoReg) {
    if (Test-Path $reg) {
        try {
            $apoPath = (Get-ItemProperty $reg).InstallPath
            if ($apoPath -and (Test-Path $apoPath)) {
                $apoInstalled = $true
                Write-Step "Equalizer APO encontrado en: $apoPath" "OK"
                break
            }
        } catch {}
    }
}

if (-not $apoInstalled) {
    Write-Step "Equalizer APO NO está instalado." "WARN"
    Write-Host "`n  Descarga e instala Equalizer APO desde:" -ForegroundColor Yellow
    Write-Host "  https://equalizerapo.sourceforge.io/" -ForegroundColor Cyan
    Write-Host "`n  Después de instalar, vuelve a ejecutar este script.`n" -ForegroundColor Yellow

    $open = Read-Host "  ¿Abrir el sitio web ahora? (s/n)"
    if ($open -match "^[sS]") {
        Start-Process "https://equalizerapo.sourceforge.io/"
    }
    Write-Host "`n  Script detenido. Re-ejecuta cuando APO esté instalado." -ForegroundColor Red
    Read-Host "  Presiona Enter para salir"
    exit 1
}

# ── 4. CONFIGURAR config.txt DE APO ──────────────────────────────────────────
Write-Header "4. Configuración de Equalizer APO"

$apoConfig = Join-Path $apoPath "config\config.txt"
$apoRemote  = Join-Path $apoPath "config\remote_eq.txt"
$includeTag = "Include: remote_eq.txt"

# Crear remote_eq.txt si no existe
if (-not (Test-Path $apoRemote)) {
    @"
# Remote EQ — gestionado por APO Remote Studio
# Este archivo se actualiza automáticamente.
Preamp: 0 dB
GraphicEQ: 25 0; 40 0; 63 0; 100 0; 160 0; 250 0; 400 0; 630 0; 1000 0; 1600 0; 2500 0; 4000 0; 6300 0; 10000 0; 16000 0
"@ | Set-Content $apoRemote -Encoding UTF8
    Write-Step "Creado remote_eq.txt" "OK" $apoRemote
} else {
    Write-Step "remote_eq.txt ya existe" "OK"
}

# Agregar Include al config.txt si no está
if (Test-Path $apoConfig) {
    $content = Get-Content $apoConfig -Raw
    if ($content -notmatch [regex]::Escape($includeTag)) {
        "`n# APO Remote Studio`n$includeTag" | Add-Content $apoConfig -Encoding UTF8
        Write-Step "Include agregado al config.txt" "OK"
    } else {
        Write-Step "Include ya está en config.txt" "OK"
    }
} else {
    @"
# Equalizer APO config — APO Remote Studio
$includeTag
"@ | Set-Content $apoConfig -Encoding UTF8
    Write-Step "Creado config.txt con Include" "OK"
}

# ── 5. CREAR ACCESO DIRECTO EN EL ESCRITORIO ────────────────────────────────
Write-Header "5. Acceso directo"

$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "APO Remote Studio.lnk"

# Encontrar pythonw (sin ventana de consola)
$pythonwPath = (Get-Command python -ErrorAction SilentlyContinue).Source
if ($pythonwPath) {
    $pythonwPath = $pythonwPath.Replace("python.exe", "pythonw.exe")
}
if (-not $pythonwPath -or -not (Test-Path $pythonwPath)) {
    $pythonwPath = (Get-Command $pythonCmd -ErrorAction SilentlyContinue).Source
}

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($shortcutPath)
$lnk.TargetPath       = $pythonwPath
$lnk.Arguments        = "`"$ApoBridgeMain`""
$lnk.WorkingDirectory = $BridgeDir
$lnk.Description      = "APO Remote Studio Bridge"
$lnk.IconLocation     = "shell32.dll,14"
$lnk.Save()

Write-Step "Acceso directo creado en el Escritorio" "OK" $shortcutPath

# ── 6. ACCESO DIRECTO DE INICIO AUTOMÁTICO ───────────────────────────────────
Write-Header "6. Inicio automático (opcional)"

$startupFolder = [Environment]::GetFolderPath("Startup")
$startupShortcut = Join-Path $startupFolder "APO Remote Studio.lnk"

$autoStart = Read-Host "  ¿Iniciar el bridge automáticamente con Windows? (s/n)"
if ($autoStart -match "^[sS]") {
    $lnk2 = $shell.CreateShortcut($startupShortcut)
    $lnk2.TargetPath       = $pythonwPath
    $lnk2.Arguments        = "`"$ApoBridgeMain`" --startup"
    $lnk2.WorkingDirectory = $BridgeDir
    $lnk2.Description      = "APO Remote Studio Bridge (auto)"
    $lnk2.IconLocation     = "shell32.dll,14"
    $lnk2.Save()
    Write-Step "Acceso directo de inicio creado" "OK" $startupShortcut
} else {
    Write-Step "Inicio automático omitido" "INFO"
}

# ── 7. INICIAR EL BRIDGE AHORA ───────────────────────────────────────────────
Write-Header "7. Iniciar el bridge"

$startNow = Read-Host "  ¿Iniciar APO Remote Studio Bridge ahora? (s/n)"
if ($startNow -match "^[sS]") {
    Start-Process -FilePath $pythonwPath -ArgumentList "`"$ApoBridgeMain`"" `
        -WorkingDirectory $BridgeDir -WindowStyle Hidden
    Write-Step "Bridge iniciado en segundo plano" "OK"
    Write-Step "Busca el icono en la bandeja del sistema" "INFO"
}

# ── RESUMEN ───────────────────────────────────────────────────────────────────
Write-Header "Instalación Completada"

Write-Host @"
  ✓ Python instalado y configurado
  ✓ Paquetes pip instalados
  ✓ Equalizer APO verificado y configurado
  ✓ Acceso directo en el Escritorio creado

  PRÓXIMOS PASOS:
  1. Instala el APK en tu celular (EqualizerAPO_Remote.apk)
  2. Inicia 'APO Remote Studio' desde el Escritorio
  3. Abre la app en el celular — se conectará automáticamente
  4. ¡Ecualizas el PC desde el celular en tiempo real!

"@ -ForegroundColor White

Read-Host "  Presiona Enter para cerrar"
