// Equalizer APO Remote: 15-Band Engine, 120 FPS RTA & Mic Noise Gate

const state = {
  connected: false,
  device: "Detectando...",
  preamp: 0.0,
  bypass: false,
  activePreset: "Plano / Reset",
  presets: [],
  bands: {},
  frequencies: ["25", "40", "63", "100", "160", "250", "400", "630", "1000", "1600", "2500", "4000", "6300", "10000", "16000"],
  gate: {
    enabled: false,
    threshold_db: -42.0,
    state: "CLOSED",
    mic_db: -80.0
  },
  spectrum: new Array(64).fill(0),
  spectrumPeaks: new Array(64).fill(0)
};

let ws = null;
let reconnectTimer = null;
let lastFpsTime = performance.now();
let framesThisSecond = 0;
let currentFps = 120;
let debounceTimers = {};

// DOM Elements
const statusBadge = document.getElementById("status-badge");
const statusText = document.getElementById("status-text");
const deviceLabel = document.getElementById("device-label");
const btnBypass = document.getElementById("btn-bypass");

const preampSlider = document.getElementById("preamp-slider");
const preampVal = document.getElementById("preamp-val");
const preampReset = document.getElementById("preamp-reset");

const btnGateToggle = document.getElementById("btn-gate-toggle");
const gateToggleLabel = document.getElementById("gate-toggle-label");
const gateIndicator = document.getElementById("gate-indicator");
const gateStateText = document.getElementById("gate-state-text");
const gateThreshSlider = document.getElementById("gate-thresh-slider");
const gateThreshVal = document.getElementById("gate-thresh-val");
const micLevelFill = document.getElementById("mic-level-fill");
const micDbReadout = document.getElementById("mic-db-readout");
const gateThreshMarker = document.getElementById("gate-thresh-marker");

const presetsContainer = document.getElementById("presets-container");
const fadersRack = document.getElementById("faders-rack");
const btnFlat = document.getElementById("btn-flat");

const canvas = document.getElementById("rta-canvas");
const ctx = canvas.getContext("2d");
const fpsCounter = document.getElementById("fps-counter");
const levelIndicator = document.getElementById("level-indicator");

// --- WebSocket Connection ---
function connectWebSocket() {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  const wsUrl = `${protocol}//${window.location.host}/ws`;

  updateStatus("connecting", "Conectando...");
  ws = new WebSocket(wsUrl);

  ws.onopen = () => {
    updateStatus("connected", "En línea");
    if (reconnectTimer) {
      clearInterval(reconnectTimer);
      reconnectTimer = null;
    }
  };

  ws.onmessage = (event) => {
    try {
      const data = JSON.parse(event.data);
      if (data.type === "spectrum") {
        state.spectrum = data.bands || state.spectrum;
        state.spectrumPeaks = data.peaks || state.spectrumPeaks;
        if (data.rms !== undefined) {
          levelIndicator.textContent = `${data.rms.toFixed(2)} RMS`;
        }
        if (data.device && state.device !== data.device) {
          state.device = data.device;
          deviceLabel.textContent = data.device;
        }
        if (data.gate) {
          updateGateUIFromStream(data.gate);
        }
      } else if (data.type === "init" || data.type === "state_update") {
        applyState(data.state, data.device);
      }
    } catch (e) {
      console.error("WS Parse error", e);
    }
  };

  ws.onclose = () => {
    updateStatus("disconnected", "Desconectado");
    if (!reconnectTimer) {
      reconnectTimer = setInterval(connectWebSocket, 2000);
    }
  };

  ws.onerror = () => {
    ws.close();
  };
}

function updateStatus(className, text) {
  statusBadge.className = `status-badge ${className}`;
  statusText.textContent = text;
}

function sendAction(action, payload = {}) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ action, ...payload }));
  }
}

