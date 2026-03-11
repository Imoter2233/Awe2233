// ============================================================================
// FILE: main.dart
// PROJECT: SYNAPSE - MEDICAL PAST QUESTIONS (FLUTTER EDITION)
// UPGRADE: LIVE FIREBASE AUTH, DEVICE BINDING, SECURE PROFILES
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

// --- FIREBASE IMPORTS ---
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'firebase_options.dart';

// ----------------------------------------------------------------------------
// 1. CONSTANTS & KEYS
// ----------------------------------------------------------------------------
const String csvUrl =
    "https://raw.githubusercontent.com/Imoter2233/Awe2233/main/data.csv";
const String themeKey = "synapse_theme_mode";
const String colorIndexKey = "synapse_color_index";
const String soundPrefKey = "synapse_sound_pref";
const String volumePrefKey = "synapse_volume_pref";
const String firstRunKey = "synapse_first_run";
const String cacheFileName = "synapse_offline_db.json";

// Auth Keys
const String isLoggedInKey = "synapse_is_logged_in";
const String userTokenKey = "synapse_user_token";
const String uniqueIdKey = "synapse_unique_id";
const String firstNameKey = "synapse_first_name";
const String surnameKey = "synapse_surname";
const String emailKey = "synapse_email";
const String welcomeSeenKey = "synapse_welcome_seen";

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

// ----------------------------------------------------------------------------
// 2. DATA MODELS
// ----------------------------------------------------------------------------
class RootItem {
  final String id;
  final String text;
  final String answer;
  final String info;

  RootItem(
      {required this.id,
      required this.text,
      required this.answer,
      required this.info});

  Map<String, dynamic> toJson() =>
      {'id': id, 'text': text, 'answer': answer, 'info': info};
  factory RootItem.fromJson(Map<String, dynamic> json) => RootItem(
        id: json['id'] ?? '',
        text: json['text'] ?? '',
        answer: json['answer'] ?? '',
        info: json['info'] ?? '',
      );
}

class QuestionModel {
  final String id;
  final String subject;
  final String topic;
  final String year;
  final String stem;
  final List<RootItem> roots;

  QuestionModel({
    required this.id,
    required this.subject,
    required this.topic,
    required this.year,
    required this.stem,
    required this.roots,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'topic': topic,
        'year': year,
        'stem': stem,
        'roots': roots.map((r) => r.toJson()).toList(),
      };

  factory QuestionModel.fromJson(Map<String, dynamic> json) => QuestionModel(
        id: json['id'] ?? '',
        subject: json['subject'] ?? '',
        topic: json['topic'] ?? '',
        year: json['year'] ?? '',
        stem: json['stem'] ?? '',
        roots: (json['roots'] as List?)
                ?.map((r) => RootItem.fromJson(r))
                .toList() ??
            [],
      );
}

// ----------------------------------------------------------------------------
// 3. BACKGROUND ISOLATE PARSERS
// ----------------------------------------------------------------------------
List<QuestionModel> _decodeCsvInBackground(String csvText) {
  List<QuestionModel> newDB = [];
  try {
    String cleanCsv = csvText.replaceAll(RegExp(r'^\xEF\xBB\xBF|\uFEFF'), '');
    cleanCsv = cleanCsv.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    List<List<dynamic>> rows = const CsvToListConverter(eol: '\n')
        .convert(cleanCsv, shouldParseNumbers: false);

    if (rows.isNotEmpty) {
      List<String> headers =
          rows[0].map((e) => e.toString().trim().toLowerCase()).toList();

      for (int r = 1; r < rows.length; r++) {
        var row = rows[r];
        Map<String, String> dict = {};
        for (int c = 0; c < headers.length; c++) {
          if (c < row.length) dict[headers[c]] = row[c].toString().trim();
        }

        if (!dict.containsKey('id') || dict['id']!.isEmpty) {
          continue;
        }
        String qId = dict['id']!;
        List<RootItem> roots = [];

        for (int i = 1; i <= 5; i++) {
          String text = dict['r${i}_text'] ?? "";
          if (text.isNotEmpty) {
            String rawAns = (dict['r${i}_ans'] ?? dict['r${i}ans'] ?? "")
                .trim()
                .toUpperCase();
            String ans = rawAns.isNotEmpty ? rawAns.substring(0, 1) : "";
            String info = dict['r${i}_info'] ?? "";
            roots.add(
                RootItem(id: "${qId}_$i", text: text, answer: ans, info: info));
          }
        }

        newDB.add(QuestionModel(
          id: qId,
          subject: dict['subject'] ?? "",
          topic: dict['topic'] ?? "Uncategorized",
          year: dict['year'] ?? "",
          stem: dict['stem'] ?? "",
          roots: roots,
        ));
      }
    }
  } catch (e) {
    debugPrint("Background Parse Error: $e");
  }
  return newDB;
}

List<QuestionModel> _decodeJsonCacheInBackground(String jsonStr) {
  try {
    List<dynamic> parsed = jsonDecode(jsonStr);
    return parsed.map((e) => QuestionModel.fromJson(e)).toList();
  } catch (e) {
    return [];
  }
}

String _encodeJsonCacheInBackground(List<QuestionModel> data) {
  return jsonEncode(data.map((e) => e.toJson()).toList());
}

// ----------------------------------------------------------------------------
// 4. APP STATE MANAGEMENT (WITH LIVE FIREBASE)
// ----------------------------------------------------------------------------
class AppState extends ChangeNotifier {
  bool isDarkMode = true;
  int themeColorIndex = 0;
  bool isFirstRun = true;
  bool isLoading = true;

  // Sound Config
  bool soundEnabled = true;
  double soundVolume = 0.5;
  double accumulatedScroll = 0.0;

  // Auth & Profile Data
  bool isLoggedIn = false;
  String userToken = "";
  String uniqueId = "";
  String firstName = "";
  String surname = "";
  String email = "";
  bool hasSeenWelcome = false;

  String errorMessage = "";

  List<QuestionModel> fullDB = [];
  List<QuestionModel> filteredDB = [];

  String searchText = "";
  List<String> activeTopics = [];
  List<String> allTopics = [];

