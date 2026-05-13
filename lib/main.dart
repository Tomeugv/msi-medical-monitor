import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'providers/monitor_provider.dart';
import 'screens/connection_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MonitorProvider()),
      ],
      child: const MSIMonitorApp(),
    ),
  );
}

class MSIMonitorApp extends StatelessWidget {
  const MSIMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MSI Medical Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
          background: Colors.black,
        ),
        useMaterial3: true,
      ),
      home: const ConnectionScreen(),
    );
  }
}
