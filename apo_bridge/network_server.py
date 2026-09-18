"""
Network Server for Equalizer APO Remote Companion:
- Multi-interface detection (Wi-Fi, Ethernet, Phone Mobile Hotspot & USB Tethering)
- aiohttp HTTP & WebSocket server (port 9876)
- Multi-subnet UDP auto-discovery beacon (port 9877)
- Instant connection engine for mobile devices
"""

import os
import json
import socket
import asyncio
import logging
from aiohttp import web

logger = logging.getLogger("APO_Server")

HTTP_PORT = 9876
UDP_BEACON_PORT = 9877


def get_all_local_ips():
    """Finds all valid non-loopback, non-APIPA IPv4 addresses on the PC."""
    found_ips = []
    try:
        import psutil
        for iface_name, addrs in psutil.net_if_addrs().items():
            for addr in addrs:
                if addr.family == socket.AF_INET:
                    ip = addr.address
                    if not ip.startswith("127.") and not ip.startswith("169.254."):
                        found_ips.append({
                            "interface": iface_name,
                            "ip": ip,
                            "netmask": addr.netmask or "255.255.255.0",
                            "broadcast": addr.broadcast or "255.255.255.255"
                        })
    except Exception as e:
        logger.warning(f"psutil network scan error: {e}")

    if not found_ips:
        # Fallback to standard outbound route detection
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            found_ips.append({
                "interface": "Default",
                "ip": ip,
                "netmask": "255.255.255.0",
                "broadcast": "255.255.255.255"
            })
        except Exception:
            found_ips.append({
                "interface": "Localhost",
                "ip": "127.0.0.1",
                "netmask": "255.0.0.0",
                "broadcast": "127.255.255.255"
            })

    return found_ips


def get_primary_ip():
    """Returns the best candidate IP for pairing."""
    all_ips = get_all_local_ips()
    # Prioritize mobile hotspot IPs (commonly 192.168.43.x, 172.20.10.x), Wi-Fi or standard LAN
    for item in all_ips:
        ip = item["ip"]
        if ip.startswith("192.168.43.") or ip.startswith("172.20.10."):
            return ip
    for item in all_ips:
        ip = item["ip"]
        if ip != "127.0.0.1":
            return ip
    return "127.0.0.1"