  Map<String, List<String>> activeTopicYears = {};

  int currentPage = 1;
  int itemsPerPage = 5;
  int get totalPages => (filteredDB.length / itemsPerPage).ceil();

  bool isExamMode = false;
  Map<String, String> userAnswers = {};
  Map<String, bool> studyRevealed = {};
  Map<String, bool> explanationRevealed = {};

  Timer? _timer;
  int timeLeftSeconds = 0;
  int finalScore = 0;
  Map<String, Map<String, int>> topicPerformance = {};

  final List<Color> availableColors = [
    const Color(0xFFF59E0B),
    const Color(0xFF14B8A6),
    const Color(0xFF8B5CF6),
  ];

  Color get currentPrimaryColor => availableColors[themeColorIndex];

  AppState() {
    initData();
  }

  Future<void> initData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    isDarkMode = prefs.getBool(themeKey) ?? true;
    themeColorIndex = prefs.getInt(colorIndexKey) ?? 0;
    soundEnabled = prefs.getBool(soundPrefKey) ?? true;
    soundVolume = prefs.getDouble(volumePrefKey) ?? 0.5;
    isFirstRun = prefs.getBool(firstRunKey) ?? true;

    // Load Auth Data
    isLoggedIn = prefs.getBool(isLoggedInKey) ?? false;
    userToken = prefs.getString(userTokenKey) ?? "";
    uniqueId = prefs.getString(uniqueIdKey) ?? "";
    firstName = prefs.getString(firstNameKey) ?? "";
    surname = prefs.getString(surnameKey) ?? "";
    email = prefs.getString(emailKey) ?? "";
    hasSeenWelcome = prefs.getBool(welcomeSeenKey) ?? false;

    await _loadLocalFileCache();
    _fetchFromServer();
  }

