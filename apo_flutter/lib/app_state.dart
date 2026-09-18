import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum EqBandMode {
  bands6('6 BANDAS (BUS)', 6),
  bands10('10 BANDAS', 10),
  bands15('15 BANDAS', 15);

  final String label;
  final int count;
  const EqBandMode(this.label, this.count);
}

/// A single parametric EQ band with a moveable frequency and gain.
class EqBand {
  double frequency; // Hz (20–20000)
  double gain;      // dB (±15)
  String? busLabel; // Optional bus descriptor (SUB, BASS, etc.)

  EqBand({required this.frequency, required this.gain, this.busLabel});

  EqBand copyWith({double? frequency, double? gain, String? busLabel}) =>
      EqBand(
        frequency: frequency ?? this.frequency,
        gain: gain ?? this.gain,
        busLabel: busLabel ?? this.busLabel,
      );

  Map<String, dynamic> toJson() => {'freq': frequency, 'gain': gain};
}

/// Central state manager for APO Remote Studio.
class AppState extends ChangeNotifier {
  // ── Connection ──────────────────────────────────────────────────────
  String hostIp = '192.168.1.9';
  int port = 9876;
  bool isConnected = false;
  bool isSearching = true;
  String connectionLog = 'Iniciando búsqueda...';

  WebSocketChannel? _channel;
  RawDatagramSocket? _udpSocket;
  Timer? _discoveryTimer;
  Timer? _sendDebounce;

  // ── Audio / APO State ───────────────────────────────────────────────
  String deviceName = 'Sin dispositivo';
  double preamp = 0.0;
  bool bypass = false;

  // Mode defaults
  static const List<(double, String)> def6 = [
    (40.0, 'SUB'),
    (120.0, 'GRAVES'),
    (500.0, 'M-BAJ'),
    (1800.0, 'M-ALT'),
    (6000.0, 'BRILLO'),
    (15000.0, 'AIRE'),
  ];
  static const List<double> def10 = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
  static const List<double> def15 = [25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 10000, 16000];

  EqBandMode bandMode = EqBandMode.bands6;

  // Parametric EQ bands (starts with 6 broad musical buses by default for ease of touch)
  List<EqBand> eqBands = def6.map((e) => EqBand(frequency: e.$1, gain: 0.0, busLabel: e.$2)).toList();


  // ── Spectrum ────────────────────────────────────────────────────────
  List<int> spectrum = List.filled(64, 0);
  List<int> spectrumPeaks = List.filled(64, 0);
  int fps = 0;
  int _frameCount = 0;
  DateTime _lastFpsCheck = DateTime.now();

  AppState() {
    _init();
  }

