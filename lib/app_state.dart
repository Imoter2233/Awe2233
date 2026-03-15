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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'models.dart';

// --- CONSTANTS & KEYS ---
// Restored Original GitHub URLs for immediate functionality
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
const String lastSyncKey = "synapse_last_sync_time";
const String globalOffsetKey = "synapse_global_offset";

// SECURE STORAGE KEYS
const String tokenExpiryKey = "synapse_secure_token_expiry";
const String customUuidKey = "synapse_secure_custom_uuid";
const String genesisGlobalKey = "synapse_secure_genesis_global";
const String genesisLocalKey = "synapse_secure_genesis_local";
const String userTokenKey = "synapse_secure_user_token";

const String isLoggedInKey = "synapse_is_logged_in";
const String uniqueIdKey = "synapse_unique_id";
const String firstNameKey = "synapse_first_name";
const String surnameKey = "synapse_surname";
const String emailKey = "synapse_email";
const String courseKey = "synapse_course";
const String levelKey = "synapse_level";
const String welcomeSeenKey = "synapse_welcome_seen";

// Initialize Secure Storage
const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

// --- BACKGROUND ISOLATE PARSERS ---
List<QuestionModel> _decodeCsvInBackground(String csvText) {
  List<QuestionModel> newDB =[];
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
        bool isScienceFormat = dict.containsKey('a') || dict.containsKey('content');

        if (isScienceFormat) {
          newDB.add(QuestionModel(
            id: qId,
            subject: dict['subject'] ?? dict['course'] ?? "General",
            topic: dict['topic'] ?? "Uncategorized",
            year: dict['year'] ?? "",
            stem: dict['stem'] ?? dict['q'] ?? "",
            roots:[],
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
          List<RootItem> roots =[];
          for (int i = 1; i <= 5; i++) {
            String text = dict['r${i}_text'] ?? "";
            if (text.isNotEmpty) {
              String rawAns = (dict['r${i}_ans'] ?? dict['r${i}ans'] ?? "").trim().toUpperCase();
              String ans = rawAns.isNotEmpty ? rawAns.substring(0, 1) : "";
              String info = dict['r${i}_info'] ?? "";
              roots.add(RootItem(id: "${qId}_$i", text: text, answer: ans, info: info));
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
    return[];
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

  // SECURITY VARIABLES
  bool isSyncRequired = false;
  Timer? _activeSessionTimer;
  DateTime _lastCheckedLocalTime = DateTime.now();
  int _lastSyncTimeMs = 0;
  int _globalTimeOffsetMs = 0;
  int _localTokenExpiryMs = 0;

  // GENESIS VARIABLES
  int _genesisGlobalMs = 0;
  int _genesisLocalMs = 0;

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

  List<QuestionModel> fullDB =[];
  List<QuestionModel> filteredDB =[];
  String searchText = "";
  
  List<String> activeTopics =[];
  List<String> allTopics =[];
  Map<String, List<String>> activeTopicYears = {};
  Map<String, Set<String>> courseTopics = {}; 

  int currentPage = 1;
  int itemsPerPage = 5;
  int get totalPages {
    int count = (filteredDB.length / itemsPerPage).ceil();
    if (count == 0) {
      return 1;
    } else {
      return count;
    }
  }

  bool isExamMode = false;
  Map<String, String> userAnswers = {};
  Map<String, bool> studyRevealed = {};
  Map<String, bool> explanationRevealed = {};

  Timer? _timer;
  int timeLeftSeconds = 0;
  int finalScore = 0;
  Map<String, Map<String, int>> topicPerformance = {};
  
  // UI CALLBACK FOR AUTO SUBMIT
  VoidCallback? onAutoSubmitTrigger;

  final List<Color> availableColors =[
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
    uniqueId = prefs.getString(uniqueIdKey) ?? "";
    firstName = prefs.getString(firstNameKey) ?? "";
    surname = prefs.getString(surnameKey) ?? "";
    email = prefs.getString(emailKey) ?? "";
    userCourse = prefs.getString(courseKey) ?? "Medicine";
    userLevel = prefs.getString(levelKey) ?? "100L";
    hasSeenWelcome = prefs.getBool(welcomeSeenKey) ?? false;

    _lastSyncTimeMs = prefs.getInt(lastSyncKey) ?? 0;
    _globalTimeOffsetMs = prefs.getInt(globalOffsetKey) ?? 0;

    // --- SECURE STORAGE MIGRATION BRIDGE ---
    userToken = await _secureStorage.read(key: userTokenKey) ?? "";
    if (userToken.isEmpty && prefs.containsKey("synapse_user_token")) {
      // Migrate old SharedPreferences token to Secure Vault
      userToken = prefs.getString("synapse_user_token") ?? "";
      if (userToken.isNotEmpty) {
        await _secureStorage.write(key: userTokenKey, value: userToken);
        await prefs.remove("synapse_user_token");
      }
    }
    
    String expStr = await _secureStorage.read(key: tokenExpiryKey) ?? "";
    _localTokenExpiryMs = int.tryParse(expStr) ?? 0;
    
    String genGlobalStr = await _secureStorage.read(key: genesisGlobalKey) ?? "";
    if (genGlobalStr.isEmpty && prefs.containsKey("synapse_genesis_global_ms")) {
      _genesisGlobalMs = prefs.getInt("synapse_genesis_global_ms") ?? 0;
      await _secureStorage.write(key: genesisGlobalKey, value: _genesisGlobalMs.toString());
    } else {
      _genesisGlobalMs = int.tryParse(genGlobalStr) ?? 0;
    }
    
    String genLocalStr = await _secureStorage.read(key: genesisLocalKey) ?? "";
    if (genLocalStr.isEmpty && prefs.containsKey("synapse_genesis_local_ms")) {
      _genesisLocalMs = prefs.getInt("synapse_genesis_local_ms") ?? 0;
      await _secureStorage.write(key: genesisLocalKey, value: _genesisLocalMs.toString());
    } else {
      _genesisLocalMs = int.tryParse(genLocalStr) ?? 0;
    }

    // THE DEAD-STATE CATCHER
    if (isLoggedIn && userToken.isEmpty) {
      isLoggedIn = false;
      await prefs.setBool(isLoggedInKey, false);
      isLoading = false;
      notifyListeners();
      return;
    }

    if (isLoggedIn && userToken.isNotEmpty) {
      _checkSession(); 

      if (!isLoggedIn) {
        isLoading = false;
        notifyListeners();
      } else if (isSyncRequired) {
        isLoading = false;
        notifyListeners();
        _startActiveSessionTimer();
      } else {
        await _loadLocalFileCache();
        // If cache fails and fullDB is empty, aggressively try internet so they don't see a blank screen
        if (fullDB.isEmpty) {
          await _fetchFromServer();
        }
        isLoading = false;
        notifyListeners();
        _startActiveSessionTimer();
      }
    } else {
      isLoading = false;
      notifyListeners();
    }
  }

  // --- SECURITY: ROBUST DATE PARSER ---
  DateTime? _parseExpiryDate(dynamic rawExpiry) {
    if (rawExpiry == null) {
      return null;
    }
    try {
      if (rawExpiry is Timestamp) {
        return rawExpiry.toDate();
      } else if (rawExpiry is String) {
        return DateTime.tryParse(rawExpiry);
      } else if (rawExpiry is int) {
        return DateTime.fromMillisecondsSinceEpoch(rawExpiry);
      }
    } catch (e) {
      debugPrint("Expiry Parse Error: $e");
    }
    return null;
  }

  // --- SECURITY: UNBLOCKABLE GLOBAL TIME FETCH ---
  Future<DateTime?> _getGlobalTime() async {
    try {
      // 1. Primary: Unblockable Google Header Time
      final response = await http.head(Uri.parse('https://google.com')).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        String? dateHeader = response.headers['date'];
        if (dateHeader != null) {
          return HttpDate.parse(dateHeader);
        }
      }
    } catch (_) {}

    try {
      // 2. Fallback: WorldTimeAPI
      final response = await http.get(Uri.parse('http://worldtimeapi.org/api/timezone/Etc/UTC')).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return DateTime.parse(data['utc_datetime']);
      }
    } catch (_) {}

    return null;
  }

  // --- SECURITY: COMPOSITE FINGERPRINT GENERATOR ---
  Future<String> _getDeviceId() async {
    if (kIsWeb) {
      return "web_device_id";
    }
    try {
      String customUuid = await _secureStorage.read(key: customUuidKey) ?? "";
      
      if (customUuid.isEmpty) {
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
        math.Random rnd = math.Random();
        String randomStr = String.fromCharCodes(Iterable.generate(16, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
        customUuid = "SYN-$randomStr";
        await _secureStorage.write(key: customUuidKey, value: customUuid);
      }

      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String hardwareId = "unknown";
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        hardwareId = androidInfo.id;
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        hardwareId = iosInfo.identifierForVendor ?? "unknown_ios";
      }
      
      return "${hardwareId}_||_$customUuid";
    } catch (e) {
      debugPrint("Device lookup error: $e");
    }
    return "unknown_device_fallback";
  }

  // --- SECURITY: RUTHLESS FIREBASE TOKEN VALIDATION ---
  Future<bool> _verifyTokenLive() async {
    try {
      DocumentSnapshot tokenDoc = await FirebaseFirestore.instance
          .collection('tokens')
          .doc(userToken)
          .get(const GetOptions(source: Source.server));

      if (!tokenDoc.exists) {
        await _executeRemoteWipe("Security Alert: Token invalid or deleted.");
        return false;
      }

      Map<String, dynamic> data = tokenDoc.data() as Map<String, dynamic>;
      
      bool isRevoked = data['isRevoked'] ?? false;
      if (isRevoked) {
        await _executeRemoteWipe("Access Revoked: Your token has been disabled.");
        return false;
      }

      String deviceId = await _getDeviceId();
      String boundDevice = data['boundDeviceId'] ?? "";
      if (boundDevice.isNotEmpty && boundDevice != deviceId) {
        await _executeRemoteWipe("Security Alert: Token cloned or bound to another device. Clear Data detected.");
        return false;
      }

      if (data.containsKey('expiryDate')) {
        DateTime? expiryDate = _parseExpiryDate(data['expiryDate']);
        if (expiryDate != null) {
          _localTokenExpiryMs = expiryDate.millisecondsSinceEpoch;
          await _secureStorage.write(key: tokenExpiryKey, value: _localTokenExpiryMs.toString());

          DateTime secureNow = DateTime.now().add(Duration(milliseconds: _globalTimeOffsetMs));
          if (secureNow.isAfter(expiryDate)) {
            await _executeRemoteWipe("Token Expired: Please purchase a new token.");
            return false;
          }
        }
      }
      return true;
    } catch (e) {
      errorMessage = "Network error. Please connect to the internet to verify your session.";
      notifyListeners();
      return false; 
    }
  }

  // --- THE TIME-BOMB SESSION CHECKER (GENESIS IMPLEMENTATION) ---
  void _checkSession() {
    if (!isLoggedIn || userToken.isEmpty) {
      return;
    }

    DateTime localNow = DateTime.now();

    // 1. THE TIME-TRAVEL TRAP (Backward Jump)
    if (localNow.isBefore(_lastCheckedLocalTime.subtract(const Duration(seconds: 5)))) {
      _executeRemoteWipe("Security Alert: System time tampering detected.");
      _activeSessionTimer?.cancel();
      return;
    }
    _lastCheckedLocalTime = localNow;

    // 2. THE GENESIS ANCHOR TRAP (Absolute Truth)
    int localElapsedMs = localNow.millisecondsSinceEpoch - _genesisLocalMs;
    int currentGenesisGlobalMs = _genesisGlobalMs + localElapsedMs;
    
    if (_localTokenExpiryMs > 0 && currentGenesisGlobalMs > _localTokenExpiryMs) {
      _executeRemoteWipe("Token Expired: Session time depleted.");
      _activeSessionTimer?.cancel();
      return;
    }

    // 3. THE OFFLINE SESSION LIMIT (2 MINUTE TESTING)
    const int sessionLimitMs = 2 * 60 * 1000; 

    if (currentGenesisGlobalMs - _lastSyncTimeMs > sessionLimitMs) {
      if (!isSyncRequired) {
        isSyncRequired = true;
        fullDB.clear();
        filteredDB.clear();
        notifyListeners();
      }
    }
  }

  void _startActiveSessionTimer() {
    _activeSessionTimer?.cancel();
    _lastCheckedLocalTime = DateTime.now();
    _activeSessionTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkSession();
    });
  }

  // --- THE "REFRESH / SYNC NOW" OVERLAY ACTION ---
  Future<void> forceSyncNow() async {
    isLoading = true;
    errorMessage = "";
    notifyListeners();

    bool isSecure = await _verifyTokenLive();
    if (!isSecure) {
      isLoading = false;
      notifyListeners();
      return; 
    }

    await _fetchFromServer();

    DateTime? globalTime = await _getGlobalTime();
    DateTime rawNow = DateTime.now();
    int syncTimeMs = globalTime?.millisecondsSinceEpoch ?? rawNow.millisecondsSinceEpoch;
    
    _globalTimeOffsetMs = syncTimeMs - rawNow.millisecondsSinceEpoch;
    _lastSyncTimeMs = syncTimeMs;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(lastSyncKey, _lastSyncTimeMs);
    await prefs.setInt(globalOffsetKey, _globalTimeOffsetMs);

    isSyncRequired = false;
    isLoading = false;
    notifyListeners();
  }

  Future<void> checkForUpdates() async {
    await forceSyncNow();
  }

  Future<void> _executeRemoteWipe(String reason) async {
    errorMessage = reason; 
    isSyncRequired = false;
    await _wipeLocalData(); 
  }

  Future<void> _wipeLocalData() async {
    fullDB.clear();
    filteredDB.clear();
    userAnswers.clear();
    studyRevealed.clear();
    explanationRevealed.clear();
    courseTopics.clear();
    allTopics.clear();
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$cacheFileName');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint("Wipe error: $e");
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(isLoggedInKey);
    await prefs.remove(uniqueIdKey);
    await prefs.remove(firstNameKey);
    await prefs.remove(surnameKey);
    await prefs.remove(emailKey);
    await prefs.remove(courseKey);
    await prefs.remove(levelKey);
    await prefs.remove(lastSyncKey);
    await prefs.remove(globalOffsetKey);
    
    // WIPE SECURE STORAGE (Except UUID, keep it to punish cloning)
    await _secureStorage.delete(key: userTokenKey);
    await _secureStorage.delete(key: tokenExpiryKey);
    await _secureStorage.delete(key: genesisGlobalKey);
    await _secureStorage.delete(key: genesisLocalKey);
    
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    
    isLoggedIn = false;
    userToken = "";
    _activeSessionTimer?.cancel();
    notifyListeners(); 
  }

  // --- SECURITY: ATOMIC TRANSACTION FOR REGISTRATION ---
  Future<void> registerToken(String token) async {
    try {
      errorMessage = "";
      DateTime rawNow = DateTime.now();
      DateTime ping = await _getGlobalTime() ?? rawNow;
      
      _globalTimeOffsetMs = ping.millisecondsSinceEpoch - rawNow.millisecondsSinceEpoch;
      int secureGlobalMs = ping.millisecondsSinceEpoch;
      String deviceId = await _getDeviceId();

      DocumentReference tokenRef = FirebaseFirestore.instance.collection('tokens').doc(token);

      String transactionError = "";
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot tokenDoc = await transaction.get(tokenRef);

        if (!tokenDoc.exists) {
          transactionError = "Invalid Token.";
          return;
        }

        Map<String, dynamic> data = tokenDoc.data() as Map<String, dynamic>;
        bool isRevoked = data['isRevoked'] ?? false;
        if (isRevoked) {
          transactionError = "Security Alert: Revoked Token.";
          return;
        }

        if (data.containsKey('expiryDate')) {
          DateTime? expiryDate = _parseExpiryDate(data['expiryDate']);
          if (expiryDate != null && secureGlobalMs > expiryDate.millisecondsSinceEpoch) {
            transactionError = "Token Expired: Please purchase a new token.";
            return;
          }
        }

        bool isUsed = data['isUsed'] ?? false;
        String boundDevice = data['boundDeviceId'] ?? "";

        if (isUsed) {
          if (boundDevice != deviceId) {
            transactionError = "Token already bound to another device.";
            return;
          }
        } else {
          transaction.update(tokenRef, {'boundDeviceId': deviceId});
        }
      });

      if (transactionError.isNotEmpty) {
        errorMessage = transactionError;
        notifyListeners();
        return;
      }

      DocumentSnapshot userCheck = await tokenRef.get();
      Map<String, dynamic> finalData = userCheck.data() as Map<String, dynamic>;
      
      if (userToken.isNotEmpty && userToken != token) {
        await _wipeLocalData();
      }

      bool isUsedFinal = finalData['isUsed'] ?? false;
      if (isUsedFinal) {
        String existingUid = finalData['usedByUid'] ?? "";
        if (existingUid.isNotEmpty) {
          DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(existingUid).get();
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
            
            // SECURE STORAGE WRITES
            await _secureStorage.write(key: userTokenKey, value: token);
            
            String genGlobalStr = await _secureStorage.read(key: genesisGlobalKey) ?? "";
            _genesisGlobalMs = genGlobalStr.isNotEmpty ? int.parse(genGlobalStr) : secureGlobalMs;
            
            String genLocalStr = await _secureStorage.read(key: genesisLocalKey) ?? "";
            _genesisLocalMs = genLocalStr.isNotEmpty ? int.parse(genLocalStr) : rawNow.millisecondsSinceEpoch;
            
            await _secureStorage.write(key: genesisGlobalKey, value: _genesisGlobalMs.toString());
            await _secureStorage.write(key: genesisLocalKey, value: _genesisLocalMs.toString());
            
            _lastSyncTimeMs = secureGlobalMs;
            await prefs.setInt(lastSyncKey, _lastSyncTimeMs);
            await prefs.setInt(globalOffsetKey, _globalTimeOffsetMs);

            if (finalData.containsKey('expiryDate')) {
              DateTime? eDate = _parseExpiryDate(finalData['expiryDate']);
              if (eDate != null) {
                _localTokenExpiryMs = eDate.millisecondsSinceEpoch;
                await _secureStorage.write(key: tokenExpiryKey, value: _localTokenExpiryMs.toString());
              }
            }

            userToken = token;
            isSyncRequired = false;
            isLoading = true;
            notifyListeners();
            await _loadLocalFileCache();
            await _fetchFromServer();
            _startActiveSessionTimer();
            return;
          }
        }
      }

      userToken = token;
      await _secureStorage.write(key: userTokenKey, value: token);
      
      _genesisGlobalMs = secureGlobalMs;
      _genesisLocalMs = rawNow.millisecondsSinceEpoch;
      await _secureStorage.write(key: genesisGlobalKey, value: _genesisGlobalMs.toString());
      await _secureStorage.write(key: genesisLocalKey, value: _genesisLocalMs.toString());
      
      _lastSyncTimeMs = secureGlobalMs;
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(lastSyncKey, _lastSyncTimeMs);
      await prefs.setInt(globalOffsetKey, _globalTimeOffsetMs);

      isSyncRequired = false;
      notifyListeners();
      _startActiveSessionTimer();
    } catch (e) {
      errorMessage = "Connection error. Weak Network.";
      notifyListeners();
    }
  }

  // --- SECURITY: ATOMIC TRANSACTION FOR PROFILE CREATION ---
  Future<void> saveUserProfile(String fName, String sName, String mail, String selCourse, String selLevel) async {
    try {
      errorMessage = "";
      String deviceId = await _getDeviceId();
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      math.Random rnd = math.Random();
      String randomStr = String.fromCharCodes(Iterable.generate(4, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
      String newUniqueId = "${fName.trim().toUpperCase()}-$randomStr";

      UserCredential userCred;
      try {
        userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: mail, password: userToken);
      } on FirebaseAuthException catch (authErr) {
        if (authErr.code == 'email-already-in-use') {
          userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: mail, password: userToken);
        } else {
          rethrow;
        }
      }

      final String uid = userCred.user!.uid;

      DocumentReference tokenRef = FirebaseFirestore.instance.collection('tokens').doc(userToken);
      String transactionError = "";
      
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot tokenDoc = await transaction.get(tokenRef);
        Map<String, dynamic> data = tokenDoc.data() as Map<String, dynamic>;
        bool isUsed = data['isUsed'] ?? false;
        
        if (isUsed && data['usedByUid'] != uid) {
          transactionError = "Error: Token was claimed by another account during setup.";
          return;
        }

        transaction.set(FirebaseFirestore.instance.collection('users').doc(uid), {
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

        transaction.update(tokenRef, {
          'isUsed': true,
          'usedByUid': uid,
          'boundDeviceId': deviceId,
          'boundCourse': selCourse,
          'boundLevel': selLevel,
        });
      });

      if (transactionError.isNotEmpty) {
        errorMessage = transactionError;
        notifyListeners();
        return;
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
      _startActiveSessionTimer();
    } catch (e) {
      errorMessage = "Signup Error.";
      notifyListeners();
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
    await _executeRemoteWipe("Logged out.");
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
      String targetUrl = (userCourse == "Medicine" && userLevel == "200L") ? medicalCsvUrl : scienceCsvUrl;
      final response = await http.get(Uri.parse(targetUrl)).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        List<QuestionModel> parsed = await compute(_decodeCsvInBackground, response.body);
        if (parsed.isNotEmpty) {
          fullDB = parsed;
          _setupData();
          
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/$cacheFileName');
          
          String jsonStr = await compute(_encodeJsonCacheInBackground, fullDB);
          await file.writeAsString(jsonStr, flush: true);
        }
      }
    } catch (e) {
      debugPrint("Sync Error.");
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
    courseTopics.clear();
    for (var q in fullDB) {
      if (q.topic.isNotEmpty) {
        uniqueTopics.add(q.topic);
        if (q.subject.isNotEmpty) {
          courseTopics.putIfAbsent(q.subject, () => <String>{});
          courseTopics[q.subject]!.add(q.topic);
        }
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
    activeTopicYears[topic] =[];
    applyFilters();
  }

  void setPage(int page) {
    if (page >= 1 && page <= totalPages) {
      currentPage = page;
      notifyListeners();
    }
  }

  void startExam(int minutes, {VoidCallback? onAutoSubmit}) {
    isExamMode = true;
    userAnswers.clear();
    timeLeftSeconds = minutes * 60;
    currentPage = 1;
    onAutoSubmitTrigger = onAutoSubmit;
    applyFilters();
    
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (timeLeftSeconds > 0) {
        timeLeftSeconds--;
        notifyListeners();
      } else {
        submitExam();
        if (onAutoSubmitTrigger != null) {
          onAutoSubmitTrigger!();
        }
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
        topicPerformance[q.topic]!['total'] = (topicPerformance[q.topic]!['total'] ?? 0) + 1;
        if (userAnswers[q.id] == q.answer) {
          correct++;
          topicPerformance[q.topic]!['correct'] = (topicPerformance[q.topic]!['correct'] ?? 0) + 1;
        }
      } else {
        for (var r in q.roots) {
          total++;
          topicPerformance[q.topic]!['total'] = (topicPerformance[q.topic]!['total'] ?? 0) + 1;
          if (userAnswers[r.id] == r.answer) {
            correct++;
            topicPerformance[q.topic]!['correct'] = (topicPerformance[q.topic]!['correct'] ?? 0) + 1;
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
    onAutoSubmitTrigger = null;
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

  void toggleStudyReveal(String key, bool value) {
    studyRevealed[key] = value;
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