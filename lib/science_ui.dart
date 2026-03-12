import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:confetti/confetti.dart';
import 'app_state.dart';
import 'models.dart';

// --- NEUMORPHIC WRAPPER ---
class NeuContainer extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final bool isDarkMode;
  final VoidCallback? onTap;

  const NeuContainer({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.margin,
    this.color,
    required this.isDarkMode,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg = color ??
        (isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFE0E5EC));
    Color shadowDark =
        isDarkMode ? const Color(0xFF020617) : const Color(0xFFA3B1C6);
    Color shadowLight =
        isDarkMode ? const Color(0xFF334155) : const Color(0xFFFFFFFF);

    Widget container = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: borderRadius ?? BorderRadius.circular(20),
        boxShadow:[
          BoxShadow(
              color: shadowDark, offset: const Offset(6, 6), blurRadius: 12),
          BoxShadow(
              color: shadowLight, offset: const Offset(-6, -6), blurRadius: 12),
        ],
      ),
      child: child,
    );

    if (onTap != null) return GestureDetector(onTap: onTap, child: container);
    return container;
  }
}

// --- SCIENCE MAIN SCREEN ---
class ScienceMainScreen extends StatefulWidget {
  final AppState app;
  const ScienceMainScreen({super.key, required this.app});
  @override
  State<ScienceMainScreen> createState() => _ScienceMainScreenState();
}