  // Helper to get device hardware ID
  Future<String> _getDeviceId() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id;
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? "unknown_ios_device";
    }
    return "unknown_device";
  }

  // --- LIVE FIREBASE TOKEN VERIFICATION ---
  Future<void> registerToken(String token) async {
    try {
      errorMessage = "";

      // 1. Check Firestore for the Token
      DocumentSnapshot tokenDoc = await FirebaseFirestore.instance
          .collection('tokens')
          .doc(token)
          .get();

      if (!tokenDoc.exists) {
        errorMessage = "Invalid Token. Please verify and try again.";
        notifyListeners();
        return;
      }

      Map<String, dynamic> data = tokenDoc.data() as Map<String, dynamic>;
      bool isUsed = data['isUsed'] ?? false;
      String deviceId = await _getDeviceId();

      // 2. Security Check: Is it already used by someone else?
      if (isUsed) {
        String boundDevice = data['boundDeviceId'] ?? "";
        if (boundDevice != deviceId) {
          errorMessage =
              "Security Alert: Token already bound to another device.";
          notifyListeners();
          return;
        }
      } else {
        // 3. Bind Device to Token immediately to lock it
        await FirebaseFirestore.instance
            .collection('tokens')
            .doc(token)
            .update({
          'boundDeviceId': deviceId,
        });
      }

      // Success! Proceed to next screen
      SharedPreferences prefs = await SharedPreferences.getInstance();
      userToken = token;
      await prefs.setString(userTokenKey, token);
      notifyListeners();
    } catch (e) {
      errorMessage = "Connection error. Ensure you have internet access.";
      notifyListeners();
    }
  }

  // --- LIVE FIREBASE PROFILE CREATION ---
  Future<void> saveUserProfile(String fName, String sName, String mail) async {
    try {
      errorMessage = "";
      String deviceId = await _getDeviceId();

      // Generate Unique ID
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      math.Random rnd = math.Random();
      String randomStr = String.fromCharCodes(Iterable.generate(
          4, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
      String newUniqueId = "${fName.trim().toUpperCase()}-$randomStr";

      // Create User in Firebase Auth (Using their secure token as their password behind the scenes)
      UserCredential userCred =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: mail,
        password: userToken,
      );

      // Send Firebase Email Verification
      await userCred.user?.sendEmailVerification();

      // Create Student Record in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCred.user!.uid)
          .set({
        'firstName': fName.trim(),
        'surname': sName.trim(),
        'email': mail.trim(),
        'uniqueId': newUniqueId,
        'deviceId': deviceId,
        'boundToken': userToken,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Mark Token as officially USED
      await FirebaseFirestore.instance
          .collection('tokens')
          .doc(userToken)
          .update({
        'isUsed': true,
        'usedByUid': userCred.user!.uid,
      });

      // Save locally
      firstName = fName.trim();
      surname = sName.trim();
      email = mail.trim();
      uniqueId = newUniqueId;
      isLoggedIn = true;

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(firstNameKey, firstName);
      await prefs.setString(surnameKey, surname);
      await prefs.setString(emailKey, email);
      await prefs.setString(uniqueIdKey, uniqueId);
      await prefs.setBool(isLoggedInKey, true);
      notifyListeners();
    } catch (e) {
      if (e is FirebaseAuthException && e.code == 'email-already-in-use') {
        errorMessage = "Email is already registered. Please contact admin.";
      } else {
        errorMessage = "Failed to create profile. Check your connection.";
      }
      notifyListeners();
      rethrow;
    }
  }

  void markWelcomeSeen() async {
    hasSeenWelcome = true;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(welcomeSeenKey, true);
  }

  void completeOnboarding() async {
    isFirstRun = false;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(firstRunKey, false);
  }

  void logOut() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await FirebaseAuth.instance.signOut();
    isLoggedIn = false;
    userToken = "";
    notifyListeners();
  }

  // --- CORE DATA & SETTINGS LOGIC ---
  Future<void> _loadLocalFileCache() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$cacheFileName');

      if (await file.exists()) {
        String jsonStr = await file.readAsString();
        if (jsonStr.isNotEmpty) {
          fullDB = await compute(_decodeJsonCacheInBackground, jsonStr);
          _setupData();
          isLoading = false;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("File Cache Read Error: $e");
    }
  }

  Future<void> _fetchFromServer() async {
    try {
      final response = await http
          .get(Uri.parse(csvUrl))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        List<QuestionModel> parsed =
            await compute(_decodeCsvInBackground, response.body);
        if (parsed.isNotEmpty) {
          errorMessage = "";
          if (parsed.length != fullDB.length || fullDB.isEmpty) {
            fullDB = parsed;
            _setupData();
            final directory = await getApplicationDocumentsDirectory();
            final file = File('${directory.path}/$cacheFileName');
            String newCacheStr =
                await compute(_encodeJsonCacheInBackground, fullDB);
            await file.writeAsString(newCacheStr, flush: true);
          }
        } else {
          errorMessage =
              "CSV fetched but 0 questions parsed. Check column headers.";
        }
      } else {
        errorMessage =
            "Network Error ${response.statusCode}: Failed to fetch GitHub CSV.";
      }
    } catch (e) {
      if (fullDB.isEmpty)
        { errorMessage = "Connection failed. Please check internet."; }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void toggleThemeMode() async {
    isDarkMode = !isDarkMode;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(themeKey, isDarkMode);
  }

  void setThemeColor(int index) async {
    themeColorIndex = index;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(colorIndexKey, themeColorIndex);
  }

  void toggleSound(bool val) async {
    soundEnabled = val;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(soundPrefKey, soundEnabled);
  }

  void setVolume(double val) async {
    soundVolume = val;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(volumePrefKey, soundVolume);
  }

  void playScrollSound() {
    if (soundEnabled) {
      HapticFeedback.selectionClick();
      SystemSound.play(SystemSoundType.click);
    }
  }

  void trackScrollTick(double delta) {
    if (!soundEnabled) {
      return;
    }
    accumulatedScroll += delta.abs();
    double threshold = 100.0 - (soundVolume * 70.0);
    if (accumulatedScroll > threshold) {
      playScrollSound();
      accumulatedScroll = 0.0;
    }
  }

  void _setupData() {
    Set<String> uniqueTopics = {};
    for (var q in fullDB) {
      if (q.topic.isNotEmpty) uniqueTopics.add(q.topic);
    }
    allTopics = uniqueTopics.toList()..sort();
    applyFilters();
  }

  void applyFilters() {
    filteredDB = fullDB.where((q) {
      bool searchMatch = searchText.isEmpty ||
          q.stem.toLowerCase().contains(searchText.toLowerCase()) ||
          q.topic.toLowerCase().contains(searchText.toLowerCase());

      bool topicMatch = true;
      if (activeTopics.isNotEmpty) {
        if (!activeTopics.contains(q.topic)) {
          topicMatch = false;
        } else {
          List<String>? enforcedYears = activeTopicYears[q.topic];
          if (enforcedYears != null && enforcedYears.isNotEmpty) {
            if (!enforcedYears.contains(q.year)) {
              topicMatch = false;
            }
          }
        }
      }
      return topicMatch && searchMatch;
    }).toList();

    currentPage = 1;
    notifyListeners();
  }

  void applyFiltersWith(List<String> tempFilters) {
    activeTopics = List.from(tempFilters);
    activeTopicYears.removeWhere((key, value) => !activeTopics.contains(key));
    applyFilters();
  }

  void removeFilter(String topic) {
    activeTopics.remove(topic);
    activeTopicYears.remove(topic);
    applyFilters();
  }

  void toggleYearForTopic(String topic, String year) {
    activeTopicYears.putIfAbsent(topic, () => []);
    if (activeTopicYears[topic]!.contains(year)) {
      activeTopicYears[topic]!.remove(year);
    } else {
      activeTopicYears[topic]!.add(year);
    }
    applyFilters();
  }

  void clearYearsForTopic(String topic) {
    activeTopicYears[topic] = [];
    applyFilters();
  }

  void setPage(int page) {
    if (page >= 1 && page <= totalPages) {
      currentPage = page;
      notifyListeners();
    }
  }

  void startExam(int minutes) {
    isExamMode = true;
    userAnswers.clear();
    timeLeftSeconds = minutes * 60;
    currentPage = 1;
    applyFilters();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (timeLeftSeconds > 0) {
        timeLeftSeconds--;
        notifyListeners();
      } else {
        submitExam();
      }
    });
    notifyListeners();
  }

  void submitExam() {
    _timer?.cancel();
    int correct = 0, total = 0;
    topicPerformance = {};

    for (var q in filteredDB) {
      if (!topicPerformance.containsKey(q.topic)) {
        topicPerformance[q.topic] = {'total': 0, 'correct': 0};
      }
      for (var r in q.roots) {
        total++;
        topicPerformance[q.topic]!['total'] =
            (topicPerformance[q.topic]!['total'] ?? 0) + 1;
        if (userAnswers[r.id] == r.answer) {
          correct++;
          topicPerformance[q.topic]!['correct'] =
              (topicPerformance[q.topic]!['correct'] ?? 0) + 1;
        }
      }
    }
    finalScore = total > 0 ? ((correct / total) * 100).toInt() : 0;
    notifyListeners();
  }

  void exitExamMode() {
    _timer?.cancel();
    isExamMode = false;
    userAnswers.clear();
    currentPage = 1;
    notifyListeners();
  }

  void handleDotClick(String rootId, String actualAns) {
    if (!isExamMode) {
      studyRevealed[rootId] = !(studyRevealed[rootId] ?? false);
    } else {
      String current = userAnswers[rootId] ?? "";
      if (current == "") {
        userAnswers[rootId] = "T";
      } else if (current == "T") {
        userAnswers[rootId] = "F";
      } else {
        userAnswers.remove(rootId);
      }
    }
    notifyListeners();
  }

  void toggleExplanation(String rootId) {
    explanationRevealed[rootId] = !(explanationRevealed[rootId] ?? false);
    notifyListeners();
  }

  bool isQuestionRevealed(String qId) {
    var q = filteredDB.firstWhere((q) => q.id == qId);
    for (var r in q.roots) {
      if (studyRevealed[r.id] == true) return true;
    }
    return false;
  }

  void toggleAllAnswersForQuestion(String questionId) {
    bool currentlyRevealed = isQuestionRevealed(questionId);
    var question = filteredDB.firstWhere((q) => q.id == questionId);
    for (var r in question.roots) {
      studyRevealed[r.id] = !currentlyRevealed;
    }
    notifyListeners();
  }
}

