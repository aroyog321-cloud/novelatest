import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../services/category_service.dart';
import '../services/database_service.dart';
import '../services/stats_service.dart';
import '../services/export_service.dart';
import '../services/notification_service.dart';
import '../theme/tokens.dart';
import '../widgets/markdown_editing_controller.dart';

// ─── Backward-compat shim ────────────────
Future<List<String>> loadAllCategories() => CategoryService.loadAllCategories();
Future<void> saveCustomCategory(String cat) => CategoryService.saveCustomCategory(cat);

class EditorScreen extends ConsumerStatefulWidget {
  final Note? note;
  const EditorScreen({super.key, this.note});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  final ScrollController _editorScrollController = ScrollController();

  late bool _isPinned;
  late bool _isFavorite;
  late bool _isNewNote;
  late String _selectedCategory;
  late String _selectedColor;
  DateTime? _reminderDate;

  bool _hasChanges = false;
  bool _isSaved = false;
  bool _focusMode = false;
  bool _typewriterMode = false;
  bool _showScrollToTop = false;
  bool _showFindReplace = false;

  // Find & Replace state
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  List<int> _findMatches = [];
  int _findMatchIndex = 0;

  Timer? _debounce;

  List<String> _availableCategories = [...kBuiltInCategories];
  int _initialWordCount = 0;

  @override
  void initState() {
    super.initState();
    _isNewNote = widget.note == null;
    _initialWordCount = widget.note?.wordCount ?? 0;

    _titleController = TextEditingController(
      text: widget.note?.title == 'Untitled' ? '' : (widget.note?.title ?? ''),
    );
    _contentController = MarkdownEditingController(
      context: context,
      text: widget.note?.content ?? '',
    );

    _isPinned = widget.note?.isPinned ?? false;
    _isFavorite = widget.note?.isFavorite ?? false;
    _selectedCategory = widget.note?.category ?? '';
    _selectedColor = widget.note?.colorLabel ?? '#FFFFFF';
    _reminderDate = widget.note?.reminder != null 
        ? DateTime.fromMillisecondsSinceEpoch(widget.note!.reminder!) 
        : null;

    _titleController.addListener(_onChanged);
    _contentController.addListener(_onChanged);
    _contentController.addListener(_checkWikiLinkTrigger);
    _contentController.addListener(_checkSlashCommandTrigger);
    _contentController.addListener(_scrollToCursor);

    _editorScrollController.addListener(() {
      final shouldShow = _editorScrollController.offset > 200;
      if (shouldShow != _showScrollToTop) {
        setState(() => _showScrollToTop = shouldShow);
      }
    });

    _loadCategories();
  }

  void _onChanged() {
    setState(() {
      _hasChanges = true;
      _isSaved = false;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), _autoSave);
  }

  void _checkWikiLinkTrigger() {
    final text = _contentController.text;
    final sel = _contentController.selection;
    if (sel.isCollapsed && sel.baseOffset >= 2) {
      final lastTwo = text.substring(sel.baseOffset - 2, sel.baseOffset);
      if (lastTwo == '[[' ) {
        _showWikiLinkPicker();
      }
    }
  }

  void _checkSlashCommandTrigger() {
    final text = _contentController.text;
    final sel = _contentController.selection;
    if (sel.isCollapsed && sel.baseOffset >= 1) {
      final lastChar = text.substring(sel.baseOffset - 1, sel.baseOffset);
      if (lastChar == '/') {
        bool isValid = false;
        if (sel.baseOffset == 1) {
          isValid = true;
        } else {
          final prevChar = text.substring(sel.baseOffset - 2, sel.baseOffset - 1);
          if (prevChar == '\n' || prevChar == ' ') isValid = true;
        }
        if (isValid) {
          _showSlashCommandPicker();
        }
      }
    }
  }

