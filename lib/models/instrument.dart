import 'package:flutter/material.dart';

enum InstrumentType { hr, spo2, bp, temp, rr, co2 }

class Instrument {
  final String id;
  final InstrumentType type;
  final String label;
  final String value;
  final String unit;
  final Color color;

  Instrument({
    required this.id,
    required this.type,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  factory Instrument.fromJson(Map<String, dynamic> json) {
    return Instrument(
      id: json['id'] ?? '',
      type: _parseType(json['type']),
      label: json['label'] ?? '',
      value: json['value']?.toString() ?? '--',
      unit: json['unit'] ?? '',
      color: _parseColor(json['color']),
    );
  }

  static InstrumentType _parseType(String? type) {
    switch (type?.toLowerCase()) {
      case 'hr': return InstrumentType.hr;
      case 'spo2': return InstrumentType.spo2;
      case 'bp': return InstrumentType.bp;
      case 'temp': return InstrumentType.temp;
      case 'rr': return InstrumentType.rr;
      case 'co2': return InstrumentType.co2;
      default: return InstrumentType.hr;
    }
  }

  static Color _parseColor(String? colorHex) {
    if (colorHex == null) return Colors.green;
    try {
      return Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
    } catch (e) {
      return Colors.green;
    }
  }
}