class _ScienceMainScreenState extends State<ScienceMainScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _pageScrollController = ScrollController();

  Color get _bg => widget.app.isDarkMode
      ? const Color(0xFF0F172A)
      : const Color(0xFFE0E5EC);
  Color get _text => widget.app.isDarkMode
      ? const Color(0xFFF3F4F6)
      : const Color(0xFF4A4A4A);
  Color get _primary => widget.app.isDarkMode
      ? const Color(0xFF818CF8)
      : const Color(0xFF4C51BF);

  void _changePage(int newPage) {
    widget.app.setPage(newPage);
    if (_pageScrollController.hasClients) {
      double offset = (newPage - 1) * 44.0;
      _pageScrollController.animateTo(offset,
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    int startIdx = (app.currentPage - 1) * app.itemsPerPage;
    int endIdx = math.min(startIdx + app.itemsPerPage, app.filteredDB.length);
    List<QuestionModel> pageItems =
        app.filteredDB.isEmpty ?[] : app.filteredDB.sublist(startIdx, endIdx);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _bg,
      drawer: _buildDrawer(app, context),
      body: SafeArea(
        child: Stack(
          children:[
            Column(
              children:[
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(15, 20, 15, 10),
                  child: Row(
                    children:[
                      NeuContainer(
                          isDarkMode: app.isDarkMode,
                          borderRadius: BorderRadius.circular(14),
                          padding: const EdgeInsets.all(12),
                          onTap: () => _scaffoldKey.currentState?.openDrawer(),
                          child: Icon(Icons.menu_open, color: _text)),
                      const Spacer(),
                      RichText(
                          text: TextSpan(
                              text: "Synapse",
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: _text,
                                  fontFamily: 'Nunito'),
                              children:[
                            TextSpan(
                                text: "_", style: TextStyle(color: _primary))
                          ])),
                      const Spacer(),
                      NeuContainer(
                          isDarkMode: app.isDarkMode,
                          borderRadius: BorderRadius.circular(14),
                          padding: const EdgeInsets.all(12),
                          onTap: () => app.toggleThemeMode(),
                          child: Icon(
                              app.isDarkMode
                                  ? Icons.wb_sunny
                                  : Icons.nightlight_round,
                              color: _text)),
                      const SizedBox(width: 12),
                      NeuContainer(
                          isDarkMode: app.isDarkMode,
                          borderRadius: BorderRadius.circular(14),
                          padding: const EdgeInsets.all(12),
                          onTap: () => _showFilterDialog(context, app),
                          child: Icon(Icons.tune, color: _text)),
                    ],
                  ),
                ),

                // Search Box Neumorphic
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  child: Container(
                    decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                            color: app.isDarkMode
                                ? Colors.white12
                                : Colors.black12,
                            width: 2)),
                    child: TextField(
                      style:
                          TextStyle(color: _text, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                          hintText: "Search ${app.userCourse} concepts...",
                          hintStyle: TextStyle(color: _text.withValues(alpha: 0.5)),
                          prefixIcon: Icon(Icons.search, color: _text),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 15)),
                      onChanged: (val) {
                        app.searchText = val;
                        app.applyFilters();
                      },
                    ),
                  ),
                ),

                // Chips
                if (app.activeTopics.isNotEmpty)
                  Container(
                    height: 50,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      children: app.activeTopics.map((t) {
                        return Container(
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 15, vertical: 8),
                          decoration: BoxDecoration(
                              color: _primary,
                              borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            children:[
                              Text(t,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                              const SizedBox(width: 8),
                              GestureDetector(
                                  onTap: () => app.removeFilter(t),
                                  child: const Icon(Icons.close,
                                      size: 14, color: Colors.white))
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                // List
                Expanded(
                  child: app.filteredDB.isEmpty
                      ? Center(
                          child: Text("No data found.",
                              style: TextStyle(
                                  color: _text.withValues(alpha: 0.5),
                                  fontWeight: FontWeight.bold)))
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.all(15),
                          itemCount: pageItems.length,
                          itemBuilder: (ctx, i) =>
                              ScienceQuestionCard(q: pageItems[i], app: app),
                        ),
                ),

                // Pagination
                if (app.totalPages > 1)
                  Container(
                    height: 80,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 15),
                    child: Row(
                      children:[
                        NeuContainer(
                            isDarkMode: app.isDarkMode,
                            padding: const EdgeInsets.all(12),
                            borderRadius: BorderRadius.circular(12),
                            onTap: app.currentPage > 1
                                ? () => _changePage(app.currentPage - 1)
                                : null,
                            child: Icon(Icons.chevron_left, color: _primary)),
                        Expanded(
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
                                          horizontal: 6, vertical: 5),
                                      width: 40,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                          color: isActive
                                              ? _primary
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      child: Text("$page",
                                          style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: isActive
                                                  ? Colors.white
                                                  : _text)),
                                    ),
                                  );
                                })),
                        NeuContainer(
                            isDarkMode: app.isDarkMode,
                            padding: const EdgeInsets.all(12),
                            borderRadius: BorderRadius.circular(12),
                            onTap: app.currentPage < app.totalPages
                                ? () => _changePage(app.currentPage + 1)
                                : null,
                            child: Icon(Icons.chevron_right, color: _primary)),
                      ],
                    ),
                  ),

                // Submit Button for Exam
                if (app.isExamMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(15, 0, 15, 15),
                    child: GestureDetector(
                        onTap: () {
                          app.submitExam();
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      ScienceResultScreen(app: app)));
                        },
                        child: NeuContainer(
                            isDarkMode: app.isDarkMode,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: const Center(
                                child: Text("SUBMIT EXAM",
                                    style: TextStyle(
                                        color: Color(0xFFE53E3E),
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.2))))),
                  )
              ],
            ),

            // FLOATING TIMER
            if (app.isExamMode)
              Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: Center(
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 25, vertical: 8),
                        decoration: BoxDecoration(
                          color: app.isDarkMode
                              ? const Color(0xFF1E293B).withValues(alpha: 0.9)
                              : const Color(0xFFE0E5EC).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2)),
                          boxShadow: const[
                            BoxShadow(
                                color: Colors.black26,
                                offset: Offset(0, 8),
                                blurRadius: 20)
                          ],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children:[
                          Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: Color(0xFFE53E3E),
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          const Text("LIVE",
                              style: TextStyle(
                                  color: Color(0xFFE53E3E),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  letterSpacing: 1)),
                          const SizedBox(width: 15),
                          Text(_formatTime(app.timeLeftSeconds),
                              style: TextStyle(
                                  color:
                                      app.isDarkMode ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'monospace',
                                  fontSize: 18)),
                        ]))),
              )
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

  // Minimal Drawer config for Science
  Widget _buildDrawer(AppState app, BuildContext context) {
    return Drawer(
      backgroundColor: _bg,
      child: Column(
        children:[
          Container(
            padding:
                const EdgeInsets.only(top: 60, left: 24, bottom: 24, right: 24),
            color: _primary,
            width: double.infinity,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
              const Icon(Icons.science, size: 40, color: Colors.white),
              const SizedBox(height: 16),
              Text("${app.firstName} ${app.surname}",
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 5),
              Text("${app.userCourse} | ${app.userLevel}",
                  style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 10),
          ListTile(
              leading: Icon(Icons.menu_book, color: _primary),
              title: const Text("Study Mode",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                app.exitExamMode();
                Navigator.pop(context);
              }),
          ListTile(
              leading: Icon(Icons.timer, color: _primary),
              title: const Text("Exam Mode",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                _showExamTimeDialog(context, app);
              }),
          const Divider(),
          ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Log Out",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                app.logOut();
              }),
        ],
      ),
    );
  }

  // Simplified filter just like Medical
  void _showFilterDialog(BuildContext context, AppState app) {
    List<String> tempFilters = List.from(app.activeTopics);
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (context, setState) {
              return AlertDialog(
                  backgroundColor: _bg,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: Text("Course Modules",
                      style:
                          TextStyle(color: _primary, fontWeight: FontWeight.w900)),
                  content: SizedBox(
                      width: double.maxFinite,
                      height: 350,
                      child: ListView.builder(
                          itemCount: app.allTopics.length,
                          itemBuilder: (c, i) {
                            String t = app.allTopics[i];
                            bool isSelected = tempFilters.contains(t);
                            return CheckboxListTile(
                                activeColor: _primary,
                                title: Text(t,
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _text)),
                                value: isSelected,
                                onChanged: (v) => setState(() {
                                      if (v == true) {
                                        tempFilters.add(t);
                                      } else {
                                        tempFilters.remove(t);
                                      }
                                    }));
                          })),
                  actions:[
                    TextButton(
                        onPressed: () {
                          tempFilters.clear();
                          app.applyFiltersWith(tempFilters);
                          Navigator.pop(ctx);
                        },
                        child: const Text("RESET")),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: _primary),
                        onPressed: () {
                          app.applyFiltersWith(tempFilters);
                          Navigator.pop(ctx);
                        },
                        child: const Text("APPLY",
                            style: TextStyle(color: Colors.white)))
                  ]);
            }));
  }

  void _showExamTimeDialog(BuildContext context, AppState app) {
    int selectedMin = 10;
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (context, setState) {
              return AlertDialog(
                  backgroundColor: _bg,
                  title: const Text("EXAM DURATION (MIN)"),
                  content: SizedBox(
                      height: 150,
                      child: ListWheelScrollView.useDelegate(
                          itemExtent: 40,
                          physics: const FixedExtentScrollPhysics(),
                          controller: FixedExtentScrollController(initialItem: 10),
                          onSelectedItemChanged: (v) {
                            app.playScrollSound();
                            setState(() => selectedMin = v);
                          },
                          childDelegate: ListWheelChildBuilderDelegate(
                              childCount: 120,
                              builder: (ctx, val) => Center(
                                  child: Text("$val",
                                      style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: selectedMin == val
                                              ? _primary
                                              : _text.withValues(
                                                  alpha: 0.4))))))),
                  actions:[
                    TextButton(
                        onPressed: () {
                          if (selectedMin == 0) selectedMin = 1;
                          app.startExam(selectedMin);
                          Navigator.pop(ctx);
                        },
                        child: Text("START EXAM",
                            style: TextStyle(
                                color: _primary, fontWeight: FontWeight.bold)))
                  ]);
            }));
  }
}