// --- State Management ---
function applyState(newState, deviceName) {
  if (!newState) return;
  state.preamp = newState.preamp;
  state.bypass = newState.bypass;
  state.bands = newState.bands || state.bands;
  state.presets = newState.presets || state.presets;
  state.activePreset = newState.active_preset || state.activePreset;
  if (newState.frequencies) {
    state.frequencies = newState.frequencies;
  }
  if (newState.gate) {
    state.gate.enabled = newState.gate.enabled;
    state.gate.threshold_db = newState.gate.threshold_db;
    state.gate.state = newState.gate.state;
    updateGateUI();
  }
  if (deviceName) {
    state.device = deviceName;
    deviceLabel.textContent = deviceName;
  }

  // Update Preamp
  preampSlider.value = state.preamp;
  preampVal.textContent = `${state.preamp > 0 ? "+" : ""}${state.preamp.toFixed(1)} dB`;

  // Update Bypass
  btnBypass.classList.toggle("active", state.bypass);

  // Update Presets
  renderPresets();

  // Update 15 Faders
  render15Faders();
}

// --- Noise Gate UI ---
function updateGateUI() {
  btnGateToggle.classList.toggle("active", state.gate.enabled);
  gateToggleLabel.textContent = state.gate.enabled ? "DESACTIVAR" : "ACTIVAR";

  gateThreshSlider.value = state.gate.threshold_db;
  gateThreshVal.textContent = `${state.gate.threshold_db.toFixed(1)} dB`;

  // Position threshold notch in meter (from -60 to -10 dB)
  const threshRatio = Math.max(0, Math.min(1, (state.gate.threshold_db + 60) / 50));
  gateThreshMarker.style.left = `${threshRatio * 100}%`;

  if (!state.gate.enabled) {
    gateIndicator.className = "gate-indicator-pill off";
    gateStateText.textContent = "DESACTIVADA";
  } else if (state.gate.state === "OPEN") {
    gateIndicator.className = "gate-indicator-pill open";
    gateStateText.textContent = "ABIERTA (VOZ)";
  } else {
    gateIndicator.className = "gate-indicator-pill closed";
    gateStateText.textContent = "CERRADA (MUTE)";
  }
}

function updateGateUIFromStream(gateInfo) {
  state.gate.state = gateInfo.state;
  state.gate.mic_db = gateInfo.mic_db;

  if (state.gate.enabled) {
    if (gateInfo.state === "OPEN") {
      gateIndicator.className = "gate-indicator-pill open";
      gateStateText.textContent = "ABIERTA (VOZ)";
    } else {
      gateIndicator.className = "gate-indicator-pill closed";
      gateStateText.textContent = "CERRADA (MUTE)";
    }
  }

  // Update meter bar fill
  const levelRatio = Math.max(0, Math.min(1, (gateInfo.mic_db + 60) / 50));
  micLevelFill.style.width = `${levelRatio * 100}%`;
  micDbReadout.textContent = `${gateInfo.mic_db.toFixed(0)} dB`;
}

btnGateToggle.addEventListener("click", () => {
  state.gate.enabled = !state.gate.enabled;
  updateGateUI();
  sendAction("set_gate_enabled", { enabled: state.gate.enabled });
});

gateThreshSlider.addEventListener("input", (e) => {
  const val = parseFloat(e.target.value);
  state.gate.threshold_db = val;
  gateThreshVal.textContent = `${val.toFixed(1)} dB`;

  const threshRatio = Math.max(0, Math.min(1, (val + 60) / 50));
  gateThreshMarker.style.left = `${threshRatio * 100}%`;

  clearTimeout(debounceTimers["gate_thresh"]);
  debounceTimers["gate_thresh"] = setTimeout(() => {
    sendAction("set_gate_threshold", { threshold: val });
  }, 40);
});

// --- Presets UI ---
function renderPresets() {
  presetsContainer.innerHTML = "";
  state.presets.forEach((preset) => {
    const chip = document.createElement("div");
    chip.className = `preset-chip ${preset === state.activePreset ? "active" : ""}`;
    chip.textContent = preset;
    chip.onclick = () => {
      sendAction("apply_preset", { name: preset });
    };
    presetsContainer.appendChild(chip);
  });
}

// --- 15-Band Faders Rack UI ---
function formatFreqLabel(freqStr) {
  const f = parseFloat(freqStr);
  if (f >= 1000) {
    const k = f / 1000;
    return `${k % 1 === 0 ? k.toFixed(0) : k.toFixed(1)}k`;
  }
  return `${f % 1 === 0 ? f.toFixed(0) : f.toFixed(1)}`;
}

