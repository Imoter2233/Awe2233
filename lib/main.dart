// ============================================================================
// FILE: main.dart
// PROJECT: SYNAPSE - MEDICAL PAST QUESTIONS (FLUTTER EDITION)
// UPGRADE: 100% Kivy-features ported. Optimized with Isolate Multi-threading.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ----------------------------------------------------------------------------
// 1. CONSTANTS & KEYS
// ----------------------------------------------------------------------------
const String csvUrl = "https://raw.githubusercontent.com/Imoter2233/synapse_asset/main/data.csv";
const String cacheKey = "synapse_offline_cache";
const String themeKey = "synapse_theme_mode";
const String firstRunKey = "synapse_first_run";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, 
  ));
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

  RootItem({required this.id, required this.text, required this.answer, required this.info});

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'answer': answer, 'info': info};
  factory RootItem.fromJson(Map<String, dynamic> json) => RootItem(
        id: json['id'],
        text: json['text'],
        answer: json['answer'],
        info: json['info'],
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
        id: json['id'],
        subject: json['subject'],
        topic: json['topic'],
        year: json['year'],
        stem: json['stem'],
        roots: (json['roots'] as List).map((r) => RootItem.fromJson(r)).toList(),
      );
}

// ----------------------------------------------------------------------------
// 3. BACKGROUND ISOLATE PARSER
// ----------------------------------------------------------------------------
List<QuestionModel> _decodeCsvInBackground(String csvText) {
  List<QuestionModel> newDB =[];
  try {
    List<List<dynamic>> rows = const CsvToListConverter().convert(csvText, eol: '\n', shouldParseNumbers: false);
    if (rows.isNotEmpty) {
      List<String> headers = rows[0].map((e) => e.toString().trim()).toList();
      for (int r = 1; r < rows.length; r++) {
        var row = rows[r];
        Map<String, String> dict = {};
        for (int c = 0; c < headers.length; c++) {
          if (c < row.length) dict[headers[c]] = row[c].toString();
        }

        if (!dict.containsKey('id') || dict['id']!.isEmpty) continue;
        String qId = dict['id']!;
        List<RootItem> roots =[];
        
        for (int i = 1; i <= 5; i++) {
          String text = dict['r${i}_text'] ?? "";
          if (text.isNotEmpty) {
            String rawAns = (dict['r${i}ans'] ?? "").trim().toUpperCase();
            String ans = rawAns.isNotEmpty ? rawAns.substring(0, 1) : "";
            String info = dict['r${i}_info'] ?? "";
            roots.add(RootItem(id: "${qId}_$i", text: text, answer: ans, info: info));
          }
        }
        newDB.add(QuestionModel(
          id: qId, subject: dict['subject'] ?? "", topic: dict['topic'] ?? "", 
          year: dict['year'] ?? "", stem: dict['stem'] ?? "", roots: roots,
        ));
      }
    }
  } catch (e) {
    debugPrint("Background Parse Error: $e");
  }
  return newDB;
}

// ----------------------------------------------------------------------------
// 4. APP STATE MANAGEMENT
// ----------------------------------------------------------------------------
class AppState extends ChangeNotifier {
  bool isDarkMode = true;
  bool isFirstRun = true;
  bool isLoading = true;

  List<QuestionModel> fullDB =[];
  List<QuestionModel> filteredDB =[];
  
  String searchText = "";
  List<String> activeTopics = [];
  List<String> allTopics =[];
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

  AppState() {
    initData();
  }

  Future<void> initData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    isDarkMode = prefs.getBool(themeKey) ?? true;
    isFirstRun = prefs.getBool(firstRunKey) ?? true;

    String? cachedData = prefs.getString(cacheKey);
    if (cachedData != null) {
      try {
        List<dynamic> jsonList = jsonDecode(cachedData);
        fullDB = jsonList.map((e) => QuestionModel.fromJson(e)).toList();
        _setupData();
        isLoading = false;
        notifyListeners();
      } catch (e) {
        debugPrint("Cache parsing error: $e");
      }
    }