// --- SCIENCE QUESTION CARD (MATH / BIO LOGIC) ---
class ScienceQuestionCard extends StatefulWidget {
  final QuestionModel q;
  final AppState app;
  const ScienceQuestionCard({super.key, required this.q, required this.app});

  @override
  State<ScienceQuestionCard> createState() => _ScienceQuestionCardState();
}

class _ScienceQuestionCardState extends State<ScienceQuestionCard> {
  bool _imgOpen = false;

  Widget _buildMathText(String text, BuildContext context, bool isDark,
      {Color? overrideColor}) {
    Color textColor = overrideColor ??
        (isDark ? const Color(0xFFF3F4F6) : const Color(0xFF4A4A4A));
    List<Widget> spans =[];
    final regex = RegExp(r'\$\$(.*?)\$\$|\$(.*?)\$', dotAll: true);
    int lastMatchEnd = 0;

    for (var match in regex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(Text(text.substring(lastMatchEnd, match.start),
            style: TextStyle(
                fontSize: 16,
                color: textColor,
                height: 1.5,
                fontWeight: FontWeight.w800)));
      }
      String mathExpr = match.group(1) ?? match.group(2) ?? '';
      spans.add(SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(mathExpr,
              textStyle: TextStyle(fontSize: 16, color: textColor),
              mathStyle: MathStyle.display,
              onErrorFallback: (err) => Text(mathExpr,
                  style: const TextStyle(color: Colors.red)))));
      lastMatchEnd = match.end;
    }
    if (lastMatchEnd < text.length) {
      spans.add(Text(text.substring(lastMatchEnd),
          style: TextStyle(
              fontSize: 16,
              color: textColor,
              height: 1.5,
              fontWeight: FontWeight.w800)));
    }
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: spans);
  }

  Widget _buildGapFillText(
      String text, String qId, AppState app, BuildContext context, bool isDark) {
    List<InlineSpan> spans =[];
    Color textColor = isDark ? const Color(0xFFF3F4F6) : const Color(0xFF4A4A4A);
    final regex = RegExp(r'\[\[(.*?)\|(.*?)\]\]');
    int lastMatchEnd = 0;
    int gapIndex = 1;

    for (var match in regex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
            text: text.substring(lastMatchEnd, match.start),
            style: TextStyle(
                color: textColor,
                fontSize: 16,
                height: 2.0,
                fontWeight: FontWeight.w800)));
      }
      String answer = match.group(1) ?? '';
      String hint = match.group(2) ?? '';
      bool isRevealed = app.studyRevealed['${qId}_gap_$gapIndex'] ?? false;
      int currentIndex = gapIndex;

      spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: () {
              app.studyRevealed['${qId}_gap_$currentIndex'] = !isRevealed;
              // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
              app.notifyListeners();
            },
            child: Tooltip(
              message: hint,
              preferBelow: false,
              textStyle: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: BoxDecoration(
                  color:
                      isDark ? const Color(0xFF818CF8) : const Color(0xFF4C51BF),
                  borderRadius: BorderRadius.circular(8)),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: isRevealed
                        ? Colors.transparent
                        : (isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFE0E5EC)),
                    borderRadius: BorderRadius.circular(8),
                    border: isRevealed
                        ? const Border(
                            bottom: BorderSide(color: Color(0xFF38A169), width: 2))
                        : Border.all(
                            color: isDark ? Colors.white12 : Colors.black12)),
                child: Text(isRevealed ? answer : '($gapIndex)',
                    style: TextStyle(
                        color: isRevealed
                            ? const Color(0xFF38A169)
                            : (isDark
                                ? const Color(0xFF818CF8)
                                : const Color(0xFF4C51BF)),
                        fontWeight: FontWeight.w900,
                        fontSize: 16)),
              ),
            ),
          )));
      lastMatchEnd = match.end;
      gapIndex++;
    }
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
          text: text.substring(lastMatchEnd),
          style: TextStyle(
              color: textColor,
              fontSize: 16,
              height: 2.0,
              fontWeight: FontWeight.w800)));
    }

    bool allRevealed = app.studyRevealed['${qId}_full'] ?? false;

    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:[
          RichText(text: TextSpan(children: spans)),
          const SizedBox(height: 25),
          GestureDetector(
              onTap: () {
                bool target = !allRevealed;
                app.studyRevealed['${qId}_full'] = target;
                for (int i = 1; i < gapIndex; i++) {
                  app.studyRevealed['${qId}_gap_$i'] = target;
                }
                // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
                app.notifyListeners();
              },
              child: NeuContainer(
                  isDarkMode: isDark,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Center(
                      child: Text(allRevealed ? "HIDE ALL ANSWERS" : "REVEAL ALL ANSWERS",
                          style: TextStyle(
                              color: isDark
                                  ? const Color(0xFF818CF8)
                                  : const Color(0xFF4C51BF),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0)))))
        ]);
  }

  Widget _buildOption(
      String letter, String text, QuestionModel q, AppState app, bool isDark) {
    bool isSelected = app.userAnswers[q.id] == letter;
    bool showAns = !app.isExamMode && (app.studyRevealed[q.id] ?? false);

    Color bg = isDark ? const Color(0xFF1E293B) : const Color(0xFFE0E5EC);
    Color textCol = isDark ? const Color(0xFFF3F4F6) : const Color(0xFF4A4A4A);

    if (isSelected) {
      bg = isDark ? const Color(0xFF818CF8) : const Color(0xFF4C51BF);
      textCol = Colors.white;
    }
    if (showAns) {
      if (q.answer == letter) {
        bg = const Color(0xFF38A169);
        textCol = Colors.white;
      } else if (isSelected) {
        bg = const Color(0xFFE53E3E);
        textCol = Colors.white;
      } else {
        bg = bg.withValues(alpha: 0.5);
        textCol = textCol.withValues(alpha: 0.5);
      }
    }

    return GestureDetector(
        onTap: () {
          if (app.isExamMode) app.handleScienceOptionClick(q.id, letter);
        },
        child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: (!isSelected && !showAns)
                    ? Border.all(
                        color: isDark ? Colors.white12 : Colors.black12)
                    : null),
            child: Row(children:[
              Text("$letter. ",
                  style: TextStyle(fontWeight: FontWeight.w900, color: textCol)),
              Expanded(
                  child: _buildMathText(text, context, isDark,
                      overrideColor: textCol))
            ])));
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = widget.app.isDarkMode;
    Color textCol = isDark ? const Color(0xFFF3F4F6) : const Color(0xFF4A4A4A);
    Color primary = isDark ? const Color(0xFF818CF8) : const Color(0xFF4C51BF);

    return NeuContainer(
        isDarkMode: isDark,
        margin: const EdgeInsets.only(bottom: 25),
        padding: const EdgeInsets.all(25),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text("${widget.q.subject} | ${widget.q.topic}",
                    style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 11))),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                    color: widget.app.isDarkMode
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFFD97706),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(widget.q.year,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11))),
          ]),
          const SizedBox(height: 20),
          if (widget.q.imageUrl.isNotEmpty) ...[
            GestureDetector(
                onTap: () => setState(() => _imgOpen = !_imgOpen),
                child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                        border: Border.all(
                            color: primary, style: BorderStyle.solid, width: 2),
                        borderRadius: BorderRadius.circular(15)),
                    alignment: Alignment.center,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children:[
                          Icon(_imgOpen ? Icons.close : Icons.camera_alt,
                              color: primary, size: 16),
                          const SizedBox(width: 8),
                          Text(
                              _imgOpen
                                  ? "HIDE ATTACHMENT"
                                  : "VIEW CLINICAL ATTACHMENT",
                              style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12))
                        ]))),
            if (_imgOpen) ...[
              const SizedBox(height: 15),
              CachedNetworkImage(
                imageUrl: widget.q.imageUrl,
                placeholder: (context, url) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (context, url, error) =>
                    const Icon(Icons.error, color: Colors.red),
                imageBuilder: (context, imageProvider) => ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image(image: imageProvider, fit: BoxFit.cover)),
              ),
            ],
            const SizedBox(height: 20),
          ],
          if (widget.q.gapContent.isNotEmpty)
            _buildGapFillText(
                widget.q.gapContent, widget.q.id, widget.app, context, isDark)
          else
            _buildMathText(widget.q.stem, context, isDark),
          const SizedBox(height: 20),
          if (widget.q.optionA.isNotEmpty) ...[
            _buildOption('A', widget.q.optionA, widget.q, widget.app, isDark),
            _buildOption('B', widget.q.optionB, widget.q, widget.app, isDark),
            _buildOption('C', widget.q.optionC, widget.q, widget.app, isDark),
            _buildOption('D', widget.q.optionD, widget.q, widget.app, isDark),
          ],
          if (!widget.app.isExamMode && widget.q.optionA.isNotEmpty) ...[
            const SizedBox(height: 15),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[
              NeuContainer(
                  isDarkMode: isDark,
                  padding: const EdgeInsets.all(8),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => widget.app.handleDotClick(widget.q.id, ''),
                  child: Icon(
                      (widget.app.studyRevealed[widget.q.id] ?? false)
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: textCol)),
            ]),
            if (widget.app.studyRevealed[widget.q.id] ?? false) ...[
              const SizedBox(height: 15),
              Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.03),
                      border: Border(left: BorderSide(color: primary, width: 4)),
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        const Text("Verified Answer",
                            style: TextStyle(
                                color: Color(0xFF38A169),
                                fontWeight: FontWeight.w900,
                                fontSize: 11)),
                        const SizedBox(height: 5),
                        Text("Option ${widget.q.answer}",
                            style: TextStyle(
                                fontWeight: FontWeight.w900, color: textCol)),
                        const SizedBox(height: 10),
                        _buildMathText(widget.q.explanation, context, isDark),
                      ]))
            ]
          ]
        ]));
  }
}

