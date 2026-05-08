import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/note.dart';
import '../models/sticky_note.dart';
import '../providers/notes_provider.dart';
import '../providers/sticky_notes_provider.dart';
import '../services/database_service.dart';
import '../theme/tokens.dart';

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  List<Note> _deletedNotes = [];
  List<StickyNote> _deletedStickyNotes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTrash();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTrash() async {
    setState(() => _isLoading = true);
    final notes = await DatabaseService.getDeletedNotes();
    final stickyNotes = await ref.read(stickyNotesProvider.notifier).getTrashedNotes();
    if (mounted) {
      setState(() {
        _deletedNotes = notes;
        _deletedStickyNotes = stickyNotes;
        _isLoading = false;
      });
    }
  }

  // --- Notes actions ---
  Future<void> _restoreNote(String id) async {
    HapticFeedback.mediumImpact();
    await DatabaseService.restoreNote(id);
    await ref.read(notesProvider.notifier).loadNotes();
    await _loadTrash();
    _showSnack('Note restored');
  }

  Future<void> _permanentlyDeleteNote(String id) async {
    HapticFeedback.heavyImpact();
    await DatabaseService.permanentlyDeleteNote(id);
    await _loadTrash();
  }

  // --- Sticky actions ---
  Future<void> _restoreSticky(String id) async {
    HapticFeedback.mediumImpact();
    await ref.read(stickyNotesProvider.notifier).restoreFromTrash(id);
    await _loadTrash();
    _showSnack('Sticky Note restored');
  }

  Future<void> _permanentlyDeleteSticky(String id) async {
    HapticFeedback.heavyImpact();
    await ref.read(stickyNotesProvider.notifier).permanentlyDeleteTrash(id);
    await _loadTrash();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.dmSans(fontSize: 13)),
        backgroundColor: NoveColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _emptyTrash() async {
    HapticFeedback.heavyImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: NoveColors.cardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Empty Trash?', style: GoogleFonts.lora(fontWeight: FontWeight.bold, color: NoveColors.primaryText(context))),
        content: Text('This will permanently delete all items in the trash. This action cannot be undone.', style: GoogleFonts.dmSans(color: NoveColors.secondaryText(context))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: GoogleFonts.dmSans(color: NoveColors.accent(context), fontWeight: FontWeight.w600))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Empty', style: GoogleFonts.dmSans(color: NoveColors.error, fontWeight: FontWeight.w600))),
        ],
      ),
    );

    if (confirm == true) {
      if (_tabController.index == 0) {
        for (final note in _deletedNotes) {
          await DatabaseService.permanentlyDeleteNote(note.id);
        }
      } else {
        for (final sticky in _deletedStickyNotes) {
          await ref.read(stickyNotesProvider.notifier).permanentlyDeleteTrash(sticky.id);
        }
      }
      await _loadTrash();
      _showSnack('Trash emptied');
    }
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete_outline_rounded, size: 64, color: NoveColors.mutedText(context)),
          const SizedBox(height: 16),
          Text(message, style: GoogleFonts.dmSans(fontSize: 18, color: NoveColors.secondaryText(context))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canEmpty = (_tabController.index == 0 && _deletedNotes.isNotEmpty) || 
                          (_tabController.index == 1 && _deletedStickyNotes.isNotEmpty);
    return Scaffold(
      backgroundColor: NoveColors.bg(context),
      appBar: AppBar(
        backgroundColor: NoveColors.bg(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: NoveColors.primaryText(context), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Trash', style: GoogleFonts.lora(color: NoveColors.primaryText(context), fontWeight: FontWeight.bold)),
        actions: [
          if (canEmpty)
            TextButton(
              onPressed: _emptyTrash,
              child: Text('Empty', style: GoogleFonts.dmSans(color: NoveColors.error, fontWeight: FontWeight.w600)),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: NoveColors.accent(context),
          unselectedLabelColor: NoveColors.mutedText(context),
          indicatorColor: NoveColors.accent(context),
          onTap: (_) => setState(() {}),
          tabs: const [
            Tab(text: 'Notes'),
            Tab(text: 'Sticky Notes'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Notes Tab
                _deletedNotes.isEmpty
                    ? _buildEmptyState('No deleted notes')
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _deletedNotes.length,
                        itemBuilder: (context, index) {
                          final note = _deletedNotes[index];
                          return Card(
                            color: NoveColors.cardBg(context),
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: NoveColors.cardBorder(context))),
                            child: ListTile(
                              title: Text(note.title.isNotEmpty ? note.title : 'Untitled', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, color: NoveColors.primaryText(context))),
                              subtitle: Text(
                                note.content.replaceAll('\n', ' '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.dmSans(color: NoveColors.secondaryText(context)),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.restore, color: NoveColors.success),
                                    tooltip: 'Restore',
                                    onPressed: () => _restoreNote(note.id),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_forever, color: NoveColors.error),
                                    tooltip: 'Delete permanently',
                                    onPressed: () => _permanentlyDeleteNote(note.id),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                // Sticky Notes Tab
                _deletedStickyNotes.isEmpty
                    ? _buildEmptyState('No deleted sticky notes')
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _deletedStickyNotes.length,
                        itemBuilder: (context, index) {
                          final sticky = _deletedStickyNotes[index];
                          Color bgColor;
                          switch (sticky.color) {
                            case StickyColor.yellow: bgColor = const Color(0xFFFDE68A); break;
                            case StickyColor.pink: bgColor = const Color(0xFFFBCFE8); break;
                            case StickyColor.green: bgColor = const Color(0xFFA7F3D0); break;
                            case StickyColor.blue: bgColor = const Color(0xFFBFDBFE); break;
                          }
                          return Card(
                            color: bgColor,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: ListTile(
                              title: Text(sticky.title.isNotEmpty ? sticky.title : 'Untitled Sticky', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, color: Colors.black87)),
                              subtitle: Text(
                                sticky.content.replaceAll('\n', ' '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.dmSans(color: Colors.black54),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.restore, color: Color(0xFF166534)), // Dark green
                                    tooltip: 'Restore',
                                    onPressed: () => _restoreSticky(sticky.id),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_forever, color: Color(0xFF991B1B)), // Dark red
                                    tooltip: 'Delete permanently',
                                    onPressed: () => _permanentlyDeleteSticky(sticky.id),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
    );
  }
}
