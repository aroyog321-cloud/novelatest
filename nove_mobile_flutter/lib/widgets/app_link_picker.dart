import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_link_service.dart';
import '../theme/tokens.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

void showAppLinkPicker({
  required BuildContext context,
  required Function(AppInfo) onAppSelected,
}) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _AppLinkPickerSheet(onAppSelected: onAppSelected),
  );
}

class _AppLinkPickerSheet extends StatefulWidget {
  final Function(AppInfo) onAppSelected;
  const _AppLinkPickerSheet({required this.onAppSelected});

  @override
  State<_AppLinkPickerSheet> createState() => _AppLinkPickerSheetState();
}

class _AppLinkPickerSheetState extends State<_AppLinkPickerSheet> with WidgetsBindingObserver {
  List<AppInfo> _apps = [];
  List<AppInfo> _filteredApps = [];
  bool _isLoading = true;
  bool _needsAccessibilityPermission = false;
  bool _needsOverlayPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadApps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_needsAccessibilityPermission || _needsOverlayPermission) {
        _loadApps();
      }
    }
  }

  Future<void> _loadApps() async {
    final hasAccessibilityPerm = await AppLinkService.isAccessibilityEnabled();
    final hasOverlayPerm = await FlutterOverlayWindow.isPermissionGranted();

    if (!hasAccessibilityPerm || !hasOverlayPerm) {
      setState(() {
        _needsAccessibilityPermission = !hasAccessibilityPerm;
        _needsOverlayPermission = !hasOverlayPerm;
        _isLoading = false;
      });
      return;
    }

    final apps = await AppLinkService.getInstalledApps();
    apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {
      _apps = apps;
      _filteredApps = apps;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: NoveColors.bg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: NoveColors.warmGray300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Link to App',
              style: GoogleFonts.lora(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: NoveColors.primaryText(context),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'This note will automatically pop up when you open the selected application.',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: NoveColors.secondaryText(context),
              ),
            ),
          ),
          
          if (_needsAccessibilityPermission || _needsOverlayPermission) ...[
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.admin_panel_settings, size: 48, color: NoveColors.accent(context)),
                      const SizedBox(height: 16),
                      Text(
                        'Permissions Required',
                        style: GoogleFonts.lora(fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'NOVE needs the following permissions to detect when you launch an app and to display the sticky note over it.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(color: NoveColors.secondaryText(context)),
                      ),
                      const SizedBox(height: 24),
                      if (_needsAccessibilityPermission)
                        ElevatedButton.icon(
                          onPressed: () async {
                            HapticFeedback.selectionClick();
                            await AppLinkService.openAccessibilitySettings();
                          },
                          icon: const Icon(Icons.settings_accessibility, size: 18),
                          label: const Text('Grant Accessibility'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NoveColors.accent(context),
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                      if (_needsAccessibilityPermission && _needsOverlayPermission)
                        const SizedBox(height: 12),
                      if (_needsOverlayPermission)
                        ElevatedButton.icon(
                          onPressed: () async {
                            HapticFeedback.selectionClick();
                            await FlutterOverlayWindow.requestPermission();
                          },
                          icon: const Icon(Icons.layers, size: 18),
                          label: const Text('Grant Display Over Apps'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NoveColors.terracotta,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        )
                    ],
                  ),
                ),
              ),
            )
          ] else if (_isLoading) ...[
            Expanded(
              child: Center(
                child: CircularProgressIndicator(color: NoveColors.accent(context)),
              ),
            )
          ] else ...[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search apps...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: NoveColors.cardBg(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _filteredApps = _apps
                        .where((a) => a.name.toLowerCase().contains(val.toLowerCase()))
                        .toList();
                  });
                },
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredApps.length,
                itemBuilder: (context, index) {
                  final app = _filteredApps[index];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDark ? NoveColors.cardDarkLight : NoveColors.warmGray100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.apps),
                    ),
                    title: Text(
                      app.name, 
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w600,
                        color: NoveColors.primaryText(context)
                      )
                    ),
                    subtitle: Text(
                      app.packageName,
                      style: GoogleFonts.dmSans(fontSize: 11, color: NoveColors.mutedText(context)),
                    ),
                    onTap: () {
                      widget.onAppSelected(app);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            )
          ],
        ],
      ),
    );
  }
}