// --- SCIENCE RESULT DASHBOARD ---
class ScienceResultScreen extends StatefulWidget {
  final AppState app;
  const ScienceResultScreen({super.key, required this.app});
  @override
  State<ScienceResultScreen> createState() => _ScienceResultScreenState();
}

class _ScienceResultScreenState extends State<ScienceResultScreen> {
  late ConfettiController _confettiController;
  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 3));
    if (widget.app.finalScore >= 80) _confettiController.play();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = widget.app.isDarkMode;
    Color primary = isDark ? const Color(0xFF818CF8) : const Color(0xFF4C51BF);
    Color textCol = isDark ? const Color(0xFFF3F4F6) : const Color(0xFF4A4A4A);

    return Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF0F172A) : const Color(0xFFE0E5EC),
        body: SafeArea(
            child: Stack(alignment: Alignment.topCenter, children:[
          SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(children:[
                Text("PERFORMANCE REPORT",
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: textCol)),
                const SizedBox(height: 25),
                NeuContainer(
                    isDarkMode: isDark,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:[
                          Text("REAL-TIME VELOCITY",
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: textCol.withValues(alpha: 0.7))),
                          Align(
                              alignment: Alignment.topRight,
                              child: Text("${widget.app.finalScore}%",
                                  style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w900,
                                      color: primary))),
                          const SizedBox(height: 20),
                          SizedBox(
                              height: 200,
                              child: LineChart(LineChartData(
                                  gridData: const FlGridData(show: false),
                                  titlesData: const FlTitlesData(show: false),
                                  borderData: FlBorderData(show: false),
                                  lineBarsData:[
                                    LineChartBarData(
                                        spots:[
                                          const FlSpot(0, 0),
                                          FlSpot(1, widget.app.finalScore * 0.4),
                                          FlSpot(2, widget.app.finalScore * 0.7),
                                          FlSpot(3, widget.app.finalScore.toDouble())
                                        ],
                                        isCurved: true,
                                        color: primary,
                                        barWidth: 4,
                                        isStrokeCapRound: true,
                                        dotData: const FlDotData(show: true),
                                        belowBarData: BarAreaData(
                                            show: true,
                                            color: primary.withValues(alpha: 0.3)))
                                  ])))
                        ])),
                const SizedBox(height: 20),
                ...widget.app.topicPerformance.entries.map((e) {
                  int total = e.value['total']!;
                  int correct = e.value['correct']!;
                  int pct = total == 0 ? 0 : ((correct / total) * 100).toInt();
                  Color color = pct >= 80
                      ? const Color(0xFF38A169)
                      : (pct >= 50
                          ? const Color(0xFFD97706)
                          : const Color(0xFFE53E3E));
                  String msg = pct >= 80
                      ? 'Excellent Mastery'
                      : (pct >= 50 ? 'Needs Practice' : 'Critical Focus Needed');

                  return Container(
                      margin: const EdgeInsets.only(bottom: 15),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFE0E5EC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border(left: BorderSide(color: color, width: 5)),
                          boxShadow:[
                            BoxShadow(
                                color: isDark
                                    ? const Color(0xFF020617)
                                    : const Color(0xFFA3B1C6),
                                offset: const Offset(2, 2),
                                blurRadius: 8)
                          ]),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children:[
                                  Text(e.key.toUpperCase(),
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: textCol.withValues(alpha: 0.6),
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(msg,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: textCol))
                                ]),
                            Text("$pct%",
                                style: TextStyle(
                                    color: color,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900)),
                          ]));
                }),
                const SizedBox(height: 30),
                GestureDetector(
                    onTap: () {
                      widget.app.exitExamMode();
                      Navigator.pop(context);
                    },
                    child: NeuContainer(
                        isDarkMode: isDark,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: const Center(
                            child: Text("RETURN TO STUDY",
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2)))))
              ])),
          ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const[
                Colors.green,
                Colors.blue,
                Colors.pink,
                Colors.orange,
                Colors.purple
              ]),
        ])));
  }
}