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

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'models.dart';

// --- CONSTANTS & KEYS ---
const String medicalCsvUrl =
    "https://raw.githubusercontent.com/Imoter2233/Awe2233/main/data.csv";
const String scienceCsvUrl =
    "https://raw.githubusercontent.com/Imoter2233/Awe2233/main/science_data.csv";

const String themeKey = "synapse_theme_mode";
const String colorIndexKey = "synapse_color_index";
const String soundPrefKey = "synapse_sound_pref";
const String volumePrefKey = "synapse_volume_pref";
const String firstRunKey = "synapse_first_run";
const String cacheFileName = "synapse_offline_db.json";

const String isLoggedInKey = "synapse_is_logged_in";
const String userTokenKey = "synapse_user_token";
const String uniqueIdKey = "synapse_unique_id";
const String firstNameKey = "synapse_first_name";
const String surnameKey = "synapse_surname";
const String emailKey = "synapse_email";
const String courseKey = "synapse_course";
const String levelKey = "synapse_level";
const String welcomeSeenKey = "synapse_welcome_seen";

// --- BACKGROUND ISOLATE PARSERS ---
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
          if (c < row.length) {
            dict[headers[c]] = row[c].toString().trim();
          }
        }

        if (!dict.containsKey('id') || dict['id']!.isEmpty) {
          continue;
        }

        String qId = dict['id']!;

        // AI Logic: Detect Science/Math MCQ format vs Medical True/False format
        bool isScienceFormat =
            dict.containsKey('a') || dict.containsKey('content');

        if (isScienceFormat) {
          newDB.add(QuestionModel(
            id: qId,
            subject: dict['subject'] ?? dict['course'] ?? "General",
            topic: dict['topic'] ?? "Uncategorized",
            year: dict['year'] ?? "",
            stem: dict['stem'] ?? dict['q'] ?? "",
            roots: [],
            optionA: dict['a'] ?? "",
            optionB: dict['b'] ?? "",
            optionC: dict['c'] ?? "",
            optionD: dict['d'] ?? "",
            answer: dict['ans'] ?? "",
            explanation: dict['exp'] ?? "",
            imageUrl: dict['img'] ?? "",
            gapContent: dict['content'] ?? "",
            isScience: true,
          ));
        } else {
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
            isScience: false,
          ));
        }
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

// --- APP STATE MANAGER ---
class AppState extends ChangeNotifier {
  bool isDarkMode = true;
  int themeColorIndex = 0;
  bool isFirstRun = true;
  bool isLoading = true;

  bool soundEnabled = true;
  double soundVolume = 0.5;
  double accumulatedScroll = 0.0;

  bool isLoggedIn = false;
  String userToken = "";
  String uniqueId = "";
  String firstName = "";
  String surname = "";
  String email = "";
  String userCourse = "Medicine"; 
  String userLevel = "100L";
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
  int get totalPages {
    int count = (filteredDB.length / itemsPerPage).ceil();
    return count == 0 ? 1 : count;
  }

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

    isLoggedIn = prefs.getBool(isLoggedInKey) ?? false;
    userToken = prefs.getString(userTokenKey) ?? "";
    uniqueId = prefs.getString(uniqueIdKey) ?? "";
    firstName = prefs.getString(firstNameKey) ?? "";
    surname = prefs.getString(surnameKey) ?? "";
    email = prefs.getString(emailKey) ?? "";
    userCourse = prefs.getString(courseKey) ?? "Medicine";
    userLevel = prefs.getString(levelKey) ?? "100L";
    hasSeenWelcome = prefs.getBool(welcomeSeenKey) ?? false;