// ----------------------------------------------------------------------------
// 5. MAIN APP WIDGET
// ----------------------------------------------------------------------------
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
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF000000) : const Color(0xFFF3F4F6),
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

  Widget _determineStartScreen() {
    if (state.isLoading) return const SplashLoaderScreen();
    if (!state.isLoggedIn) {
      if (state.userToken.isEmpty) return TokenScreen(app: state);
      return RegistrationScreen(app: state);
    }
    if (state.isFirstRun) return OnboardingScreen(app: state);
    return MainScreen(app: state);
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

// ----------------------------------------------------------------------------
// 6. AUTHENTICATION & ONBOARDING SCREENS
// ----------------------------------------------------------------------------

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
      setState(() =>
          _errorMsg = "Invalid format. Must be 17 alphanumeric characters.");
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    // Call Live Firebase Action
    await widget.app.registerToken(token);

    // Check if Firebase threw an error
    if (widget.app.errorMessage.isNotEmpty) {
      setState(() {
        _isLoading = false;
        _errorMsg = widget.app.errorMessage;
      });
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
              children: [
                Icon(Icons.lock_outline,
                    size: 80, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 20),
                Text("Device Verification",
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 10),
                Text("Enter your 17-digit security token to bind this device.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6))),
                const SizedBox(height: 40),
                TextField(
                  controller: _tokenController,
                  maxLength: 17,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]'))
                  ],
                  style: const TextStyle(
                      fontSize: 20,
                      letterSpacing: 2,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    counterText: "",
                    hintText: "XXXX-XXXX-XXXX-XXXX",
                    hintStyle: TextStyle(
                        letterSpacing: 0,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.3)),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.outline)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.outline)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2)),
                    errorText: _errorMsg,
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isLoading ? null : _verifyToken,
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text("VERIFY & BIND",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: widget.app.isDarkMode
                                    ? Colors.black
                                    : Colors.white)),
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

  void _submitProfile() async {
    if (_surController.text.isEmpty ||
        _firstController.text.isEmpty ||
        !_emailController.text.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please fill all fields correctly.")));
      return;
    }
    setState(() => _isLoading = true);

    try {
      // Call Live Firebase Action
      await widget.app.saveUserProfile(_firstController.text.trim(),
          _surController.text.trim(), _emailController.text.trim());
      if (!mounted) {
        return;
      }
      if (widget.app.errorMessage.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(widget.app.errorMessage)));
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text("Student Profile")),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Complete Profile",
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 5),
                Text("Your verified token is bound. Set up your details.",
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6))),
                const SizedBox(height: 30),
                _buildField("Surname", _surController, false),
                const SizedBox(height: 15),
                _buildField("First Name", _firstController, false),
                const SizedBox(height: 15),
                _buildField("Email Address", _emailController, true),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isLoading ? null : _submitProfile,
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text("COMPLETE SETUP",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: widget.app.isDarkMode
                                    ? Colors.black
                                    : Colors.white)),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
      String label, TextEditingController controller, bool isEmail) {
    return TextField(
      controller: controller,
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: Theme.of(context).colorScheme.outline)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: Theme.of(context).colorScheme.outline)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary, width: 2)),
      ),
    );
  }
}

