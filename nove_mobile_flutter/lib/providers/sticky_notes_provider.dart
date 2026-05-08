import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/sticky_note.dart';
import '../services/app_link_service.dart';
import 'package:uuid/uuid.dart';

const _key = 'sticky_notes_v1';
const _trashKey = 'trashed_stickies_v1';
const _pinnedKey = 'pinned_stickies_v1';
const _uuid = Uuid();

final poppedOutNoteProvider = StateProvider<StickyNote?>((ref) => null);

class StickyNotesNotifier extends StateNotifier<List<StickyNote>> {
  StickyNotesNotifier() : super([]);
  
  List<String> _pinnedIds = [];

  Future<void> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    
    final raw = prefs.getString(_key);
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      state = list.map((m) => StickyNote.fromMap(Map<String, dynamic>.from(m))).toList();
    }
    
    final rawPinned = prefs.getString(_pinnedKey) ?? '[]';
    _pinnedIds = List<String>.from(jsonDecode(rawPinned));
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state.map((n) => n.toMap()).toList()));
  }

  Future<void> createNote(String title, StickyColor color, [String content = '']) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final note = StickyNote(
      id: 'sticky_${now}_${_uuid.v4().substring(0, 6)}',
      title: title,
      content: content,
      color: color,
      createdAt: now,
    );
    state = [note, ...state];
    await _save();
  }

  Future<void> updateNoteContent(String id, String newContent) async {
    state = state.map((n) {
      if (n.id == id) return n.copyWith(content: newContent);
      return n;
    }).toList();
    await _save();
  }

  Future<void> updateNotePosition(String id, double x, double y) async {
    state = state.map((n) {
      if (n.id == id) return n.copyWith(x: x, y: y);
      return n;
    }).toList();
    await _save();
  }

  bool isPinned(String id) => _pinnedIds.contains(id);

  Future<void> togglePin(String id) async {
    if (_pinnedIds.contains(id)) {
      _pinnedIds.remove(id);
    } else {
      _pinnedIds.add(id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinnedKey, jsonEncode(_pinnedIds));
    state = [...state]; 
  }

  Future<void> moveToTrash(String id) async {
    final noteIndex = state.indexWhere((n) => n.id == id);
    if (noteIndex == -1) return;
    final note = state[noteIndex];
    
    state = state.where((n) => n.id != id).toList();
    await _save();
    
    final prefs = await SharedPreferences.getInstance();
    final rawTrash = prefs.getString(_trashKey) ?? '[]';
    final trashList = jsonDecode(rawTrash) as List;
    trashList.insert(0, note.toMap());
    await prefs.setString(_trashKey, jsonEncode(trashList));
    
    await _syncNativeLinks();
  }

  Future<void> linkApp(String noteId, String packageName, String appName) async {
    state = state.map((n) {
      if (n.id == noteId) {
        return n.copyWith(linkedApp: LinkedApp(packageName: packageName, name: appName));
      }
      return n;
    }).toList();
    await _save();
    await _syncNativeLinks();
  }

  Future<void> unlinkApp(String noteId) async {
    state = state.map((n) {
      if (n.id == noteId) return n.copyWith(clearLink: true);
      return n;
    }).toList();
    await _save();
    await _syncNativeLinks();
  }

  Future<void> _syncNativeLinks() async {
    final links = <String, String>{};
    for (final note in state) {
      if (note.linkedApp != null) {
        links[note.linkedApp!.packageName] = note.id;
      }
    }
    await AppLinkService.syncLinks(links);
  }

  Future<List<StickyNote>> getTrashedNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final rawTrash = prefs.getString(_trashKey) ?? '[]';
    final trashList = jsonDecode(rawTrash) as List;
    return trashList.map((m) => StickyNote.fromMap(Map<String, dynamic>.from(m))).toList();
  }

  Future<void> restoreFromTrash(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final rawTrash = prefs.getString(_trashKey) ?? '[]';
    final trashList = jsonDecode(rawTrash) as List;
    
    final noteMap = trashList.firstWhere((m) => m['id'] == id, orElse: () => null);
    if (noteMap != null) {
      trashList.removeWhere((m) => m['id'] == id);
      await prefs.setString(_trashKey, jsonEncode(trashList));
      final note = StickyNote.fromMap(Map<String, dynamic>.from(noteMap));
      state = [note, ...state];
      await _save();
    }
  }

  Future<void> permanentlyDeleteTrash(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final rawTrash = prefs.getString(_trashKey) ?? '[]';
    final trashList = jsonDecode(rawTrash) as List;
    trashList.removeWhere((m) => m['id'] == id);
    await prefs.setString(_trashKey, jsonEncode(trashList));
  }

  Future<void> clearAll() async {
    state = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    _pinnedIds.clear();
    await prefs.remove(_pinnedKey);
    await _syncNativeLinks();
  }
}

final stickyNotesProvider = StateNotifierProvider<StickyNotesNotifier, List<StickyNote>>(
  (ref) => StickyNotesNotifier(),
);