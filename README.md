# 🎛️ Plugin APO + App Flutter (APO Remote Studio)

> **Control remoto inalámbrico y visualizador en tiempo real para Equalizer APO en Windows mediante aplicación móvil Flutter (Android) y servidor puente en Python.**

[![GitHub Release](https://img.shields.io/github/v/release/efrakingz/plugin-apo-app-flutter?style=for-the-badge&color=blue)](https://github.com/efrakingz/plugin-apo-app-flutter/releases/latest)
[![Download APK](https://img.shields.io/badge/Descargar-APK%20Android%20v1.0.0-success?style=for-the-badge&logo=android)](https://github.com/efrakingz/plugin-apo-app-flutter/releases/download/v1.0.0/EqualizerAPO_Remote.apk)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

---

## 📱 ¿Cómo instalar la aplicación en tu móvil?

1. **Descargar el APK:**
   - 📥 Haz clic en el botón de arriba o descarga directamente [EqualizerAPO_Remote.apk](https://github.com/efrakingz/plugin-apo-app-flutter/releases/download/v1.0.0/EqualizerAPO_Remote.apk).
2. **Instalar en Android:**
   - Abre el archivo descargado en tu teléfono.
   - Si Android te pide autorización para *"Instalar aplicaciones de fuentes desconocidas"*, concédela para tu navegador o gestor de archivos.
   - Toca **Instalar** y luego **Abrir**.
3. **Conectar a tu PC:**
   - Asegúrate de que el teléfono y la PC estén conectados a la **misma red Wi-Fi**.
   - Escanea el código QR que muestra el servidor de la PC o ingresa la IP manualmente.

---

## 💻 ¿Cómo instalar y configurar el Bridge en Windows?

El proyecto incluye un script automatizado para PowerShell que instala todas las dependencias necesarias:

1. **Requisitos previos en Windows:**
   - Tener instalado [Equalizer APO](https://sourceforge.net/projects/equalizerapo/).
2. **Ejecutar el instalador automático:**
   - Abre **PowerShell como Administrador** en la carpeta del proyecto.
   - Ejecuta:
     ```powershell
     .\install_apo_bridge.ps1
     ```
   - El instalador se encargará de:
     - Detectar o instalar Python 3.12 silenciosamente.
     - Instalar dependencias de Python (`aiohttp`, `websockets`, `pyaudiowpatch`, `PyQt6`, `qrcode`, `Pillow`, `pywin32`).
     - Habilitar la regla del Firewall de Windows para el puerto de conexión.
     - Verificar la instalación de Equalizer APO y su ruta de configuración.
3. **Iniciar el servidor:**
   - Ejecuta el lanzador gráfico:
     ```powershell
     python apo_bridge/qr_launcher.py
     ```
   - Aparecerá una ventana moderna con un **código QR** y la dirección IP de tu PC en la red local.

---

## ✨ Características principales

- 📡 **Conexión de ultra baja latencia:** Comunicación bidireccional mediante WebSockets a 60 FPS.
- 🎚️ **Control total de ecualización:**
  - Control de ganancia Pre-Amp.
  - Bandas de ecualización gráfica paramétrica en tiempo real.
  - Presets integrados (Bass Boost, Flat, Vocal, Rock, Pop, etc.).
- 📊 **Visualizador de audio en tiempo real:**
  - Captura de audio loopback directo de Windows (WASAPI) mediante `pyaudiowpatch`.
  - Transformada Rápida de Fourier (FFT) calculada en tiempo real.
  - Visualizador dinámico con motor Flame / Canvas en Flutter con efecto neón.
- 📷 **Fácil vinculación:**
  - Escáner de código QR integrado en la app para emparejamiento en 1 segundo.
  - Modo manual por dirección IP y puerto.
- 🌐 **Web Remote de respaldo:** Incluye una interfaz web HTML5 accesible desde cualquier navegador en la red local.

---

## 📂 Estructura del Repositorio

```text
├── EqualizerAPO_Remote.apk     # Instalador listo para Android
├── install_apo_bridge.ps1      # Script de instalación automática para Windows
├── apo_bridge/                 # Servidor Bridge en Python (Windows)
│   ├── apo_manager.py          # Lógica de lectura/escritura en Equalizer APO
│   ├── audio_loopback.py       # Captura de audio WASAPI y FFT en tiempo real
│   ├── network_server.py       # Servidor HTTP/WebSocket
│   ├── qr_launcher.py          # Interfaz gráfica PyQt6 con código QR
│   └── web_remote/             # Cliente web alternativo (HTML/CSS/JS)
└── apo_flutter/                # Código fuente de la app móvil Flutter
    ├── lib/
    │   ├── game/               # Visualizador de audio basado en Flame
    │   ├── screens/            # Pantallas de ecualización y conexión
    │   ├── theme/              # Estilos visuales oscuros y de neón
    │   └── widgets/            # Sliders, analizadores y barras de control
    └── pubspec.yaml            # Dependencias de Flutter
```

---

## 🛠️ Tecnologías Utilizadas

- **App Móvil:** [Flutter](https://flutter.dev/) & [Dart](https://dart.dev/), [Flame Engine](https://flame-engine.org/) para visualización.
- **Servidor Windows:** [Python 3](https://python.org/), `aiohttp`, `websockets`, `pyaudiowpatch`, `PyQt6`.
- **Motor de Audio:** [Equalizer APO](https://sourceforge.net/projects/equalizerapo/).

---

## 💖 Apoya el Proyecto (Donaciones y Aportes)

Si este proyecto te ha sido de utilidad para controlar tu audio o te gusta la integración visual en tiempo real, puedes apoyar su desarrollo y mantenimiento continuo con un aporte:

[![Ko-fi](https://img.shields.io/badge/Ko--fi-F16061?style=for-the-badge&logo=ko-fi&logoColor=white)](https://ko-fi.com/efrakingz)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy_Me_A_Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/efrakingz)
[![PayPal](https://img.shields.io/badge/PayPal-Donar-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://www.paypal.com/donate/?business=efrakingz131@gmail.com&currency_code=USD)

> *Nota: También puedes apoyar dejando una estrella ⭐ en este repositorio o compartiéndolo en comunidades de audio y tecnología.*

---

## 🤝 Cómo Colaborar

¡Las contribuciones son bienvenidas!
1. Haz un **Fork** del proyecto.
2. Crea tu rama de características (`git checkout -b feature/NuevaFuncion`).
3. Realiza tus commits (`git commit -m 'Añadir nueva función'`).
4. Haz push a la rama (`git push origin feature/NuevaFuncion`).
5. Abre un **Pull Request**.

Si encuentras algún problema o tienes sugerencias de nuevas características, abre un [Issue](https://github.com/efrakingz/plugin-apo-app-flutter/issues).

---

## 📄 Licencia

Este proyecto está bajo la Licencia MIT. Consulta el archivo [LICENSE](LICENSE) para más detalles.
