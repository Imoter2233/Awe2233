import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'app_state.dart';
import 'models.dart';

class MedicalMainScreen extends StatefulWidget {
  final AppState app;
  const MedicalMainScreen({super.key, required this.app});

  @override
  State<MedicalMainScreen> createState() => _MedicalMainScreenState();
}

class _MedicalMainScreenState extends State<MedicalMainScreen> {
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
        offset, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut,
      );
    }
  }

  void _showYearSelectorBottomSheet(BuildContext context, AppState app, String topic) {
    List<String> availableYears = app.fullDB.where((q) => q.topic == topic && q.year.isNotEmpty).map((q) => q.year).toSet().toList()..sort((a, b) => b.compareTo(a));

    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return StatefulBuilder(builder: (BuildContext context, StateSetter setModalState) {
            List<String> currentSelectedYears = app.activeTopicYears[topic] ??[];
            bool isAllYears = currentSelectedYears.isEmpty;

            return Container(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:[
                  Container(margin: const EdgeInsets.only(top: 12, bottom: 8), height: 5, width: 40, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline, borderRadius: BorderRadius.circular(10))),
                  Padding(padding: const EdgeInsets.all(16.0), child: Text("Filter Years for $topic", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                  Flexible(
                    child: NotificationListener<ScrollUpdateNotification>(
                      onNotification: (notif) { 
                        app.trackScrollTick(notif.scrollDelta ?? 0); 
                        return false; 
                      },
                      child: ListView(
                        shrinkWrap: true, physics: const BouncingScrollPhysics(),
                        children:[
                          CheckboxListTile(
                            checkColor: app.isDarkMode ? Colors.black : Colors.white,
                            title: Text("All Years", style: TextStyle(fontWeight: isAllYears ? FontWeight.bold : FontWeight.normal)),
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
                            bool isSelected = currentSelectedYears.contains(year);
                            return CheckboxListTile(
                              checkColor: app.isDarkMode ? Colors.black : Colors.white,
                              title: Text(year, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
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

  // --- SECURITY: THE LOCKOUT OVERLAY ---
  Widget _buildSyncOverlay(AppState app) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children:[
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_clock_rounded, size: 80, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 30),
          Text(
            "Weekly Sync Required", 
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)
          ),
          const SizedBox(height: 15),
          Text(
            "Your offline session has expired. Please connect to the internet and tap Refresh to securely sync your clinical data.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))
          ),
          const SizedBox(height: 40),
          if (app.isLoading)
            const CircularProgressIndicator()
          else
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: app.isDarkMode ? Colors.black : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 5,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 24),
                label: const Text("Sync Now", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1.2)),
                onPressed: () {
                  app.forceSyncNow();
                }
              )
            ),
          if (app.errorMessage.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5))
              ),
              child: Text(
                app.errorMessage, 
                textAlign: TextAlign.center, 
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)
              )
            )
          ]
        ]
      )
    );
  }

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
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => MedicalResultScreen(app: app)));
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
                          hintText: "Search medical questions...",
                          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                          prefixIcon: const Icon(Icons.search), filled: false,
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
            if (_showBanner && !app.isExamMode && !app.isSyncRequired)
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
                          Text("Ready to crush your ${app.userCourse} (${app.userLevel}) boards? Select your topics to begin.", style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8))),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 24), 
                      color: Theme.of(context).colorScheme.primary, 
                      onPressed: () { 
                        setState(() {
                          _showBanner = false;
                        }); 
                        app.markWelcomeSeen(); 
                      }
                    )
                  ],
                ),
              ),
            if (app.activeTopics.isNotEmpty && !app.isSyncRequired)
              Container(
                height: 50, alignment: Alignment.centerLeft,
                child: ListView(
                  scrollDirection: Axis.horizontal, physics: const BouncingScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                  children: app.activeTopics.map((t) {
                    List<String> selectedYears = app.activeTopicYears[t] ??[];
                    bool isYearFiltered = selectedYears.isNotEmpty;
                    String yearDisplay = isYearFiltered ? (selectedYears.length == 1 ? selectedYears.first : "${selectedYears.length} Yrs") : "All";

                    return Container(
                      margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(15)),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(15), onTap: () => _showYearSelectorBottomSheet(context, app, t),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12, right: 5),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children:[
                                Text(t, style: TextStyle(color: app.isDarkMode ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                if (isYearFiltered) Padding(padding: const EdgeInsets.only(left: 4), child: Text("($yearDisplay)", style: TextStyle(color: app.isDarkMode ? Colors.black54 : Colors.white70, fontWeight: FontWeight.w900, fontSize: 11))),
                                Icon(Icons.arrow_drop_down, size: 18, color: app.isDarkMode ? Colors.black54 : Colors.white70),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => app.removeFilter(t),
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
              child: app.isSyncRequired
                  ? _buildSyncOverlay(app)
                  : app.filteredDB.isEmpty
                      ? Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Text(app.errorMessage.isNotEmpty ? app.errorMessage : "No questions match your criteria.", textAlign: TextAlign.center, style: TextStyle(color: app.errorMessage.isNotEmpty ? Colors.redAccent : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 16))))
                      : NotificationListener<ScrollUpdateNotification>(
                          onNotification: (notif) { 
                            app.trackScrollTick(notif.scrollDelta ?? 0); 
                            return false; 
                          },
                          child: ListView.builder(
                            physics: const BouncingScrollPhysics(), padding: const EdgeInsets.all(15), itemCount: pageItems.length,
                            itemBuilder: (ctx, i) => Padding(padding: const EdgeInsets.only(bottom: 20), child: MedicalQuestionCard(q: pageItems[i], app: app)),
                          ),
                        ),
            ),
            if (app.totalPages > 1 && !app.isSyncRequired)
              Container(
                height: 60, padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children:[
                    IconButton(icon: const Icon(Icons.chevron_left), onPressed: app.currentPage > 1 ? () => _changePage(app.currentPage - 1) : null),
                    Expanded(
                        child: NotificationListener<ScrollUpdateNotification>(
                      onNotification: (notif) { 
                        app.trackScrollTick(notif.scrollDelta ?? 0); 
                        return false; 
                      },
                      child: ListView.builder(
                          controller: _pageScrollController, scrollDirection: Axis.horizontal, itemCount: app.totalPages,
                          itemBuilder: (context, index) {
                            int page = index + 1; 
                            bool isActive = page == app.currentPage;
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
    int m = seconds ~/ 60; 
    int s = seconds % 60;
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
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle, boxShadow: const[BoxShadow(color: Colors.black12, blurRadius: 10)]), child: Icon(Icons.psychology, size: 40, color: Theme.of(context).colorScheme.primary)),
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
                        onTap: () { 
                          Clipboard.setData(ClipboardData(text: app.uniqueId)); 
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ID Copied!"))); 
                        },
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
                _buildDrawerItem(context, icon: Icons.menu_book_rounded, title: "Study Mode", onTap: () { 
                  app.exitExamMode(); 
                  Navigator.pop(context); 
                }),
                _buildDrawerItem(context, icon: Icons.timer_rounded, title: "Exam Mode", onTap: () { 
                  Navigator.pop(context); 
                  _showExamTimeDialog(context, app); 
                }),
                _buildDrawerItem(context, icon: Icons.sync_rounded, title: "Check for Updates", subtitle: "Secure manual sync", onTap: () { 
                  Navigator.pop(context); 
                  app.checkForUpdates(); 
                }),
                _buildDrawerItem(context, icon: Icons.logout_rounded, title: "Log Out", subtitle: "Testing only", onTap: () { 
                  Navigator.pop(context); 
                  app.logOut(); 
                }),
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
                  width: double.maxFinite, height: 450,
                  child: Column(
                    children:[
                      Expanded(
                          child: NotificationListener<ScrollUpdateNotification>(
                        onNotification: (notif) { 
                          app.trackScrollTick(notif.scrollDelta ?? 0); 
                          return false; 
                        },
                        child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 10), itemCount: app.allTopics.length,
                            itemBuilder: (c, i) {
                              String t = app.allTopics[i]; 
                              bool isSelected = tempFilters.contains(t);
                              return ListTile(
                                title: Text(t, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                                trailing: Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked, color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      tempFilters.remove(t);
                                    } else {
                                      tempFilters.add(t);
                                    }
                                  });
                                }
                              );
                            }),
                      )),
                      Container(
                        height: 60, padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children:[
                            Expanded(
                              child: TextButton(
                                style: TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3), foregroundColor: Theme.of(context).colorScheme.onSurface), 
                                onPressed: () { 
                                  setState(() {
                                    tempFilters.clear();
                                  }); 
                                  app.activeTopicYears.clear(); 
                                  app.applyFiltersWith(tempFilters); 
                                  Navigator.pop(ctx); 
                                }, 
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
            }));
  }

  void _showExamTimeDialog(BuildContext context, AppState app) {
    int selectedHour = 0; 
    int selectedMin = 10;
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (context, setState) {
              return AlertDialog(
                  backgroundColor: Theme.of(context).colorScheme.surface, title: const Text("EXAM DURATION", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  content: SizedBox(
                      height: 200,
                      child: Row(children:[
                        Expanded(
                          child: Column(
                            children:[
                              Text("HR", style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                              Expanded(
                                child: ListWheelScrollView.useDelegate(
                                    itemExtent: 40, physics: const FixedExtentScrollPhysics(), perspective: 0.005,
                                    onSelectedItemChanged: (v) { 
                                      app.playScrollSound(); 
                                      setState(() {
                                        selectedHour = v;
                                      }); 
                                    },
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
                                    onSelectedItemChanged: (v) { 
                                      app.playScrollSound(); 
                                      setState(() {
                                        selectedMin = v;
                                      }); 
                                    },
                                    childDelegate: ListWheelChildBuilderDelegate(childCount: 60, builder: (ctx, val) { return Center(child: Text("$val".padLeft(2, '0'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: selectedMin == val ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)))); })),
                              ),
                            ],
                          ),
                        )
                      ])),
                  actions:[
                    TextButton(
                      onPressed: () { 
                        int totalMins = selectedHour * 60 + selectedMin; 
                        if (totalMins == 0) {
                          totalMins = 1;
                        } 
                        
                        // INJECTED AUTO-SUBMIT CALLBACK
                        app.startExam(totalMins, onAutoSubmit: () {
                          if (mounted) {
                            Navigator.push(
                              context, 
                              MaterialPageRoute(builder: (_) => MedicalResultScreen(app: app))
                            );
                          }
                        }); 
                        Navigator.pop(ctx); 
                      }, 
                      child: Text("START", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16))
                    )
                  ]);
            }));
  }
}