class SplashLoaderScreen extends StatelessWidget {
  const SplashLoaderScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RichText(
              text: TextSpan(
                text: "SYNAPSE",
                style: TextStyle(
                    fontSize: 45,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface),
                children: [
                  TextSpan(
                      text: ".",
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary))
                ],
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

class _BouncingDotsState extends State<BouncingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildDot(double delay) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        double offset = 0;
        double phase = (_controller.value - delay) % 1.0;
        if (phase < 0) phase += 1.0;
        if (phase < 0.5) offset = -math.sin(phase * 2 * math.pi) * 15;

        return Transform.translate(
          offset: Offset(0, offset),
          child: Container(
            width: 18,
            height: 18,
            decoration:
                BoxDecoration(color: widget.color, shape: BoxShape.circle),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildDot(0.0),
        const SizedBox(width: 15),
        _buildDot(0.15),
        const SizedBox(width: 15),
        _buildDot(0.30)
      ],
    );
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
            children: [
              const Spacer(),
              Icon(Icons.school_outlined,
                  size: 100, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              Text("Welcome to Synapse.",
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Text(
                  "Your ultimate medical exam preparation tool. Select topics, study answers, and ace your boards.",
                  style: TextStyle(
                      fontSize: 15,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6)),
                  textAlign: TextAlign.center),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: app.completeOnboarding,
                  child: Text("START STUDYING",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: app.isDarkMode ? Colors.black : Colors.white)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 7. MAIN FEED SCREEN
// ----------------------------------------------------------------------------
class MainScreen extends StatefulWidget {
  final AppState app;
  const MainScreen({super.key, required this.app});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _pageScrollController = ScrollController();
  bool _showBanner = true;

  @override
  void initState() {
    super.initState();
    _showBanner = !widget.app.hasSeenWelcome;
  }

  void _changePage(int newPage) {
    widget.app.setPage(newPage);
    if (_pageScrollController.hasClients) {
      double offset = (newPage - 1) * 44.0;
      _pageScrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _showYearSelectorBottomSheet(
      BuildContext context, AppState app, String topic) {
    List<String> availableYears = app.fullDB
        .where((q) => q.topic == topic && q.year.isNotEmpty)
        .map((q) => q.year)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
            List<String> currentSelectedYears =
                app.activeTopicYears[topic] ?? [];
            bool isAllYears = currentSelectedYears.isEmpty;

            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    height: 5,
                    width: 40,
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outline,
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text("Filter Years for $topic",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  Flexible(
                    child: NotificationListener<ScrollUpdateNotification>(
                      onNotification: (notif) {
                        app.trackScrollTick(notif.scrollDelta ?? 0);
                        return false;
                      },
                      child: ListView(
                        shrinkWrap: true,
                        physics: const BouncingScrollPhysics(),
                        children: [
                          CheckboxListTile(
                            checkColor:
                                app.isDarkMode ? Colors.black : Colors.white,
                            title: Text("All Years",
                                style: TextStyle(
                                    fontWeight: isAllYears
                                        ? FontWeight.bold
                                        : FontWeight.normal)),
                            value: isAllYears,
                            onChanged: (bool? value) {
                              if (value == true) {
                                app.clearYearsForTopic(topic);
                                setModalState(() {});
                              }
                            },
                          ),
                          const Divider(height: 1),
                          ...availableYears.map((year) {
                            bool isSelected =
                                currentSelectedYears.contains(year);
                            return CheckboxListTile(
                              checkColor:
                                  app.isDarkMode ? Colors.black : Colors.white,
                              title: Text(year,
                                  style: TextStyle(
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal)),
                              value: isSelected,
                              onChanged: (bool? value) {
                                app.toggleYearForTopic(topic, year);
                                setModalState(() {});
                              },
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          });
        });
  }

  @override
  void dispose() {
    _pageScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    int startIdx = (app.currentPage - 1) * app.itemsPerPage;
    int endIdx = math.min(startIdx + app.itemsPerPage, app.filteredDB.length);
    List<QuestionModel> pageItems =
        app.filteredDB.isEmpty ? [] : app.filteredDB.sublist(startIdx, endIdx);

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(app, context),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                      bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outline))),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                        left: 5, right: 10, top: 10, bottom: 5),
                    child: Row(
                      children: [
                        IconButton(
                            icon: const Icon(Icons.menu),
                            onPressed: () =>
                                _scaffoldKey.currentState?.openDrawer()),
                        RichText(
                          text: TextSpan(
                            text: "SYNAPSE",
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface),
                            children: [
                              TextSpan(
                                  text: ".",
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary))
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (app.isExamMode)
                          Container(
                            margin: const EdgeInsets.only(right: 15),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: app.isDarkMode
                                      ? Colors.black87
                                      : Colors.grey.shade300,
                                  offset: const Offset(3, 3),
                                  blurRadius: 6,
                                ),
                                BoxShadow(
                                  color: app.isDarkMode
                                      ? Colors.grey.shade800
                                      : Colors.white,
                                  offset: const Offset(-3, -3),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  app.submitExam();
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              ResultScreen(app: app)));
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: Text("SUBMIT",
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          letterSpacing: 1.2)),
                                ),
                              ),
                            ),
                          ),
                        if (app.isExamMode)
                          Text(_formatTime(app.timeLeftSeconds),
                              style: const TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                        IconButton(
                            icon: const Icon(Icons.tune),
                            onPressed: () => _showFilterDialog(context, app)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(15, 10, 15, 15),
                    child: SizedBox(
                      height: 45,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: "Search questions...",
                          hintStyle: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.5)),
                          prefixIcon: const Icon(Icons.search),
                          filled: false,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22.5),
                              borderSide: BorderSide(
                                  color:
                                      Theme.of(context).colorScheme.outline)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22.5),
                              borderSide: BorderSide(
                                  color:
                                      Theme.of(context).colorScheme.outline)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22.5),
                              borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 1.5)),
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (val) {
                          app.searchText = val;
                          app.applyFilters();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_showBanner && !app.isExamMode)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(15),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.3))),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Welcome, ${app.firstName}!",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.primary)),
                          const SizedBox(height: 4),
                          Text(
                              "Ready to crush your medical boards today? Select your topics to begin.",
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.8))),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 24, weight: 700),
                      color: Theme.of(context).colorScheme.primary,
                      onPressed: () {
                        setState(() => _showBanner = false);
                        app.markWelcomeSeen();
                      },
                    )
                  ],
                ),
              ),
            if (app.activeTopics.isNotEmpty)
              Container(
                height: 50,
                alignment: Alignment.centerLeft,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  children: app.activeTopics.map((t) {
                    List<String> selectedYears = app.activeTopicYears[t] ?? [];
                    bool isYearFiltered = selectedYears.isNotEmpty;

                    String yearDisplay = isYearFiltered
                        ? (selectedYears.length == 1
                            ? selectedYears.first
                            : "${selectedYears.length} Yrs")
                        : "All";

                    return Container(
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(15)),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(15),
                          onTap: () =>
                              _showYearSelectorBottomSheet(context, app, t),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12, right: 5),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(t,
                                    style: TextStyle(
                                        color: app.isDarkMode
                                            ? Colors.black
                                            : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12)),
                                if (isYearFiltered)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Text("($yearDisplay)",
                                        style: TextStyle(
                                            color: app.isDarkMode
                                                ? Colors.black54
                                                : Colors.white70,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11)),
                                  ),
                                Icon(Icons.arrow_drop_down,
                                    size: 18,
                                    color: app.isDarkMode
                                        ? Colors.black54
                                        : Colors.white70),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => app.removeFilter(t),
                                  child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                          color: app.isDarkMode
                                              ? Colors.black12
                                              : Colors.white24,
                                          shape: BoxShape.circle),
                                      child: Icon(Icons.close,
                                          size: 14,
                                          color: app.isDarkMode
                                              ? Colors.black
                                              : Colors.white)),
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            Expanded(
              child: app.filteredDB.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Text(
                          app.errorMessage.isNotEmpty
                              ? app.errorMessage
                              : "No questions match your criteria.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: app.errorMessage.isNotEmpty
                                  ? Colors.redAccent
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.6),
                              fontSize: 16),
                        ),
                      ),
                    )
                  : NotificationListener<ScrollUpdateNotification>(
                      onNotification: (notif) {
                        app.trackScrollTick(notif.scrollDelta ?? 0);
                        return false;
                      },
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.all(15),
                        itemCount: pageItems.length,
                        itemBuilder: (ctx, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: QuestionCard(q: pageItems[i], app: app)),
                      ),
                    ),
            ),
            if (app.totalPages > 1)
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: app.currentPage > 1
                            ? () => _changePage(app.currentPage - 1)
                            : null),
                    Expanded(
                        child: NotificationListener<ScrollUpdateNotification>(
                      onNotification: (notif) {
                        app.trackScrollTick(notif.scrollDelta ?? 0);
                        return false;
                      },
                      child: ListView.builder(
                          controller: _pageScrollController,
                          scrollDirection: Axis.horizontal,
                          itemCount: app.totalPages,
                          itemBuilder: (context, index) {
                            int page = index + 1;
                            bool isActive = page == app.currentPage;
                            return GestureDetector(
                                onTap: () => _changePage(page),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 12),
                                  width: 36,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      color: isActive
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Text("$page",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isActive
                                              ? (app.isDarkMode
                                                  ? Colors.black
                                                  : Colors.white)
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .onSurface)),
                                ));
                          }),
                    )),
                    IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: app.currentPage < app.totalPages
                            ? () => _changePage(app.currentPage + 1)
                            : null),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    int m = seconds ~/ 60;
    int s = seconds % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  Widget _buildDrawer(AppState app, BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(20))),
      child: Column(
        children: [
          Container(
            padding:
                const EdgeInsets.only(top: 55, left: 24, bottom: 24, right: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                  Theme.of(context).colorScheme.surface
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 10)
                      ]),
                  child: Icon(Icons.psychology,
                      size: 40, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  "${app.firstName} ${app.surname}",
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("ID: ${app.uniqueId}",
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12)),
                      const SizedBox(width: 5),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: app.uniqueId));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("ID Copied!")));
                        },
                        child: Icon(Icons.copy,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildDrawerItem(context,
                    icon: Icons.menu_book_rounded,
                    title: "Study Mode", onTap: () {
                  app.exitExamMode();
                  Navigator.pop(context);
                }),
                _buildDrawerItem(context,
                    icon: Icons.timer_rounded, title: "Exam Mode", onTap: () {
                  Navigator.pop(context);
                  _showExamTimeDialog(context, app);
                }),
                _buildDrawerItem(context,
                    icon: Icons.logout_rounded,
                    title: "Log Out",
                    subtitle: "Testing only", onTap: () {
                  Navigator.pop(context);
                  app.logOut();
                }),
                const Divider(height: 20),
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 10, bottom: 10),
                  child: Text("APPEARANCE",
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5))),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    const Expanded(
                        child: Text("Theme Color",
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15))),
                    ...List.generate(app.availableColors.length, (index) {
                      bool isSelected = app.themeColorIndex == index;
                      return GestureDetector(
                        onTap: () => app.setThemeColor(index),
                        child: Container(
                          margin: const EdgeInsets.only(left: 8),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: app.availableColors[index],
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                    width: 2)
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                      );
                    }),
                  ]),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text("Dark Mode",
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  trailing: Switch(
                    value: app.isDarkMode,
                    onChanged: (val) => app.toggleThemeMode(),
                  ),
                ),
                const Divider(height: 20),
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 10, bottom: 5),
                  child: Text("SOUNDS & HAPTICS",
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5))),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text("Scroll Ticks",
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  subtitle: Text("Mechanical wheel sounds",
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.primary)),
                  trailing: Switch(
                    value: app.soundEnabled,
                    onChanged: (val) => app.toggleSound(val),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.volume_down,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5)),
                      Expanded(
                        child: Slider(
                          value: app.soundVolume,
                          inactiveColor: Theme.of(context).colorScheme.outline,
                          onChanged: app.soundEnabled
                              ? (val) {
                                  app.setVolume(val);
                                }
                              : null,
                        ),
                      ),
                      Icon(Icons.volume_up,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text("© awe 2026",
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context,
      {required IconData icon,
      required String title,
      String? subtitle,
      required VoidCallback onTap}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).colorScheme.primary))
          : null,
      onTap: onTap,
    );
  }

  void _showFilterDialog(BuildContext context, AppState app) {
    List<String> tempFilters = List.from(app.activeTopics);

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (context, setState) {
              return AlertDialog(
                backgroundColor: Theme.of(context).colorScheme.surface,
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 450,
                  child: Column(
                    children: [
                      Expanded(
                          child: NotificationListener<ScrollUpdateNotification>(
                        onNotification: (notif) {
                          app.trackScrollTick(notif.scrollDelta ?? 0);
                          return false;
                        },
                        child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            itemCount: app.allTopics.length,
                            itemBuilder: (c, i) {
                              String t = app.allTopics[i];
                              bool isSelected = tempFilters.contains(t);
                              return ListTile(
                                title: Text(t,
                                    style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal)),
                                trailing: Icon(
                                    isSelected
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.3)),
                                onTap: () => setState(() => isSelected
                                    ? tempFilters.remove(t)
                                    : tempFilters.add(t)),
                              );
                            }),
                      )),
                      Container(
                        height: 60,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            Expanded(
                                child: TextButton(
                                    style: TextButton.styleFrom(
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .outline
                                            .withValues(alpha: 0.3),
                                        foregroundColor: Theme.of(context)
                                            .colorScheme
                                            .onSurface),
                                    onPressed: () {
                                      setState(() => tempFilters.clear());
                                      app.activeTopicYears.clear();
                                      app.applyFiltersWith(tempFilters);
                                      Navigator.pop(ctx);
                                    },
                                    child: const Text("RESET",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold)))),
                            const SizedBox(width: 10),
                            Expanded(
                                child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        foregroundColor: app.isDarkMode
                                            ? Colors.black
                                            : Colors.white),
                                    onPressed: () {
                                      app.applyFiltersWith(tempFilters);
                                      Navigator.pop(ctx);
                                    },
                                    child: const Text("APPLY",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold))))
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              );
            }));
  }

  void _showExamTimeDialog(BuildContext context, AppState app) {
    int selectedHour = 0;
    int selectedMin = 10;

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (context, setState) {
              return AlertDialog(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  title: const Text("EXAM DURATION",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  content: SizedBox(
                      height: 200,
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text("HR",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6))),
                              Expanded(
                                child: ListWheelScrollView.useDelegate(
                                    itemExtent: 40,
                                    physics: const FixedExtentScrollPhysics(),
                                    perspective: 0.005,
                                    onSelectedItemChanged: (v) {
                                      app.playScrollSound();
                                      setState(() => selectedHour = v);
                                    },
                                    childDelegate: ListWheelChildBuilderDelegate(
                                        childCount: 13,
                                        builder: (ctx, i) => Center(
                                            child: Text("$i".padLeft(2, '0'),
                                                style: TextStyle(
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.bold,
                                                    color: selectedHour == i
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withValues(
                                                                alpha:
                                                                    0.4)))))),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text("MIN",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6))),
                              Expanded(
                                child: ListWheelScrollView.useDelegate(
                                    itemExtent: 40,
                                    physics: const FixedExtentScrollPhysics(),
                                    perspective: 0.005,
                                    controller: FixedExtentScrollController(
                                        initialItem: 10),
                                    onSelectedItemChanged: (v) {
                                      app.playScrollSound();
                                      setState(() => selectedMin = v);
                                    },
                                    childDelegate:
                                        ListWheelChildBuilderDelegate(
                                            childCount: 60,
                                            builder: (ctx, val) {
                                              return Center(
                                                  child: Text(
                                                      "$val".padLeft(2, '0'),
                                                      style: TextStyle(
                                                          fontSize: 22,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: selectedMin ==
                                                                  val
                                                              ? Theme.of(
                                                                      context)
                                                                  .colorScheme
                                                                  .primary
                                                              : Theme.of(
                                                                      context)
                                                                  .colorScheme
                                                                  .onSurface
                                                                  .withValues(
                                                                      alpha:
                                                                          0.4))));
                                            })),
                              ),
                            ],
                          ),
                        )
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () {
                          int totalMins = selectedHour * 60 + selectedMin;
                          if (totalMins == 0) totalMins = 1;
                          app.startExam(totalMins);
                          Navigator.pop(ctx);
                        },
                        child: Text("START",
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)))
                  ]);
            }));
  }
}

