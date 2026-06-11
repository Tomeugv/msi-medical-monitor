import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/ble_peripheral_provider.dart';
import '../models/instrument.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enterFullScreenMode();
    });
  }

  @override
  void dispose() {
    _exitFullScreenMode();
    super.dispose();
  }

  Future<void> _enterFullScreenMode() async {
    await Future.delayed(Duration.zero);

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _exitFullScreenMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BLEPeripheralProvider>(
      builder: (context, provider, child) {
        final backgroundColor =
            provider.isDarkTheme ? Colors.black : Colors.white;

        return PopScope(
          canPop: false,
          onPopInvoked: (bool didPop) async {
            if (didPop) return;

            final shouldExit = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Salir del Monitor'),
                    content:
                        const Text('¿Deseas volver a la pantalla de conexión?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Salir'),
                      ),
                    ],
                  ),
                ) ??
                false;

            if (shouldExit && context.mounted) {
              _exitFullScreenMode();
              Navigator.pop(context);
            }
          },
          child: Scaffold(
            backgroundColor: backgroundColor,
            body: Builder(
              builder: (context) {
                final instruments = provider.instruments;

                if (instruments.isEmpty) {
                  return ColoredBox(color: backgroundColor);
                }

                return _DynamicGrid(
                  instruments: instruments,
                  isDarkTheme: provider.isDarkTheme,
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _DynamicGrid extends StatelessWidget {
  final List<Instrument> instruments;
  final bool isDarkTheme;

  const _DynamicGrid({
    required this.instruments,
    required this.isDarkTheme,
  });

  List<int> _computeRowDistribution(int total, bool isLandscape) {
    if (total == 0) return [];
    if (total == 1) return [1];
    if (total == 2) return [2];
    if (total == 3) return isLandscape ? [3] : [2, 1];
    if (total == 4) return [2, 2];
    if (total == 5) return isLandscape ? [3, 2] : [2, 2, 1];
    if (total == 6) return isLandscape ? [3, 3] : [2, 2, 2];
    if (total == 7) return isLandscape ? [4, 3] : [2, 2, 2, 1];
    if (total == 8) return isLandscape ? [4, 4] : [2, 2, 2, 2];
    if (total == 9) return isLandscape ? [3, 3, 3] : [2, 2, 2, 3];
    if (total == 10) return isLandscape ? [5, 5] : [2, 2, 2, 2, 2];
    if (total == 11) return isLandscape ? [6, 5] : [2, 2, 2, 2, 3];
    if (total == 12) return isLandscape ? [6, 6] : [2, 2, 2, 2, 2, 2];

    if (isLandscape) {
      const cols = 4;
      final rows = (total / cols).ceil();
      final distribution = List<int>.filled(rows, cols);
      final remainder = total % cols;

      if (remainder != 0) {
        distribution[rows - 1] = remainder;
      }

      return distribution;
    }

    final rows = (total / 2).ceil();
    final distribution = List<int>.filled(rows, 2);

    if (total % 2 != 0) {
      distribution[rows - 1] = 1;
    }

    return distribution;
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;
    final count = instruments.length;

    final rowDistribution = _computeRowDistribution(count, isLandscape);
    final rows = rowDistribution.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final rowHeight = totalHeight / rows;

        var startIndex = 0;

        return Column(
          children: List.generate(rows, (rowIdx) {
            final itemsInRow = rowDistribution[rowIdx];

            final rowInstruments =
                instruments.sublist(startIndex, startIndex + itemsInRow);

            startIndex += itemsInRow;

            final baseFontSize = (rowHeight * 0.4).clamp(24.0, 100.0);
            final valueFontSize = baseFontSize;
            final unitFontSize = baseFontSize * 0.3;
            final labelFontSize = baseFontSize * 0.2;

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Row(
                  children: rowInstruments.map((instrument) {
                    return Expanded(
                      child: _InstrumentCard(
                        instrument: instrument,
                        valueFontSize: valueFontSize,
                        unitFontSize: unitFontSize,
                        labelFontSize: labelFontSize,
                        isDarkTheme: isDarkTheme,
                      ),
                    );
                  }).toList(),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _InstrumentCard extends StatefulWidget {
  final Instrument instrument;
  final double valueFontSize;
  final double unitFontSize;
  final double labelFontSize;
  final bool isDarkTheme;

  const _InstrumentCard({
    required this.instrument,
    required this.valueFontSize,
    required this.unitFontSize,
    required this.labelFontSize,
    required this.isDarkTheme,
  });

  @override
  State<_InstrumentCard> createState() => _InstrumentCardState();
}

class _InstrumentCardState extends State<_InstrumentCard> {
  static const List<int> _heartRateOffsets = [0, 1, 0, -1, 0];

  final Random _random = Random();

  Timer? _heartRateVisualTimer;
  var _heartRateOffsetIndex = 0;

  bool get _isHeartRate => _isHeartRateInstrument(widget.instrument);

  @override
  void initState() {
    super.initState();
    _configureHeartRateVisualTimer();
  }

  @override
  void didUpdateWidget(covariant _InstrumentCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final wasHeartRate = _isHeartRateInstrument(oldWidget.instrument);
    final isHeartRate = _isHeartRateInstrument(widget.instrument);

    /*
     * No reiniciamos la oscilación por cambios de valor.
     * Si el usuario sube/baja manualmente la FC, mantenemos el mismo ritmo visual
     * y solo cambiamos la base numérica.
     */
    if (oldWidget.instrument.id != widget.instrument.id ||
        oldWidget.instrument.type != widget.instrument.type ||
        oldWidget.instrument.unit != widget.instrument.unit ||
        wasHeartRate != isHeartRate) {
      _configureHeartRateVisualTimer();
    }
  }

  @override
  void dispose() {
    _heartRateVisualTimer?.cancel();
    super.dispose();
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

  void _configureHeartRateVisualTimer() {
    _heartRateVisualTimer?.cancel();
    _heartRateVisualTimer = null;
    _heartRateOffsetIndex = 0;

    if (!_isHeartRate || _parseHeartRate(widget.instrument.value) == null) {
      return;
    }

    _scheduleNextHeartRateVisualTick();
  }

  void _scheduleNextHeartRateVisualTick() {
    _heartRateVisualTimer?.cancel();

    if (!_isHeartRate || _parseHeartRate(widget.instrument.value) == null) {
      return;
    }

    /*
     * Oscilación más lenta y menos robótica.
     * Cada cambio tarda entre 2.4s y 4.4s aproximadamente.
     */
    final delayMs = 2400 + _random.nextInt(2000);

    _heartRateVisualTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;

      setState(() {
        _heartRateOffsetIndex =
            (_heartRateOffsetIndex + 1) % _heartRateOffsets.length;
      });

      _scheduleNextHeartRateVisualTick();
    });
  }

  int? _parseHeartRate(String value) {
    final match = RegExp(r'\d+').firstMatch(value);

    if (match == null) return null;

    return int.tryParse(match.group(0)!);
  }

  String _displayValue() {
    if (!_isHeartRate) return widget.instrument.value;

    final baseHeartRate = _parseHeartRate(widget.instrument.value);

    if (baseHeartRate == null) return widget.instrument.value;

    final offset = _heartRateOffsets[_heartRateOffsetIndex];

    return (baseHeartRate + offset).toString();
  }

  String _displayUnit() {
    final unit = widget.instrument.unit.trim();

    if (unit.toLowerCase() == 'mmhg') return 'mmHg';

    return unit.toUpperCase();
  }

  String _calculateMap() {
    final parts = widget.instrument.value.split('/');

    if (parts.length != 2) return '';

    final systolic = int.tryParse(parts[0].trim());
    final diastolic = int.tryParse(parts[1].trim());

    if (systolic == null || diastolic == null) return '';

    final meanArterialPressure =
        diastolic + ((systolic - diastolic) / 3).round();

    return meanArterialPressure.toString();
  }

  @override
  Widget build(BuildContext context) {
    final isBloodPressure = widget.instrument.type == InstrumentType.bp;
    final mapValue = isBloodPressure ? _calculateMap() : '';

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: widget.isDarkTheme ? Colors.black : Colors.white,
        border: Border.all(
          color: widget.isDarkTheme
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.1),
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.8,
                  colors: [
                    widget.instrument.color
                        .withOpacity(widget.isDarkTheme ? 0.03 : 0.02),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Text(
              widget.instrument.label.toUpperCase(),
              style: GoogleFonts.jetBrainsMono(
                color: widget.isDarkTheme
                    ? Colors.white.withOpacity(0.68)
                    : Colors.black.withOpacity(0.78),
                fontSize: widget.labelFontSize.clamp(8.0, 20.0),
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _displayValue(),
                    style: GoogleFonts.jetBrainsMono(
                      color: widget.instrument.color,
                      fontSize: widget.valueFontSize,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -5,
                    ),
                  ),
                ),
                if (isBloodPressure && mapValue.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '($mapValue)',
                    style: GoogleFonts.jetBrainsMono(
                      color: widget.isDarkTheme
                          ? widget.instrument.color.withOpacity(0.75)
                          : widget.instrument.color.withOpacity(0.9),
                      fontSize: widget.unitFontSize.clamp(10.0, 24.0),
                      letterSpacing: 2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  _displayUnit(),
                  style: GoogleFonts.jetBrainsMono(
                    color: widget.isDarkTheme
                        ? widget.instrument.color.withOpacity(0.7)
                        : widget.instrument.color.withOpacity(0.9),
                    fontSize: widget.unitFontSize.clamp(10.0, 24.0),
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
          const Positioned(
            bottom: 12,
            right: 12,
            child: Opacity(
              opacity: 0.1,
              child: Icon(Icons.show_chart, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }
}
