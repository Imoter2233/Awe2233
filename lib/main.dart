import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// Import our new split files
import 'app_state.dart';
import 'auth_screen.dart';
import 'medical_ui.dart';
import 'science_ui.dart';

const MethodChannel platformChannel = MethodChannel('com.synapse.app/secure');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // INITIALIZE FIREBASE
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  try {
    if (!kIsWeb && Platform.isAndroid) {
      await platformChannel.invokeMethod('enableSecureFlag');
    }
  } catch (e) {
    debugPrint("Failed to secure screen: $e");
  }

  runApp(const SynapseApp());
}

class SynapseApp extends StatefulWidget {
  const SynapseApp({super.key});
  @override
  State<SynapseApp> createState() => _SynapseAppState();
}

class _SynapseAppState extends State<SynapseApp> {
  final AppState state = AppState();

  @override
  void initState() {
    super.initState();
    state.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }

  ThemeData _buildTheme(bool isDark, Color primary) {
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF3F4F6),
      colorScheme: isDark
          ? ColorScheme.dark(
              primary: primary,
              surface: const Color(0xFF111827),
              onSurface: const Color(0xFFF9FAFB),
              outline: const Color(0xFF1F2937),
            )
          : ColorScheme.light(
              primary: primary,
              surface: const Color(0xFFFFFFFF),
              onSurface: const Color(0xFF111827),
              outline: const Color(0xFFE5E7EB),
            ),
      fontFamily: 'Roboto',
    );
  }

  // The Traffic Controller: Routes user based on their locked Course Profile
  Widget _determineStartScreen() {
    if (state.isLoading) return const SplashLoaderScreen();
    
    // If not logged in, show Auth Gatekeeper
    if (!state.isLoggedIn) {
      if (state.userToken.isEmpty) return TokenScreen(app: state);
      return RegistrationScreen(app: state);
    }

    // If logged in, check their registered course to load the correct UI
    if (state.userCourse == "Medicine") {
      return MedicalMainScreen(app: state); // The old UI
    } else {
      return ScienceMainScreen(app: state); // The new Math/Bio UI
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(state.isDarkMode, state.currentPrimaryColor),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: _determineStartScreen(),
      ),
    );
  }
}