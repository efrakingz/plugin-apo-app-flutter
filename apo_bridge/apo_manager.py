"""
APO Manager: Manages Equalizer APO configuration files on Windows.
- 15-band default ISO graphic EQ with all genre presets
- Microphone Noise Gate support with threshold and instant toggle
- Atomic file writing to C:\\Program Files\\EqualizerAPO\\config\\remote_eq.txt
"""

import os
import shutil
import logging
import threading

logger = logging.getLogger("APO_Manager")

APO_CONFIG_DIR = r"C:\Program Files\EqualizerAPO\config"
MAIN_CONFIG_FILE = os.path.join(APO_CONFIG_DIR, "config.txt")
REMOTE_EQ_FILE = os.path.join(APO_CONFIG_DIR, "remote_eq.txt")
BACKUP_CONFIG_FILE = os.path.join(APO_CONFIG_DIR, "config.txt.bak")
CUSTOM_PRESETS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "custom_presets.json")

# Standard 15 ISO frequency bands (Default)
BANDS_15 = [25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000]

# Presets specifically tuned for the 15-band equalizer
PRESETS_15 = {
    "Plano / Reset": {f: 0.0 for f in BANDS_15},
    "Bass Boost Extremo": {
        25: 8.5, 40: 8.0, 63: 6.5, 100: 4.5, 160: 2.0, 250: 0.5,
        400: 0.0, 630: 0.0, 1000: 0.0, 1600: 0.0, 2500: 0.5, 4000: 1.0,
        6300: 1.5, 10000: 2.0, 16000: 1.5
    },
    "Bass Punch (Graves Secos)": {
        25: 3.0, 40: 5.5, 63: 6.5, 100: 5.0, 160: 2.5, 250: 0.5,
        400: -0.5, 630: -1.0, 1000: 0.0, 1600: 1.0, 2500: 1.5, 4000: 2.0,
        6300: 2.5, 10000: 2.0, 16000: 1.5
    },
    "Claridad Vocal (Podcast / Streaming)": {
        25: -8.0, 40: -5.0, 63: -2.0, 100: 0.0, 160: -1.0, 250: -1.0,
        400: 0.5, 630: 1.5, 1000: 2.5, 1600: 3.5, 2500: 4.0, 4000: 3.5,
        6300: 2.5, 10000: 2.0, 16000: 1.0
    },
    "Rock & Metal": {
        25: 4.5, 40: 4.0, 63: 3.0, 100: 1.5, 160: -0.5, 250: -1.5,
        400: -1.0, 630: 0.5, 1000: 1.5, 1600: 2.5, 2500: 3.5, 4000: 4.0,
        6300: 3.5, 10000: 4.0, 16000: 3.5
    },
    "Electrónica & Club (EDM)": {
        25: 6.5, 40: 6.0, 63: 5.0, 100: 2.5, 160: 0.5, 250: 0.0,
        400: 0.5, 630: 1.0, 1000: 1.5, 1600: 2.0, 2500: 3.0, 4000: 4.0,
        6300: 4.5, 10000: 5.0, 16000: 4.5
    },
    "Hip Hop & Trap (808 Sub)": {
        25: 7.5, 40: 7.5, 63: 6.0, 100: 3.5, 160: 1.0, 250: 0.0,
        400: -0.5, 630: 0.0, 1000: 1.0, 1600: 1.5, 2500: 2.5, 4000: 3.0,
        6300: 3.5, 10000: 4.0, 16000: 3.5
    },
    "Pop Brillante (Airy & Crisp)": {
        25: 2.5, 40: 3.0, 63: 2.5, 100: 1.5, 160: 0.0, 250: -0.5,
        400: 0.0, 630: 1.0, 1000: 2.0, 1600: 2.5, 2500: 3.0, 4000: 3.5,
        6300: 4.0, 10000: 4.5, 16000: 4.0
    },
    "Sonido Cálido (Warm Vintage)": {
        25: 3.0, 40: 3.5, 63: 3.5, 100: 2.5, 160: 2.0, 250: 1.5,
        400: 1.0, 630: 0.5, 1000: 0.0, 1600: -0.5, 2500: -1.0, 4000: -1.5,
        6300: -2.0, 10000: -3.0, 16000: -4.0
    },
    "Acústico & En Vivo": {
        25: 1.0, 40: 1.5, 63: 1.5, 100: 1.0, 160: 0.5, 250: 0.0,
        400: 0.5, 630: 1.0, 1000: 1.5, 1600: 2.0, 2500: 2.5, 4000: 2.5,
        6300: 2.5, 10000: 2.5, 16000: 2.0
    },
    "Gaming (Pasos y Audio Espacial)": {
        25: -3.0, 40: -1.5, 63: 0.0, 100: 1.0, 160: 2.5, 250: 2.0,
        400: 1.5, 630: 2.0, 1000: 3.0, 1600: 4.0, 2500: 4.5, 4000: 5.0,
        6300: 4.0, 10000: 3.0, 16000: 2.0
    },
    "Películas & Cine (Diálogos + FX)": {
        25: 5.0, 40: 4.5, 63: 3.5, 100: 1.5, 160: 0.0, 250: -1.0,
        400: 0.5, 630: 1.5, 1000: 2.5, 1600: 3.0, 2500: 2.5, 4000: 2.0,
        6300: 2.5, 10000: 3.5, 16000: 3.0
    },
    "Sonrisa Clásica (V-Shape)": {
        25: 6.0, 40: 5.0, 63: 4.0, 100: 2.5, 160: 0.5, 250: -1.0,
        400: -2.0, 630: -2.0, 1000: -1.5, 1600: 0.0, 2500: 1.5, 4000: 3.0,
        6300: 4.5, 10000: 5.5, 16000: 6.0
    },
    "De-Esser (Anti-Sibilancia)": {
        25: 0.0, 40: 0.0, 63: 0.0, 100: 0.0, 160: 0.0, 250: 0.0,
        400: 0.0, 630: 0.0, 1000: 0.0, 1600: 0.0, 2500: -1.0, 4000: -2.5,
        6300: -6.0, 10000: -5.0, 16000: -2.0
    },
    "Realce de Agudos (Air Boost)": {
        25: 0.0, 40: 0.0, 63: 0.0, 100: 0.0, 160: 0.0, 250: 0.0,
        400: 0.0, 630: 0.0, 1000: 0.5, 1600: 1.0, 2500: 2.0, 4000: 3.5,
        6300: 5.0, 10000: 6.5, 16000: 7.0
    },
    "Medios Cálidos (Guitarras / Acordes)": {
        25: -1.0, 40: 0.0, 63: 0.5, 100: 1.0, 160: 2.0, 250: 3.0,
        400: 3.5, 630: 4.0, 1000: 3.5, 1600: 2.5, 2500: 1.5, 4000: 0.5,
        6300: 0.0, 10000: -0.5, 16000: -1.0
    }
}


