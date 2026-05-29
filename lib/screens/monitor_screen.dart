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

  /// Calcula la distribución más equilibrada sin celdas vacías.
  /// Devuelve una lista de enteros donde cada elemento es el número de elementos por fila.
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
    // Para más elementos, usamos un algoritmo simple: intentamos 4 columnas en horizontal
    if (isLandscape) {
      int cols = 4;
      int rows = (total / cols).ceil();
      List<int> distribution = List.filled(rows, cols);
      int remainder = total % cols;
      if (remainder != 0) {
        distribution[rows - 1] = remainder;
      }
      return distribution;
    } else {
      // Vertical: siempre 2 columnas, pero la última puede tener 1
      int rows = (total / 2).ceil();
      List<int> distribution = List.filled(rows, 2);
      if (total % 2 != 0) {
        distribution[rows - 1] = 1;
      }
      return distribution;
    }
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

        // Construir las filas según la distribución
        int startIndex = 0;
        return Column(
          children: List.generate(rows, (rowIdx) {
            final itemsInRow = rowDistribution[rowIdx];
            final rowInstruments =
                instruments.sublist(startIndex, startIndex + itemsInRow);
            startIndex += itemsInRow;

            // Calcular tamaño de fuente base según la altura de la fila
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

class _InstrumentCard extends StatelessWidget {
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

  String _calculateMap() {
    final parts = instrument.value.split('/');
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
    final isBloodPressure = instrument.type == InstrumentType.bp;

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isDarkTheme ? Colors.black : Colors.white,
        border: Border.all(
          color: isDarkTheme
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.1),
        ),
      ),
      child: Stack(
        children: [
          // Gradiente de fondo
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.8,
                  colors: [
                    instrument.color.withOpacity(isDarkTheme ? 0.03 : 0.02),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Etiqueta superior
          Positioned(
            top: 12,
            left: 12,
            child: Text(
              instrument.label.toUpperCase(),
              style: GoogleFonts.jetBrainsMono(
                color: isDarkTheme
                    ? Colors.white.withOpacity(0.4)
                    : Colors.black.withOpacity(0.6),
                fontSize: labelFontSize.clamp(8.0, 20.0),
                letterSpacing: 2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Valor y unidad centrados
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    instrument.value,
                    style: GoogleFonts.jetBrainsMono(
                      color: instrument.color,
                      fontSize: valueFontSize,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -5,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  instrument.unit.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    color: isDarkTheme
                        ? instrument.color.withOpacity(0.7)
                        : instrument.color.withOpacity(0.9),
                    fontSize: unitFontSize.clamp(10.0, 24.0),
                    letterSpacing: 4,
                  ),
                ),
                if (isBloodPressure) ...[
                  const SizedBox(height: 8),
                  Text(
                    'PAM ${_calculateMap()}',
                    style: GoogleFonts.jetBrainsMono(
                      color: isDarkTheme
                          ? instrument.color.withOpacity(0.6)
                          : instrument.color.withOpacity(0.8),
                      fontSize: unitFontSize.clamp(8.0, 18.0),
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Icono decorativo
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