    _fetchFromServer(prefs);
  }

  Future<void> _fetchFromServer(SharedPreferences prefs) async {
    try {
      final response = await http.get(Uri.parse(csvUrl)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        List<QuestionModel> parsed = await compute(_decodeCsvInBackground, response.body);
        if (parsed.isNotEmpty) {
          fullDB = parsed;
          String jsonToCache = jsonEncode(fullDB.map((e) => e.toJson()).toList());
          await prefs.setString(cacheKey, jsonToCache);
          _setupData();
        }
      }
    } catch (e) {
      debugPrint("Network error: $e");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void completeOnboarding() async {
    isFirstRun = false;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(firstRunKey, false);
  }

  void toggleTheme() async {
    isDarkMode = !isDarkMode;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(themeKey, isDarkMode);
  }

  void _setupData() {
    allTopics = fullDB.map((e) => e.topic).where((t) => t.isNotEmpty).toSet().toList()..sort();
    applyFilters();
  }

  void applyFilters() {
    filteredDB = fullDB.where((q) {
      bool topicMatch = activeTopics.isEmpty || activeTopics.contains(q.topic);
      bool searchMatch = searchText.isEmpty || 
          q.stem.toLowerCase().contains(searchText.toLowerCase()) || 
          q.topic.toLowerCase().contains(searchText.toLowerCase());
      return topicMatch && searchMatch;
    }).toList();
    currentPage = 1;
    notifyListeners();
  }

  void applyFiltersWith(List<String> tempFilters) {
    activeTopics = List.from(tempFilters);
    applyFilters();
  }

  void removeFilter(String topic) {
    activeTopics.remove(topic);
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
        topicPerformance[q.topic]!['total'] = (topicPerformance[q.topic]!['total'] ?? 0) + 1;
        if (userAnswers[r.id] == r.answer) {
          correct++;
          topicPerformance[q.topic]!['correct'] = (topicPerformance[q.topic]!['correct'] ?? 0) + 1;
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
    if (isExamMode) return;
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

  ThemeData _buildTheme(bool isDark) {
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: isDark ? const Color(0xFF000000) : const Color(0xFFF3F4F6),
      colorScheme: isDark 
        ? const ColorScheme.dark(
            primary: Color(0xFFF59E0B),
            surface: Color(0xFF111827),
            onSurface: Color(0xFFF9FAFB),
            outline: Color(0xFF1F2937),
          )
        : const ColorScheme.light(
            primary: Color(0xFF3B82F6),
            surface: Color(0xFFFFFFFF),
            onSurface: Color(0xFF111827),
            outline: Color(0xFFE5E7EB),
          ),
      fontFamily: 'Roboto',
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(state.isDarkMode),
      home: state.isLoading 
          ? const SplashLoaderScreen() 
          : (state.isFirstRun ? OnboardingScreen(app: state) : MainScreen(app: state)),
    );
  }
}

// ----------------------------------------------------------------------------
// 6. SPLASH SCREEN & ONBOARDING
// ----------------------------------------------------------------------------
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
                text: "SYNAPSE",
                style: TextStyle(fontSize: 45, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
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
        if (phase < 0.5) {
          offset = -math.sin(phase * 2 * math.pi) * 15;
        }
        return Transform.translate(
          offset: Offset(0, offset),
          child: Container(
            width: 18, height: 18,
            decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children:[_buildDot(0.0), const SizedBox(width: 15), _buildDot(0.15), const SizedBox(width: 15), _buildDot(0.30)],
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
            children:[
              const Spacer(),
              Icon(Icons.school_outlined, size: 100, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              Text("Welcome to Synapse.", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Text("Your ultimate medical exam preparation tool. Select topics, study answers, and ace your boards.", style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)), textAlign: TextAlign.center),
              const Spacer(),
              SizedBox(
                width: double.infinity, height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
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

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    int startIdx = (app.currentPage - 1) * app.itemsPerPage;
    int endIdx = math.min(startIdx + app.itemsPerPage, app.filteredDB.length);
    List<QuestionModel> pageItems = app.filteredDB.isEmpty ?[] : app.filteredDB.sublist(startIdx, endIdx);

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(app, context),
      body: SafeArea(
        child: Column(
          children:[
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outline))
              ),
              child: Column(
                children:[
                  Padding(
                    padding: const EdgeInsets.only(left: 5, right: 10, top: 10, bottom: 5),
                    child: Row(
                      children:[
                        IconButton(icon: const Icon(Icons.menu), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
                        RichText(
                          text: TextSpan(
                            text: "SYNAPSE",
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                            children:[TextSpan(text: ".", style: TextStyle(color: Theme.of(context).colorScheme.primary))],
                          ),
                        ),
                        const Spacer(),
                        if (app.isExamMode)
                          Text(_formatTime(app.timeLeftSeconds), style: const TextStyle(color: Color(0xFFEF4444), fontSize: 22, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.tune), onPressed: () => _showFilterDialog(context, app)),
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
                          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                          prefixIcon: const Icon(Icons.search),
                          filled: false,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(22.5), borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22.5), borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22.5), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)),
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
            if (app.activeTopics.isNotEmpty)
              Container(
                height: 50,
                alignment: Alignment.centerLeft,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  children: app.activeTopics.map((t) => Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.only(left: 12, right: 5),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(15)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children:[
                        Text(t, style: TextStyle(color: app.isDarkMode ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => app.removeFilter(t),
                          child: Icon(Icons.close, size: 16, color: app.isDarkMode ? Colors.black : Colors.white),
                        )
                      ],
                    )
                  )).toList(),
                ),
              ),
            Expanded(
              child: app.filteredDB.isEmpty
                  ? const Center(child: Text("No questions match your criteria."))
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(15),
                      itemCount: pageItems.length,
                      itemBuilder: (ctx, i) => Padding(padding: const EdgeInsets.only(bottom: 20), child: QuestionCard(q: pageItems[i], app: app)),
                    ),
            ),
            if (app.isExamMode)
              Padding(
                padding: const EdgeInsets.all(15),
                child: SizedBox(
                  width: double.infinity, height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () {
                      app.submitExam();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(app: app)));
                    },
                    child: Text("SUBMIT EXAM", style: TextStyle(color: app.isDarkMode ? Colors.black : Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              )
            else if (app.totalPages > 1)
              Container(
                height: 60,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children:[
                    IconButton(icon: const Icon(Icons.chevron_left), onPressed: app.currentPage > 1 ? () => app.setPage(app.currentPage - 1) : null),
                    Expanded(
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: app.totalPages,
                        itemBuilder: (context, index) {
                          int page = index + 1;
                          bool isActive = page == app.currentPage;
                          return GestureDetector(
                            onTap: () => app.setPage(page),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                              width: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isActive ? Theme.of(context).colorScheme.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(10)
                              ),
                              child: Text("$page", style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isActive ? (app.isDarkMode ? Colors.black : Colors.white) : Theme.of(context).colorScheme.onSurface
                              )),
                            )
                          );
                        }
                      )
                    ),
                    IconButton(icon: const Icon(Icons.chevron_right), onPressed: app.currentPage < app.totalPages ? () => app.setPage(app.currentPage + 1) : null),
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(16))),
      child: Column(
        children:[
          Container(
            height: 160,
            width: double.infinity,
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.only(left: 20, bottom: 20),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                Icon(Icons.psychology, size: 45, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 10),
                RichText(text: TextSpan(text: "SYNAPSE", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface), children:[TextSpan(text: ".", style: TextStyle(color: Theme.of(context).colorScheme.primary))])),
                Text("Medical Study Platform", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13)),
              ],
            )
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Align(alignment: Alignment.centerLeft, child: Text("MENU", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.bold, fontSize: 13))),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text("Study Mode"),
            onTap: () { app.exitExamMode(); Navigator.pop(context); }
          ),
          ListTile(
            leading: const Icon(Icons.edit_document),
            title: const Text("Exam Mode"),
            onTap: () { Navigator.pop(context); _showExamTimeDialog(context, app); }
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text("Toggle Theme"),
            onTap: () { app.toggleTheme(); Navigator.pop(context); }
          ),
        ],
      ),
    );
  }

  void _showFilterDialog(BuildContext context, AppState app) {
    List<String> tempFilters = List.from(app.activeTopics);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            contentPadding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: SizedBox(
              width: double.maxFinite,
              height: 450,
              child: Column(
                children:[
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      itemCount: app.allTopics.length,
                      itemBuilder: (c, i) {
                        String t = app.allTopics[i];
                        bool isSelected = tempFilters.contains(t);
                        return ListTile(
                          title: Text(t, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                          trailing: Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked, color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
                          onTap: () => setState(() => isSelected ? tempFilters.remove(t) : tempFilters.add(t)),
                        );
                      }
                    )
                  ),
                  Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children:[
                        Expanded(
                          child: TextButton(
                            style: TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3), foregroundColor: Theme.of(context).colorScheme.onSurface),
                            onPressed: () => setState(() => tempFilters.clear()),
                            child: const Text("RESET", style: TextStyle(fontWeight: FontWeight.bold))
                          )
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: app.isDarkMode ? Colors.black : Colors.white),
                            onPressed: () {
                              app.applyFiltersWith(tempFilters);
                              Navigator.pop(ctx);
                            },
                            child: const Text("APPLY", style: TextStyle(fontWeight: FontWeight.bold))
                          )
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
          );
        }
      )
    );
  }

  void _showExamTimeDialog(BuildContext context, AppState app) {
    int selectedHour = 0;
    int selectedMin = 10;
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: const Text("EXAM DURATION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children:[
                        Text("HR", style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                        Expanded(
                          child: ListWheelScrollView.useDelegate(
                            itemExtent: 40, physics: const FixedExtentScrollPhysics(), perspective: 0.005,
                            onSelectedItemChanged: (v) => setState(() => selectedHour = v),
                            childDelegate: ListWheelChildBuilderDelegate(
                              childCount: 13,
                              builder: (ctx, i) => Center(child: Text("$i".padLeft(2, '0'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: selectedHour == i ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4))))
                            )
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children:[
                        Text("MIN", style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                        Expanded(
                          child: ListWheelScrollView.useDelegate(
                            itemExtent: 40, physics: const FixedExtentScrollPhysics(), perspective: 0.005,
                            onSelectedItemChanged: (v) => setState(() => selectedMin = v * 5),
                            childDelegate: ListWheelChildBuilderDelegate(
                              childCount: 12,
                              builder: (ctx, index) {
                                int val = index * 5;
                                return Center(child: Text("$val".padLeft(2, '0'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: selectedMin == val ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4))));
                              }
                            )
                          ),
                        ),
                      ],
                    ),
                  )
                ]
              )
            ),
            actions:[
              TextButton(
                onPressed: () {
                  int totalMins = selectedHour * 60 + selectedMin;
                  if (totalMins == 0) totalMins = 10;
                  app.startExam(totalMins);
                  Navigator.pop(ctx);
                },
                child: Text("START", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16))
              )
            ]
          );
        }
      )
    );
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
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.outline)),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children:[
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline, borderRadius: BorderRadius.circular(6)), child: Text(q.topic, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(6)), child: Text(q.year, style: TextStyle(color: app.isDarkMode ? Colors.black : Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 15),
          Text(q.stem, style: const TextStyle(fontSize: 17, height: 1.4, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          ...q.roots.map((r) => _RootWidget(r: r, app: app)),
          if (!app.isExamMode) ...[
            const SizedBox(height: 15),
            GestureDetector(
              onTap: () => app.toggleAllAnswersForQuestion(q.id),
              child: Container(
                width: double.infinity, height: 42, alignment: Alignment.center, 
                decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outline), borderRadius: BorderRadius.circular(8)), 
                child: Text(app.isQuestionRevealed(q.id) ? "HIDE ANSWERS" : "SHOW ANSWERS", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.bold, fontSize: 12))
              ),
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
        dotBg = userAns == "T" ? const Color(0xFF10B981) : const Color(0xFFEF4444);
        dotBorder = dotBg;
        dotTextColor = Colors.white;
      }
    } else if (isRevealed) {
      dotText = r.answer;
      dotBg = r.answer == "T" ? const Color(0xFF10B981) : const Color(0xFFEF4444);
      dotBorder = dotBg;
      dotTextColor = Colors.white;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children:[
              GestureDetector(
                onTap: () => app.handleDotClick(r.id, r.answer),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200), width: 34, height: 34, alignment: Alignment.center, 
                  decoration: BoxDecoration(color: dotBg, shape: BoxShape.circle, border: Border.all(color: dotBorder, width: 1.5)), 
                  child: Text(dotText, style: TextStyle(fontWeight: FontWeight.bold, color: dotTextColor, fontSize: 14))
                ),
              ),
              const SizedBox(width: 15),
              Expanded(child: GestureDetector(onTap: () => app.toggleExplanation(r.id), child: Text(r.text, style: const TextStyle(fontSize: 15, height: 1.3)))),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutQuad,
          child: (showExp && !app.isExamMode) 
            ? Container(
                margin: const EdgeInsets.only(left: 49, bottom: 5, right: 10),
                child: Text(r.info, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontStyle: FontStyle.italic, fontSize: 13))
              ) 
            : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// 9. RESULT & REVIEW SCREENS
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
            children:[
              const SizedBox(height: 50, child: Text("CLINICAL EVALUATION", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
              SizedBox(
                height: 220,
                child: Stack(
                  alignment: Alignment.center, 
                  children:[
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: app.finalScore / 100),
                      duration: const Duration(seconds: 2),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return SizedBox(
                          width: 150, height: 150,
                          child: CircularProgressIndicator(
                            value: value, strokeWidth: 14, 
                            backgroundColor: Theme.of(context).colorScheme.outline, 
                            color: passed ? const Color(0xFF10B981) : const Color(0xFFEF4444)
                          )
                        );
                      }
                    ),
                    Text("${app.finalScore}%", style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold)),
                  ]
                ),
              ),
              Container(
                height: 70, width: double.infinity, alignment: Alignment.centerLeft, padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
                child: Text(passed ? "BOARD READINESS: High." : "REMEDIATION: Required.", style: const TextStyle(fontWeight: FontWeight.bold))
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity, height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ReviewScreen(app: app))), 
                  child: const Text("REVIEW TOPICS", style: TextStyle(fontWeight: FontWeight.bold))
                )
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.onSurface, foregroundColor: Theme.of(context).colorScheme.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
                  onPressed: () { app.exitExamMode(); Navigator.pop(context); }, 
                  child: const Text("RETURN TO STUDY", style: TextStyle(fontWeight: FontWeight.bold))
                )
              ),
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
          children:[
            SizedBox(
              height: 50,
              child: Row(
                children:[
                  IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                  const Text("TOPIC BREAKDOWN", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              )
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: topics.length,
                separatorBuilder: (_, __) => const SizedBox(height: 15),
                itemBuilder: (ctx, i) {
                  String topic = topics[i].key;
                  int total = topics[i].value['total']!;
                  int correct = topics[i].value['correct']!;
                  int pct = total == 0 ? 0 : ((correct / total) * 100).toInt();
                  
                  Color color = pct >= 80 ? const Color(0xFF10B981) : (pct >= 50 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));
                  IconData icon = pct >= 80 ? Icons.check_circle : (pct >= 50 ? Icons.error : Icons.cancel);

                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.outline)),
                    child: Row(children:[
                      Icon(icon, color: color, size: 28),
                      const SizedBox(width: 15),
                      Expanded(child: Text(topic, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                      Text("$pct%", style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
                    ]),
                  );
                },
              ),
            ),
          ],
        ),
      )
    );
  }
}