// main.dart
// Cloud-ready Flutter entry — CloudService (YOLO + CNN + Gemini)
// Flutter 3.35+ / Gradle 8.9 / Kotlin 1.9+ compatible

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

// Screens
import 'welcome_screen.dart';
import 'homepage.dart';
import 'service_page.dart';
import 'about_page.dart';
import 'portfolio_page.dart';
import 'contact_page.dart';
import 'blog_page.dart';
import 'settings_page.dart';

// Providers / Services
import 'settings_provider.dart';
import 'cloud_service.dart'; // ✅ Unified backend service

// Shared CloudService instance
final CloudService _cloud = CloudService();

/// Initializes Firebase, permissions, and Cloud backend
Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔹 Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🔹 Orientation & style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 🔹 Camera permission
  final camStatus = await Permission.camera.request();
  if (!camStatus.isGranted) {
    debugPrint('⚠️ Camera permission not granted.');
  }

  // 🔹 CloudService init
  try {
    await _cloud.initialize();
    debugPrint(_cloud.isReady
        ? '✅ Cloud service initialized.'
        : '⚠️ Cloud backend not ready.');
  } catch (e, st) {
    debugPrint('❌ Cloud init failed: $e\n$st');
  }
}

Future<void> main() async {
  await _bootstrap();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider<CloudService>.value(value: _cloud),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    final theme = ThemeData(
      useMaterial3: false,
      colorSchemeSeed: const Color(0xFF1B5E20),
      brightness: settings.isDarkMode ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor:
          settings.isDarkMode ? Colors.black : Colors.white,
      fontFamily: 'Inter',
      appBarTheme: AppBarTheme(
        backgroundColor:
            settings.isDarkMode ? Colors.grey[900] : const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        elevation: 2,
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CropEye',
      theme: theme,
      home: const _BootstrapGate(child: WelcomeScreen()),
      routes: {
        '/home': (_) => const HomePage(),
        '/service': (_) => const ServiceSection(),
        '/about': (_) => const AboutSection(),
        '/portfolio': (_) => const PortfolioSection(),
        '/contact': (_) => const ContactPage(),
        '/blog': (_) => const BlogSection(),
        '/settings': (_) => const SettingsPage(),
      },
      onUnknownRoute: (_) =>
          MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }
}

class _BootstrapGate extends StatefulWidget {
  final Widget child;
  const _BootstrapGate({required this.child});

  @override
  State<_BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<_BootstrapGate> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
    setState(() {
      _ready = false;
      _error = null;
    });

    try {
      final cloud = context.read<CloudService>();
      if (!cloud.isReady) {
        await cloud.initialize();
      }
      setState(() => _ready = cloud.isReady);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;

    return Scaffold(
      body: Center(
        child: _error == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  SizedBox(height: 14),
                  Text('Initializing AI Service...'),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 36, color: Colors.red),
                  const SizedBox(height: 8),
                  const Text(
                    'Service Initialization Failed',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _initializeService,
                    child: const Text('Retry'),
                  ),
                ],
              ),
      ),
    );
  }
}
