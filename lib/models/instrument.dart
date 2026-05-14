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
    // Try to guess type from keys if not explicitly provided
    String typeStr = json['type']?.toString() ?? '';
    if (typeStr.isEmpty) {
      if (json.containsKey('hr') || json.containsKey('HR'))
        typeStr = 'hr';
      else if (json.containsKey('spo2') || json.containsKey('SpO2'))
        typeStr = 'spo2';
      else if (json.containsKey('bp') || json.containsKey('BP'))
        typeStr = 'bp';
      else if (json.containsKey('temp') || json.containsKey('TEMP'))
        typeStr = 'temp';
    }

    // Try to find value from dynamic keys
    String valueStr = json['value']?.toString() ?? '--';
    if (valueStr == '--') {
      valueStr = (json['hr'] ??
                  json['HR'] ??
                  json['spo2'] ??
                  json['SpO2'] ??
                  json['bp'] ??
                  json['BP'] ??
                  json['temp'] ??
                  json['TEMP'])
              ?.toString() ??
          '--';
    }

    return Instrument(
      id: json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      type: _parseType(typeStr),
      label: json['label']?.toString() ?? _getDefaultLabel(typeStr),
      value: valueStr,
      unit: json['unit']?.toString() ?? _getDefaultUnit(typeStr),
      color:
          _parseColor(json['color']?.toString() ?? _getDefaultColor(typeStr)),
    );
  }

  static String _getDefaultLabel(String type) {
    switch (type.toLowerCase()) {
      case 'hr':
        return 'HEART RATE';
      case 'spo2':
        return 'SpO2';
      case 'bp':
        return 'BLOOD PRESSURE';
      case 'temp':
        return 'TEMP';
      case 'rr':
        return 'RR';
      case 'co2':
        return 'EtCO2';
      default:
        return 'INSTRUMENT';
    }
  }

  static String _getDefaultUnit(String type) {
    switch (type.toLowerCase()) {
      case 'hr':
        return 'BPM';
      case 'spo2':
        return '%';
      case 'bp':
        return 'mmHg';
      case 'temp':
        return '°C';
      case 'rr':
        return '/min';
      default:
        return '';
    }
  }

  static String _getDefaultColor(String type) {
    switch (type.toLowerCase()) {
      case 'hr':
        return '#22c55e';
      case 'spo2':
        return '#3b82f6';
      case 'bp':
        return '#ef4444';
      case 'temp':
        return '#f59e0b';
      default:
        return '#ffffff';
    }
  }

  static InstrumentType _parseType(String? type) {
    switch (type?.toLowerCase()) {
      case 'hr':
        return InstrumentType.hr;
      case 'spo2':
        return InstrumentType.spo2;
      case 'bp':
        return InstrumentType.bp;
      case 'temp':
        return InstrumentType.temp;
      case 'rr':
        return InstrumentType.rr;
      case 'co2':
        return InstrumentType.co2;
      default:
        return InstrumentType.hr;
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