class APOManager:
    def __init__(self):
        self._write_lock = threading.Lock()
        self.preamp = 0.0
        self.bypass = False
        self.current_bands = {freq: 0.0 for freq in BANDS_15}
        self.active_preset = "Plano / Reset"
        

        self._ensure_setup()
        self.custom_presets = self._load_custom_presets()
        self._load_current_state()

    def _ensure_setup(self):
        """Ensures remote_eq.txt exists and is included in config.txt."""
        if not os.path.exists(APO_CONFIG_DIR):
            logger.warning(f"Equalizer APO directory not found at {APO_CONFIG_DIR}")
            return

        if os.path.exists(MAIN_CONFIG_FILE) and not os.path.exists(BACKUP_CONFIG_FILE):
            try:
                shutil.copy2(MAIN_CONFIG_FILE, BACKUP_CONFIG_FILE)
                logger.info(f"Created backup of main config at {BACKUP_CONFIG_FILE}")
            except Exception as e:
                logger.error(f"Failed to create config backup: {e}")

        if os.path.exists(MAIN_CONFIG_FILE):
            try:
                with open(MAIN_CONFIG_FILE, "r", encoding="utf-8", errors="ignore") as f:
                    lines = f.readlines()

                needs_write = False
                has_include = False
                new_lines = []

                for line in lines:
                    stripped = line.strip()
                    if "remote_eq.txt" in stripped:
                        has_include = True
                        if stripped.startswith("#"):
                            new_lines.append("Include: remote_eq.txt\n")
                            needs_write = True
                        else:
                            new_lines.append(line)
                    elif stripped.startswith("Include: example.txt"):
                        new_lines.append("# Include: example.txt\n")
                        needs_write = True
                    else:
                        new_lines.append(line)

                if not has_include:
                    new_lines.append("\n# Injected by APO Remote Bridge\nInclude: remote_eq.txt\n")
                    needs_write = True

                if needs_write:
                    with open(MAIN_CONFIG_FILE, "w", encoding="utf-8") as f:
                        f.writelines(new_lines)
                    logger.info("Ensured active Include: remote_eq.txt in config.txt")
            except Exception as e:
                logger.error(f"Error checking/updating config.txt: {e}")

        if not os.path.exists(REMOTE_EQ_FILE):
            self.write_eq()

    def _load_current_state(self):
        """Loads state from remote_eq.txt if available."""
        if not os.path.exists(REMOTE_EQ_FILE):
            return

        try:
            with open(REMOTE_EQ_FILE, "r", encoding="utf-8", errors="ignore") as f:
                lines = f.readlines()

            for line in lines:
                line = line.strip()
                if line.startswith("Preamp:"):
                    parts = line.split()
                    if len(parts) >= 2:
                        try:
                            self.preamp = float(parts[1])
                        except ValueError:
                            pass
                elif line.startswith("GraphicEQ:"):
                    data_part = line[len("GraphicEQ:"):].strip()
                    pairs = data_part.split(";")
                    for p in pairs:
                        p = p.strip()
                        if not p:
                            continue
                        tokens = p.split()
                        if len(tokens) >= 2:
                            try:
                                freq = float(tokens[0])
                                gain = float(tokens[1])
                                if freq in self.current_bands:
                                    self.current_bands[freq] = gain
                            except ValueError:
                                pass
        except Exception as e:
            logger.error(f"Failed to load state from remote_eq.txt: {e}")

    def write_eq(self):
        """Writes current settings to remote_eq.txt for Equalizer APO to hot-reload."""
        if not os.path.exists(APO_CONFIG_DIR):
            return False

        with self._write_lock:
            try:
                sorted_freqs = sorted(self.current_bands.keys())
                eq_items = []
                for f in sorted_freqs:
                    gain = 0.0 if self.bypass else self.current_bands[f]
                    freq_str = f"{f:.1f}" if (f % 1 != 0) else f"{int(f)}"
                    eq_items.append(f"{freq_str} {gain:.2f}")

                graphic_eq_line = "; ".join(eq_items)
                preamp_val = 0.0 if self.bypass else self.preamp

                # Build configuration file content
                content = (
                    f"# Equalizer APO Wireless Remote File\n"
                    f"# Real-Time Sync Engine\n"
                    f"Preamp: {preamp_val:.2f} dB\n"
                    f"GraphicEQ: {graphic_eq_line}\n"
                )

                # Retry up to 5 times (8ms intervals) if Windows audio engine momentarily holds read handle
                written = False
                for _ in range(5):
                    try:
                        with open(REMOTE_EQ_FILE, "w", encoding="utf-8") as f:
                            f.write(content)
                            f.flush()
                        written = True
                        break
                    except (PermissionError, OSError):
                        import time
                        time.sleep(0.008)

                if not written:
                    logger.warning("Could not write remote_eq.txt after 5 retries")
                    return False

                # Touch main config.txt timestamp to trigger Equalizer APO file watcher reload
                try:
                    if os.path.exists(MAIN_CONFIG_FILE):
                        os.utime(MAIN_CONFIG_FILE, None)
                except Exception:
                    pass

                return True
            except Exception as e:
                logger.error(f"Error writing to remote_eq.txt: {e}")
                return False

    def set_preamp(self, db: float):
        self.preamp = max(-20.0, min(20.0, float(db)))
        self.active_preset = "Personalizado"
        return self.write_eq()

    def set_band(self, freq: float, gain_db: float):
        gain = max(-20.0, min(20.0, float(gain_db)))
        self.current_bands[float(freq)] = gain
        self.active_preset = "Personalizado"
        return self.write_eq()

    def set_all_bands(self, bands_dict: dict):
        for f, g in bands_dict.items():
            freq = float(f)
            if freq in self.current_bands:
                self.current_bands[freq] = max(-20.0, min(20.0, float(g)))
        self.active_preset = "Personalizado"
        return self.write_eq()

    def set_parametric_bands(self, bands_list: list):
        """Replace all bands with a new set of {freq, gain} pairs (parametric EQ)."""
        if not bands_list:
            return False
        new_bands = {}
        for item in bands_list:
            try:
                freq = float(item.get("freq", 0))
                gain = max(-20.0, min(20.0, float(item.get("gain", 0))))
                if freq > 0:
                    new_bands[freq] = gain
            except (ValueError, TypeError):
                pass
        if new_bands:
            self.current_bands = new_bands
            self.active_preset = "Personalizado"
            return self.write_eq()
        return False

    def _load_custom_presets(self):
        try:
            if os.path.exists(CUSTOM_PRESETS_FILE):
                import json
                with open(CUSTOM_PRESETS_FILE, "r", encoding="utf-8") as f:
                    return json.load(f)
        except Exception as e:
            logger.warning(f"Could not load custom presets: {e}")
        return {}

    def _save_custom_presets(self):
        try:
            import json
            with open(CUSTOM_PRESETS_FILE, "w", encoding="utf-8") as f:
                json.dump(self.custom_presets, f, indent=2, ensure_ascii=False)
        except Exception as e:
            logger.error(f"Could not save custom presets: {e}")

    def save_preset(self, preset_name: str):
        if not preset_name or not preset_name.strip():
            return False
        name = preset_name.strip()
        self.custom_presets[name] = {
            "preamp": self.preamp,
            "bands": {str(f): g for f, g in self.current_bands.items()}
        }
        self.active_preset = name
        self._save_custom_presets()
        logger.info(f"Custom preset '{name}' saved successfully!")
        return True

    def delete_preset(self, preset_name: str):
        if preset_name in self.custom_presets:
            del self.custom_presets[preset_name]
            self._save_custom_presets()
            logger.info(f"Custom preset '{preset_name}' deleted.")
            return True
        return False

    def apply_preset(self, preset_name: str):
        if preset_name in self.custom_presets:
            p = self.custom_presets[preset_name]
            if "preamp" in p:
                self.preamp = float(p["preamp"])
            if "bands" in p:
                self.current_bands = {float(f): float(g) for f, g in p["bands"].items()}
            self.active_preset = preset_name
            return self.write_eq()
        elif preset_name in PRESETS_15:
            preset = PRESETS_15[preset_name]
            for f, g in preset.items():
                self.current_bands[float(f)] = float(g)
            self.active_preset = preset_name
            return self.write_eq()
        return False

    def set_bypass(self, bypass_state: bool):
        self.bypass = bool(bypass_state)
        return self.write_eq()

    def get_state(self):
        return {
            "preamp": self.preamp,
            "bypass": self.bypass,
            "bands": {f"{f:g}": round(g, 2) for f, g in sorted(self.current_bands.items())},
            "active_preset": self.active_preset,
            "presets": list(self.custom_presets.keys()) + list(PRESETS_15.keys()),
            "custom_presets": list(self.custom_presets.keys()),
            "frequencies": [f"{f:g}" for f in BANDS_15]
        }