// ----------------------------------------------------------------------------
class MedicalQuestionCard extends StatelessWidget {
  final QuestionModel q;
  final AppState app;
  const MedicalQuestionCard({super.key, required this.q, required this.app});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.outline)),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:[
          Row(children:[
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline, borderRadius: BorderRadius.circular(6)), child: Text(q.topic, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(6)), child: Text(q.year, style: TextStyle(color: app.isDarkMode ? Colors.black : Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 15),
          Text(q.stem, style: const TextStyle(fontSize: 17, height: 1.4, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          ...q.roots.map((r) => MedicalRootWidget(r: r, app: app)),
          if (!app.isExamMode) ...[
            const SizedBox(height: 15),
            GestureDetector(
              onTap: () => app.toggleAllAnswersForQuestion(q.id),
              child: Container(
                  width: double.infinity, height: 42, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outline), borderRadius: BorderRadius.circular(8)),
                  child: Text(app.isQuestionRevealed(q.id) ? "HIDE ANSWERS" : "SHOW ANSWERS", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.bold, fontSize: 12))),
            )
          ]
        ],
      ),
    );
  }
}

class MedicalRootWidget extends StatelessWidget {
  final RootItem r;
  final AppState app;
  const MedicalRootWidget({super.key, required this.r, required this.app});

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
                child: AnimatedContainer(duration: const Duration(milliseconds: 200), width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(color: dotBg, shape: BoxShape.circle, border: Border.all(color: dotBorder, width: 1.5)), child: Text(dotText, style: TextStyle(fontWeight: FontWeight.bold, color: dotTextColor, fontSize: 14))),
              ),
              const SizedBox(width: 15),
              Expanded(child: GestureDetector(onTap: () => app.toggleExplanation(r.id), child: Text(r.text, style: const TextStyle(fontSize: 15, height: 1.3)))),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200), curve: Curves.easeOutQuad,
          child: (showExp && !app.isExamMode) ? Container(margin: const EdgeInsets.only(left: 49, bottom: 5, right: 10), child: Text(r.info, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontStyle: FontStyle.italic, fontSize: 13))) : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