  Future<void> _loadCategories() async {
    final cats = await CategoryService.loadAllCategories();
    if (mounted) setState(() => _availableCategories = cats);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _titleController.dispose();
    _contentController.dispose();
    _editorScrollController.dispose();
    _findController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  String get _effectiveTitle {
    final t = _titleController.text.trim();
    if (t.isNotEmpty) return t;
    final lines = _contentController.text.split('\n').where((l) => l.trim().isNotEmpty);
    if (lines.isEmpty) return 'Untitled';
    return lines.first.trim();
  }

  void _recordWordStats() {
    final newWordCount = _contentController.text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length;
    final diff = newWordCount - _initialWordCount;
    if (diff > 0) StatsService.addWords(diff);
    _initialWordCount = newWordCount;
  }

  Future<void> _saveAndClose() async {
    _debounce?.cancel();
    final content = _contentController.text.trim();
    final title = _effectiveTitle;

    if (content.isEmpty && _titleController.text.trim().isEmpty) {
      if (!_isNewNote && widget.note != null) {
        final confirm = await _showDiscardConfirm();
        if (confirm == true) {
          await ref.read(notesProvider.notifier).deleteNote(widget.note!.id);
        }
        if (mounted) Navigator.pop(context);
      } else {
        if (mounted) Navigator.pop(context);
      }
      return;
    }

    _recordWordStats();

    if (_isNewNote) {
      await ref.read(notesProvider.notifier).createNote(
            content,
            title: title,
            colorLabel: _selectedColor,
            category: _selectedCategory.isNotEmpty ? _selectedCategory : null,
            reminder: _reminderDate?.millisecondsSinceEpoch,
          );
    } else if (_hasChanges && widget.note != null) {
      await ref.read(notesProvider.notifier).updateNote(
        widget.note!.id,
        title: title,
        content: content,
        isPinned: _isPinned,
        isFavorite: _isFavorite,
        colorLabel: _selectedColor,
        category: _selectedCategory.isNotEmpty ? _selectedCategory : null,
        reminder: _reminderDate?.millisecondsSinceEpoch,
      );
      // Logic for versions... NoteService.updateNote returned Note?, but provider version returns void (optimistic)
      // I'll stick to the provider for consistency
    }

    HapticFeedback.lightImpact();
    if (mounted) Navigator.pop(context);
  }

  Future<bool?> _showDiscardConfirm() {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NoveColors.cardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Empty note', style: GoogleFonts.lora(fontWeight: FontWeight.bold, color: NoveColors.primaryText(context))),
        content: Text('This note is empty. Discard it?', style: GoogleFonts.dmSans(color: NoveColors.secondaryText(context))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Keep', style: GoogleFonts.dmSans(color: NoveColors.accent(context), fontWeight: FontWeight.w600))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Discard', style: GoogleFonts.dmSans(color: NoveColors.error))),
        ],
      ),
    );
  }

  Future<void> _autoSave() async {
    if (!_hasChanges) return;
    _recordWordStats();
    if (!_isNewNote && widget.note != null) {
      await ref.read(notesProvider.notifier).updateNote(
        widget.note!.id,
        title: _effectiveTitle,
        content: _contentController.text.trim(),
        isPinned: _isPinned,
        isFavorite: _isFavorite,
        colorLabel: _selectedColor,
        category: _selectedCategory.isNotEmpty ? _selectedCategory : null,
        reminder: _reminderDate?.millisecondsSinceEpoch,
      );
      if (mounted) setState(() { _isSaved = true; _hasChanges = false; });
    }
  }

  void _insertFormatting(String prefix, [String? suffix]) {
    HapticFeedback.selectionClick();
    var sel = _contentController.selection;
    if (!sel.isValid) sel = TextSelection.collapsed(offset: _contentController.text.length);
    final text = _contentController.text;
    final selected = sel.textInside(text);
    final replacement = suffix != null ? '$prefix$selected$suffix' : '$prefix$selected';
    final newText = text.replaceRange(sel.start, sel.end, replacement);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + replacement.length),
    );
  }

  // ─── WikiLink Picker ───────────────────────────────────────────────────────
  Future<void> _showWikiLinkPicker() async {
    final notes = ref.read(notesProvider).notes;
    showModalBottomSheet(
      context: context,
      backgroundColor: NoveColors.cardBg(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: NoveColors.warmGray300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('Link to Note', style: NoveTypography.h3(ctx)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final n = notes[index];
                return ListTile(
                  title: Text(n.title.isNotEmpty ? n.title : 'Untitled', style: NoveTypography.body(ctx)),
                  onTap: () {
                    Navigator.pop(ctx);
                    final name = n.title.isNotEmpty ? n.title : 'Untitled';
                    final sel = _contentController.selection;
                    final text = _contentController.text;
                    final newText = text.replaceRange(sel.start, sel.end, '$name]] ');
                    _contentController.value = TextEditingValue(
                      text: newText,
                      selection: TextSelection.collapsed(offset: sel.start + name.length + 3),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Slash Command Picker ──────────────────────────────────────────────────
  Future<void> _showSlashCommandPicker() async {
    final commands = [
      {'icon': Icons.title, 'label': 'Heading 1', 'insert': '# '},
      {'icon': Icons.title, 'label': 'Heading 2', 'insert': '## '},
      {'icon': Icons.title, 'label': 'Heading 3', 'insert': '### '},
      {'icon': Icons.format_list_bulleted, 'label': 'Bullet List', 'insert': '• '},
      {'icon': Icons.check_box_outlined, 'label': 'To-do List', 'insert': '☐ '},
      {'icon': Icons.format_quote, 'label': 'Quote', 'insert': '> '},
      {'icon': Icons.format_strikethrough, 'label': 'Strikethrough', 'insert': '~~text~~'},
      {'icon': Icons.code, 'label': 'Code Block', 'insert': '`\n\n`'},
      {'icon': Icons.image_outlined, 'label': 'Image', 'action': _insertImage},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: NoveColors.cardBg(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: NoveColors.warmGray300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Commands', style: NoveTypography.h3(ctx)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: commands.length,
                itemBuilder: (context, index) {
                  final cmd = commands[index];
                  return ListTile(
                    leading: Icon(cmd['icon'] as IconData, color: NoveColors.secondaryText(ctx)),
                    title: Text(cmd['label'] as String, style: NoveTypography.body(ctx)),
                    onTap: () {
                      Navigator.pop(ctx);
                      
                      final sel = _contentController.selection;
                      final text = _contentController.text;
                      final newText = text.replaceRange(sel.baseOffset - 1, sel.baseOffset, '');
                      _contentController.value = TextEditingValue(
                        text: newText,
                        selection: TextSelection.collapsed(offset: sel.baseOffset - 1),
                      );

                      if (cmd.containsKey('action')) {
                        (cmd['action'] as Function)();
                      } else if (cmd.containsKey('insert')) {
                        _insertFormatting(cmd['insert'] as String);
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─── Templates ─────────────────────────────────────────────────────────────
  Future<void> _showTemplatePicker() async {
    final templates = [
      {'title': 'Meeting Notes', 'content': '# Meeting: \n**Date:** \n**Attendees:** \n\n## Agenda\n• \n\n## Action Items\n☐ \n'},
      {'title': 'Daily Journal', 'content': '# Journal - \n\n## Morning Thoughts\n\n## Things I am grateful for\n1. \n2. \n3. \n'},
      {'title': 'Project Plan', 'content': '# Project: \n\n## Objectives\n• \n\n## Milestones\n☐ Phase 1: \n☐ Phase 2: \n\n## Notes\n'},
      {'title': 'Code Snippet', 'content': '# Snippet: \n\n**Description:** \n\n```\n// Your code here\n```\n'},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: NoveColors.cardBg(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: NoveColors.warmGray300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Templates', style: NoveTypography.h3(ctx)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: templates.length,
                itemBuilder: (context, index) {
                  final t = templates[index];
                  return ListTile(
                    leading: Icon(Icons.file_copy_outlined, color: NoveColors.secondaryText(ctx)),
                    title: Text(t['title']!, style: NoveTypography.body(ctx)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _contentController.text = t['content']!;
                      _titleController.text = t['title']!;
                      _onChanged();
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ─── Find & Replace ───────────────────────────────────────────────────────
  void _updateFindMatches() {
    final query = _findController.text;
    if (query.isEmpty) { setState(() { _findMatches = []; _findMatchIndex = 0; }); return; }
    final text = _contentController.text;
    final matches = <int>[];
    int idx = 0;
    while (true) {
      idx = text.toLowerCase().indexOf(query.toLowerCase(), idx);
      if (idx == -1) break;
      matches.add(idx);
      idx += query.length;
    }
    setState(() { _findMatches = matches; _findMatchIndex = 0; });
    if (matches.isNotEmpty) {
      _contentController.selection = TextSelection(baseOffset: matches[0], extentOffset: matches[0] + query.length);
    }
  }

  void _navigateMatch(int direction) {
    if (_findMatches.isEmpty) return;
    setState(() { _findMatchIndex = (_findMatchIndex + direction).clamp(0, _findMatches.length - 1); });
    final idx = _findMatches[_findMatchIndex];
    _contentController.selection = TextSelection(baseOffset: idx, extentOffset: idx + _findController.text.length);
  }

  void _replaceCurrentMatch() {
    if (_findMatches.isEmpty) return;
    final idx = _findMatches[_findMatchIndex];
    final query = _findController.text;
    final replacement = _replaceController.text;
    _contentController.text = _contentController.text.replaceRange(idx, idx + query.length, replacement);
    _onChanged();
    _updateFindMatches();
  }

  void _replaceAllMatches() {
    final query = _findController.text;
    if (query.isEmpty) return;
    _contentController.text = _contentController.text.replaceAll(query, _replaceController.text);
    _onChanged();
    _updateFindMatches();
  }

  // ─── Advanced Actions ──────────────────────────────────────────────────────
  Future<void> _insertImage() async {
    HapticFeedback.mediumImpact();
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: NoveColors.cardBg(context),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.camera_alt_outlined), title: const Text('Camera'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final file = await picker.pickImage(source: source, imageQuality: 85);
    if (file != null) _insertFormatting('![img](${file.path})');
  }

  Future<void> _setReminder() async {
    HapticFeedback.lightImpact();
    final date = await showDatePicker(
      context: context,
      initialDate: _reminderDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_reminderDate ?? DateTime.now()),
    );
    if (time == null || !mounted) return;
    
    final finalDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      _reminderDate = finalDate;
      _hasChanges = true;
    });

    if (widget.note != null) {
      await NotificationService.scheduleReminder(
        id: widget.note!.id.hashCode,
        title: 'Reminder: $_effectiveTitle',
        body: '${_contentController.text.substring(0, _contentController.text.length > 50 ? 50 : _contentController.text.length).trim()}...',
        scheduledDate: finalDate,
      );
    }
  }

  Future<void> _exportPdf() async {
    HapticFeedback.mediumImpact();
    final noteToExport = Note(
      id: widget.note?.id ?? 'temp',
      title: _effectiveTitle,
      content: _contentController.text,
      createdAt: widget.note?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      colorLabel: _selectedColor,
      isPinned: _isPinned,
      isFavorite: _isFavorite,
      wordCount: _initialWordCount,
      charCount: _contentController.text.length,
      readTimeMinutes: (_initialWordCount / 200).clamp(0.5, double.infinity),
    );
    await ExportService.exportNoteToPdf(noteToExport);
  }

  Future<void> _showVersionHistory() async {
    if (_isNewNote || widget.note == null) return;
    HapticFeedback.lightImpact();
    final versions = await DatabaseService.getVersions(widget.note!.id);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NoveColors.cardBg(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 16),
            Text('Version History', style: NoveTypography.h2(ctx)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                itemCount: versions.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final v = versions[i];
                  return ListTile(
                    title: Text(DateFormat('MMM d, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(v.updatedAt))),
                    subtitle: Text('${v.wordCount} words'),
                    trailing: TextButton(onPressed: () { Navigator.pop(ctx); _contentController.text = v.content; _titleController.text = v.title; _onChanged(); }, child: const Text('Restore')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddCategorySheet() async {
    final controller = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NoveColors.cardBg(context),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 24, right: 24, top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'New Category Name')),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  await saveCustomCategory(name);
                  await _loadCategories();
                  setState(() => _selectedCategory = name);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Add Category'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _toggleFocusMode() {
    HapticFeedback.mediumImpact();
    setState(() {
      _focusMode = !_focusMode;
      SystemChrome.setEnabledSystemUIMode(_focusMode ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    });
  }

  void _toggleFavorite() { HapticFeedback.selectionClick(); setState(() { _isFavorite = !_isFavorite; _hasChanges = true; }); }
  void _togglePin() { HapticFeedback.selectionClick(); setState(() { _isPinned = !_isPinned; _hasChanges = true; }); }

  void _scrollToCursor() {
    if (!_typewriterMode || !_contentController.selection.isCollapsed) return;
    
    // We wait for the selection to settle
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final text = _contentController.text;
      final offset = _contentController.selection.baseOffset;
      if (offset < 0) return;

      // Approximate line height from theme
      final lineCount = '\n'.allMatches(text.substring(0, offset)).length;
      const lineHeight = 28.0; 
      
      final viewportHeight = MediaQuery.of(context).size.height;
      // We want the cursor to be around 40% from the top
      final targetScroll = (lineCount * lineHeight) - (viewportHeight * 0.4);
      
      if (targetScroll > 0) {
        _editorScrollController.animateTo(
          targetScroll,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final wordCount = _initialWordCount;
    final readTime = (wordCount / 200).ceil().clamp(1, 99);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: NoveColors.bg(context),
      resizeToAvoidBottomInset: false, // Handle manually for smoother toolbar
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Bar ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: NoveColors.bg(context), border: Border(bottom: BorderSide(color: NoveColors.cardBorder(context), width: 0.5))),
              child: Row(
                children: [
                  GestureDetector(onTap: () {
                    _autoSave(); // Save silently and just go back
                    Navigator.pop(context);
                  }, child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16)),
                  const Spacer(),
                  _FormatIconBtn(icon: Icons.notifications_none_rounded, tooltip: 'Reminder', onTap: _setReminder, isDark: isDark, expand: false),
                  _FormatIconBtn(icon: Icons.picture_as_pdf_outlined, tooltip: 'Export PDF', onTap: _exportPdf, isDark: isDark, expand: false),
                  if (_isNewNote) _FormatIconBtn(icon: Icons.dashboard_customize_outlined, tooltip: 'Templates', onTap: _showTemplatePicker, isDark: isDark, expand: false),
                  _FormatIconBtn(icon: _typewriterMode ? Icons.vertical_align_center_rounded : Icons.vertical_align_center_outlined, tooltip: 'Typewriter', onTap: () => setState(() => _typewriterMode = !_typewriterMode), isDark: isDark, expand: false),
                  _FormatIconBtn(icon: _focusMode ? Icons.center_focus_weak : Icons.center_focus_strong, tooltip: 'Focus', onTap: _toggleFocusMode, isDark: isDark, expand: false),
                  _FormatIconBtn(icon: _isFavorite ? Icons.star_rounded : Icons.star_border_rounded, tooltip: 'Favorite', onTap: _toggleFavorite, isDark: isDark, expand: false),
                  _FormatIconBtn(icon: _isPinned ? Icons.push_pin : Icons.push_pin_outlined, tooltip: 'Pin', onTap: _togglePin, isDark: isDark, expand: false),
                  if (!_isNewNote) _FormatIconBtn(icon: Icons.history_rounded, tooltip: 'History', onTap: _showVersionHistory, isDark: isDark, expand: false),
                  TextButton(
                    onPressed: _saveAndClose, 
                    child: Text('Save', style: NoveTypography.body(context).copyWith(color: NoveColors.accent(context), fontWeight: FontWeight.bold))
                  ),
                ],
              ),
            ),

            if (!_focusMode) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: TextField(
                  controller: _titleController,
                  style: NoveTypography.h1(context),
                  decoration: const InputDecoration(hintText: 'Title', border: InputBorder.none),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  children: [
                    ..._availableCategories.map((cat) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _CategoryChip(label: cat, isActive: _selectedCategory == cat, onTap: () => setState(() => _selectedCategory = cat), context: context),
                    )),
                    _FormatIconBtn(icon: Icons.add_circle_outline, tooltip: 'New Cat', onTap: _showAddCategorySheet, isDark: isDark, expand: false),
                  ],
                ),
              ),
            ],

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _contentController,
                  scrollController: _editorScrollController,
                  maxLines: null,
                  expands: true,
                  autofocus: _isNewNote,
                  style: NoveTypography.editorFont(style: const TextStyle(fontSize: 18)),
                  decoration: const InputDecoration(hintText: 'Start writing...', border: InputBorder.none),
                ),
              ),
            ),

            // ── Toolbar & Keyboard Spacer ───────────────────────────────
            if (!_focusMode)
              Container(
                margin: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset + 8 : 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_showFindReplace)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: NoveColors.cardBg(context), borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: [
                            Row(children: [
                              Expanded(child: TextField(controller: _findController, onChanged: (_) => _updateFindMatches(), decoration: const InputDecoration(hintText: 'Find...'))),
                              IconButton(icon: const Icon(Icons.arrow_upward), onPressed: () => _navigateMatch(-1)),
                              IconButton(icon: const Icon(Icons.arrow_downward), onPressed: () => _navigateMatch(1)),
                              IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _showFindReplace = false)),
                            ]),
                            Row(children: [
                              Expanded(child: TextField(controller: _replaceController, decoration: const InputDecoration(hintText: 'Replace...'))),
                              TextButton(onPressed: _replaceCurrentMatch, child: const Text('Replace')),
                              TextButton(onPressed: _replaceAllMatches, child: const Text('All')),
                            ]),
                          ],
                        ),
                      ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: NoveColors.cardBg(context), borderRadius: BorderRadius.circular(NoveRadii.md), border: Border.all(color: NoveColors.cardBorder(context), width: 0.5)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _FormatBtn(label: 'B', bold: true, onTap: () => _insertFormatting('**', '**'), isDark: isDark),
                          _FormatBtn(label: 'I', italic: true, onTap: () => _insertFormatting('_', '_'), isDark: isDark),
                          _FormatBtn(label: 'S̶', onTap: () => _insertFormatting('~~', '~~'), isDark: isDark),
                          _FormatBtn(label: '#', onTap: () => _insertFormatting('# '), isDark: isDark),
                          _FormatIconBtn(icon: Icons.format_list_bulleted, tooltip: 'List', onTap: () => _insertFormatting('• '), isDark: isDark),
                          _FormatIconBtn(icon: Icons.check_box_outlined, tooltip: 'Task', onTap: () => _insertFormatting('☐ '), isDark: isDark),
                          _FormatIconBtn(icon: Icons.image_outlined, tooltip: 'Image', onTap: _insertImage, isDark: isDark),
                          _FormatIconBtn(icon: Icons.search_rounded, tooltip: 'Find', onTap: () => setState(() => _showFindReplace = !_showFindReplace), isDark: isDark),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          Text('$wordCount words · $readTime min', style: NoveTypography.caption(context)),
                          const Spacer(),
                          if (_isSaved) Row(children: [Icon(Icons.check_circle, size: 12, color: NoveColors.accent(context)), const SizedBox(width: 4), Text('Saved', style: NoveTypography.caption(context).copyWith(color: NoveColors.accent(context)))]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final BuildContext context;
  const _CategoryChip({required this.label, required this.isActive, required this.onTap, required this.context});

  @override
  Widget build(BuildContext _) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: isActive ? NoveColors.accent(context) : Colors.transparent, borderRadius: BorderRadius.circular(NoveRadii.full), border: Border.all(color: isActive ? Colors.transparent : NoveColors.cardBorder(context))),
        child: Text(label, style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600, color: isActive ? Colors.white : NoveColors.secondaryText(context))),
      ),
    );
  }
}

class _FormatBtn extends StatelessWidget {
  final String label;
  final bool bold;
  final bool italic;
  final VoidCallback onTap;
  final bool isDark;
  const _FormatBtn({required this.label, required this.onTap, required this.isDark, this.bold = false, this.italic = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(child: Text(label, style: GoogleFonts.dmSans(fontSize: 15, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, fontStyle: italic ? FontStyle.italic : FontStyle.normal, color: NoveColors.secondaryText(context)))),
        ),
      ),
    );
  }
}

class _FormatIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isDark;
  final bool expand;
  const _FormatIconBtn({required this.icon, required this.tooltip, required this.onTap, required this.isDark, this.expand = true});

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(onTap: onTap, child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, size: 20, color: NoveColors.secondaryText(context))));
    return expand ? Expanded(child: child) : child;
  }
}