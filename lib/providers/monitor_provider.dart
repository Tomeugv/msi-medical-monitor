import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/instrument.dart';

class MonitorProvider with ChangeNotifier {
  final _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;

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

  // Buffer for incoming data fragments
  String _dataBuffer = "";

  Future<bool> _requestPermissions() async {
    if (await Permission.bluetoothScan.request().isGranted &&
        await Permission.bluetoothConnect.request().isGranted &&
        await Permission.location.request().isGranted) {
      return true;
    }
    return false;
  }

  void startScan() async {
    final hasPermissions = await _requestPermissions();
    if (!hasPermissions) {
      debugPrint("Bluetooth permissions denied");
      return;
    }

    _foundDevices = [];
    _isScanning = true;
    notifyListeners();

    // Use a service UUID filter if known, otherwise scan all
    _scanSubscription = _ble.scanForDevices(withServices: []).listen((device) {
      final index = _foundDevices.indexWhere((d) => d.id == device.id);
      if (index == -1) {
        _foundDevices.add(device);
        notifyListeners();
      }
    }, onError: (e) => stopScan());

    Future.delayed(const Duration(seconds: 15), stopScan);
  }

  void stopScan() {
    _scanSubscription?.cancel();
    _isScanning = false;
    notifyListeners();
  }

  void connect(String deviceId) {
    stopScan(); // Stop scan before connecting - critical for many Android devices
    _status = DeviceConnectionState.connecting;
    _connectedDeviceId = deviceId;
    _dataBuffer = "";
    notifyListeners();

    _connectionSubscription = _ble
        .connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 20),
    )
        .listen((update) async {
      debugPrint(
          "BLE Connection state for $deviceId: ${update.connectionState}");
      _status = update.connectionState;

      if (update.connectionState == DeviceConnectionState.connected) {
        debugPrint(
            "Successfully connected to $deviceId. Discovering services...");
        try {
          final services = await _ble.discoverServices(deviceId);
          for (final service in services) {
            debugPrint("Discovered Service: ${service.serviceId}");
            for (final characteristic in service.characteristics) {
              debugPrint(
                  "  Characteristic: ${characteristic.characteristicId} [Notify: ${characteristic.isNotifiable}, Write: ${characteristic.isWritableWithResponse}]");
            }
          }

          // Try to negotiate MTU
          final mtu = await _ble.requestMtu(deviceId: deviceId, mtu: 512);
          debugPrint("MTU negotiated: $mtu");
        } catch (e) {
          debugPrint("Discovery or MTU failed: $e");
        }
        _setupNotifications(deviceId);
      }
      notifyListeners();
    }, onError: (error) {
      debugPrint("BLE Connection error for $deviceId: $error");
      _status = DeviceConnectionState.disconnected;
      notifyListeners();
    });
  }

  void _setupNotifications(String deviceId) async {
    try {
      final services = await _ble.discoverServices(deviceId);

      // UUIDs for HM-10 BLE module (common UART service)
      final serviceUuid = Uuid.parse("0000ffe0-0000-1000-8000-00805f9b34fb");
      final characteristicUuid =
          Uuid.parse("0000ffe1-0000-1000-8000-00805f9b34fb");

      DiscoveredService? targetService;
      DiscoveredCharacteristic? targetChar;

      // First try to find the standard UART service
      for (var s in services) {
        if (s.serviceId == serviceUuid) {
          targetService = s;
          for (var c in s.characteristics) {
            if (c.characteristicId == characteristicUuid) {
              targetChar = c;
              break;
            }
          }
        }
      }

      // If not found, look for ANY notifiable characteristic
      if (targetChar == null) {
        for (var s in services) {
          for (var c in s.characteristics) {
            if (c.isNotifiable) {
              targetService = s;
              targetChar = c;
              debugPrint(
                  "Found alternative notifiable characteristic: ${c.characteristicId}");
              break;
            }
          }
          if (targetChar != null) break;
        }
      }

      if (targetChar == null || targetService == null) {
        debugPrint("No suitable characteristic found for data reception");
        return;
      }

      final characteristic = QualifiedCharacteristic(
        serviceId: targetService.serviceId,
        characteristicId: targetChar.characteristicId,
        deviceId: deviceId,
      );

      _notificationSubscription =
          _ble.subscribeToCharacteristic(characteristic).listen((data) {
        try {
          final chunk = utf8.decode(data);
          _dataBuffer += chunk;

          // Medical JSONs usually start with [ and end with ]
          final startIdx = _dataBuffer.indexOf('[');
          final endIdx = _dataBuffer.lastIndexOf(']');

          if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
            final jsonString = _dataBuffer.substring(startIdx, endIdx + 1);
            final List<dynamic> jsonList = json.decode(jsonString);
            _instruments = jsonList.map((j) => Instrument.fromJson(j)).toList();
            _dataBuffer =
                _dataBuffer.substring(endIdx + 1); // Keep remaining bit if any
            notifyListeners();
          }
        } catch (e) {
          debugPrint("Parse error: $e");
          // Don't clear buffer yet, might be mid-packet
          if (_dataBuffer.length > 4096) _dataBuffer = ""; // Safety clear
        }
      }, onError: (e) => debugPrint("Subscription error: $e"));
    } catch (e) {
      debugPrint("Notification setup failed: $e");
    }
  }

  void disconnect() {
    _notificationSubscription?.cancel();
    _connectionSubscription?.cancel();
    _status = DeviceConnectionState.disconnected;
    _connectedDeviceId = null;
    _dataBuffer = "";
    notifyListeners();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _notificationSubscription?.cancel();
    super.dispose();
  }
}
