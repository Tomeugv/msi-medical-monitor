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

  // Use lowercase for consistency (Android is case-insensitive but better to match)
  final String serviceUuid = "0000ffe0-0000-1000-8000-00805f9b34fb";
  final String characteristicUuid = "0000ffe1-0000-1000-8000-00805f9b34fb";

  final StringBuffer _buffer = StringBuffer();
  bool _isInitialized = false;

  BLEPeripheralProvider() {
    _initBle();
  }

  Future<void> _initBle() async {
    if (_isInitialized) return;
    try {
      await BlePeripheral.initialize();
      _isInitialized = true;
      debugPrint("✅ BLE Peripheral initialized");

      BlePeripheral.setWriteRequestCallback((
        String deviceId,
        String characteristicId,
        int offset,
        Uint8List? value,
      ) {
        debugPrint(
            "🔥🔥🔥 WRITE REQUEST from $deviceId, char: $characteristicId, size: ${value?.length}");
        if (value != null && value.isNotEmpty) {
          _onDataReceived(value);
        }
        return WriteRequestResult();
      });

      BlePeripheral.setConnectionStateChangeCallback(
          (String deviceId, bool connected) {
        debugPrint("🔗 Connection: $deviceId connected=$connected");
        if (connected) {
          _connectedCentralId = deviceId;
          _buffer.clear();
        } else {
          _connectedCentralId = null;
        }
        notifyListeners();
      });
    } catch (e) {
      debugPrint("❌ BLE init failed: $e");
    }
  }

  Future<void> startAdvertising() async {
    debugPrint("🚀 Starting advertising...");

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
      debugPrint("❌ Missing permissions");
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
      debugPrint("✅ Service added: $serviceUuid, Char: $characteristicUuid");

      await Future.delayed(const Duration(milliseconds: 200));

      await BlePeripheral.startAdvertising(
        services: [serviceUuid],
        localName: "MSI-MONITOR",
      );

      _isAdvertising = true;
      _buffer.clear();
      _connectedCentralId = null;
      notifyListeners();
      debugPrint("✅ Advertising as MSI-MONITOR");
    } catch (e) {
      debugPrint("❌ Failed to start advertising: $e");
    }
  }

  Future<void> stopAdvertising() async {
    try {
      await BlePeripheral.stopAdvertising();
      _isAdvertising = false;
      _connectedCentralId = null;
      _buffer.clear();
      notifyListeners();
      debugPrint("Stopped advertising");
    } catch (e) {
      debugPrint("Error stopping advertising: $e");
    }
  }

  void _onDataReceived(List<int> bytes) {
    try {
      final chunk = utf8.decode(bytes);
      _buffer.write(chunk);
      debugPrint(
          "📦 Received ${bytes.length} bytes. Buffer length: ${_buffer.length}");

      final full = _buffer.toString();
      int start = full.indexOf('[');
      if (start == -1) {
        debugPrint("No start bracket, waiting...");
        return;
      }

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
      if (end == -1) {
        debugPrint("JSON incomplete, waiting...");
        return;
      }

      final jsonString = full.substring(start, end + 1);
      debugPrint("📦 Extracted JSON (${jsonString.length} chars)");
      try {
        final List<dynamic> jsonList = json.decode(jsonString);
        _instruments = jsonList.map((j) => Instrument.fromJson(j)).toList();
        debugPrint("✅ Updated ${_instruments.length} instruments");
        notifyListeners();
      } catch (e) {
        debugPrint("❌ Parse error: $e");
      }
      _buffer.clear();
      _buffer.write(full.substring(end + 1));
    } catch (e) {
      debugPrint("❌ Error: $e");
      _buffer.clear();
    }
  }

  @override
  void dispose() {
    BlePeripheral.stopAdvertising();
    super.dispose();
  }
}
