import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/ble_peripheral_provider.dart';
import '../models/instrument.dart';

class MonitorScreen extends StatelessWidget {
  const MonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onDoubleTap: () => Navigator.pop(context),
        child: Consumer<BLEPeripheralProvider>(
          builder: (context, provider, child) {
            if (provider.instruments.isEmpty) {
              return const Center(
                child: Text(
                  'WAITING FOR TELEMETRY...',
                  style: TextStyle(color: Colors.white24, letterSpacing: 4),
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final count = provider.instruments.length;
                int crossAxisCount = 1;

                if (count > 4) {
                  crossAxisCount = 3;
                } else if (count > 1) {
                  crossAxisCount = 2;
                }

                final double itemWidth = constraints.maxWidth / crossAxisCount;
                final int rowCount = (count / crossAxisCount).ceil();
                final double itemHeight = constraints.maxHeight / rowCount;
                final double ratio = itemWidth / itemHeight;

                return GridView.builder(
                  padding: const EdgeInsets.all(2),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: ratio,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                  ),
                  itemCount: count,
                  itemBuilder: (context, index) {
                    return _InstrumentCard(
                        instrument: provider.instruments[index]);
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _InstrumentCard extends StatelessWidget {
  final Instrument instrument;

  const _InstrumentCard({required this.instrument});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.white.withOpacity(0.05)),
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
                    instrument.color.withOpacity(0.03),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 24,
            left: 24,
            child: Text(
              instrument.label.toUpperCase(),
              style: GoogleFonts.jetBrainsMono(
                color: Colors.white.withOpacity(0.4),
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w500,
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
                    instrument.value,
                    style: GoogleFonts.jetBrainsMono(
                      color: instrument.color,
                      fontSize: 120,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -5,
                    ),
                  ),
                ),
                Text(
                  instrument.unit.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    color: Colors.white.withOpacity(0.2),
                    fontSize: 16,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
          const Positioned(
            bottom: 24,
            right: 24,
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
