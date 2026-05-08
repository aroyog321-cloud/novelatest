import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';
import 'dart:io';
import 'dart:convert';

class DatabaseService {
  static final List<Note> _notes = [];
  static bool _initialized = false;

  static Future<File> get _file async {
    final directory = await getApplicationDocumentsDirectory();
    return File(join(directory.path, 'nove_notes.json'));
  }

  /// Load notes from disk into memory. Safe to call multiple times — skips if
  /// already initialised. Call [forceReload] only when you genuinely need a
  /// fresh read (e.g. after external changes).
  static Future<void> init({bool forceReload = false}) async {
    if (_initialized && !forceReload) return;
    try {
      final file = await _file;
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _notes.clear();
        _notes.addAll(jsonList.map((j) => Note.fromJson(j)));
      }
    } catch (e) {
      debugPrint('Error loading notes: $e');
    }
    _initialized = true;
  }

  static Future<void> _save() async {
    try {
      final file = await _file;
      final jsonList = _notes.map((n) => n.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving notes: $e');
    }
  }

  static Future<void> close() async {
    _notes.clear();
    _initialized = false;
  }

  /// Sort helper: pinned notes first, then newest-updated first.
  static int _sortNotes(Note a, Note b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    return b.updatedAt.compareTo(a.updatedAt);
  }

  static Future<List<Note>> getAllNotes() async {
    await init();
    final sorted = _notes.where((n) => !n.isDeleted).toList()..sort(_sortNotes);
    return sorted;
  }

  static Future<Note?> getNoteById(String id) async {
    await init();
    try {
      return _notes.firstWhere((note) => note.id == id);
    } catch (e) {
      return null;
    }
  }

  static Future<List<Note>> getPinnedNotes() async {
    await init();
    return _notes.where((note) => note.isPinned && !note.isDeleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  static Future<List<Note>> getFavoriteNotes() async {
    await init();
    return _notes.where((note) => note.isFavorite && !note.isDeleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  static Future<List<Note>> searchNotes(String query) async {
    await init();
    final searchTerm = query.toLowerCase();
    final filtered = _notes.where((note) =>
        !note.isDeleted &&
        (note.title.toLowerCase().contains(searchTerm) ||
        note.content.toLowerCase().contains(searchTerm))).toList();
    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered;
  }

  static Future<int> insertNote(Note note) async {
    await init();
    _notes.add(note);
    await _save();
    return 1;
  }

  static Future<int> updateNote(Note note) async {
    await init();
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      _notes[index] = note;
      await _save();
      return 1;
    }
    return 0;
  }

  static Future<int> deleteNote(String id) async {
    await init();
    final index = _notes.indexWhere((n) => n.id == id);
    if (index != -1) {
      _notes[index] = _notes[index].copyWith(isDeleted: true);
      await _save();
      return 1;
    }
    return 0;
  }

  static Future<int> permanentlyDeleteNote(String id) async {
    await init();
    final initialLength = _notes.length;
    _notes.removeWhere((note) => note.id == id);
    await _save();
    return initialLength - _notes.length;
  }

  static Future<List<Note>> getDeletedNotes() async {
    await init();
    return _notes.where((note) => note.isDeleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  static Future<void> restoreNote(String id) async {
    await init();
    final index = _notes.indexWhere((n) => n.id == id);
    if (index != -1) {
      _notes[index] = _notes[index].copyWith(isDeleted: false);
      await _save();
    }
  }

  static Future<int> getNotesCount() async {
    await init();
    return _notes.where((n) => !n.isDeleted).length;
  }

  static Future<List<Note>> getNotesByCategory(String category) async {
    await init();
    return _notes.where((note) => !note.isDeleted && note.category == category).toList()
      ..sort(_sortNotes);
  }

  // ─── Note Version History ────────────────────────────────────────────────

  /// Maximum number of versions retained per note.
  static const int _maxVersionsPerNote = 10;

  static Future<File> get _versionsFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File(join(directory.path, 'nove_versions.json'));
  }

  /// Saves a snapshot of [note] as a new version entry.
  /// Keeps only the last [_maxVersionsPerNote] versions per note.
  static Future<void> saveVersion(Note note) async {
    try {
      final file = await _versionsFile;
      Map<String, dynamic> allVersions = {};
      if (await file.exists()) {
        final content = await file.readAsString();
        allVersions = Map<String, dynamic>.from(jsonDecode(content));
      }

      final List<dynamic> noteVersions = List.from(allVersions[note.id] ?? []);
      // Each version entry: snapshot of the note + a saved timestamp
      noteVersions.add({
        ...note.toJson(),
        'saved_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Keep only the most recent _maxVersionsPerNote
      if (noteVersions.length > _maxVersionsPerNote) {
        noteVersions.removeRange(0, noteVersions.length - _maxVersionsPerNote);
      }

      allVersions[note.id] = noteVersions;
      await file.writeAsString(jsonEncode(allVersions));
    } catch (e) {
      debugPrint('Error saving version: $e');
    }
  }

  /// Returns a list of historical [Note] snapshots for [noteId],
  /// newest first. Each snapshot's [updatedAt] reflects when the note
  /// was last modified at that point; [createdAt] is preserved.
  static Future<List<Note>> getVersions(String noteId) async {
    try {
      final file = await _versionsFile;
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final allVersions = Map<String, dynamic>.from(jsonDecode(content));
      final List<dynamic> raw = allVersions[noteId] ?? [];
      final versions = raw.map((v) => Note.fromJson(Map<String, dynamic>.from(v))).toList();
      return versions.reversed.toList(); // Newest first
    } catch (e) {
      debugPrint('Error reading versions: $e');
      return [];
    }
  }

  /// Removes all saved versions for [noteId] (e.g. after deleting a note).
  static Future<void> deleteVersions(String noteId) async {
    try {
      final file = await _versionsFile;
      if (!await file.exists()) return;
      final content = await file.readAsString();
      final allVersions = Map<String, dynamic>.from(jsonDecode(content));
      allVersions.remove(noteId);
      await file.writeAsString(jsonEncode(allVersions));
    } catch (e) {
      debugPrint('Error deleting versions: $e');
    }
  }
}