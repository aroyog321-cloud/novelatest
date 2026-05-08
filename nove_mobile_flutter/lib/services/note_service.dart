import 'package:uuid/uuid.dart';
import '../models/note.dart';
import 'database_service.dart';

class NoteService {
  static const _uuid = Uuid();

  /// Calculate read time in minutes (returns 0 for empty content)
  static double _calculateReadTime(String content) {
    final wordCount = content
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .length;
    if (wordCount == 0) return 0.0;
    return (wordCount / 200).clamp(0.5, double.infinity);
  }

  /// Calculate word count
  static int _calculateWordCount(String content) {
    return content
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .length;
  }
  
  /// Extract tags (hashtags like #work) from content
  static List<String> _extractTags(String content) {
    final regex = RegExp(r'#(\w+)');
    return regex.allMatches(content).map((m) => m.group(1)!).toSet().toList();
  }

  /// Extract title from content (first line, truncated to 100 chars)
  static String _extractTitle(String content) {
    final firstLine = content.split('\n').first.trim();
    if (firstLine.isEmpty) return 'Untitled';
    if (firstLine.length > 100) {
      return '${firstLine.substring(0, 97)}...';
    }
    return firstLine;
  }

  static Future<List<Note>> getAllNotes() async {
    return await DatabaseService.getAllNotes();
  }

  static Future<Note?> getNoteById(String id) async {
    return await DatabaseService.getNoteById(id);
  }

  static Future<List<Note>> getPinnedNotes() async {
    return await DatabaseService.getPinnedNotes();
  }

  static Future<List<Note>> getFavoriteNotes() async {
    return await DatabaseService.getFavoriteNotes();
  }

  static Future<List<Note>> searchNotes(String query) async {
    if (query.isEmpty) return getAllNotes();
    return await DatabaseService.searchNotes(query);
  }

  static Future<Note> createNote(
    String content, {
    String? titleOverride,
    String? category,
    String colorLabel = '#FFFFFF',
    bool isPinned = false,
    bool isFavorite = false,
    int? reminder,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'note_${now}_${_uuid.v4().substring(0, 8)}';
    final title = (titleOverride != null && titleOverride.isNotEmpty)
        ? titleOverride
        : _extractTitle(content);
    final wordCount = _calculateWordCount(content);
    final charCount = content.length;
    final readTimeMinutes = _calculateReadTime(content);

    final note = Note(
      id: id,
      title: title,
      content: content,
      category: category,
      colorLabel: colorLabel,
      isPinned: isPinned,
      isFavorite: isFavorite,
      createdAt: now,
      updatedAt: now,
      wordCount: wordCount,
      charCount: charCount,
      readTimeMinutes: readTimeMinutes,
      reminder: reminder,
      tags: _extractTags(content),
    );

    await DatabaseService.insertNote(note);
    return note;
  }

  static Future<Note?> updateNote(
    String id, {
    String? title,
    String? content,
    String? category,
    String? colorLabel,
    bool? isPinned,
    bool? isFavorite,
    int? reminder,
  }) async {
    final existing = await DatabaseService.getNoteById(id);
    if (existing == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    final newContent = content ?? existing.content;
    final resolvedTitle = (title != null && title.isNotEmpty)
        ? title
        : _extractTitle(newContent);
    final wordCount = _calculateWordCount(newContent);
    final charCount = newContent.length;
    final readTimeMinutes = _calculateReadTime(newContent);

    final updatedNote = existing.copyWith(
      title: resolvedTitle,
      content: newContent,
      category: category ?? existing.category,
      colorLabel: colorLabel ?? existing.colorLabel,
      isPinned: isPinned ?? existing.isPinned,
      isFavorite: isFavorite ?? existing.isFavorite,
      updatedAt: now,
      wordCount: wordCount,
      charCount: charCount,
      readTimeMinutes: readTimeMinutes,
      reminder: reminder ?? existing.reminder,
      tags: _extractTags(newContent),
    );

    await DatabaseService.updateNote(updatedNote);
    return updatedNote;
  }

  static Future<bool> deleteNote(String id) async {
    final affected = await DatabaseService.deleteNote(id);
    return affected > 0;
  }

  static Future<Note?> togglePin(String id) async {
    final note = await DatabaseService.getNoteById(id);
    if (note == null) return null;
    return await updateNote(id, isPinned: !note.isPinned);
  }

  static Future<Note?> toggleFavorite(String id) async {
    final note = await DatabaseService.getNoteById(id);
    if (note == null) return null;
    return await updateNote(id, isFavorite: !note.isFavorite);
  }

  static Future<int> getNotesCount() async {
    return await DatabaseService.getNotesCount();
  }

  static Future<List<Note>> getNotesByCategory(String category) async {
    return await DatabaseService.getNotesByCategory(category);
  }

  static Future<void> clearAll() async {
    final notes = await getAllNotes();
    for (final note in notes) {
      await DatabaseService.deleteNote(note.id);
    }
  }
}