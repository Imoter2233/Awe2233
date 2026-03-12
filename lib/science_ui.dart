import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/services.dart';
import 'app_state.dart';
import 'models.dart';

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
  bool _showBanner = true;
  bool _masterExpandAll = true; 

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
        offset, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut,
      );
    }
  }

  void _showYearSelectorBottomSheet(BuildContext context, AppState app, String courseCode) {
    List<String> availableYears = app.fullDB
        .where((q) => q.subject == courseCode && q.year.isNotEmpty)
        .map((q) => q.year)
        .toSet()
        .toList()
        ..sort((a, b) => b.compareTo(a));

    List<String> courseTopics = app.courseTopics[courseCode]?.toList() ??[];
    if (courseTopics.isEmpty) return;
    String representativeTopic = courseTopics.first;

    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return StatefulBuilder(builder: (BuildContext context, StateSetter setModalState) {
            List<String> currentSelectedYears = app.activeTopicYears[representativeTopic] ??[];
            bool isAllYears = currentSelectedYears.isEmpty;

            return Container(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:[
                  Container(margin: const EdgeInsets.only(top: 12, bottom: 8), height: 5, width: 40, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline, borderRadius: BorderRadius.circular(10))),
                  Padding(padding: const EdgeInsets.all(16.0), child: Text("Filter Years for $courseCode", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  Flexible(
                    child: NotificationListener<ScrollUpdateNotification>(
                      onNotification: (notif) { app.trackScrollTick(notif.scrollDelta ?? 0); return false; },
                      child: ListView(
                        shrinkWrap: true, physics: const BouncingScrollPhysics(),
                        children:[
                          CheckboxListTile(
                            checkColor: app.isDarkMode ? Colors.black : Colors.white,
                            title: Text("All Years", style: TextStyle(fontWeight: isAllYears ? FontWeight.bold : FontWeight.normal)),
                            value: isAllYears,
                            onChanged: (bool? value) { 
                              if (value == true) { 
                                for (String t in courseTopics) { app.clearYearsForTopic(t); }
                                setModalState(() {}); 
                              } 
                            },
                          ),
                          const Divider(height: 1),
                          ...availableYears.map((year) {
                            bool isSelected = currentSelectedYears.contains(year);
                            return CheckboxListTile(
                              checkColor: app.isDarkMode ? Colors.black : Colors.white,
                              title: Text(year, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                              value: isSelected,
                              onChanged: (bool? value) { 
                                for (String t in courseTopics) { app.toggleYearForTopic(t, year); }
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
    List<QuestionModel> pageItems = app.filteredDB.isEmpty ?[] : app.filteredDB.sublist(startIdx, endIdx);

    List<String> activeCourseCodes = app.courseTopics.keys
        .where((c) => app.courseTopics[c]!.any((t) => app.activeTopics.contains(t)))
        .toList();

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(app, context),
      body: SafeArea(
        child: Column(
          children:[
            Container(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outline))),
              child: Column(
                children:[
                  Padding(
                    padding: const EdgeInsets.only(left: 5, right: 10, top: 10, bottom: 5),
                    child: Row(
                      children:[
                        IconButton(icon: const Icon(Icons.menu), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
                        RichText(
                          text: TextSpan(
                            text: "SYNAPSE", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                            children:[TextSpan(text: ".", style: TextStyle(color: Theme.of(context).colorScheme.primary))],
                          ),
                        ),
                        const Spacer(),
                        if (!app.isExamMode)
                           IconButton(
                             icon: Icon(_masterExpandAll ? Icons.unfold_less : Icons.unfold_more), 
                             tooltip: _masterExpandAll ? "Collapse All" : "Expand All",
                             onPressed: () => setState(() => _masterExpandAll = !_masterExpandAll)
                           ),
                        if (app.isExamMode)
                          Container(
                            margin: const EdgeInsets.only(right: 15),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(20),
                              boxShadow:[
                                BoxShadow(color: app.isDarkMode ? Colors.black87 : Colors.grey.shade300, offset: const Offset(3, 3), blurRadius: 6),
                                BoxShadow(color: app.isDarkMode ? Colors.grey.shade800 : Colors.white, offset: const Offset(-3, -3), blurRadius: 6),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  app.submitExam();
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => ScienceResultScreen(app: app)));
                                },
                                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text("SUBMIT", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2))),
                              ),
                            ),
                          ),
                        if (app.isExamMode)
                          Text(_formatTime(app.timeLeftSeconds), style: const TextStyle(color: Color(0xFFEF4444), fontSize: 20, fontWeight: FontWeight.bold)),
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
                          hintText: "Search science concepts...",
                          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                          prefixIcon: const Icon(Icons.search), filled: false,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(22.5), borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22.5), borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22.5), borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5)),
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (val) { app.searchText = val; app.applyFilters(); },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_showBanner && !app.isExamMode)
              Container(
                width: double.infinity, margin: const EdgeInsets.all(15), padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3))),
                child: Row(
                  children:[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:[
                          Text("Welcome, ${app.firstName}!", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                          const SizedBox(height: 4),
                          Text("Ready to crush your ${app.userCourse} (${app.userLevel}) modules? Select your courses to begin.", style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8))),
                        ],
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close, size: 24), color: Theme.of(context).colorScheme.primary, onPressed: () { setState(() => _showBanner = false); app.markWelcomeSeen(); })
                  ],
                ),
              ),
            if (activeCourseCodes.isNotEmpty)
              Container(
                height: 50, alignment: Alignment.centerLeft,
                child: ListView(
                  scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  children: activeCourseCodes.map((courseCode) {
                    
                    String representativeTopic = app.courseTopics[courseCode]?.first ?? "";
                    List<String> selectedYears = app.activeTopicYears[representativeTopic] ??[];
                    bool isYearFiltered = selectedYears.isNotEmpty;
                    String yearDisplay = isYearFiltered ? (selectedYears.length == 1 ? selectedYears.first : "${selectedYears.length} Yrs") : "All";

                    return Container(
                      margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(15)),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(15), onTap: () => _showYearSelectorBottomSheet(context, app, courseCode),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12, right: 5),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children:[
                                Text(courseCode, style: TextStyle(color: app.isDarkMode ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                if (isYearFiltered) Padding(padding: const EdgeInsets.only(left: 4), child: Text("($yearDisplay)", style: TextStyle(color: app.isDarkMode ? Colors.black54 : Colors.white70, fontWeight: FontWeight.w900, fontSize: 11))),
                                Icon(Icons.arrow_drop_down, size: 18, color: app.isDarkMode ? Colors.black54 : Colors.white70),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () {
                                    for(var t in app.courseTopics[courseCode]!) {
                                      app.removeFilter(t);
                                    }
                                  },
                                  child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(color: app.isDarkMode ? Colors.black12 : Colors.white24, shape: BoxShape.circle), child: Icon(Icons.close, size: 14, color: app.isDarkMode ? Colors.black : Colors.white)),
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
                  ? Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Text(app.errorMessage.isNotEmpty ? app.errorMessage : "No questions match your criteria.", textAlign: TextAlign.center, style: TextStyle(color: app.errorMessage.isNotEmpty ? Colors.redAccent : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 16))))
                  : NotificationListener<ScrollUpdateNotification>(
                      onNotification: (notif) { app.trackScrollTick(notif.scrollDelta ?? 0); return false; },
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(), padding: const EdgeInsets.all(15), itemCount: pageItems.length,
                        itemBuilder: (ctx, i) => Padding(padding: const EdgeInsets.only(bottom: 20), child: ScienceQuestionCard(q: pageItems[i], app: app, isGloballyExpanded: _masterExpandAll)),
                      ),
                    ),
            ),
            if (app.totalPages > 1)
              Container(
                height: 60, padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children:[
                    IconButton(icon: const Icon(Icons.chevron_left), onPressed: app.currentPage > 1 ? () => _changePage(app.currentPage - 1) : null),
                    Expanded(
                        child: NotificationListener<ScrollUpdateNotification>(
                      onNotification: (notif) { app.trackScrollTick(notif.scrollDelta ?? 0); return false; },
                      child: ListView.builder(
                          controller: _pageScrollController, scrollDirection: Axis.horizontal, itemCount: app.totalPages,
                          itemBuilder: (context, index) {
                            int page = index + 1; bool isActive = page == app.currentPage;
                            return GestureDetector(
                              onTap: () => _changePage(page),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12), width: 36, alignment: Alignment.center,
                                decoration: BoxDecoration(color: isActive ? Theme.of(context).colorScheme.primary : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                                child: Text("$page", style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? (app.isDarkMode ? Colors.black : Colors.white) : Theme.of(context).colorScheme.onSurface)),
                              ),
                            );
                          }),
                    )),
                    IconButton(icon: const Icon(Icons.chevron_right), onPressed: app.currentPage < app.totalPages ? () => _changePage(app.currentPage + 1) : null),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    int m = seconds ~/ 60; int s = seconds % 60;
    return "${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
  }

  Widget _buildDrawer(AppState app, BuildContext context) {
    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(20))),
      child: Column(
        children:[
          Container(
            padding: const EdgeInsets.only(top: 55, left: 24, bottom: 24, right: 24),
            decoration: BoxDecoration(gradient: LinearGradient(colors:[Theme.of(context).colorScheme.primary.withValues(alpha: 0.8), Theme.of(context).colorScheme.surface], begin: Alignment.topLeft, end: Alignment.bottomRight)),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle, boxShadow: const[BoxShadow(color: Colors.black12, blurRadius: 10)]), child: Icon(Icons.science, size: 40, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(height: 16),
                Text("${app.firstName} ${app.surname}", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children:[
                      Text("ID: ${app.uniqueId}", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(width: 5),
                      GestureDetector(
                        onTap: () { Clipboard.setData(ClipboardData(text: app.uniqueId)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ID Copied!"))); },
                        child: Icon(Icons.copy, size: 14, color: Theme.of(context).colorScheme.primary),
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
              children:[
                _buildDrawerItem(context, icon: Icons.menu_book_rounded, title: "Study Mode", onTap: () { app.exitExamMode(); Navigator.pop(context); }),
                _buildDrawerItem(context, icon: Icons.timer_rounded, title: "Exam Mode", onTap: () { Navigator.pop(context); _showExamTimeDialog(context, app); }),
                _buildDrawerItem(context, icon: Icons.logout_rounded, title: "Log Out", subtitle: "Testing only", onTap: () { Navigator.pop(context); app.logOut(); }),
                const Divider(height: 20),
                Padding(padding: const EdgeInsets.only(left: 16, top: 10, bottom: 10), child: Text("APPEARANCE", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children:[
                    const Expanded(child: Text("Theme Color", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                    ...List.generate(app.availableColors.length, (index) {
                      bool isSelected = app.themeColorIndex == index;
                      return GestureDetector(
                        onTap: () => app.setThemeColor(index),
                        child: Container(
                          margin: const EdgeInsets.only(left: 8), width: 28, height: 28,
                          decoration: BoxDecoration(color: app.availableColors[index], shape: BoxShape.circle, border: isSelected ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2) : null),
                          child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                        ),
                      );
                    }),
                  ]),
                ),
                ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16), title: const Text("Dark Mode", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)), trailing: Switch(value: app.isDarkMode, onChanged: (val) => app.toggleThemeMode())),
                const Divider(height: 20),
                Padding(padding: const EdgeInsets.only(left: 16, top: 10, bottom: 5), child: Text("SOUNDS & HAPTICS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)))),
                ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16), title: const Text("Scroll Ticks", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)), subtitle: Text("Mechanical wheel sounds", style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)), trailing: Switch(value: app.soundEnabled, onChanged: (val) => app.toggleSound(val))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children:[
                      Icon(Icons.volume_down, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                      Expanded(child: Slider(value: app.soundVolume, inactiveColor: Theme.of(context).colorScheme.outline, onChanged: app.soundEnabled ? (val) { app.setVolume(val); } : null)),
                      Icon(Icons.volume_up, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16.0), child: Text("© awe 2026", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 12, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context, {required IconData icon, required String title, String? subtitle, required VoidCallback onTap}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)) : null,
      onTap: onTap,
    );
  }

  void _showFilterDialog(BuildContext context, AppState app) {
    List<String> tempFilters = List.from(app.activeTopics);
    
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (context, setState) {
              return AlertDialog(
                backgroundColor: Theme.of(context).colorScheme.surface, contentPadding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                content: SizedBox(
                  width: double.maxFinite, height: 500,
                  child: Column(
                    children:[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outline))),
                        child: const Text("Course Modules", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      Expanded(
                          child: NotificationListener<ScrollUpdateNotification>(
                        onNotification: (notif) { app.trackScrollTick(notif.scrollDelta ?? 0); return false; },
                        child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 5), 
                            itemCount: app.courseTopics.keys.length,
                            itemBuilder: (c, i) {
                              String courseCode = app.courseTopics.keys.elementAt(i);
                              List<String> topics = app.courseTopics[courseCode]!.toList()..sort();
                              bool allSelected = topics.every((t) => tempFilters.contains(t));

                              return ExpansionTile(
                                iconColor: Theme.of(context).colorScheme.primary,
                                collapsedIconColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                title: Text(courseCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                children:[
                                  // SELECT ALL CHECKBOX
                                  CheckboxListTile(
                                    activeColor: Theme.of(context).colorScheme.primary,
                                    checkColor: app.isDarkMode ? Colors.black : Colors.white,
                                    title: const Text("Select All", style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                                    value: allSelected,
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          for (var t in topics) { if (!tempFilters.contains(t)) tempFilters.add(t); }
                                        } else {
                                          for (var t in topics) { tempFilters.remove(t); }
                                        }
                                      });
                                    }
                                  ),
                                  const Divider(height: 1),
                                  // INDIVIDUAL TOPICS
                                  ...topics.map((t) {
                                    bool isSelected = tempFilters.contains(t);
                                    return CheckboxListTile(
                                      activeColor: Theme.of(context).colorScheme.primary,
                                      checkColor: app.isDarkMode ? Colors.black : Colors.white,
                                      title: Text(t, style: const TextStyle(fontSize: 14)),
                                      value: isSelected,
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) {
                                            tempFilters.add(t);
                                          } else {
                                            tempFilters.remove(t);
                                          }
                                        });
                                      }
                                    );
                                  })
                                ],
                              );
                            }),
                      )),
                      Container(
                        height: 60, padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children:[
                            Expanded(child: TextButton(style: TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3), foregroundColor: Theme.of(context).colorScheme.onSurface), onPressed: () { setState(() => tempFilters.clear()); app.activeTopicYears.clear(); app.applyFiltersWith(tempFilters); Navigator.pop(ctx); }, child: const Text("RESET", style: TextStyle(fontWeight: FontWeight.bold)))),
                            const SizedBox(width: 10),
                            Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: app.isDarkMode ? Colors.black : Colors.white), onPressed: () { app.applyFiltersWith(tempFilters); Navigator.pop(ctx); }, child: const Text("APPLY", style: TextStyle(fontWeight: FontWeight.bold))))
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
    int selectedHour = 0; int selectedMin = 10;
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (context, setState) {
              return AlertDialog(
                  backgroundColor: Theme.of(context).colorScheme.surface, title: const Text("EXAM DURATION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  content: SizedBox(
                      height: 200,
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            children:[
                              Text("HR", style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                              Expanded(
                                child: ListWheelScrollView.useDelegate(
                                    itemExtent: 40, physics: const FixedExtentScrollPhysics(), perspective: 0.005,
                                    onSelectedItemChanged: (v) { app.playScrollSound(); setState(() => selectedHour = v); },
                                    childDelegate: ListWheelChildBuilderDelegate(childCount: 13, builder: (ctx, i) => Center(child: Text("$i".padLeft(2, '0'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: selectedHour == i ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)))))),
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
                                    itemExtent: 40, physics: const FixedExtentScrollPhysics(), perspective: 0.005, controller: FixedExtentScrollController(initialItem: 10),
                                    onSelectedItemChanged: (v) { app.playScrollSound(); setState(() => selectedMin = v); },
                                    childDelegate: ListWheelChildBuilderDelegate(childCount: 60, builder: (ctx, val) { return Center(child: Text("$val".padLeft(2, '0'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: selectedMin == val ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)))); })),
                              ),
                            ],
                          ),
                        )
                      ])),
                  actions:[TextButton(onPressed: () { int totalMins = selectedHour * 60 + selectedMin; if (totalMins == 0) totalMins = 1; app.startExam(totalMins); Navigator.pop(ctx); }, child: Text("START", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16)))]);
            }));
  }
}