class MedicalResultScreen extends StatefulWidget {
  final AppState app;
  const MedicalResultScreen({super.key, required this.app});

  @override
  State<MedicalResultScreen> createState() => _MedicalResultScreenState();
}

class _MedicalResultScreenState extends State<MedicalResultScreen> {
  late ConfettiController _confettiController;
  
  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    if (widget.app.finalScore == 100) {
      _confettiController.play();
    }
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
                  const SizedBox(height: 50, child: Text("CLINICAL EVALUATION", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                  SizedBox(
                    height: 220,
                    child: Stack(alignment: Alignment.center, children:[
                      TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: widget.app.finalScore / 100), duration: const Duration(seconds: 2), curve: Curves.easeOutCubic,
                          builder: (context, value, child) { return SizedBox(width: 150, height: 150, child: CircularProgressIndicator(value: value, strokeWidth: 14, backgroundColor: Theme.of(context).colorScheme.outline, color: passed ? const Color(0xFF10B981) : const Color(0xFFEF4444))); }),
                      Text("${widget.app.finalScore}%", style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                  Container(height: 70, width: double.infinity, alignment: Alignment.centerLeft, padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)), child: Text(passed ? "BOARD READINESS: High." : "REMEDIATION: Required.", style: const TextStyle(fontWeight: FontWeight.bold))),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity, 
                    height: 55, 
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MedicalReviewScreen(app: widget.app))), 
                      child: const Text("REVIEW TOPICS", style: TextStyle(fontWeight: FontWeight.bold))
                    )
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity, 
                    height: 55, 
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.onSurface, foregroundColor: Theme.of(context).colorScheme.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
                      onPressed: () { 
                        widget.app.exitExamMode(); 
                        Navigator.pop(context); 
                      }, 
                      child: const Text("RETURN TO STUDY", style: TextStyle(fontWeight: FontWeight.bold))
                    )
                  ),
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

