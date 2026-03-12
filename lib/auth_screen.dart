import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_state.dart';

// --- 1. TOKEN VERIFICATION SCREEN ---
class TokenScreen extends StatefulWidget {
  final AppState app;
  const TokenScreen({super.key, required this.app});
  @override
  State<TokenScreen> createState() => _TokenScreenState();
}

class _TokenScreenState extends State<TokenScreen> {
  final TextEditingController _tokenController = TextEditingController();
  bool _isLoading = false;
  String? _errorMsg;

  void _verifyToken() async {
    String token = _tokenController.text.trim().toUpperCase();
    if (token.length != 17 || !RegExp(r'^[A-Z0-9]+$').hasMatch(token)) {
      setState(() => _errorMsg = "Invalid format. Must be 17 characters.");
      return;
    }

    setState(() { _isLoading = true; _errorMsg = null; });
    await widget.app.registerToken(token);
    if (!mounted) return;
    if (widget.app.errorMessage.isNotEmpty) {
      setState(() { _isLoading = false; _errorMsg = widget.app.errorMessage; });
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children:[
                Icon(Icons.lock_outline, size: 80, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 20),
                Text("Device Verification", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 10),
                Text("Enter your 17-digit security token to bind this device.", textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: 40),
                TextField(
                  controller: _tokenController,
                  maxLength: 17, textCapitalization: TextCapitalization.characters,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]'))],
                  style: const TextStyle(fontSize: 20, letterSpacing: 2, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    counterText: "", hintText: "XXXX-XXXX-XXXX-XXXX",
                    hintStyle: TextStyle(letterSpacing: 0, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
                    filled: true, fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)),
                    errorText: _errorMsg,
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity, height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: _isLoading ? null : _verifyToken,
                    child: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text("VERIFY & BIND", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: widget.app.isDarkMode ? Colors.black : Colors.white)),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- 2. REGISTRATION SCREEN (WITH SCROLL WHEELS & VIP PLACEHOLDERS) ---
class RegistrationScreen extends StatefulWidget {
  final AppState app;
  const RegistrationScreen({super.key, required this.app});
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _surController = TextEditingController();
  final TextEditingController _firstController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  
  bool _isLoading = false;

  final List<String> courses =["Medicine", "Mathematics", "Physics", "Biology"];
  final List<String> levels =["100L", "200L", "300L", "400L", "500L", "600L"];
  int _selectedCourseIdx = 0;
  int _selectedLevelIdx = 0;

  void _submitProfile() async {
    if (_surController.text.isEmpty || _firstController.text.isEmpty || !_emailController.text.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields correctly.")));
      return;
    }
    setState(() => _isLoading = true);

    try {
      await widget.app.saveUserProfile(
          _firstController.text.trim(),
          _surController.text.trim(),
          _emailController.text.trim(),
          courses[_selectedCourseIdx],
          levels[_selectedLevelIdx],
      );

      if (!mounted) return;
      if (widget.app.errorMessage.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.app.errorMessage)));
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        String errorMsg = widget.app.errorMessage.isNotEmpty ? widget.app.errorMessage : "Registration failed. Check network.";
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text("Student Profile")),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                Text("Complete Profile", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 5),
                Text("Your verified token will be permanently bound to the course and level you select below.", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: 25),
                
                // VIP PLACEHOLDERS APPLIED HERE
                _buildField("Surname", "e.g., Abuul", _surController, false),
                const SizedBox(height: 15),
                _buildField("First Name", "e.g., Bemdee", _firstController, false),
                const SizedBox(height: 15),
                _buildField("Email Address", "e.g., Orburazipporah@gmail.com", _emailController, true),
                const SizedBox(height: 25),

                // SCROLL WHEELS FOR COURSE & LEVEL
                Text("PROGRAM LOCK", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary, letterSpacing: 1.5)),
                const SizedBox(height: 10),
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Theme.of(context).colorScheme.outline)
                  ),
                  child: Row(
                    children:[
                      // COURSE WHEEL
                      Expanded(
                        flex: 3,
                        child: ListWheelScrollView.useDelegate(
                          itemExtent: 40, physics: const FixedExtentScrollPhysics(), perspective: 0.005,
                          onSelectedItemChanged: (v) { widget.app.playScrollSound(); setState(() => _selectedCourseIdx = v); },
                          childDelegate: ListWheelChildBuilderDelegate(
                            childCount: courses.length,
                            builder: (ctx, i) => Center(child: Text(courses[i], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _selectedCourseIdx == i ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)))),
                          ),
                        ),
                      ),
                      // DIVIDER
                      Container(width: 1, color: Theme.of(context).colorScheme.outline),
                      // LEVEL WHEEL
                      Expanded(
                        flex: 2,
                        child: ListWheelScrollView.useDelegate(
                          itemExtent: 40, physics: const FixedExtentScrollPhysics(), perspective: 0.005,
                          onSelectedItemChanged: (v) { widget.app.playScrollSound(); setState(() => _selectedLevelIdx = v); },
                          childDelegate: ListWheelChildBuilderDelegate(
                            childCount: levels.length,
                            builder: (ctx, i) => Center(child: Text(levels[i], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _selectedLevelIdx == i ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)))),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                
                SizedBox(
                  width: double.infinity, height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: _isLoading ? null : _submitProfile,
                    child: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text("COMPLETE SETUP", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: widget.app.isDarkMode ? Colors.black : Colors.white)),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, String hint, TextEditingController controller, bool isEmail) {
    return TextField(
      controller: controller,
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
        labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
        filled: true, fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)),
      ),
    );
  }
}

// --- 3. ONBOARDING & LOADER SCREENS ---
class SplashLoaderScreen extends StatelessWidget {
  const SplashLoaderScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children:[
            RichText(
              text: TextSpan(
                text: "SYNAPSE", style: TextStyle(fontSize: 45, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                children:[TextSpan(text: ".", style: TextStyle(color: Theme.of(context).colorScheme.primary))],
              ),
            ),
            const SizedBox(height: 30),
            BouncingDots(color: Theme.of(context).colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class BouncingDots extends StatefulWidget {
  final Color color;
  const BouncingDots({super.key, required this.color});
  @override
  State<BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<BouncingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Widget _buildDot(double delay) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        double offset = 0; double phase = (_controller.value - delay) % 1.0;
        if (phase < 0) phase += 1.0;
        if (phase < 0.5) offset = -math.sin(phase * 2 * math.pi) * 15;
        return Transform.translate(offset: Offset(0, offset), child: Container(width: 18, height: 18, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children:[_buildDot(0.0), const SizedBox(width: 15), _buildDot(0.15), const SizedBox(width: 15), _buildDot(0.30)]);
  }
}

class OnboardingScreen extends StatelessWidget {
  final AppState app;
  const OnboardingScreen({super.key, required this.app});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children:[
              const Spacer(),
              Icon(Icons.school_outlined, size: 100, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              Text("Welcome to Synapse.", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Text("Your ultimate exam preparation tool. Tailored precisely to your selected course.", style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)), textAlign: TextAlign.center),
              const Spacer(),
              SizedBox(
                width: double.infinity, height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: app.completeOnboarding,
                  child: Text("START STUDYING", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: app.isDarkMode ? Colors.black : Colors.white)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}