    if (isLoggedIn) {
      await _loadLocalFileCache();
      _fetchFromServer();
    } else {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<String> _getDeviceId() async {
    if (kIsWeb) {
      return "web_device_id";
    }
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? "unknown_ios_device";
      }
    } catch (e) {
      debugPrint("Device lookup error: $e");
    }
    return "unknown_device";
  }

  Future<void> registerToken(String token) async {
    try {
      errorMessage = "";
      DocumentSnapshot tokenDoc =
          await FirebaseFirestore.instance.collection('tokens').doc(token).get();

      if (!tokenDoc.exists) {
        errorMessage = "Invalid Token. Please verify and try again.";
        notifyListeners();
        return;
      }

      Map<String, dynamic> data = tokenDoc.data() as Map<String, dynamic>;
      bool isUsed = data['isUsed'] ?? false;
      String deviceId = await _getDeviceId();

      if (isUsed) {
        String boundDevice = data['boundDeviceId'] ?? "";
        if (boundDevice != deviceId) {
          errorMessage = "Security Alert: Token already bound to another device.";
          notifyListeners();
          return;
        }
        
        // AUTO-LOGIN LOGIC: Fetch existing profile
        String existingUid = data['usedByUid'] ?? "";
        if (existingUid.isNotEmpty) {
          DocumentSnapshot userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(existingUid)
              .get();
          if (userDoc.exists) {
            Map<String, dynamic> uData = userDoc.data() as Map<String, dynamic>;
            firstName = uData['firstName'] ?? "";
            surname = uData['surname'] ?? "";
            email = uData['email'] ?? "";
            uniqueId = uData['uniqueId'] ?? "";
            userCourse = uData['course'] ?? "Medicine";
            userLevel = uData['level'] ?? "100L";
            isLoggedIn = true;

            SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setString(firstNameKey, firstName);
            await prefs.setString(surnameKey, surname);
            await prefs.setString(emailKey, email);
            await prefs.setString(uniqueIdKey, uniqueId);
            await prefs.setString(courseKey, userCourse);
            await prefs.setString(levelKey, userLevel);
            await prefs.setBool(isLoggedInKey, true);

            isLoading = true;
            notifyListeners();
            await _loadLocalFileCache();
            await _fetchFromServer();
            return;
          }
        }
      } else {
        await FirebaseFirestore.instance
            .collection('tokens')
            .doc(token)
            .update({'boundDeviceId': deviceId});
      }

      SharedPreferences prefs = await SharedPreferences.getInstance();
      userToken = token;
      await prefs.setString(userTokenKey, token);
      notifyListeners();
    } catch (e) {
      errorMessage = "Connection error. Ensure you have internet access.";
      notifyListeners();
    }
  }

  Future<void> saveUserProfile(String fName, String sName, String mail,
      String selCourse, String selLevel) async {
    try {
      errorMessage = "";
      String deviceId = await _getDeviceId();
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      math.Random rnd = math.Random();
      String randomStr = String.fromCharCodes(Iterable.generate(
          4, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
      String newUniqueId = "${fName.trim().toUpperCase()}-$randomStr";

      UserCredential userCred;
      try {
        userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: mail, password: userToken);
        await userCred.user?.sendEmailVerification();
      } on FirebaseAuthException catch (authErr) {
        if (authErr.code == 'email-already-in-use') {
          userCred = await FirebaseAuth.instance
              .signInWithEmailAndPassword(email: mail, password: userToken);
        } else {
          rethrow;
        }
      }

      final String uid = userCred.user!.uid;

      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'firstName': fName.trim(),
          'surname': sName.trim(),
          'email': mail.trim(),
          'uniqueId': newUniqueId,
          'deviceId': deviceId,
          'boundToken': userToken,
          'course': selCourse,
          'level': selLevel,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await FirebaseFirestore.instance.collection('tokens').doc(userToken).set({
          'isUsed': true,
          'usedByUid': uid,
          'boundDeviceId': deviceId,
          'boundCourse': selCourse,
          'boundLevel': selLevel,
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint("Firestore save error: $e");
      }

      firstName = fName.trim();
      surname = sName.trim();
      email = mail.trim();
      uniqueId = newUniqueId;
      userCourse = selCourse;
      userLevel = selLevel;
      isLoggedIn = true;

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(firstNameKey, firstName);
      await prefs.setString(surnameKey, surname);
      await prefs.setString(emailKey, email);
      await prefs.setString(uniqueIdKey, uniqueId);
      await prefs.setString(courseKey, userCourse);
      await prefs.setString(levelKey, userLevel);
      await prefs.setBool(isLoggedInKey, true);

      isLoading = true;
      notifyListeners();
      await _loadLocalFileCache();
      await _fetchFromServer();
    } catch (e) {
      if (e is FirebaseAuthException) {
        errorMessage = e.message ?? "Authentication failed.";
      } else {
        errorMessage = "Signup Error: Ensure internet and correct token.";
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
      // THE SMART SWITCHER: Load the correct CSV based on the student's locked Program
      String targetUrl = (userCourse == "Medicine") ? medicalCsvUrl : scienceCsvUrl;

      final response = await http
          .get(Uri.parse(targetUrl))
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
          errorMessage = "No questions found for $userCourse. Check database.";
        }
      } else {
        errorMessage = "Server Error ${response.statusCode}.";
      }
    } catch (e) {
      if (fullDB.isEmpty) {
        errorMessage = "Connection failed. Please check internet.";
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void toggleThemeMode() async {
    isDarkMode = !isDarkMode;
    notifyListeners();
    SharedPreferences p = await SharedPreferences.getInstance();
    await p.setBool(themeKey, isDarkMode);
  }

  void setThemeColor(int index) async {
    themeColorIndex = index;
    notifyListeners();
    SharedPreferences p = await SharedPreferences.getInstance();
    await p.setInt(colorIndexKey, themeColorIndex);
  }

  void toggleSound(bool val) async {
    soundEnabled = val;
    notifyListeners();
    SharedPreferences p = await SharedPreferences.getInstance();
    await p.setBool(soundPrefKey, soundEnabled);
  }

  void setVolume(double val) async {
    soundVolume = val;
    notifyListeners();
    SharedPreferences p = await SharedPreferences.getInstance();
    await p.setDouble(volumePrefKey, soundVolume);
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
    if (accumulatedScroll > (100.0 - (soundVolume * 70.0))) {
      playScrollSound();
      accumulatedScroll = 0.0;
    }
  }

  void _setupData() {
    Set<String> uniqueTopics = {};
    for (var q in fullDB) {
      if (q.topic.isNotEmpty) {
        uniqueTopics.add(q.topic);
      }
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
          if (enforcedYears != null &&
              enforcedYears.isNotEmpty &&
              !enforcedYears.contains(q.year)) {
            topicMatch = false;
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
    activeTopicYears.removeWhere((k, v) => !activeTopics.contains(k));
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

      if (q.isScience) {
        total++;
        topicPerformance[q.topic]!['total'] =
            (topicPerformance[q.topic]!['total'] ?? 0) + 1;
        if (userAnswers[q.id] == q.answer) {
          correct++;
          topicPerformance[q.topic]!['correct'] =
              (topicPerformance[q.topic]!['correct'] ?? 0) + 1;
        }
      } else {
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

  void handleScienceOptionClick(String qId, String choice) {
    if (!isExamMode) {
      return;
    }
    if (userAnswers[qId] == choice) {
      userAnswers.remove(qId);
    } else {
      userAnswers[qId] = choice;
    }
    notifyListeners();
  }

  void toggleExplanation(String rootId) {
    explanationRevealed[rootId] = !(explanationRevealed[rootId] ?? false);
    notifyListeners();
  }

  bool isQuestionRevealed(String qId) {
    var q = filteredDB.firstWhere((q) => q.id == qId);
    if (q.isScience) {
      return studyRevealed[qId] ?? false;
    }
    for (var r in q.roots) {
      if (studyRevealed[r.id] == true) {
        return true;
      }
    }
    return false;
  }

  void toggleAllAnswersForQuestion(String questionId) {
    bool currentlyRevealed = isQuestionRevealed(questionId);
    var question = filteredDB.firstWhere((q) => q.id == questionId);
    if (question.isScience) {
      studyRevealed[questionId] = !currentlyRevealed;
    } else {
      for (var r in question.roots) {
        studyRevealed[r.id] = !currentlyRevealed;
      }
    }
    notifyListeners();
  }
}