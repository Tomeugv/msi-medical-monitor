import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../models/instrument.dart';

class MonitorProvider with ChangeNotifier {
  final _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  
  bool _isScanning = false;
  bool get isScanning => _isScanning;
  
  DeviceConnectionState _status = DeviceConnectionState.disconnected;
  DeviceConnectionState get status => _status;
  
  List<DiscoveredDevice> _foundDevices = [];
  List<DiscoveredDevice> get foundDevices => _foundDevices;

  List<Instrument> _instruments = [];
  List<Instrument> get instruments => _instruments;

  String? _connectedDeviceId;
  String? get connectedDeviceId => _connectedDeviceId;

  void startScan() {
    _foundDevices = [];
    _isScanning = true;
    notifyListeners();

    _scanSubscription = _ble.scanForDevices(withServices: []).listen((device) {
      final index = _foundDevices.indexWhere((d) => d.id == device.id);
      if (index == -1) {
        _foundDevices.add(device);
        notifyListeners();
      }
    });

    // Auto-stop scan after 10s
    Future.delayed(const Duration(seconds: 10), stopScan);
  }

  void stopScan() {
    _scanSubscription?.cancel();
    _isScanning = false;
    notifyListeners();
  }

  void connect(String deviceId) {
    _status = DeviceConnectionState.connecting;
    notifyListeners();

    _connectionSubscription = _ble.connectToDevice(id: deviceId).listen((update) {
      _status = update.connectionState;
      if (update.connectionState == DeviceConnectionState.connected) {
        _connectedDeviceId = deviceId;
        _setupNotifications(deviceId);
      }
      notifyListeners();
    }, onError: (Object e) {
      _status = DeviceConnectionState.disconnected;
      notifyListeners();
    });
  }

  void _setupNotifications(String deviceId) {
    // These UUIDs should match the ones in your Dashboard app (clinical_ether)
    final serviceUuid = Uuid.parse("0000ffe0-0000-1000-8000-00805f9b34fb");
    final characteristicUuid = Uuid.parse("0000ffe1-0000-1000-8000-00805f9b34fb");

    final characteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: deviceId,
    );

    _ble.subscribeToCharacteristic(characteristic).listen((data) {
      try {
        final stringData = utf8.decode(data);
        final List<dynamic> jsonList = json.decode(stringData);
        _instruments = jsonList.map((j) => Instrument.fromJson(j)).toList();
        notifyListeners();
      } catch (e) {
        debugPrint("Error parsing BLE data: $e");
      }
    });
  }

  void disconnect() {
    _connectionSubscription?.cancel();
    _status = DeviceConnectionState.disconnected;
    _connectedDeviceId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }
}