  // ── Init ─────────────────────────────────────────────────────────────
  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('last_host_ip');
      if (saved != null && saved.isNotEmpty) {
        hostIp = saved;
        _log('IP guardada: $hostIp');
      }
      final savedMode = prefs.getString('eq_band_mode');
      if (savedMode != null) {
        bandMode = EqBandMode.values.firstWhere(
          (m) => m.name == savedMode,
          orElse: () => EqBandMode.bands6,
        );
        _applyModeFrequencies();
      }
    } catch (_) {}

    _connectWs();
    _startUdpDiscovery();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!isConnected) _probeCandidates();
    });
  }

  void _log(String msg) {
    connectionLog = msg;
    notifyListeners();
  }

  Future<void> _saveIp(String ip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_host_ip', ip);
    } catch (_) {}
  }

  Future<void> _saveBandMode(String modeName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('eq_band_mode', modeName);
    } catch (_) {}
  }

  // ── UDP Discovery ─────────────────────────────────────────────────────
  void _startUdpDiscovery() async {
    try {
      _udpSocket?.close();
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 9877);
      _udpSocket!.broadcastEnabled = true;
      _log('Escuchando beacon UDP en :9877');

      _udpSocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _udpSocket?.receive();
        if (dg == null) return;
        try {
          final json = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
          if (json['service'] == 'apo_remote' && !isConnected) {
            final newIp = (json['primary_ip'] ?? json['ip']) as String?;
            if (newIp != null) {
              hostIp = newIp;
              port = (json['port'] as int?) ?? 9876;
              _log('Beacon → $newIp:$port');
              _saveIp(newIp);
              _connectWs();
            }
          }
        } catch (_) {}
      });
    } catch (e) {
      _log('UDP error: $e');
    }
  }

  void _probeCandidates() async {
    final candidates = [
      hostIp, '192.168.1.1', '192.168.1.9',
      '192.168.43.1', '192.168.43.2',
      '172.20.10.1', '172.20.10.2',
      '10.0.0.1', '10.0.0.2',
      '192.168.0.1', '192.168.0.10',
    ];
    for (final ip in candidates) {
      if (isConnected) return;
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(milliseconds: 350);
        final req = await client.getUrl(Uri.parse('http://$ip:$port/api/info'));
        final resp = await req.close();
        if (resp.statusCode == 200) {
          final body = await resp.transform(utf8.decoder).join();
          final data = jsonDecode(body) as Map<String, dynamic>;
          if (data['status'] == 'online') {
            hostIp = ip;
            _log('Encontrado en $ip');
            await _saveIp(ip);
            _connectWs();
            return;
          }
        }
      } catch (_) {}
    }
  }

  // ── WebSocket ─────────────────────────────────────────────────────────
  void connectTo(String ip, int p) {
    hostIp = ip;
    port = p;
    _log('Conectando a $ip:$p...');
    _connectWs();
  }

  void _connectWs() {
    _channel?.sink.close();
    try {
      _channel = WebSocketChannel.connect(Uri.parse('ws://$hostIp:$port/ws'));
      _channel!.stream.listen(
        (msg) {
          if (!isConnected) {
            isConnected = true;
            isSearching = false;
            _log('Conectado a $hostIp:$port');
            _saveIp(hostIp);
            notifyListeners();
          }
          _handleMessage(msg);
        },
        onDone: () {
          isConnected = false;
          isSearching = true;
          _log('Desconectado. Buscando...');
          notifyListeners();
        },
        onError: (_) {
          isConnected = false;
          isSearching = true;
          notifyListeners();
        },
      );
    } catch (e) {
      isConnected = false;
      isSearching = true;
      _log('Error: $e');
      notifyListeners();
    }
  }

  bool isUserInteracting = false;

  void startInteraction() {
    isUserInteracting = true;
  }

  void endInteraction() {
    isUserInteracting = false;
    _sendAllBands();
  }

  // ── Message Handler ───────────────────────────────────────────────────
  void _handleMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'spectrum') {
        _frameCount++;
        final now = DateTime.now();
        final diffMs = now.difference(_lastFpsCheck).inMilliseconds;
        bool shouldNotify = false;
        if (diffMs >= 500) {
          fps = ((_frameCount * 1000) / diffMs).round();
          _frameCount = 0;
          _lastFpsCheck = now;
          shouldNotify = true;
        }
        final b = data['bands'];
        final p = data['peaks'];
        if (b != null) spectrum = List<int>.from(b as List);
        if (p != null) spectrumPeaks = List<int>.from(p as List);
        if (data['device'] != null && deviceName != data['device']) {
          deviceName = data['device'] as String;
          shouldNotify = true;
        }
        if (shouldNotify) notifyListeners();
        return; // Do NOT call notifyListeners 120 times/sec — Flame renders directly from state.spectrum
      } else if (type == 'init' || type == 'state_update') {
        final s = data['state'] as Map<String, dynamic>?;
        if (s != null) {
          if (!isUserInteracting) {
            preamp = (s['preamp'] as num?)?.toDouble() ?? preamp;
            bypass = (s['bypass'] as bool?) ?? bypass;

            // Load bands from bridge (keyed by frequency string)
            final bMap = s['bands'] as Map<String, dynamic>?;
            if (bMap != null && bMap.isNotEmpty) {
              final incomingBands = <EqBand>[];
              bMap.forEach((k, v) {
                final f = double.tryParse(k);
                final g = (v as num?)?.toDouble() ?? 0.0;
                if (f != null) incomingBands.add(EqBand(frequency: f, gain: g));
              });
              incomingBands.sort((a, b) => a.frequency.compareTo(b.frequency));

              // Cleanly apply the curve across the symmetrically spaced frequencies of current bandMode
              _applyModeFrequencies(incomingBands);
            }
          }
        }
        if (data['device'] != null) deviceName = data['device'] as String;
        notifyListeners();
      }
    } catch (_) {}
  }

  // ── Commands ──────────────────────────────────────────────────────────
  void send(String action, Map<String, dynamic> payload) {
    if (!isConnected || _channel == null) return;
    _channel!.sink.add(jsonEncode({'action': action, ...payload}));
  }

  /// Move a parametric EQ band to a new frequency and gain.
  /// Debounced to avoid flooding the bridge.
  void moveBand(int index, double freq, double gain) {
    if (index < 0 || index >= eqBands.length) return;
    freq = freq.clamp(20.0, 20000.0);
    gain = gain.clamp(-15.0, 15.0);
    // Snap gain to 0 when very close
    if (gain.abs() < 0.2) gain = 0.0;
    eqBands[index] = EqBand(
      frequency: freq,
      gain: gain,
      busLabel: eqBands[index].busLabel,
    );
    notifyListeners();
    _debouncedSendBands();
  }

  /// Switch EQ mode between 6 buses, 10 bands, or 15 bands while preserving curve
  void setBandMode(EqBandMode mode) {
    if (bandMode == mode) return;
    bandMode = mode;
    _saveBandMode(mode.name);
    _applyModeFrequencies();
    notifyListeners();
    _sendAllBands();
  }

  void _applyModeFrequencies([List<EqBand>? source]) {
    final src = source ?? eqBands;
    switch (bandMode) {
      case EqBandMode.bands6:
        eqBands = def6.map((e) {
          final gain = _interpolateGainFromList(src, e.$1);
          return EqBand(frequency: e.$1, gain: gain, busLabel: e.$2);
        }).toList();
        break;
      case EqBandMode.bands10:
        eqBands = def10.map((f) {
          final gain = _interpolateGainFromList(src, f);
          return EqBand(frequency: f, gain: gain);
        }).toList();
        break;
      case EqBandMode.bands15:
        eqBands = def15.map((f) {
          final gain = _interpolateGainFromList(src, f);
          return EqBand(frequency: f, gain: gain);
        }).toList();
        break;
    }
  }

  double _interpolateGainFromList(List<EqBand> source, double targetFreq) {
    if (source.isEmpty) return 0.0;
    if (source.length == 1) return source.first.gain;
    final sorted = List<EqBand>.from(source)
      ..sort((a, b) => a.frequency.compareTo(b.frequency));
    if (targetFreq <= sorted.first.frequency) return sorted.first.gain;
    if (targetFreq >= sorted.last.frequency) return sorted.last.gain;

    for (int i = 0; i < sorted.length - 1; i++) {
      final f0 = sorted[i].frequency;
      final f1 = sorted[i + 1].frequency;
      if (targetFreq >= f0 && targetFreq <= f1) {
        final logF0 = math.log(f0);
        final logF1 = math.log(f1);
        final logTarget = math.log(targetFreq);
        final t = (logTarget - logF0) / (logF1 - logF0);
        return sorted[i].gain + t * (sorted[i + 1].gain - sorted[i].gain);
      }
    }
    return 0.0;
  }

  /// Calculates the combined musical curve for broad buses (sigma=0.85 octaves)
  double calculateBusGainAt(double freq) {
    if (eqBands.isEmpty) return 0.0;
    if (bandMode != EqBandMode.bands6) {
      return _interpolateGainFromList(eqBands, freq);
    }

    const sigma = 0.85; // Broad musical bandwidth (~1.2 octaves)
    double totalGain = 0.0;

    for (final b in eqBands) {
      if (b.gain.abs() < 0.02) continue;
      final octDiff = (math.log(freq) - math.log(b.frequency)) / math.ln2;
      double bell = math.exp(- (octDiff * octDiff) / (2.0 * sigma * sigma));

      // Sub-bass shelf extension for SUB
      if (b.frequency <= 45.0 && freq < b.frequency) {
        bell = 1.0;
      }
      // High-shelf extension for AIRE
      if (b.frequency >= 14000.0 && freq > b.frequency) {
        bell = 1.0;
      }

      totalGain += b.gain * bell;
    }

    return totalGain.clamp(-15.0, 15.0);
  }

  void _debouncedSendBands() {
    _sendDebounce?.cancel();
    _sendDebounce = Timer(const Duration(milliseconds: 25), _sendAllBands);
  }

  void _sendAllBands() {
    if (bandMode == EqBandMode.bands6) {
      // In 6-Band Bus Mode: evaluate the broad musical curve across 25 log-spaced points
      // so Equalizer APO applies a rich, pronounced bus EQ rather than narrow spikes!
      final evalBands = <Map<String, dynamic>>[];
      const numPoints = 25;
      const fMin = 20.0;
      const fMax = 20000.0;
      final logMin = math.log(fMin);
      final logMax = math.log(fMax);

      for (int i = 0; i < numPoints; i++) {
        final t = i / (numPoints - 1);
        final freq = math.exp(logMin + t * (logMax - logMin));
        final gain = calculateBusGainAt(freq);
        evalBands.add({
          'freq': double.parse(freq.toStringAsFixed(1)),
          'gain': double.parse(gain.toStringAsFixed(2)),
        });
      }
      send('set_parametric_bands', {'bands': evalBands});
    } else {
      final sorted = List<EqBand>.from(eqBands)
        ..sort((a, b) => a.frequency.compareTo(b.frequency));
      send('set_parametric_bands', {
        'bands': sorted.map((b) => b.toJson()).toList(),
      });
    }
  }

  Timer? _preampDebounce;
  void setPreamp(double gain) {
    preamp = gain.clamp(-15.0, 15.0);
    notifyListeners();
    _preampDebounce?.cancel();
    _preampDebounce = Timer(const Duration(milliseconds: 25), () {
      send('set_preamp', {'gain': preamp});
    });
  }

  void setBypass(bool state) {
    bypass = state;
    notifyListeners();
    send('set_bypass', {'state': state});
  }

  void resetEq() {
    for (final band in eqBands) {
      band.gain = 0.0;
    }
    preamp = 0.0;
    notifyListeners();
    _sendAllBands();
    send('set_preamp', {'gain': 0.0});
  }


  @override
  void dispose() {
    _preampDebounce?.cancel();
    _sendDebounce?.cancel();
    _discoveryTimer?.cancel();
    _udpSocket?.close();
    _channel?.sink.close();
    super.dispose();
  }
}