// ----------------------------------------------------------------------------
// 8. QUESTION CARD AND ROOT WIDGETS
// ----------------------------------------------------------------------------
class QuestionCard extends StatelessWidget {
  final QuestionModel q;
  final AppState app;
  const QuestionCard({super.key, required this.q, required this.app});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outline)),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(q.topic,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(q.year,
                    style: TextStyle(
                        color: app.isDarkMode ? Colors.black : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 15),
          Text(q.stem,
              style: const TextStyle(
                  fontSize: 17, height: 1.4, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          ...q.roots.map((r) => _RootWidget(r: r, app: app)),
          if (!app.isExamMode) ...[
            const SizedBox(height: 15),
            GestureDetector(
              onTap: () => app.toggleAllAnswersForQuestion(q.id),
              child: Container(
                  width: double.infinity,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outline),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                      app.isQuestionRevealed(q.id)
                          ? "HIDE ANSWERS"
                          : "SHOW ANSWERS",
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                          fontWeight: FontWeight.bold,
                          fontSize: 12))),
            )
          ]
        ],
      ),
    );
  }
}

class _RootWidget extends StatelessWidget {
  final RootItem r;
  final AppState app;
  const _RootWidget({required this.r, required this.app});

  @override
  Widget build(BuildContext context) {
    bool isRevealed = app.studyRevealed[r.id] ?? false;
    String userAns = app.userAnswers[r.id] ?? "";
    bool showExp = app.explanationRevealed[r.id] ?? false;

    Color dotBg = Colors.transparent;
    Color dotBorder = Theme.of(context).colorScheme.outline;
    Color dotTextColor = Theme.of(context).colorScheme.onSurface;
    String dotText = "•";

    if (app.isExamMode) {
      if (userAns == "T" || userAns == "F") {
        dotText = userAns;
        dotBg =
            userAns == "T" ? const Color(0xFF10B981) : const Color(0xFFEF4444);
        dotBorder = dotBg;
        dotTextColor = Colors.white;
      }
    } else if (isRevealed) {
      dotText = r.answer;
      dotBg =
          r.answer == "T" ? const Color(0xFF10B981) : const Color(0xFFEF4444);
      dotBorder = dotBg;
      dotTextColor = Colors.white;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => app.handleDotClick(r.id, r.answer),
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: dotBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: dotBorder, width: 1.5)),
                    child: Text(dotText,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: dotTextColor,
                            fontSize: 14))),
              ),
              const SizedBox(width: 15),
              Expanded(
                  child: GestureDetector(
                      onTap: () => app.toggleExplanation(r.id),
                      child: Text(r.text,
                          style: const TextStyle(fontSize: 15, height: 1.3)))),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutQuad,
          child: (showExp && !app.isExamMode)
              ? Container(
                  margin: const EdgeInsets.only(left: 49, bottom: 5, right: 10),
                  child: Text(r.info,
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                          fontStyle: FontStyle.italic,
                          fontSize: 13)))
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// 9. RESULT, REVIEW & DETAILED DRILL-DOWN SCREENS
// ----------------------------------------------------------------------------
class ResultScreen extends StatelessWidget {
  final AppState app;
  const ResultScreen({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    bool passed = app.finalScore >= 70;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            children: [
              const SizedBox(
                  height: 50,
                  child: Text("CLINICAL EVALUATION",
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold))),
              SizedBox(
                height: 220,
                child: Stack(alignment: Alignment.center, children: [
                  TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: app.finalScore / 100),
                      duration: const Duration(seconds: 2),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return SizedBox(
                            width: 150,
                            height: 150,
                            child: CircularProgressIndicator(
                                value: value,
                                strokeWidth: 14,
                                backgroundColor:
                                    Theme.of(context).colorScheme.outline,
                                color: passed
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFEF4444)));
                      }),
                  Text("${app.finalScore}%",
                      style: const TextStyle(
                          fontSize: 38, fontWeight: FontWeight.bold)),
                ]),
              ),
              Container(
                  height: 70,
                  width: double.infinity,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(
                      passed
                          ? "BOARD READINESS: High."
                          : "REMEDIATION: Required.",
                      style: const TextStyle(fontWeight: FontWeight.bold))),
              const Spacer(),
              SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ReviewScreen(app: app))),
                      child: const Text("REVIEW TOPICS",
                          style: TextStyle(fontWeight: FontWeight.bold)))),
              const SizedBox(height: 20),
              SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.onSurface,
                          foregroundColor:
                              Theme.of(context).colorScheme.surface,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      onPressed: () {
                        app.exitExamMode();
                        Navigator.pop(context);
                      },
                      child: const Text("RETURN TO STUDY",
                          style: TextStyle(fontWeight: FontWeight.bold)))),
            ],
          ),
        ),
      ),
    );
  }
}

