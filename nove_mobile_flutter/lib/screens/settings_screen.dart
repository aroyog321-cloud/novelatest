import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart'; 
import '../theme/tokens.dart';
import '../services/note_service.dart';
import '../services/security_service.dart'; // ADDED
import '../providers/notes_provider.dart';
import 'trash_screen.dart';
import '../services/stats_service.dart';
import '../../main.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _companionEnabled = true;
  bool _isExporting = false;
  bool _isLocked = false; 
  int _streak = 0;
  int _wordsToday = 0;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final locked = await SecurityService.isLockEnabled(); 
    final stats = await StatsService.getStats();
    setState(() {
      _companionEnabled = prefs.getBool('companion_enabled') ?? true;
      _isLocked = locked;
      _streak = stats['streak'] ?? 0;
      _wordsToday = stats['wordsToday'] ?? 0;
    });
  }

  Future<void> _saveCompanionPref(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('companion_enabled', val);
  }

  // ADDED: Handles turning lock on/off safely
  Future<void> _toggleLock(bool val) async {
    if (val) {
      final success = await SecurityService.authenticate();
      if (success) {
        await SecurityService.setLockEnabled(true);
        setState(() => _isLocked = true);
      }
    } else {
      final success = await SecurityService.authenticate();
      if (success) {
        await SecurityService.setLockEnabled(false);
        setState(() => _isLocked = false);
      }
    }
  }

  Future<void> _handleExport() async {
    setState(() => _isExporting = true);
    HapticFeedback.mediumImpact();

    try {
      final notes = await NoteService.getAllNotes();
      if (notes.isEmpty) {
        if (mounted) _showSnack('No notes to export.');
        return;
      }

      final buffer = StringBuffer();
      buffer.writeln('NOVE — Notes Export');
      buffer.writeln('Exported: ${DateTime.now().toLocal().toString().substring(0, 16)}');
      buffer.writeln('Total notes: ${notes.length}');
      buffer.writeln('=' * 48);
      buffer.writeln();

      for (final note in notes) {
        buffer.writeln(note.title.isNotEmpty ? note.title : 'Untitled');
        if ((note.category ?? '').isNotEmpty) {
          buffer.writeln('Category: ${note.category}');
        }
        buffer.writeln('Created: ${DateTime.fromMillisecondsSinceEpoch(note.createdAt).toLocal().toString().substring(0, 16)}');
        buffer.writeln('-' * 32);
        buffer.writeln(note.content);
        buffer.writeln();
        buffer.writeln('=' * 48);
        buffer.writeln();
      }

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toLocal().toString().substring(0, 16).replaceAll(':', '-').replaceAll(' ', '_');
      final file = File('${directory.path}/nove_export_$timestamp.txt');
      await file.writeAsString(buffer.toString());

      if (mounted) {
        final xfile = XFile(file.path);
        // ignore: deprecated_member_use
        await Share.shareXFiles([xfile], subject: 'My NOVE Notes Export');
        _showSnack('Export ready to save or share.', isSuccess: true);
      }
    } catch (e) {
      if (mounted) _showSnack('Export failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showSnack(String msg, {bool isSuccess = false}) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.info_outline,
              size: 16,
              color: isSuccess ? NoveColors.amber : Colors.white70,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(msg, style: GoogleFonts.dmSans(fontSize: 13))),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleDeleteAll() {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NoveColors.cardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete all notes?', style: GoogleFonts.lora(fontWeight: FontWeight.bold, color: NoveColors.primaryText(context))),
        content: Text('This action is permanent and cannot be undone. All your notes will be gone forever.', style: GoogleFonts.dmSans(color: NoveColors.secondaryText(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.dmSans(color: NoveColors.accent(context), fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () async {
              await NoteService.clearAll();
              await ref.read(notesProvider.notifier).loadNotes();
              if (mounted) {
                Navigator.pop(context);
                _showSnack('All notes deleted.');
              }
            },
            child: Text('Delete all', style: GoogleFonts.dmSans(color: NoveColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _handleResetOnboarding() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NoveColors.cardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset onboarding?', style: GoogleFonts.lora(fontWeight: FontWeight.bold, color: NoveColors.primaryText(context))),
        content: Text('You will see the welcome screens again on next launch.', style: GoogleFonts.dmSans(color: NoveColors.secondaryText(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.dmSans(color: NoveColors.accent(context))),
          ),
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('onboarding_done', false);
              if (mounted) {
                Navigator.pop(context);
                _showSnack('Onboarding will show on next launch.', isSuccess: true);
              }
            },
            child: Text('Reset', style: GoogleFonts.dmSans(color: NoveColors.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeMode = ref.watch(themeModeProvider);
    final notesState = ref.watch(notesProvider);

    return Scaffold(
      backgroundColor: NoveColors.bg(context),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            const SizedBox(height: 32),
            _sectionLabel('Your Journey', context: context),
            _JourneyDashboard(
              totalNotes: notesState.notes.length,
              totalWords: notesState.notes.fold(0, (sum, n) => sum + n.wordCount),
              streak: _streak,
              dailyGoal: 500, // Hardcoded for now or fetched from service
              wordsToday: _wordsToday,
            ),
            const SizedBox(height: 32),

            _sectionLabel('Appearance', context: context),
            _SettingsCard(
              isDark: isDark,
              children: [
                _SettingsRow(
                  icon: Icons.dark_mode_outlined,
                  iconBgColor: isDark ? const Color(0xFF2F2A22) : const Color(0xFFEEEDFE),
                  iconColor: const Color(0xFF534AB7),
                  title: 'Dark mode',
                  subtitle: 'Follows system by default',
                  trailing: DropdownButton<ThemeMode>(
                    value: themeMode,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    style: GoogleFonts.dmSans(fontSize: 12, color: NoveColors.secondaryText(context)),
                    dropdownColor: NoveColors.cardBg(context),
                    items: const [
                      DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                      DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                      DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        HapticFeedback.lightImpact();
                        ref.read(themeModeProvider.notifier).setMode(val);
                      }
                    },
                  ),
                ),
                _Divider(isDark: isDark),
                _SettingsRow(
                  icon: Icons.light_mode_outlined,
                  iconBgColor: isDark ? const Color(0xFF2F2A22) : const Color(0xFFFAEEDA),
                  iconColor: NoveColors.amberDark,
                  title: 'Show floating companion',
                  subtitle: 'Quick-capture bubble on screen',
                  trailing: Switch(
                    value: _companionEnabled,
                      onChanged: (v) {
                        HapticFeedback.lightImpact();
                        setState(() => _companionEnabled = v);
                        _saveCompanionPref(v);
                      },
                      activeThumbColor: NoveColors.accent(context),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _sectionLabel('Data & Privacy', context: context),
            _SettingsCard(
              isDark: isDark,
              children: [
                _SettingsRow(
                  icon: Icons.ios_share_rounded, 
                  iconBgColor: isDark ? const Color(0xFF1A2A1A) : const Color(0xFFEAF3DE),
                  iconColor: const Color(0xFF3B6D11),
                  title: 'Export & Share Notes',
                  subtitle: 'Save notes via Share Sheet (.txt)',
                  trailing: _isExporting
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: NoveColors.accent(context)))
                      : Icon(Icons.chevron_right_rounded, color: NoveColors.mutedText(context)),
                  onTap: _handleExport,
                ),
                _Divider(isDark: isDark),
                // CHANGED: Wired up the Biometric Switch here
                _SettingsRow(
                  icon: Icons.lock_outline_rounded,
                  iconBgColor: isDark ? const Color(0xFF1A1A2A) : const Color(0xFFEEEDFE),
                  iconColor: const Color(0xFF534AB7),
                  title: 'Biometric App Lock',
                  subtitle: 'Secure notes with FaceID/Fingerprint',
                  trailing: Switch(
                    value: _isLocked,
                    onChanged: (v) {
                      HapticFeedback.lightImpact();
                      _toggleLock(v);
                    },
                    activeThumbColor: NoveColors.accent(context),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                _Divider(isDark: isDark),
                _SettingsRow(
                  icon: Icons.undo_rounded,
                  iconBgColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEBE5D9),
                  iconColor: NoveColors.warmGray600,
                  title: 'Reset onboarding',
                  subtitle: 'See welcome screens on next launch',
                  trailing: Icon(Icons.chevron_right_rounded, color: NoveColors.mutedText(context)),
                  onTap: _handleResetOnboarding,
                ),
                _Divider(isDark: isDark),
                _SettingsRow(
                  icon: Icons.delete_sweep_rounded,
                  iconBgColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF0F0F0),
                  iconColor: NoveColors.secondaryText(context),
                  title: 'Trash',
                  subtitle: 'Restore deleted notes',
                  trailing: Icon(Icons.chevron_right_rounded, color: NoveColors.mutedText(context)),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashScreen()));
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            _sectionLabel('Danger Zone', context: context, color: NoveColors.error),
            _SettingsCard(
              isDark: isDark,
              borderColor: NoveColors.error.withValues(alpha: 0.2),
              children: [
                _SettingsRow(
                  icon: Icons.delete_outline_rounded,
                  iconBgColor: const Color(0xFFFCEBEB),
                  iconColor: NoveColors.error,
                  title: 'Delete all notes',
                  subtitle: 'Permanent — cannot be undone',
                  titleColor: NoveColors.error,
                  trailing: Icon(Icons.chevron_right_rounded, color: NoveColors.error.withValues(alpha: 0.6)),
                  onTap: _handleDeleteAll,
                ),
              ],
            ),
            const SizedBox(height: 24),

            _sectionLabel('About', context: context),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? NoveColors.cardDark : NoveColors.warmGray100.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(NoveRadii.lg),
                border: Border.all(color: NoveColors.cardBorder(context), width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Privacy statement', style: GoogleFonts.lora(fontSize: 18, fontWeight: FontWeight.bold, color: NoveColors.primaryText(context))),
                  const SizedBox(height: 10),
                  Text('NOVE is built with a privacy-first mindset. Your thoughts, sketches, and notes never leave your device unless you manually export them.', style: GoogleFonts.dmSans(fontSize: 13, color: NoveColors.secondaryText(context), height: 1.6)),
                ],
              ),
            ),
            const SizedBox(height: 40),

            Center(child: Text('Crafted for the intentional mind.', style: GoogleFonts.caveat(fontSize: 22, color: NoveColors.mutedText(context)))),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }
}

Widget _sectionLabel(String label, {required BuildContext context, Color? color}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 4),
    child: Text(label, style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: color ?? NoveColors.mutedText(context))),
  );
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final Color? borderColor;
  final bool isDark;

  const _SettingsCard({required this.children, required this.isDark, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NoveColors.cardBg(context),
        borderRadius: BorderRadius.circular(NoveRadii.lg),
        border: Border.all(color: borderColor ?? NoveColors.cardBorder(context), width: borderColor != null ? 1 : 0.5),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  const _SettingsRow({required this.icon, required this.iconBgColor, required this.iconColor, required this.title, required this.subtitle, required this.trailing, this.onTap, this.titleColor});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NoveRadii.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: iconColor, size: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600, color: titleColor ?? NoveColors.primaryText(context))),
                  const SizedBox(height: 1),
                  Text(subtitle, style: GoogleFonts.dmSans(fontSize: 12, color: NoveColors.secondaryText(context))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final bool isDark;
  const _Divider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 0.5, thickness: 0.5, color: NoveColors.cardBorder(context), indent: 66, endIndent: 0);
  }
}

class _JourneyDashboard extends StatelessWidget {
  final int totalNotes;
  final int totalWords;
  final int streak;
  final int dailyGoal;
  final int wordsToday;

  const _JourneyDashboard({
    required this.totalNotes,
    required this.totalWords,
    required this.streak,
    required this.dailyGoal,
    required this.wordsToday,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (wordsToday / dailyGoal).clamp(0.0, 1.0);
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: NoveColors.cardBg(context),
        borderRadius: BorderRadius.circular(NoveRadii.xxl),
        border: Border.all(color: NoveColors.cardBorder(context)),
        boxShadow: NoveShadows.cardElevated(context),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatItem(label: 'TOTAL NOTES', value: '$totalNotes', icon: Icons.description_outlined),
              _StatItem(label: 'STREAK', value: '$streak', icon: Icons.local_fire_department_rounded, color: NoveColors.amberDark),
              _StatItem(label: 'WORDS', value: '$totalWords', icon: Icons.edit_note_rounded, color: NoveColors.accent(context)),
            ],
          ),
          const SizedBox(height: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('DAILY GOAL', style: NoveTypography.label(context)),
                  Text('${(progress * 100).toInt()}%', style: NoveTypography.label(context).copyWith(color: NoveColors.accent(context))),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(NoveRadii.full),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: NoveColors.bg(context),
                  valueColor: AlwaysStoppedAnimation<Color>(NoveColors.accent(context)),
                ),
              ),
              const SizedBox(height: 8),
              Text('$wordsToday / $dailyGoal words today', style: NoveTypography.caption(context)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _StatItem({required this.label, required this.value, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color ?? NoveColors.secondaryText(context), size: 20),
        const SizedBox(height: 8),
        Text(value, style: NoveTypography.h3(context).copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: NoveTypography.label(context).copyWith(fontSize: 9)),
      ],
    );
  }
}