function render15Faders() {
  fadersRack.innerHTML = "";

  state.frequencies.forEach((freqStr) => {
    const freq = parseFloat(freqStr);
    const gain = state.bands[freqStr] !== undefined ? state.bands[freqStr] : 0.0;

    const col = document.createElement("div");
    col.className = "fader-col";

    const valLabel = document.createElement("div");
    valLabel.className = "fader-gain-val";
    valLabel.textContent = `${gain > 0 ? "+" : ""}${gain.toFixed(1)}`;

    const slot = document.createElement("div");
    slot.className = "fader-slot";

    const centerLine = document.createElement("div");
    centerLine.className = "fader-center-line";

    const fill = document.createElement("div");
    fill.className = "fader-fill";

    const thumb = document.createElement("div");
    thumb.className = "fader-thumb";

    slot.appendChild(centerLine);
    slot.appendChild(fill);
    slot.appendChild(thumb);

    const freqLabel = document.createElement("div");
    freqLabel.className = "fader-freq-label";
    freqLabel.textContent = formatFreqLabel(freqStr);

    col.appendChild(valLabel);
    col.appendChild(slot);
    col.appendChild(freqLabel);

    updateFaderVisuals(slot, fill, thumb, valLabel, gain);
    setupFaderInteraction(slot, freq, fill, thumb, valLabel);

    fadersRack.appendChild(col);
  });
}

function updateFaderVisuals(slot, fill, thumb, valLabel, gain) {
  const slotHeight = 170;
  const thumbHeight = 28;
  const halfTravel = (slotHeight - thumbHeight) / 2;

  const ratio = Math.max(-1, Math.min(1, gain / 20));
  const topPos = halfTravel - ratio * halfTravel;

  thumb.style.top = `${topPos}px`;

  if (ratio >= 0) {
    fill.style.top = `${topPos + thumbHeight / 2}px`;
    fill.style.bottom = `${halfTravel + thumbHeight / 2}px`;
    fill.style.background = "var(--accent-cyan)";
  } else {
    fill.style.top = `${halfTravel + thumbHeight / 2}px`;
    fill.style.bottom = `${slotHeight - (topPos + thumbHeight / 2)}px`;
    fill.style.background = "var(--accent-magenta)";
  }

  valLabel.textContent = `${gain > 0 ? "+" : ""}${gain.toFixed(1)}`;
  valLabel.style.color = gain > 0 ? "var(--accent-cyan)" : gain < 0 ? "var(--accent-magenta)" : "var(--text-dim)";
}

function setupFaderInteraction(slot, freq, fill, thumb, valLabel) {
  let isDragging = false;

  const handlePointer = (clientY) => {
    const rect = slot.getBoundingClientRect();
    const slotHeight = rect.height;
    const thumbHeight = 28;
    const halfTravel = (slotHeight - thumbHeight) / 2;

    const relY = Math.max(0, Math.min(slotHeight, clientY - rect.top));
    const thumbCenterY = relY - thumbHeight / 2;
    const fromCenter = halfTravel - thumbCenterY;
    let gain = (fromCenter / halfTravel) * 20;
    gain = Math.max(-20, Math.min(20, Math.round(gain * 2) / 2)); // 0.5 dB steps

    state.bands[freq.toString()] = gain;
    updateFaderVisuals(slot, fill, thumb, valLabel, gain);

    clearTimeout(debounceTimers[freq]);
    debounceTimers[freq] = setTimeout(() => {
      sendAction("set_band", { freq, gain });
    }, 35);
  };

  slot.addEventListener("pointerdown", (e) => {
    isDragging = true;
    slot.setPointerCapture(e.pointerId);
    handlePointer(e.clientY);
  });

  slot.addEventListener("pointermove", (e) => {
    if (isDragging) {
      handlePointer(e.clientY);
    }
  });

  const endDrag = (e) => {
    if (isDragging) {
      isDragging = false;
      try {
        slot.releasePointerCapture(e.pointerId);
      } catch (_) {}
    }
  };

  slot.addEventListener("pointerup", endDrag);
  slot.addEventListener("pointercancel", endDrag);

  slot.addEventListener("dblclick", () => {
    state.bands[freq.toString()] = 0.0;
    updateFaderVisuals(slot, fill, thumb, valLabel, 0.0);
    sendAction("set_band", { freq, gain: 0.0 });
  });
}