class MedicalReviewScreen extends StatelessWidget {
  final AppState app;
  const MedicalReviewScreen({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    var topics = app.topicPerformance.entries.toList();
    return Scaffold(
        body: SafeArea(
      child: Column(
        children:[
          SizedBox(height: 50, child: Row(children:[IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)), const Text("TOPIC BREAKDOWN", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))])),
          Expanded(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: (notif) { 
                app.trackScrollTick(notif.scrollDelta ?? 0); 
                return false; 
              },
              child: ListView.separated(
                physics: const BouncingScrollPhysics(), padding: const EdgeInsets.all(20), itemCount: topics.length, separatorBuilder: (_, __) => const SizedBox(height: 15),
                itemBuilder: (ctx, i) {
                  String topic = topics[i].key; 
                  int total = topics[i].value['total']!; 
                  int correct = topics[i].value['correct']!; 
                  int pct = total == 0 ? 0 : ((correct / total) * 100).toInt();
                  Color color = pct >= 80 ? const Color(0xFF10B981) : (pct >= 50 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));
                  IconData icon = pct >= 80 ? Icons.check_circle : (pct >= 50 ? Icons.error : Icons.cancel);
                  
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MedicalDetailedReviewScreen(app: app, topic: topic))),
                      child: Container(
                        padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.outline)),
                        child: Row(children:[Icon(icon, color: color, size: 28), const SizedBox(width: 15), Expanded(child: Text(topic, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))), Text("$pct%", style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(width: 10), Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3))]),
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

class MedicalDetailedReviewScreen extends StatelessWidget {
  final AppState app;
  final String topic;
  const MedicalDetailedReviewScreen({super.key, required this.app, required this.topic});

  @override
  Widget build(BuildContext context) {
    List<QuestionModel> topicQuestions = app.filteredDB.where((q) => q.topic == topic).toList();
    return Scaffold(
        body: SafeArea(
      child: Column(
        children:[
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outline))), child: Row(children:[IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)), Expanded(child: Text(topic, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis))])),
          Expanded(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: (notif) { 
                app.trackScrollTick(notif.scrollDelta ?? 0); 
                return false; 
              },
              child: ListView.builder(
                physics: const BouncingScrollPhysics(), padding: const EdgeInsets.all(15), itemCount: topicQuestions.length,
                itemBuilder: (ctx, i) => Padding(padding: const EdgeInsets.only(bottom: 20), child: MedicalReviewQuestionCard(q: topicQuestions[i], app: app)),
              ),
            ),
          ),
        ],
      ),
    ));
  }
}

class MedicalReviewQuestionCard extends StatelessWidget {
  final QuestionModel q;
  final AppState app;
  const MedicalReviewQuestionCard({super.key, required this.q, required this.app});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.outline)),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:[
          Row(children:[
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline, borderRadius: BorderRadius.circular(6)), child: Text(q.topic, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(6)), child: Text(q.year, style: TextStyle(color: app.isDarkMode ? Colors.black : Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 15),
          Text(q.stem, style: const TextStyle(fontSize: 17, height: 1.4, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          ...q.roots.map((r) => MedicalReviewRootWidget(r: r, app: app)),
        ],
      ),
    );
  }
}

class MedicalReviewRootWidget extends StatelessWidget {
  final RootItem r;
  final AppState app;
  const MedicalReviewRootWidget({super.key, required this.r, required this.app});

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
      children:[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children:[
              Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(color: dotBg, shape: BoxShape.circle, border: Border.all(color: dotBorder, width: 1.5)), child: Text(dotText, style: TextStyle(fontWeight: FontWeight.bold, color: dotTextColor, fontSize: 14))),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:[
                    GestureDetector(onTap: () => app.toggleExplanation(r.id), child: Text(r.text, style: const TextStyle(fontSize: 15, height: 1.3))),
                    const SizedBox(height: 6),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(4)), child: Row(mainAxisSize: MainAxisSize.min, children:[Icon(badgeIcon, size: 12, color: badgeTextColor), const SizedBox(width: 4), Text(badgeText, style: TextStyle(color: badgeTextColor, fontSize: 10, fontWeight: FontWeight.bold))]))
                  ],
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200), curve: Curves.easeOutQuad,
          child: showExp ? Container(margin: const EdgeInsets.only(left: 49, bottom: 10, right: 10), child: Text(r.info, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontStyle: FontStyle.italic, fontSize: 13))) : const SizedBox.shrink(),
        ),
      ],
    );
  }
}