import 'dart:async';
import 'dart:convert';
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

  // UI callback fired when dashboard explicitly signals simulation end.
  VoidCallback? onSimulationEnd;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _beepPlayer = AudioPlayer();
  final AudioPlayer _cuffPlayer = AudioPlayer();
  String? _lastTempValue;
  bool _isPlayingCuffSound = false;
  Instrument? _pendingBPInstrument;

  final String serviceUuid = "0000ffe0-0000-1000-8000-00805f9b34fb";
  final String characteristicUuid = "0000ffe1-0000-1000-8000-00805f9b34fb";

  final StringBuffer _buffer = StringBuffer();
  bool _isInitialized = false;

  BLEPeripheralProvider() {
    _initAndStartAdvertising();
  }

  // Inicializa BLE y arranca la publicidad automáticamente
  Future<void> _initAndStartAdvertising() async {
    await _initBle();
    // Esperamos un momento para que todo esté listo
    await Future.delayed(const Duration(milliseconds: 500));
    // Arrancamos la publicidad si no está ya activa
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
            "📩 WRITE REQUEST from $deviceId, char: $characteristicId, size: ${value?.length}");
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
      });
    } catch (e) {
      debugPrint("❌ BLE init falló: $e");
    }
  }

  // Reinicia la publicidad (útil si algo falla)
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

    bool granted = permissions[Permission.bluetoothAdvertise]!.isGranted &&
        permissions[Permission.bluetoothConnect]!.isGranted &&
        permissions[Permission.location]!.isGranted;

    if (!granted) {
      debugPrint("❌ Permisos insuficientes para publicidad BLE");
      return;
    }

    try {
      // Detener publicidad anterior si existe
      await BlePeripheral.stopAdvertising();
      await Future.delayed(const Duration(milliseconds: 200));

      // Limpiar todos los servicios anteriores (evita duplicados)
      // Nota: removeAllServices puede no existir en tu versión del plugin.
      // Si no existe, simplemente no lo llames.

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
      _pendingBPInstrument = null;
      _isPlayingCuffSound = false;
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
      _pendingBPInstrument = null;
      _isPlayingCuffSound = false;
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
          "📦 Recibido ${bytes.length} bytes. Buffer: ${_buffer.length}");

      final full = _buffer.toString();
      int start = full.indexOf('[');
      if (start == -1) return;

      int depth = 0;
      int end = -1;
      for (int i = start; i < full.length; i++) {
        if (full[i] == '[')
          depth++;
        else if (full[i] == ']') {
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

        final updatedNonBpInstruments = <Instrument>[];
        Instrument? pendingBpInstrument;

        for (final item in jsonList) {
          if (item is! Map<String, dynamic>) {
            continue;
          }

          final instrument = Instrument.fromJson(item);

          if (instrument.type == InstrumentType.bp) {
            pendingBpInstrument = instrument;
            continue;
          }

          if (instrument.type == InstrumentType.temp) {
            final newTempValue = instrument.value;
            if (newTempValue.isNotEmpty &&
                _lastTempValue != null &&
                newTempValue != _lastTempValue) {
              _playBeepSound();
            }
            if (newTempValue.isNotEmpty) {
              _lastTempValue = newTempValue;
            }
          }

          updatedNonBpInstruments.add(instrument);
        }

        if (updatedNonBpInstruments.isNotEmpty) {
          _instruments =
              _mergeInstruments(_instruments, updatedNonBpInstruments);
          debugPrint(
              "✅ Actualizados ${_instruments.length} instrumentos no-BP");
          notifyListeners();
        }

        if (pendingBpInstrument != null) {
          _pendingBPInstrument = pendingBpInstrument;
          if (!_isPlayingCuffSound) {
            _playCuffSoundAndUpdateBP();
          }
        }

        // Detectar comando de fin de simulación
        if (jsonList.isNotEmpty &&
            jsonList[0] is Map<String, dynamic> &&
            jsonList[0]['type'] == 'end_simulation') {
          debugPrint("🏁 Comando de fin de simulación recibido");
          _instruments = [];
          _lastTempValue = null;
          _pendingBPInstrument = null;
          _isPlayingCuffSound = false;
          _cuffPlayer.stop();
          notifyListeners();
          if (onSimulationEnd != null) {
            onSimulationEnd!();
          }
          _buffer.clear();
          _buffer.write(full.substring(end + 1));
          return;
        }

        if (pendingBpInstrument == null && updatedNonBpInstruments.isEmpty) {
          final parsedInstruments = jsonList
              .whereType<Map<String, dynamic>>()
              .map((j) => Instrument.fromJson(j))
              .toList();
          _instruments = parsedInstruments;
          debugPrint("✅ Actualizados ${_instruments.length} instrumentos");
          notifyListeners();
        }
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

  Future<void> _playBeepSound() async {
    try {
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
      await _cuffPlayer.play(AssetSource('sounds/cuff.wav'));
      await _cuffPlayer.onPlayerComplete.first;
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
    // No detenemos publicidad al cerrar la app? El usuario puede decidir,
    // pero para limpiar recursos lo hacemos.
    _audioPlayer.dispose();
    _beepPlayer.dispose();
    _cuffPlayer.dispose();
    BlePeripheral.stopAdvertising();
    super.dispose();
  }
}