// --- Preamp Slider Event ---
preampSlider.addEventListener("input", (e) => {
  const val = parseFloat(e.target.value);
  state.preamp = val;
  preampVal.textContent = `${val > 0 ? "+" : ""}${val.toFixed(1)} dB`;

  clearTimeout(debounceTimers["preamp"]);
  debounceTimers["preamp"] = setTimeout(() => {
    sendAction("set_preamp", { value: val });
  }, 40);
});

preampReset.addEventListener("click", () => {
  preampSlider.value = 0;
  state.preamp = 0;
  preampVal.textContent = "0.0 dB";
  sendAction("set_preamp", { value: 0 });
});

// --- Bypass Event ---
btnBypass.addEventListener("click", () => {
  state.bypass = !state.bypass;
  btnBypass.classList.toggle("active", state.bypass);
  sendAction("set_bypass", { state: state.bypass });
});

// --- Reset Flat EQ ---
btnFlat.addEventListener("click", () => {
  sendAction("apply_preset", { name: "Plano / Reset" });
});

// --- 120 FPS High-Performance Canvas RTA Visualizer ---
function resizeCanvas() {
  const rect = canvas.parentElement.getBoundingClientRect();
  canvas.width = rect.width * (window.devicePixelRatio || 1);
  canvas.height = rect.height * (window.devicePixelRatio || 1);
  ctx.scale(window.devicePixelRatio || 1, window.devicePixelRatio || 1);
}

window.addEventListener("resize", resizeCanvas);
setTimeout(resizeCanvas, 100);

function draw120FPS() {
  const w = canvas.parentElement.clientWidth;
  const h = canvas.parentElement.clientHeight;

  ctx.clearRect(0, 0, w, h);

  const numBands = state.spectrum.length;
  if (numBands === 0) {
    requestAnimationFrame(draw120FPS);
    return;
  }

  // Subtle grid lines
  ctx.strokeStyle = "rgba(255, 255, 255, 0.04)";
  ctx.lineWidth = 1;
  for (let y = h * 0.25; y < h; y += h * 0.25) {
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(w, y);
    ctx.stroke();
  }

  const barGap = 2;
  const barWidth = Math.max(2, (w - (numBands - 1) * barGap) / numBands);

  // Neon Gradient
  const gradient = ctx.createLinearGradient(0, 0, 0, h);
  gradient.addColorStop(0.0, "#ff007f"); // High peak
  gradient.addColorStop(0.3, "#00f0ff"); // Mid presence
  gradient.addColorStop(0.8, "#00ff9d"); // Bass punch
  gradient.addColorStop(1.0, "rgba(0, 255, 157, 0.15)");

  for (let i = 0; i < numBands; i++) {
    const val = state.spectrum[i] / 100.0;
    const peak = state.spectrumPeaks[i] / 100.0;

    const barHeight = Math.max(2, val * (h - 10));
    const x = i * (barWidth + barGap);
    const y = h - barHeight;

    ctx.fillStyle = gradient;
    ctx.beginPath();
    ctx.roundRect(x, y, barWidth, barHeight, [2, 2, 0, 0]);
    ctx.fill();

    if (peak > 0.04) {
      const peakY = h - Math.max(2, peak * (h - 10));
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(x, peakY, barWidth, 1.5);
    }
  }

  // Real-Time 120 FPS Benchmark
  framesThisSecond++;
  const now = performance.now();
  if (now - lastFpsTime >= 500) {
    currentFps = Math.round((framesThisSecond * 1000) / (now - lastFpsTime));
    fpsCounter.textContent = `${currentFps} FPS`;
    framesThisSecond = 0;
    lastFpsTime = now;
  }

  requestAnimationFrame(draw120FPS);
}

// --- Tabs Switching ---
const navButtons = document.querySelectorAll(".nav-btn");
const tabScreens = document.querySelectorAll(".tab-screen");

navButtons.forEach((btn) => {
  btn.addEventListener("click", () => {
    const targetTabId = btn.getAttribute("data-tab");
    navButtons.forEach((b) => b.classList.remove("active"));
    tabScreens.forEach((s) => s.classList.remove("active"));

    btn.classList.add("active");
    const targetScreen = document.getElementById(targetTabId);
    if (targetScreen) {
      targetScreen.classList.add("active");
    }
    if (targetTabId === "tab-eq") {
      resizeCanvas();
    }
  });
});

// Start 120 FPS animation and connect WebSocket
requestAnimationFrame(draw120FPS);
connectWebSocket();
