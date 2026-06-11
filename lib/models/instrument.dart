import 'package:flutter/material.dart';

enum InstrumentType { hr, spo2, bp, temp, rr, co2, glu, unknown }

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
    String typeStr = json['type']?.toString() ?? '';

    if (typeStr.isEmpty) {
      if (json.containsKey('hr') || json.containsKey('HR')) {
        typeStr = 'hr';
      } else if (json.containsKey('spo2') || json.containsKey('SpO2')) {
        typeStr = 'spo2';
      } else if (json.containsKey('bp') || json.containsKey('BP')) {
        typeStr = 'bp';
      } else if (json.containsKey('temp') || json.containsKey('TEMP')) {
        typeStr = 'temp';
      } else if (json.containsKey('rr') || json.containsKey('RR')) {
        typeStr = 'rr';
      } else if (json.containsKey('resp') || json.containsKey('RESP')) {
        typeStr = 'resp';
      } else if (json.containsKey('co2') || json.containsKey('CO2')) {
        typeStr = 'co2';
      } else if (json.containsKey('glu') ||
          json.containsKey('GLU') ||
          json.containsKey('glucose') ||
          json.containsKey('glucemia')) {
        typeStr = 'glu';
      }
    }

    String valueStr = json['value']?.toString() ?? '--';

    if (valueStr == '--') {
      valueStr = (json['hr'] ??
                  json['HR'] ??
                  json['spo2'] ??
                  json['SpO2'] ??
                  json['bp'] ??
                  json['BP'] ??
                  json['temp'] ??
                  json['TEMP'] ??
                  json['rr'] ??
                  json['RR'] ??
                  json['resp'] ??
                  json['RESP'] ??
                  json['co2'] ??
                  json['CO2'] ??
                  json['glu'] ??
                  json['GLU'] ??
                  json['glucose'] ??
                  json['glucemia'])
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
      case 'fc':
        return 'HEART RATE';
      case 'spo2':
        return 'SpO2';
      case 'bp':
      case 'pani':
      case 'pai':
        return 'BLOOD PRESSURE';
      case 'temp':
      case 'temperature':
      case 'temperatura':
        return 'TEMP';
      case 'rr':
      case 'resp':
      case 'fr':
        return 'RR';
      case 'co2':
      case 'etco2':
        return 'EtCO2';
      case 'glu':
      case 'glucose':
      case 'glucemia':
        return 'GLUCEMIA';
      default:
        return 'INSTRUMENT';
    }
  }

  static String _getDefaultUnit(String type) {
    switch (type.toLowerCase()) {
      case 'hr':
      case 'fc':
        return 'LPM';
      case 'spo2':
        return '%';
      case 'bp':
      case 'pani':
      case 'pai':
        return 'mmHg';
      case 'temp':
      case 'temperature':
      case 'temperatura':
        return '°C';
      case 'rr':
      case 'resp':
      case 'fr':
        return '/min';
      case 'co2':
      case 'etco2':
        return 'mmHg';
      case 'glu':
      case 'glucose':
      case 'glucemia':
        return 'mg/dL';
      default:
        return '';
    }
  }

  static String _getDefaultColor(String type) {
    switch (type.toLowerCase()) {
      case 'hr':
      case 'fc':
        return '#22c55e';
      case 'spo2':
        return '#3b82f6';
      case 'bp':
      case 'pani':
      case 'pai':
        return '#ef4444';
      case 'temp':
      case 'temperature':
      case 'temperatura':
        return '#f59e0b';
      case 'rr':
      case 'resp':
      case 'fr':
        return '#eab308';
      case 'co2':
      case 'etco2':
        return '#a855f7';
      case 'glu':
      case 'glucose':
      case 'glucemia':
        return '#f97316';
      default:
        return '#ffffff';
    }
  }

  static InstrumentType _parseType(String? type) {
    switch (type?.toLowerCase()) {
      case 'hr':
      case 'fc':
      case 'lpm':
        return InstrumentType.hr;
      case 'spo2':
        return InstrumentType.spo2;
      case 'bp':
      case 'pani':
      case 'pai':
      case 'pani/pai':
        return InstrumentType.bp;
      case 'temp':
      case 'temperature':
      case 'temperatura':
        return InstrumentType.temp;
      case 'rr':
      case 'resp':
      case 'fr':
        return InstrumentType.rr;
      case 'co2':
      case 'etco2':
        return InstrumentType.co2;
      case 'glu':
      case 'glucose':
      case 'glucemia':
        return InstrumentType.glu;
      default:
        return InstrumentType.unknown;
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
