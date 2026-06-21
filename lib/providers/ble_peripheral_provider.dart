import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/instrument.dart';

class BLEPeripheralProvider with ChangeNotifier {
  bool _isAdvertising = false;
  bool get isAdvertising => _isAdvertising;

  bool _isDarkTheme = true;
  bool get isDarkTheme => _isDarkTheme;

  void setTheme(bool dark) {
    if (_isDarkTheme != dark) {
      _isDarkTheme = dark;
      notifyListeners();
    }
  }

  List<Instrument> _instruments = [];
  List<Instrument> get instruments => _instruments;

  String? _connectedCentralId;
  String? get connectedCentralId => _connectedCentralId;

  VoidCallback? onSimulationEnd;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _beepPlayer = AudioPlayer();
  final AudioPlayer _heartRateBeepPlayer = AudioPlayer();
  final AudioPlayer _cuffPlayer = AudioPlayer();

  static const double _beepVolume = 0.55;
  static const double _heartRateBeepVolume = 0.55;
  static const double _cuffVolume = 1.0;

  final Random _random = Random();

  String? _lastTempValue;

  Timer? _pendingTempTimer;
  Instrument? _pendingTempInstrument;

  bool _isPlayingCuffSound = false;
  Instrument? _pendingBPInstrument;
  String? _lastBpValue;

  Timer? _heartRateBeepTimer;
  bool _heartRateBeepLoopActive = false;
  int? _targetHeartRateForBeep;
  double? _smoothedHeartRateForBeep;

  final String serviceUuid = "0000ffe0-0000-1000-8000-00805f9b34fb";
  final String characteristicUuid = "0000ffe1-0000-1000-8000-00805f9b34fb";

  final StringBuffer _buffer = StringBuffer();
  bool _isInitialized = false;

  BLEPeripheralProvider() {
    _initAndStartAdvertising();
  }

  Future<void> _initAndStartAdvertising() async {
    await _initBle();
    await Future.delayed(const Duration(milliseconds: 500));

    if (!_isAdvertising) {
      await startAdvertising();
    }
  }