class ReviewScreen extends StatelessWidget {
  final AppState app;
  const ReviewScreen({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    var topics = app.topicPerformance.entries.toList();
    return Scaffold(
        body: SafeArea(
      child: Column(
        children: [
          SizedBox(
              height: 50,
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context)),
                  const Text("TOPIC BREAKDOWN",
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              )),
          Expanded(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: (notif) {
                app.trackScrollTick(notif.scrollDelta ?? 0);
                return false;
              },
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(20),
                itemCount: topics.length,
                separatorBuilder: (_, __) => const SizedBox(height: 15),
                itemBuilder: (ctx, i) {
                  String topic = topics[i].key;
                  int total = topics[i].value['total']!;
                  int correct = topics[i].value['correct']!;
                  int pct = total == 0 ? 0 : ((correct / total) * 100).toInt();

                  Color color = pct >= 80
                      ? const Color(0xFF10B981)
                      : (pct >= 50
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFFEF4444));
                  IconData icon = pct >= 80
                      ? Icons.check_circle
                      : (pct >= 50 ? Icons.error : Icons.cancel);

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => DetailedReviewScreen(
                                  app: app, topic: topic))),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Theme.of(context).colorScheme.outline)),
                        child: Row(children: [
                          Icon(icon, color: color, size: 28),
                          const SizedBox(width: 15),
                          Expanded(
                              child: Text(topic,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold))),
                          Text("$pct%",
                              style: TextStyle(
                                  color: color,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(width: 10),
                          Icon(Icons.chevron_right,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.3)),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ));
  }
}