class NetworkServer:
    def __init__(self, apo_manager, loopback_analyzer, static_dir=None):
        self.apo_manager = apo_manager
        self.loopback_analyzer = loopback_analyzer
        self.static_dir = static_dir
        self.all_interfaces = get_all_local_ips()
        self.local_ip = get_primary_ip()
        self.ws_clients = set()
        self.app = web.Application()
        self.runner = None
        self.site = None
        self.loop = None
        self.udp_task = None
        
        self._setup_routes()

    def _setup_routes(self):
        self.app.router.add_get("/api/state", self.handle_get_state)
        self.app.router.add_get("/api/info", self.handle_get_info)
        self.app.router.add_get("/download/app.apk", self.handle_download_apk)
        self.app.router.add_get("/ws", self.handle_websocket)

        if self.static_dir and os.path.exists(self.static_dir):
            self.app.router.add_get("/", self.handle_index)
            self.app.router.add_static("/", self.static_dir, show_index=True, follow_symlinks=True)

    async def handle_download_apk(self, request):
        apk_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "EqualizerAPO_Remote.apk")
        if not os.path.exists(apk_path):
            alt_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apo_flutter", "build", "app", "outputs", "flutter-apk", "app-release.apk")
            if os.path.exists(alt_path):
                apk_path = alt_path
        if os.path.exists(apk_path):
            return web.FileResponse(apk_path, headers={
                "Content-Disposition": 'attachment; filename="EqualizerAPO_Remote.apk"'
            })
        return web.Response(text="APK aun no compilado o no encontrado.", status=404)

    async def handle_index(self, request):
        index_path = os.path.join(self.static_dir, "index.html")
        return web.FileResponse(index_path)

    async def handle_get_info(self, request):
        self.all_interfaces = get_all_local_ips()
        self.local_ip = get_primary_ip()
        return web.json_response({
            "status": "online",
            "device": self.loopback_analyzer.device_name,
            "primary_ip": self.local_ip,
            "all_ips": [item["ip"] for item in self.all_interfaces],
            "interfaces": self.all_interfaces,
            "port": HTTP_PORT,
            "ws_url": f"ws://{self.local_ip}:{HTTP_PORT}/ws",
            "http_url": f"http://{self.local_ip}:{HTTP_PORT}"
        })

    async def handle_get_state(self, request):
        return web.json_response(self.apo_manager.get_state())

    async def handle_websocket(self, request):
        ws = web.WebSocketResponse(heartbeat=15.0)
        await ws.prepare(request)
        
        self.ws_clients.add(ws)
        logger.info(f"Mobile client connected! Total clients: {len(self.ws_clients)}")

        try:
            init_payload = json.dumps({
                "type": "init",
                "state": self.apo_manager.get_state(),
                "device": self.loopback_analyzer.device_name
            })
            await ws.send_str(init_payload)

            async for msg in ws:
                if msg.type == web.WSMsgType.TEXT:
                    try:
                        data = json.loads(msg.data)
                        await self._process_client_action(data, ws)
                    except json.JSONDecodeError:
                        pass
                elif msg.type == web.WSMsgType.ERROR:
                    logger.warning(f"WebSocket error: {ws.exception()}")
        finally:
            self.ws_clients.discard(ws)
            logger.info(f"Client disconnected. Remaining: {len(self.ws_clients)}")

        return ws

    async def _process_client_action(self, data, sender_ws):
        action = data.get("action")
        changed = False

        if action == "set_preamp":
            val = float(data.get("gain", data.get("value", 0.0)))
            self.apo_manager.set_preamp(val)
            changed = True
        elif action == "set_band":
            freq = float(data.get("freq"))
            gain = float(data.get("gain"))
            self.apo_manager.set_band(freq, gain)
            changed = True
        elif action == "set_all_bands":
            bands = data.get("bands", {})
            self.apo_manager.set_all_bands(bands)
            changed = True
        elif action == "apply_preset":
            name = str(data.get("name"))
            self.apo_manager.apply_preset(name)
            changed = True
        elif action == "save_preset":
            name = str(data.get("name", "Mi Preset"))
            self.apo_manager.save_preset(name)
            changed = True
        elif action == "delete_preset":
            name = str(data.get("name", ""))
            self.apo_manager.delete_preset(name)
            changed = True
        elif action == "set_bypass":
            state = bool(data.get("state"))
            self.apo_manager.set_bypass(state)
            changed = True
        elif action == "set_parametric_bands":
            bands = data.get("bands", [])
            self.apo_manager.set_parametric_bands(bands)
            changed = True

        if changed:
            update_payload = json.dumps({
                "type": "state_update",
                "state": self.apo_manager.get_state()
            })
            await self.broadcast_message(update_payload)

    async def broadcast_message(self, message_str):
        if not self.ws_clients:
            return
        tasks = []
        for ws in list(self.ws_clients):
            if not ws.closed:
                tasks.append(ws.send_str(message_str))
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    def on_spectrum_update(self, spectrum_data):
        if not self.ws_clients or not self.loop or self.loop.is_closed():
            return

        payload = json.dumps(spectrum_data)
        asyncio.run_coroutine_threadsafe(self.broadcast_message(payload), self.loop)

    async def _udp_beacon_loop(self):
        """Broadcasts presence over UDP across all interfaces (LAN, Wi-Fi, Phone Hotspot)."""
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.setblocking(False)

        while True:
            try:
                self.all_interfaces = get_all_local_ips()
                self.local_ip = get_primary_ip()

                beacon_dict = {
                    "service": "apo_remote",
                    "name": "Equalizer APO PC Bridge",
                    "primary_ip": self.local_ip,
                    "all_ips": [item["ip"] for item in self.all_interfaces],
                    "port": HTTP_PORT,
                    "ws_url": f"ws://{self.local_ip}:{HTTP_PORT}/ws",
                    "http_url": f"http://{self.local_ip}:{HTTP_PORT}"
                }
                beacon_bytes = json.dumps(beacon_dict).encode("utf-8")

                # Send to global broadcast
                try:
                    sock.sendto(beacon_bytes, ("255.255.255.255", UDP_BEACON_PORT))
                except Exception:
                    pass

                # Send to interface-specific broadcast addresses
                for iface in self.all_interfaces:
                    bcast = iface.get("broadcast")
                    if bcast and bcast != "255.255.255.255":
                        try:
                            sock.sendto(beacon_bytes, (bcast, UDP_BEACON_PORT))
                        except Exception:
                            pass
            except Exception:
                pass

            await asyncio.sleep(1.0)

    async def start(self):
        self.loop = asyncio.get_running_loop()
        self.runner = web.AppRunner(self.app)
        await self.runner.setup()
        self.site = web.TCPSite(self.runner, "0.0.0.0", HTTP_PORT)
        await self.site.start()
        
        self.udp_task = asyncio.create_task(self._udp_beacon_loop())
        logger.info(f"APO Server listening on all interfaces at port {HTTP_PORT}")
        logger.info(f"Primary URL: http://{self.local_ip}:{HTTP_PORT}")

    async def stop(self):
        if self.udp_task:
            self.udp_task.cancel()
        for ws in list(self.ws_clients):
            await ws.close()
        if self.runner:
            await self.runner.cleanup()
        logger.info("Server stopped.")