  Future<void> _initBle() async {
    if (_isInitialized) return;

    try {
      await BlePeripheral.initialize();
      _isInitialized = true;
      debugPrint("✅ BLE Peripheral inicializado");

      BlePeripheral.setWriteRequestCallback((
        String deviceId,
        String characteristicId,
        int offset,
        Uint8List? value,
      ) {
        debugPrint(
          "📩 WRITE REQUEST from $deviceId, char: $characteristicId, size: ${value?.length}",
        );

        if (value != null && value.isNotEmpty) {
          _onDataReceived(value);
        }

        return WriteRequestResult();
      });

      BlePeripheral.setConnectionStateChangeCallback(
        (String deviceId, bool connected) {
          debugPrint("🔗 Conexión: $deviceId connected=$connected");

          if (connected) {
            _connectedCentralId = deviceId;
            _buffer.clear();
          } else {
            _connectedCentralId = null;
          }

          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint("❌ BLE init falló: $e");
    }
  }

  Future<void> restartAdvertising() async {
    debugPrint("🔄 Reiniciando publicidad...");

    await stopAdvertising();
    await Future.delayed(const Duration(milliseconds: 300));
    await startAdvertising();
  }

  Future<void> startAdvertising() async {
    if (_isAdvertising) {
      debugPrint("⚠️ Publicidad ya activa");
      return;
    }

    debugPrint("🚀 Iniciando advertising...");

    if (!_isInitialized) {
      await _initBle();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    final permissions = await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    final granted =
        permissions[Permission.bluetoothAdvertise]?.isGranted == true &&
            permissions[Permission.bluetoothConnect]?.isGranted == true &&
            permissions[Permission.location]?.isGranted == true;

    if (!granted) {
      debugPrint("❌ Permisos insuficientes para publicidad BLE");
      return;
    }

    try {
      await BlePeripheral.stopAdvertising();
      await Future.delayed(const Duration(milliseconds: 200));

      final characteristic = BleCharacteristic(
        uuid: characteristicUuid,
        properties: [CharacteristicProperties.write.index],
        value: null,
        permissions: [AttributePermissions.writeable.index],
      );

      final bleService = BleService(
        uuid: serviceUuid,
        primary: true,
        characteristics: [characteristic],
      );

      await BlePeripheral.addService(bleService);

      debugPrint("✅ Servicio añadido: $serviceUuid, Char: $characteristicUuid");

      await Future.delayed(const Duration(milliseconds: 200));

      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: "MSI-MONITOR",
      );

      _isAdvertising = true;
      _buffer.clear();
      _connectedCentralId = null;

      _lastTempValue = null;
      _pendingTempInstrument = null;
      _pendingTempTimer?.cancel();
      _pendingTempTimer = null;

      _pendingBPInstrument = null;
      _lastBpValue = null;
      _isPlayingCuffSound = false;

      _stopHeartRateBeep();

      notifyListeners();

      debugPrint("✅ Publicando como MSI-MONITOR");
    } catch (e) {
      debugPrint("❌ Error al iniciar advertising: $e");
    }
  }

  Future<void> stopAdvertising() async {
    if (!_isAdvertising) {
      debugPrint("⚠️ Publicidad ya detenida");
      return;
    }

    try {
      await BlePeripheral.stopAdvertising();

      _isAdvertising = false;
      _connectedCentralId = null;
      _buffer.clear();

      _lastTempValue = null;
      _pendingTempInstrument = null;
      _pendingTempTimer?.cancel();
      _pendingTempTimer = null;

      _pendingBPInstrument = null;
      _lastBpValue = null;
      _isPlayingCuffSound = false;

      _stopHeartRateBeep();

      notifyListeners();

      debugPrint("Publicidad detenida");
    } catch (e) {
      debugPrint("Error al detener advertising: $e");
    }
  }

  void _onDataReceived(List<int> bytes) {
    try {
      final chunk = utf8.decode(bytes);
      _buffer.write(chunk);

      debugPrint(
        "📦 Recibido ${bytes.length} bytes. Buffer: ${_buffer.length}",
      );

      final full = _buffer.toString();

      final start = full.indexOf('[');
      if (start == -1) return;

      var depth = 0;
      var end = -1;

      for (var i = start; i < full.length; i++) {
        if (full[i] == '[') {
          depth++;
        } else if (full[i] == ']') {
          depth--;

          if (depth == 0) {
            end = i;
            break;
          }
        }
      }

      if (end == -1) return;

      final jsonString = full.substring(start, end + 1);

      debugPrint("📦 JSON extraído (${jsonString.length} chars)");

      try {
        final List<dynamic> jsonList = json.decode(jsonString);

        if (jsonList.isNotEmpty &&
            jsonList[0] is Map<String, dynamic> &&
            jsonList[0]['type'] == 'set_theme') {
          final theme = jsonList[0]['theme'];

          setTheme(theme == 'dark');

          _buffer.clear();
          _buffer.write(full.substring(end + 1));

          return;
        }

        if (jsonList.isNotEmpty &&
            jsonList[0] is Map<String, dynamic> &&
            jsonList[0]['type'] == 'end_simulation') {
          debugPrint("🏁 Comando de fin de simulación recibido");

          _instruments = [];

          _lastTempValue = null;
          _pendingTempInstrument = null;
          _pendingTempTimer?.cancel();
          _pendingTempTimer = null;

          _pendingBPInstrument = null;
          _lastBpValue = null;
          _isPlayingCuffSound = false;

          unawaited(_cuffPlayer.stop());
          _stopHeartRateBeep();

          notifyListeners();

          if (onSimulationEnd != null) {
            onSimulationEnd!();
          }

          _buffer.clear();
          _buffer.write(full.substring(end + 1));

          return;
        }

        _processInstrumentPayload(jsonList);
      } catch (e) {
        debugPrint("❌ Error parseando JSON: $e");
      }

      _buffer.clear();
      _buffer.write(full.substring(end + 1));
    } catch (e) {
      debugPrint("❌ Error procesando datos: $e");
      _buffer.clear();
    }
  }

  void _processInstrumentPayload(List<dynamic> jsonList) {
    final updatedNonBpInstruments = <Instrument>[];
    final visibleNonBpIds = <String>{};

    Instrument? receivedBpInstrument;
    var receivedBp = false;
    var receivedTemperature = false;

    for (final item in jsonList) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      final instrument = Instrument.fromJson(item);

      if (instrument.type == InstrumentType.bp) {
        receivedBp = true;
        receivedBpInstrument = instrument;
        continue;
      }

      visibleNonBpIds.add(instrument.id);

      if (instrument.type == InstrumentType.temp) {
        receivedTemperature = true;
        _handleTemperatureInstrumentFromPayload(instrument);
        continue;
      }

      updatedNonBpInstruments.add(instrument);
    }

    _instruments.removeWhere((instrument) {
      if (instrument.type == InstrumentType.bp) {
        return !receivedBp;
      }

      return !visibleNonBpIds.contains(instrument.id);
    });

    if (!receivedTemperature) {
      _cancelPendingTemperature();
      _lastTempValue = null;
    }

    if (updatedNonBpInstruments.isNotEmpty) {
      _instruments = _mergeInstruments(
        _instruments,
        updatedNonBpInstruments,
      );
    }

    if (receivedBp && receivedBpInstrument != null) {
      _handleBloodPressureInstrumentFromPayload(receivedBpInstrument);
    }

    if (!receivedBp) {
      _pendingBPInstrument = null;
      _lastBpValue = null;

      if (_isPlayingCuffSound) {
        unawaited(_cuffPlayer.stop());
      }

      _isPlayingCuffSound = false;
    }

    _updateHeartRateBeep();

    debugPrint("✅ Monitor actualizado: ${_instruments.length} instrumentos");

    notifyListeners();
  }

  void _handleBloodPressureInstrumentFromPayload(Instrument instrument) {
    final currentIndex = _instruments.indexWhere(
      (item) => item.type == InstrumentType.bp || item.id == instrument.id,
    );

    final previousValue = _lastBpValue;
    final newValue = instrument.value;

    final wasAlreadyVisible = currentIndex != -1;
    final valueChanged = previousValue != null && previousValue != newValue;

    _lastBpValue = newValue;

    if (!wasAlreadyVisible || valueChanged) {
      _pendingBPInstrument = instrument;

      if (!_isPlayingCuffSound) {
        unawaited(_playCuffSoundAndUpdateBP());
      }

      return;
    }

    _instruments[currentIndex] = instrument;
  }

  void _handleTemperatureInstrumentFromPayload(Instrument instrument) {
    final index = _instruments.indexWhere((item) => item.id == instrument.id);

    if (index != -1) {
      _handleTemperatureUpdate(instrument);
      _instruments[index] = instrument;
      return;
    }

    _pendingTempInstrument = instrument;

    if (_pendingTempTimer != null) {
      return;
    }

    final delayMs = 5000 + _random.nextInt(5001);

    debugPrint("🌡️ Termómetro pendiente. Aparecerá en ${delayMs}ms");

    _pendingTempTimer = Timer(Duration(milliseconds: delayMs), () {
      final pending = _pendingTempInstrument;

      _pendingTempTimer = null;
      _pendingTempInstrument = null;

      if (pending == null) return;

      _instruments = _mergeInstruments(_instruments, [pending]);
      _lastTempValue = pending.value;

      unawaited(_playBeepSound());

      debugPrint("🌡️ Termómetro mostrado tras espera con beep");

      notifyListeners();
    });
  }

  void _cancelPendingTemperature() {
    _pendingTempInstrument = null;
    _pendingTempTimer?.cancel();
    _pendingTempTimer = null;
  }

  void _handleTemperatureUpdate(Instrument instrument) {
    final newTempValue = instrument.value;

    if (newTempValue.isNotEmpty &&
        _lastTempValue != null &&
        newTempValue != _lastTempValue) {
      unawaited(_playBeepSound());
    }

    if (newTempValue.isNotEmpty) {
      _lastTempValue = newTempValue;
    }
  }

  bool _isHeartRateInstrument(Instrument instrument) {
    if (instrument.type != InstrumentType.hr) return false;

    final id = instrument.id.toLowerCase();
    final label = instrument.label.toLowerCase();
    final unit = instrument.unit.toLowerCase();

    return id.contains('hr') ||
        id.contains('fc') ||
        label == 'fc' ||
        label.contains('heart') ||
        unit == 'lpm' ||
        unit == 'bpm';
  }

  int? _heartRateFromInstrument(Instrument instrument) {
    if (!_isHeartRateInstrument(instrument)) return null;

    final match = RegExp(r'\d+').firstMatch(instrument.value);

    if (match == null) return null;

    final bpm = int.tryParse(match.group(0)!);

    if (bpm == null || bpm <= 0) return null;

    return bpm;
  }

  int? _currentVisibleHeartRate() {
    for (final instrument in _instruments) {
      final bpm = _heartRateFromInstrument(instrument);

      if (bpm != null) {
        return bpm;
      }
    }

    return null;
  }

  void _updateHeartRateBeep() {
    final bpm = _currentVisibleHeartRate();

    if (bpm == null) {
      _stopHeartRateBeep();
      return;
    }

    _targetHeartRateForBeep = bpm;

    if (_heartRateBeepLoopActive && _heartRateBeepTimer != null) {
      return;
    }

    _startHeartRateBeepLoop(bpm);
  }

  void _startHeartRateBeepLoop(int bpm) {
    _stopHeartRateBeep();

    _targetHeartRateForBeep = bpm;
    _smoothedHeartRateForBeep = bpm.toDouble();
    _heartRateBeepLoopActive = true;

    unawaited(_playHeartRateBeepSound());

    _scheduleNextHeartRateBeep();
  }

  void _scheduleNextHeartRateBeep() {
    _heartRateBeepTimer?.cancel();
    _heartRateBeepTimer = null;

    if (!_heartRateBeepLoopActive || _targetHeartRateForBeep == null) {
      _stopHeartRateBeep();
      return;
    }

    final target = _targetHeartRateForBeep!.toDouble();
    final previous = _smoothedHeartRateForBeep ?? target;

    final smoothed = previous + (target - previous) * 0.35;
    _smoothedHeartRateForBeep = smoothed;

    final intervalMs = (60000 / smoothed).round().clamp(250, 3000).toInt();

    _heartRateBeepTimer = Timer(Duration(milliseconds: intervalMs), () {
      if (!_heartRateBeepLoopActive || _targetHeartRateForBeep == null) {
        return;
      }

      unawaited(_playHeartRateBeepSound());
      _scheduleNextHeartRateBeep();
    });

    debugPrint(
      "🔊 Beep FC/LPM: target=${_targetHeartRateForBeep} lpm, "
      "smooth=${smoothed.toStringAsFixed(1)}, intervalo=${intervalMs}ms",
    );
  }

  void _stopHeartRateBeep() {
    _heartRateBeepTimer?.cancel();
    _heartRateBeepTimer = null;

    _heartRateBeepLoopActive = false;
    _targetHeartRateForBeep = null;
    _smoothedHeartRateForBeep = null;

    unawaited(_heartRateBeepPlayer.stop());
  }

  Future<void> _playHeartRateBeepSound() async {
    if (_isPlayingCuffSound) return;

    try {
      await _heartRateBeepPlayer.stop();
      await _heartRateBeepPlayer.setVolume(_heartRateBeepVolume);
      await _heartRateBeepPlayer.play(AssetSource('sounds/beep.wav'));
    } catch (e) {
      debugPrint("❌ Error al reproducir beep FC/LPM: $e");
    }
  }

  Future<void> _playBeepSound() async {
    try {
      await _beepPlayer.stop();
      await _beepPlayer.setVolume(_beepVolume);
      await _beepPlayer.play(AssetSource('sounds/beep.wav'));
    } catch (e) {
      debugPrint("❌ Error al reproducir beep: $e");
    }
  }

  List<Instrument> _mergeInstruments(
    List<Instrument> current,
    List<Instrument> updates,
  ) {
    final merged = List<Instrument>.from(current);

    for (final instrument in updates) {
      final index = merged.indexWhere((item) => item.id == instrument.id);

      if (index == -1) {
        merged.add(instrument);
      } else {
        merged[index] = instrument;
      }
    }

    return merged;
  }

  Future<void> _playCuffSoundAndUpdateBP() async {
    if (_isPlayingCuffSound) return;

    _isPlayingCuffSound = true;

    try {
      // Mientras suena el manguito, evitamos que el beep de FC lo corte o lo
      // haga perder el evento de finalización en algunos teléfonos.
      await _heartRateBeepPlayer.stop();

      await _cuffPlayer.stop();
      await _cuffPlayer.setVolume(_cuffVolume);
      await _cuffPlayer.play(AssetSource('sounds/cuff.wav'));

      // Fallback: si Android/audioplayers no emite onPlayerComplete porque otro
      // sonido interrumpe el cuff, igualmente mostramos PANI/PAI tras un tiempo
      // razonable para no dejar el módulo bloqueado para siempre.
      await Future.any([
        _cuffPlayer.onPlayerComplete.first,
        Future.delayed(const Duration(seconds: 9)),
      ]);
    } catch (e) {
      debugPrint("❌ Error al reproducir el sonido del manguito: $e");
    } finally {
      final pending = _pendingBPInstrument;
      _pendingBPInstrument = null;

      if (pending != null) {
        _instruments = _mergeInstruments(_instruments, [pending]);
        notifyListeners();
      }

      _isPlayingCuffSound = false;
    }
  }

  @override
  void dispose() {
    _stopHeartRateBeep();

    _pendingTempTimer?.cancel();

    _audioPlayer.dispose();
    _beepPlayer.dispose();
    _heartRateBeepPlayer.dispose();
    _cuffPlayer.dispose();

    BlePeripheral.stopAdvertising();

    super.dispose();
  }
}
