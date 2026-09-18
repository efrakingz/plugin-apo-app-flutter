"""
Equalizer APO Remote Companion Launcher:
- Generates pairing QR code
- Multi-IP selector (Home Wi-Fi, Phone Hotspot, USB Tethering)
- Launches WASAPI loopback analyzer and WebSocket/HTTP server
- Displays sleek companion GUI window with connection status
"""

import sys
import os
import io
import asyncio
import threading
import logging
import qrcode
from PIL import Image

from PyQt6.QtCore import Qt, QTimer, pyqtSignal, QObject
from PyQt6.QtGui import QFont, QPixmap, QImage, QIcon, QColor
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QFrame, QComboBox, QSizePolicy,
    QSystemTrayIcon, QMenu, QInputDialog
)

# Bridge modules
from apo_manager import APOManager
from audio_loopback import AudioLoopbackAnalyzer
from network_server import NetworkServer, get_all_local_ips, get_primary_ip, HTTP_PORT

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("APO_Launcher")


class APORemoteApp(QMainWindow):
    def __init__(self, server, analyzer, manager):
        super().__init__()
        self.server = server
        self.analyzer = analyzer
        self.manager = manager
        
        self.all_interfaces = get_all_local_ips()
        self.current_ip = get_primary_ip()
        self.mobile_url = f"http://{self.current_ip}:{HTTP_PORT}"

        self.setWindowTitle("Equalizer APO - Puente Remoto Inalámbrico")
        self.setFixedSize(510, 730)
        self.setStyleSheet("""
            QMainWindow {
                background-color: #06080e;
            }
            QLabel {
                color: #e2e8f0;
                font-family: 'Segoe UI', 'Outfit', sans-serif;
            }
            QComboBox {
                background-color: #121826;
                color: #00f0ff;
                border: 1px solid rgba(0, 240, 255, 0.3);
                border-radius: 8px;
                padding: 6px 12px;
                font-weight: 600;
                font-family: Consolas, monospace;
            }
            QComboBox::drop-down {
                border: none;
            }
            QComboBox QAbstractItemView {
                background-color: #121826;
                color: #00f0ff;
                selection-background-color: #1c253b;
                border: 1px solid rgba(0, 240, 255, 0.3);
            }
            QPushButton {
                background-color: #151c2d;
                color: #00f0ff;
                border: 1px solid rgba(0, 240, 255, 0.3);
                border-radius: 9px;
                padding: 10px 18px;
                font-weight: bold;
                font-size: 13px;
            }
            QPushButton:hover {
                background-color: #1c253b;
                border-color: #00f0ff;
            }
            QPushButton#btnPrimary {
                background: qlineargradient(x1:0, y1:0, x2:1, y2:1, stop:0 #0077ff, stop:1 #00f0ff);
                color: #040810;
                border: none;
            }
            QPushButton#btnPrimary:hover {
                background: #00f0ff;
            }
        """)

        self._init_ui()

        # Update timer
        self.timer = QTimer(self)
        self.timer.timeout.connect(self._update_status)
        self.timer.start(1000)

    def _init_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        layout.setContentsMargins(26, 22, 26, 22)
        layout.setSpacing(14)

        # Header Title
        header_box = QVBoxLayout()
        header_box.setSpacing(4)
        title = QLabel("EQUALIZER APO REMOTE")
        title.setFont(QFont("Segoe UI", 16, QFont.Weight.Bold))
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        title.setStyleSheet("color: #00f0ff; letter-spacing: 1.2px;")

        subtitle = QLabel("Auto-conexión por Wi-Fi o Zona Portátil (Hotspot)")
        subtitle.setFont(QFont("Segoe UI", 9))
        subtitle.setAlignment(Qt.AlignmentFlag.AlignCenter)
        subtitle.setStyleSheet("color: #8292a6;")

        header_box.addWidget(title)
        header_box.addWidget(subtitle)
        layout.addLayout(header_box)

        # Network Interface Selector Box
        iface_box = QHBoxLayout()
        iface_label = QLabel("Red / IP:")
        iface_label.setFont(QFont("Segoe UI", 9, QFont.Weight.Bold))
        iface_label.setStyleSheet("color: #8292a6;")

        self.combo_ip = QComboBox()
        for item in self.all_interfaces:
            self.combo_ip.addItem(f"{item['ip']} ({item['interface']})", item["ip"])

        self.combo_ip.currentIndexChanged.connect(self._on_ip_changed)
        iface_box.addWidget(iface_label)
        iface_box.addWidget(self.combo_ip)
        layout.addLayout(iface_box)

        # QR Code Frame
        qr_frame = QFrame()
        qr_frame.setStyleSheet("""
            QFrame {
                background-color: #0e1320;
                border: 1px solid rgba(0, 240, 255, 0.25);
                border-radius: 18px;
            }
        """)
        qr_layout = QVBoxLayout(qr_frame)
        qr_layout.setContentsMargins(18, 16, 18, 16)
        qr_layout.setAlignment(Qt.AlignmentFlag.AlignCenter)

        # Generate QR code image
        self.qr_label = QLabel()
        self.qr_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._refresh_qr()
        qr_layout.addWidget(self.qr_label)

        hint = QLabel("Escanea con la cámara de tu celular para entrar de una")
        hint.setFont(QFont("Segoe UI", 9, QFont.Weight.DemiBold))
        hint.setAlignment(Qt.AlignmentFlag.AlignCenter)
        hint.setStyleSheet("color: #00ff9d; margin-top: 6px;")
        qr_layout.addWidget(hint)

        layout.addWidget(qr_frame)

        # IP URL Box
        url_box = QFrame()
        url_box.setStyleSheet("""
            QFrame {
                background-color: #121826;
                border: 1px solid rgba(0, 240, 255, 0.25);
                border-radius: 10px;
                padding: 4px;
            }
        """)
        url_layout = QHBoxLayout(url_box)
        url_layout.setContentsMargins(12, 6, 12, 6)

        self.url_label = QLabel(self.mobile_url)
        self.url_label.setFont(QFont("Consolas", 11, QFont.Weight.Bold))
        self.url_label.setStyleSheet("color: #00f0ff;")
        url_layout.addWidget(self.url_label)

        btn_copy = QPushButton("Copiar")
        btn_copy.setFixedWidth(75)
        btn_copy.clicked.connect(self._copy_url)
        url_layout.addWidget(btn_copy)

        layout.addWidget(url_box)

        # Presets Management Frame
        preset_frame = QFrame()
        preset_frame.setStyleSheet("""
            QFrame {
                background-color: #0d1322;
                border: 1px solid rgba(0, 240, 255, 0.25);
                border-radius: 12px;
                padding: 4px;
            }
        """)
        preset_layout = QVBoxLayout(preset_frame)
        preset_layout.setContentsMargins(12, 8, 12, 8)
        preset_layout.setSpacing(6)

        p_header = QHBoxLayout()
        p_title = QLabel("Presets de Ecualizador:")
        p_title.setFont(QFont("Segoe UI", 9, QFont.Weight.Bold))
        p_title.setStyleSheet("color: #00f0ff;")

        self.preset_active_label = QLabel(f"Activo: {self.manager.active_preset}")
        self.preset_active_label.setFont(QFont("Segoe UI", 8))
        self.preset_active_label.setStyleSheet("color: #ffaa00;")
        self.preset_active_label.setAlignment(Qt.AlignmentFlag.AlignRight)

        p_header.addWidget(p_title)
        p_header.addWidget(self.preset_active_label)
        preset_layout.addLayout(p_header)

        p_row = QHBoxLayout()
        p_row.setSpacing(8)
        self.combo_presets = QComboBox()
        self.combo_presets.setFont(QFont("Segoe UI", 9))
        self._refresh_presets_combo()
        p_row.addWidget(self.combo_presets, stretch=3)

        btn_load_preset = QPushButton("▶ Cargar")
        btn_load_preset.setFixedHeight(34)
        btn_load_preset.clicked.connect(self._on_load_preset)
        p_row.addWidget(btn_load_preset, stretch=1)

        btn_save_preset = QPushButton("💾 Guardar Preset")
        btn_save_preset.setObjectName("btnPrimary")
        btn_save_preset.setFixedHeight(34)
        btn_save_preset.clicked.connect(self._on_save_preset)
        p_row.addWidget(btn_save_preset, stretch=2)

        preset_layout.addLayout(p_row)
        layout.addWidget(preset_frame)

        # Status Info Bar
        info_layout = QHBoxLayout()
        self.dev_label = QLabel(f"Audio: {self.analyzer.device_name}")
        self.dev_label.setFont(QFont("Segoe UI", 8))
        self.dev_label.setStyleSheet("color: #8292a6;")

        self.clients_label = QLabel("Celulares conectados: 0")
        self.clients_label.setFont(QFont("Segoe UI", 8, QFont.Weight.Bold))
        self.clients_label.setStyleSheet("color: #00ff9d;")
        self.clients_label.setAlignment(Qt.AlignmentFlag.AlignRight)

        info_layout.addWidget(self.dev_label)
        info_layout.addWidget(self.clients_label)
        layout.addLayout(info_layout)

        # Action Buttons
        btn_layout = QHBoxLayout()
        btn_open = QPushButton("Abrir en Navegador")
        btn_open.setObjectName("btnPrimary")
        btn_open.clicked.connect(self._open_browser)

        btn_hide = QPushButton("Minimizar")
        btn_hide.clicked.connect(self.showMinimized)

        btn_layout.addWidget(btn_open)
        btn_layout.addWidget(btn_hide)
        layout.addLayout(btn_layout)

    def _refresh_qr(self):
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_M,
            box_size=7,
            border=2,
        )
        qr.add_data(self.mobile_url)
        qr.make(fit=True)

        img = qr.make_image(fill_color="#00f0ff", back_color="#0e1320").convert("RGBA")
        buffer = io.BytesIO()
        img.save(buffer, format="PNG")
        buffer.seek(0)

        qimg = QImage.fromData(buffer.getvalue())
        self.qr_label.setPixmap(QPixmap.fromImage(qimg))

    def _on_ip_changed(self, index):
        selected_ip = self.combo_ip.itemData(index)
        if selected_ip:
            self.current_ip = selected_ip
            self.mobile_url = f"http://{self.current_ip}:{HTTP_PORT}"
            self.url_label.setText(self.mobile_url)
            self._refresh_qr()

    def _refresh_presets_combo(self):
        self.combo_presets.clear()
        custom = list(self.manager.custom_presets.keys())
        if custom:
            self.combo_presets.addItem("── TUS PRESETS ──", "")
            for p in custom:
                self.combo_presets.addItem(f"★ {p}", p)
        self.combo_presets.addItem("── PRESETS DE FÁBRICA ──", "")
        for p in self.manager.get_state()["presets"]:
            if p not in custom:
                self.combo_presets.addItem(p, p)

    def _on_save_preset(self):
        default_name = f"Mi Preset {len(self.manager.custom_presets) + 1}"
        name, ok = QInputDialog.getText(
            self, "Guardar Preset de Ecualizador",
            "Ingresa un nombre para tu nuevo preset:",
            text=default_name
        )
        if ok and name.strip():
            clean_name = name.strip()
            self.manager.save_preset(clean_name)
            self._refresh_presets_combo()
            self.preset_active_label.setText(f"Activo: {clean_name}")
            import json
            payload = json.dumps({
                "type": "state_update",
                "state": self.manager.get_state()
            })
            if self.server and self.server.loop:
                asyncio.run_coroutine_threadsafe(
                    self.server.broadcast_message(payload),
                    self.server.loop
                )

    def _on_load_preset(self):
        data = self.combo_presets.currentData()
        name = data if data else self.combo_presets.currentText()
        if not name or name.startswith("──"):
            return
        if self.manager.apply_preset(name):
            self.preset_active_label.setText(f"Activo: {name}")
            import json
            payload = json.dumps({
                "type": "state_update",
                "state": self.manager.get_state()
            })
            if self.server and self.server.loop:
                asyncio.run_coroutine_threadsafe(
                    self.server.broadcast_message(payload),
                    self.server.loop
                )

    def _update_status(self):
        clients = len(self.server.ws_clients)
        self.clients_label.setText(f"Celulares conectados: {clients}")
        if self.analyzer.device_name:
            name = self.analyzer.device_name
            if len(name) > 32:
                name = name[:30] + "..."
            self.dev_label.setText(f"Audio: {name}")
        if hasattr(self, "preset_active_label") and hasattr(self.manager, "active_preset"):
            self.preset_active_label.setText(f"Activo: {self.manager.active_preset}")

    def _copy_url(self):
        clipboard = QApplication.clipboard()
        clipboard.setText(self.mobile_url)

    def _open_browser(self):
        import webbrowser
        webbrowser.open(self.mobile_url)

    def _setup_tray(self):
        self._is_force_quit = False
        self.tray_icon = QSystemTrayIcon(self)
        pixmap = QPixmap(32, 32)
        pixmap.fill(QColor("#00F0FF"))
        self.tray_icon.setIcon(QIcon(pixmap))
        self.tray_icon.setToolTip("Equalizer APO Remote - Activo (120 FPS)")

        tray_menu = QMenu()
        act_show = tray_menu.addAction("Abrir Panel QR")
        act_show.triggered.connect(self._restore_from_tray)
        act_browser = tray_menu.addAction("Abrir en Navegador")
        act_browser.triggered.connect(self._open_browser)
        tray_menu.addSeparator()
        act_exit = tray_menu.addAction("Salir por Completo")
        act_exit.triggered.connect(self._force_quit)

        self.tray_icon.setContextMenu(tray_menu)
        self.tray_icon.activated.connect(self._on_tray_activated)
        self.tray_icon.show()

    def _on_tray_activated(self, reason):
        if reason in (QSystemTrayIcon.ActivationReason.DoubleClick, QSystemTrayIcon.ActivationReason.Trigger):
            self._restore_from_tray()

    def _restore_from_tray(self):
        self.show()
        self.activateWindow()
        self.raise_()

    def _force_quit(self):
        self._is_force_quit = True
        if hasattr(self, "tray_icon"):
            self.tray_icon.hide()
        QApplication.quit()

    def closeEvent(self, event):
        if getattr(self, "_is_force_quit", False):
            event.accept()
        else:
            self.hide()
            if hasattr(self, "tray_icon") and self.tray_icon.isVisible():
                self.tray_icon.showMessage(
                    "Equalizer APO Remote",
                    "El puente sigue activo en segundo plano para tu celular.",
                    QSystemTrayIcon.MessageIcon.Information,
                    1500
                )
            event.ignore()


def run_bridge_app():
    manager = APOManager()
    analyzer = AudioLoopbackAnalyzer(apo_manager=manager, fps=120)
    
    web_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web_remote")
    server = NetworkServer(manager, analyzer, static_dir=web_dir)
    
    analyzer.callback = server.on_spectrum_update
    analyzer.start()

    async_loop = asyncio.new_event_loop()
    def start_async_loop():
        asyncio.set_event_loop(async_loop)
        async_loop.run_until_complete(server.start())
        async_loop.run_forever()

    server_thread = threading.Thread(target=start_async_loop, daemon=True)
    server_thread.start()

    app = QApplication(sys.argv)
    window = APORemoteApp(server, analyzer, manager)
    window._setup_tray()

    is_startup = any(arg in sys.argv for arg in ["--startup", "--minimized", "--tray", "--silent"])
    if not is_startup:
        window.show()

    exit_code = app.exec()

    analyzer.stop()
    async_loop.call_soon_threadsafe(async_loop.stop)
    sys.exit(exit_code)


if __name__ == "__main__":
    try:
        run_bridge_app()
    except Exception as e:
        logger.error(f"Fatal error in launcher: {e}", exc_info=True)
        sys.exit(1)