// --- SCIENCE QUESTION CARD (MATH / BIO LOGIC) ---
class ScienceQuestionCard extends StatefulWidget {
  final QuestionModel q;
  final AppState app;
  final bool isGloballyExpanded;
  const ScienceQuestionCard({super.key, required this.q, required this.app, required this.isGloballyExpanded});

  @override
  State<ScienceQuestionCard> createState() => _ScienceQuestionCardState();
}

class _ScienceQuestionCardState extends State<ScienceQuestionCard> {
  bool _imgOpen = false;
  late bool _isLocallyExpanded;

  @override
  void initState() {
    super.initState();
    _isLocallyExpanded = widget.isGloballyExpanded;
  }

  @override
  void didUpdateWidget(covariant ScienceQuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isGloballyExpanded != widget.isGloballyExpanded) {
      _isLocallyExpanded = widget.isGloballyExpanded;
    }
  }

  Widget _buildMathText(String text, BuildContext context, bool isDark, {Color? overrideColor}) {
    Color textColor = overrideColor ?? Theme.of(context).colorScheme.onSurface;
    List<Widget> spans =[];
    final regex = RegExp(r'\$\$(.*?)\$\$|\$(.*?)\$', dotAll: true);
    int lastMatchEnd = 0;

    for (var match in regex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(Text(text.substring(lastMatchEnd, match.start), style: TextStyle(fontSize: 16, color: textColor, height: 1.5, fontWeight: FontWeight.bold)));
      }
      String mathExpr = match.group(1) ?? match.group(2) ?? '';
      spans.add(SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(mathExpr, textStyle: TextStyle(fontSize: 16, color: textColor), mathStyle: MathStyle.display, onErrorFallback: (err) => Text(mathExpr, style: const TextStyle(color: Colors.red)))));
      lastMatchEnd = match.end;
    }
    if (lastMatchEnd < text.length) {
      spans.add(Text(text.substring(lastMatchEnd), style: TextStyle(fontSize: 16, color: textColor, height: 1.5, fontWeight: FontWeight.bold)));
    }
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: spans);
  }

  Widget _buildOption(String letter, String text, QuestionModel q, AppState app, bool isDark) {
    bool isSelected = app.userAnswers[q.id] == letter;
    bool showAns = !app.isExamMode && (app.explanationRevealed[q.id] ?? false);

    Color bg = Theme.of(context).colorScheme.surface;
    Color textCol = Theme.of(context).colorScheme.onSurface;
    Color borderColor = Theme.of(context).colorScheme.outline;

    if (isSelected) {
      bg = Theme.of(context).colorScheme.primary;
      textCol = isDark ? Colors.black : Colors.white;
      borderColor = bg;
    }
    if (showAns) {
      if (q.answer == letter) {
        bg = const Color(0xFF10B981); 
        textCol = Colors.white;
        borderColor = bg;
      } else if (isSelected) {
        bg = const Color(0xFFEF4444); 
        textCol = Colors.white;
        borderColor = bg;
      } else {
        bg = bg.withValues(alpha: 0.5);
        textCol = textCol.withValues(alpha: 0.5);
        borderColor = borderColor.withValues(alpha: 0.5);
      }
    }

    return GestureDetector(
        onTap: () {
          if (app.isExamMode) app.handleScienceOptionClick(q.id, letter);
        },
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 1.5)),
            child: Row(children:[
              Text("$letter. ", style: TextStyle(fontWeight: FontWeight.w900, color: textCol, fontSize: 16)),
              Expanded(child: _buildMathText(text, context, isDark, overrideColor: textCol))
            ])));
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = widget.app.isDarkMode;
    Color primary = Theme.of(context).colorScheme.primary;
    bool showExplanation = widget.app.explanationRevealed[widget.q.id] ?? false;

    return Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.outline)),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:[
          Row(children:[
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFE0E7FF), borderRadius: BorderRadius.circular(6)), child: Text(widget.q.subject, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4338CA)))),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(6)), child: Text(widget.q.year, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 15),
          
          if (widget.q.imageUrl.isNotEmpty) ...[
            GestureDetector(
                onTap: () => setState(() => _imgOpen = !_imgOpen),
                child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                        border: Border.all(color: primary, style: BorderStyle.solid, width: 2),
                        borderRadius: BorderRadius.circular(15)),
                    alignment: Alignment.center,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children:[
                          Icon(_imgOpen ? Icons.close : Icons.camera_alt, color: primary, size: 16),
                          const SizedBox(width: 8),
                          Text(_imgOpen ? "HIDE ATTACHMENT" : "VIEW CLINICAL ATTACHMENT",
                              style: TextStyle(color: primary, fontWeight: FontWeight.w900, fontSize: 12))
                        ]))),
            if (_imgOpen) ...[
              const SizedBox(height: 15),
              CachedNetworkImage(
                imageUrl: widget.q.imageUrl,
                placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.red),
                imageBuilder: (context, imageProvider) => ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image(image: imageProvider, fit: BoxFit.cover)),
              ),
            ],
            const SizedBox(height: 20),
          ],
          
          _buildMathText(widget.q.stem, context, isDark),
          
          if (_isLocallyExpanded) ...[
            const SizedBox(height: 20),
            if (widget.q.optionA.isNotEmpty) ...[
              _buildOption('A', widget.q.optionA, widget.q, widget.app, isDark),
              _buildOption('B', widget.q.optionB, widget.q, widget.app, isDark),
              _buildOption('C', widget.q.optionC, widget.q, widget.app, isDark),
              _buildOption('D', widget.q.optionD, widget.q, widget.app, isDark),
            ],
          ],

          const SizedBox(height: 15),
          Row(
            children:[
              if (!widget.app.isExamMode && widget.q.optionA.isNotEmpty)
                Container(
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: Theme.of(context).colorScheme.outline)),
                  child: IconButton(
                    icon: const Icon(Icons.list_alt_rounded),
                    color: showExplanation ? primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    onPressed: () => widget.app.toggleExplanation(widget.q.id),
                  ),
                ),
              const SizedBox(width: 10),
              Container(
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: Theme.of(context).colorScheme.outline)),
                child: IconButton(
                  icon: Icon(_isLocallyExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded),
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  onPressed: () => setState(() => _isLocallyExpanded = !_isLocallyExpanded),
                ),
              ),
              const Spacer(),
              Text(widget.q.topic, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),

          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: (!widget.app.isExamMode && showExplanation) ? Padding(
              padding: const EdgeInsets.only(top: 15),
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                  border: const Border(left: BorderSide(color: Color(0xFF4C51BF), width: 4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:[
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children:[
                        Text("Verified Answer", style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12)),
                        Row(
                          children:[
                            Icon(Icons.smart_toy_rounded, size: 14, color: Color(0xFF4C51BF)),
                            SizedBox(width: 4),
                            Text("ASK AWE AI", style: TextStyle(color: Color(0xFF4C51BF), fontWeight: FontWeight.w900, fontSize: 11)),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text("Option ${widget.q.answer}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 10),
                    _buildMathText(widget.q.explanation, context, isDark),
                  ],
                ),
              ),
            ) : const SizedBox.shrink(),
          )
        ]
      )
    );
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
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    if (widget.app.finalScore >= 70) _confettiController.play();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool passed = widget.app.finalScore >= 70;
    return Scaffold(
      body: SafeArea(
        child: Stack(
          alignment: Alignment.topCenter,
          children:[
            Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                children:[
                  const SizedBox(height: 50, child: Text("PERFORMANCE REPORT", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                  SizedBox(
                    height: 220,
                    child: Stack(alignment: Alignment.center, children:[
                      TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: widget.app.finalScore / 100), duration: const Duration(seconds: 2), curve: Curves.easeOutCubic,
                          builder: (context, value, child) { return SizedBox(width: 150, height: 150, child: CircularProgressIndicator(value: value, strokeWidth: 14, backgroundColor: Theme.of(context).colorScheme.outline, color: passed ? const Color(0xFF10B981) : const Color(0xFFEF4444))); }),
                      Text("${widget.app.finalScore}%", style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                  Container(height: 70, width: double.infinity, alignment: Alignment.centerLeft, padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.outline)), child: Text(passed ? "EVALUATION: Mastery Achieved." : "EVALUATION: Needs Practice.", style: const TextStyle(fontWeight: FontWeight.bold))),
                  const Spacer(),
                  SizedBox(width: double.infinity, height: 55, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.onSurface, foregroundColor: Theme.of(context).colorScheme.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: () { widget.app.exitExamMode(); Navigator.pop(context); }, child: const Text("RETURN TO STUDY", style: TextStyle(fontWeight: FontWeight.bold)))),
                ],
              ),
            ),
            ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const[Colors.green, Colors.blue, Colors.orange, Colors.purple],
            ),
          ],
        ),
      ),
    );
  }
}