class DetailedReviewScreen extends StatelessWidget {
  final AppState app;
  final String topic;
  const DetailedReviewScreen(
      {super.key, required this.app, required this.topic});

  @override
  Widget build(BuildContext context) {
    List<QuestionModel> topicQuestions =
        app.filteredDB.where((q) => q.topic == topic).toList();

    return Scaffold(
        body: SafeArea(
      child: Column(
        children: [
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outline))),
              child: Row(
                children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context)),
                  Expanded(
                    child: Text(topic,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              )),
          Expanded(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: (notif) {
                app.trackScrollTick(notif.scrollDelta ?? 0);
                return false;
              },
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(15),
                itemCount: topicQuestions.length,
                itemBuilder: (ctx, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _ReviewQuestionCard(q: topicQuestions[i], app: app)),
              ),
            ),
          ),
        ],
      ),
    ));
  }
}

class _ReviewQuestionCard extends StatelessWidget {
  final QuestionModel q;
  final AppState app;
  const _ReviewQuestionCard({required this.q, required this.app});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outline)),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(q.topic,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(q.year,
                    style: TextStyle(
                        color: app.isDarkMode ? Colors.black : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 15),
          Text(q.stem,
              style: const TextStyle(
                  fontSize: 17, height: 1.4, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          ...q.roots.map((r) => _ReviewRootWidget(r: r, app: app)),
        ],
      ),
    );
  }
}

class _ReviewRootWidget extends StatelessWidget {
  final RootItem r;
  final AppState app;
  const _ReviewRootWidget({required this.r, required this.app});

  @override
  Widget build(BuildContext context) {
    String userAns = app.userAnswers[r.id] ?? "";
    String actualAns = r.answer;
    bool showExp = app.explanationRevealed[r.id] ?? false;

    bool isCorrect = userAns == actualAns;
    bool isUnanswered = userAns == "";

    Color dotBg = Colors.transparent;
    Color dotBorder = Theme.of(context).colorScheme.outline;
    Color dotTextColor = Theme.of(context).colorScheme.onSurface;
    String dotText = actualAns;

    Color badgeColor = Colors.transparent;
    Color badgeTextColor = Colors.white;
    String badgeText = "";
    IconData? badgeIcon;

    if (isUnanswered) {
      dotBorder = Colors.grey;
      dotTextColor = Colors.grey;
      badgeColor = Colors.grey.shade600;
      badgeText = "UNANSWERED";
      badgeIcon = Icons.remove;
    } else if (isCorrect) {
      dotBg = const Color(0xFF10B981);
      dotBorder = dotBg;
      dotTextColor = Colors.white;
      badgeColor = const Color(0xFF10B981).withValues(alpha: 0.2);
      badgeTextColor = const Color(0xFF10B981);
      badgeText = "CORRECT";
      badgeIcon = Icons.check;
    } else {
      dotBg = const Color(0xFFEF4444);
      dotBorder = dotBg;
      dotTextColor = Colors.white;
      badgeColor = const Color(0xFFEF4444).withValues(alpha: 0.2);
      badgeTextColor = const Color(0xFFEF4444);
      badgeText = "YOU CHOSE: $userAns";
      badgeIcon = Icons.close;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: dotBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: dotBorder, width: 1.5)),
                  child: Text(dotText,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: dotTextColor,
                          fontSize: 14))),
              const SizedBox(width: 15),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                      onTap: () => app.toggleExplanation(r.id),
                      child: Text(r.text,
                          style: const TextStyle(fontSize: 15, height: 1.3))),
                  const SizedBox(height: 6),
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(4)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, size: 12, color: badgeTextColor),
                          const SizedBox(width: 4),
                          Text(badgeText,
                              style: TextStyle(
                                  color: badgeTextColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ))
                ],
              )),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutQuad,
          child: showExp
              ? Container(
                  margin:
                      const EdgeInsets.only(left: 49, bottom: 10, right: 10),
                  child: Text(r.info,
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                          fontStyle: FontStyle.italic,
                          fontSize: 13)))
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
