import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:ble_peripheral/ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/instrument.dart';

class BLEPeripheralProvider with ChangeNotifier {
  bool _isAdvertising = false;
  bool get isAdvertising => _isAdvertising;

  List<Instrument> _instruments = [];
  List<Instrument> get instruments => _instruments;

  String? _connectedCentralId;
  String? get connectedCentralId => _connectedCentralId;

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
        _instruments = jsonList.map((j) => Instrument.fromJson(j)).toList();
        debugPrint("✅ Actualizados ${_instruments.length} instrumentos");
        notifyListeners();
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

  @override
  void dispose() {
    // No detenemos publicidad al cerrar la app? El usuario puede decidir,
    // pero para limpiar recursos lo hacemos.
    BlePeripheral.stopAdvertising();
    super.dispose();
  }
}
