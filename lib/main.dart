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

  // SECURITY: Prevent screen recording and screenshots on Android
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
    state.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
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

  // STRICT ROUTING GATEKEEPER
  Widget _determineStartScreen() {
    // 1. GLOBAL LOADING STATE
    if (state.isLoading) {
      return const SplashLoaderScreen();
    }
    
    // 2. AUTHENTICATION GATEKEEPER
    // If the security engine triggers _executeRemoteWipe, isLoggedIn becomes false.
    if (!state.isLoggedIn) {
      if (state.userToken.isEmpty) {
        return TokenScreen(app: state);
      }
      return RegistrationScreen(app: state);
    }

    // 3. STRICT COURSE & LEVEL ROUTING
    // Security overlays (Sync Required) are handled within these screens.
    if (state.userCourse == "Medicine" && state.userLevel == "200L") {
      return MedicalMainScreen(app: state); 
    } else if (state.userCourse == "Medicine" && state.userLevel == "100L") {
      return ScienceMainScreen(app: state); 
    } else {
      // Fallback for unconfigured combinations
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Text(
              "Curriculum for ${state.userCourse} ${state.userLevel} is currently unavailable.",
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(state.isDarkMode, state.currentPrimaryColor),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeIn,
        switchOutCurve: Curves.easeOut,
        child: _determineStartScreen(),
      ),
    );
  }
}

// --- REUSABLE SPLASH LOADER ---
class SplashLoaderScreen extends StatelessWidget {
  const SplashLoaderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children:[
            const Icon(Icons.psychology, size: 80, color: Colors.orange),
            const SizedBox(height: 20),
            RichText(
              text: const TextSpan(
                text: "SYNAPSE",
                style: TextStyle(
                  fontSize: 28, 
                  fontWeight: FontWeight.bold, 
                  color: Colors.white,
                  letterSpacing: 2.0,
                ),
                children:[
                  TextSpan(text: ".", style: TextStyle(color: Colors.orange)),
                ],
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: Colors.orange),
          ],
        ),
      ),
    );
  }
}