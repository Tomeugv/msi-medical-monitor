import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../providers/ble_peripheral_provider.dart';
import 'monitor_screen.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  bool _hasNavigated = false;
  bool _waitingForData = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkForNavigation();
  }

  void _checkForNavigation() {
    final provider = context.read<BLEPeripheralProvider>();

    if (provider.instruments.isNotEmpty && !_hasNavigated) {
      _navigateToMonitor(provider);
      return;
    }

    if (provider.connectedCentralId != null &&
        !_waitingForData &&
        !_hasNavigated) {
      _waitingForData = true;
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;

        if (provider.instruments.isNotEmpty && !_hasNavigated) {
          _navigateToMonitor(provider);
        }

        _waitingForData = false;
      });
    }
  }

  void _navigateToMonitor(BLEPeripheralProvider provider) {
    if (_hasNavigated) return;

    _hasNavigated = true;

    // Asignar callback para volver a ConnectionScreen al finalizar simulación
    if (provider.onSimulationEnd == null) {
      provider.onSimulationEnd = () {
        if (mounted) {
          Navigator.pop(context);
          _hasNavigated = false;
          provider.onSimulationEnd = null;
        }
      };
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MonitorScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BLEPeripheralProvider>(
      builder: (context, provider, child) {
        _checkForNavigation();

        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 48),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: const Icon(LucideIcons.bluetooth,
                        color: Colors.white70, size: 24),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'MSI Medical Monitor',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Make this device discoverable so a Dashboard can send telemetry data.\n'
                    'Once connected, patient data will appear automatically.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: provider.isAdvertising
                          ? Colors.green.withOpacity(0.1)
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: provider.isAdvertising
                            ? Colors.green.withOpacity(0.5)
                            : Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          provider.isAdvertising
                              ? LucideIcons.radio
                              : LucideIcons.bluetoothOff,
                          size: 48,
                          color: provider.isAdvertising
                              ? Colors.green
                              : Colors.white38,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          provider.isAdvertising
                              ? "DISCOVERABLE AS MSI-MONITOR"
                              : "NOT ADVERTISING",
                          style: TextStyle(
                            color: provider.isAdvertising
                                ? Colors.green
                                : Colors.white38,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (provider.isAdvertising)
                          Text(
                            provider.connectedCentralId != null
                                ? "Central connected – waiting for data..."
                                : "Waiting for Dashboard connection...",
                            style:
                                TextStyle(color: Colors.white24, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: provider.isAdvertising
                          ? provider.stopAdvertising
                          : () async {
                              await provider.startAdvertising();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Monitor is now discoverable as MSI-MONITOR'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            },
                      icon: Icon(
                        provider.isAdvertising
                            ? LucideIcons.stopCircle
                            : LucideIcons.play,
                        size: 20,
                      ),
                      label: Text(
                        provider.isAdvertising
                            ? 'Stop Advertising'
                            : 'Start Advertising',
                        style: const TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            provider.isAdvertising ? Colors.red : Colors.white,
                        foregroundColor: provider.isAdvertising
                            ? Colors.white
                            : Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
