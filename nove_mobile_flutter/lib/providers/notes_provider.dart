import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/note_service.dart';
import '../models/note.dart';

class NotesState {
  final List<Note> notes;
  final bool isLoading;
  final String? searchQuery;
  final String? selectedTag;
  final String? error;

  NotesState({
    this.notes = const [],
    this.isLoading = false,
    this.searchQuery,
    this.selectedTag,
    this.error,
  });

  List<String> get allTags {
    final tags = <String>{};
    for (final note in notes) {
      tags.addAll(note.tags);
    }
    return tags.toList()..sort();
  }

  NotesState copyWith({
    List<Note>? notes,
    bool? isLoading,
    String? searchQuery,
    String? selectedTag,
    bool clearSearch = false,
    bool clearTag = false,
    String? error,
  }) {
    return NotesState(
      notes: notes ?? this.notes,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: clearSearch ? null : (searchQuery ?? this.searchQuery),
      selectedTag: clearTag ? null : (selectedTag ?? this.selectedTag),
      error: error ?? this.error,
    );
  }
}

class NotesNotifier extends StateNotifier<NotesState> {
  NotesNotifier() : super(NotesState(isLoading: true)) {
    loadNotes();
  }

  Future<void> loadNotes() async {
    if (state.notes.isEmpty) {
      state = state.copyWith(isLoading: true, error: null);
    }
    try {
      final notes = await NoteService.getAllNotes();
      state = state.copyWith(notes: notes, isLoading: false, error: null, clearSearch: true, clearTag: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> search(String query) async {
    state = state.copyWith(isLoading: true, searchQuery: query, error: null);
    try {
      final notes = await NoteService.searchNotes(query);
      state = state.copyWith(notes: notes, isLoading: false, clearTag: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void selectTag(String? tag) {
    state = state.copyWith(selectedTag: tag, clearTag: tag == null);
  }

  Future<Note> createNote(
    String content, {
    String? title,
    String colorLabel = '#FFFFFF',
    String? category,
    bool isPinned = false,
    bool isFavorite = false,
    int? reminder,
  }) async {
    try {
      final note = await NoteService.createNote(
        content,
        titleOverride: title,
        colorLabel: colorLabel,
        category: category,
        isPinned: isPinned,
        isFavorite: isFavorite,
        reminder: reminder,
      );
      // Optimistic: prepend immediately
      state = state.copyWith(notes: [note, ...state.notes]);
      return note;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> updateNote(
    String id, {
    String? title,
    String? content,
    bool? isPinned,
    bool? isFavorite,
    String? colorLabel,
    String? category,
    int? reminder,
  }) async {
    try {
      await NoteService.updateNote(
        id,
        title: title,
        content: content,
        isPinned: isPinned,
        isFavorite: isFavorite,
        colorLabel: colorLabel,
        category: category,
        reminder: reminder,
      );
      // Optimistic local update — no DB round-trip
      final updatedNotes = state.notes.map((n) {
        if (n.id != id) return n;
        return n.copyWith(
          title: title ?? n.title,
          content: content ?? n.content,
          isPinned: isPinned ?? n.isPinned,
          isFavorite: isFavorite ?? n.isFavorite,
          colorLabel: colorLabel ?? n.colorLabel,
          category: category ?? n.category,
          reminder: reminder ?? n.reminder,
        );
      }).toList();
      state = state.copyWith(notes: updatedNotes);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      await loadNotes(); // Re-sync on error
    }
  }

  Future<void> deleteNote(String id) async {
    // Optimistic remove first so the card disappears instantly
    state = state.copyWith(notes: state.notes.where((n) => n.id != id).toList());
    try {
      await NoteService.deleteNote(id);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      await loadNotes(); // Re-sync on error
    }
  }

  /// Optimistic pin toggle — no DB round-trip on success
  Future<void> togglePin(String id) async {
    final current = state.notes.firstWhere((n) => n.id == id, orElse: () => throw StateError('Note not found'));
    final newPinned = !current.isPinned;
    state = state.copyWith(
      notes: state.notes.map((n) => n.id == id ? n.copyWith(isPinned: newPinned) : n).toList(),
    );
    try {
      await NoteService.togglePin(id);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      await loadNotes(); // Re-sync on error
    }
  }

  /// Optimistic favorite toggle — no DB round-trip on success
  Future<void> toggleFavorite(String id) async {
    final current = state.notes.firstWhere((n) => n.id == id, orElse: () => throw StateError('Note not found'));
    final newFav = !current.isFavorite;
    state = state.copyWith(
      notes: state.notes.map((n) => n.id == id ? n.copyWith(isFavorite: newFav) : n).toList(),
    );
    try {
      await NoteService.toggleFavorite(id);
    } catch (e) {
      state = state.copyWith(error: e.toString());
      await loadNotes(); // Re-sync on error
    }
  }
}

final notesProvider = StateNotifierProvider<NotesNotifier, NotesState>((ref) {
  return NotesNotifier();
});

final databaseInitProvider = FutureProvider<void>((ref) async {
  await NoteService.getAllNotes();
});