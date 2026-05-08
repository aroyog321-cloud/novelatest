import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../services/category_service.dart';
import '../services/stats_service.dart';
import '../theme/tokens.dart';
import 'editor_screen.dart';

enum _SortOrder { updatedDesc, updatedAsc, titleAsc, titleDesc, wordCountDesc }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String _selectedCategory = 'All';
  bool _isSearching = false;
  _SortOrder _sortOrder = _SortOrder.updatedDesc;
  List<String> _categories = ['All', 'Work', 'Ideas', 'Personal', 'Urgent', '★ Starred'];

  int _streak = 0;
  int _wordsToday = 0;
  final Set<String> _selectedNoteIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notesProvider.notifier).loadNotes();
    });
    _refreshCategories();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final stats = await StatsService.getStats();
    if (mounted) {
      setState(() {
        _streak = stats['streak'] ?? 0;
        _wordsToday = stats['wordsToday'] ?? 0;
      });
    }
  }

  Future<void> _refreshCategories() async {
    final custom = await CategoryService.loadAllCategories();
    if (mounted) {
      setState(() {
        _categories = ['All', ...custom, '★ Starred'];
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    if (query.isEmpty) {
      ref.read(notesProvider.notifier).loadNotes();
    } else {
      ref.read(notesProvider.notifier).search(query);
    }
  }

  void _openNote(Note note) {
    if (_isSelectionMode) {
      _toggleNoteSelection(note.id);
      return;
    }
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(note: note)),
    ).then((_) {
      ref.read(notesProvider.notifier).loadNotes();
      _refreshCategories();
      _loadStats();
    });
  }

  void _toggleNoteSelection(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedNoteIds.contains(id)) {
        _selectedNoteIds.remove(id);
        if (_selectedNoteIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedNoteIds.add(id);
        _isSelectionMode = true;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedNoteIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _bulkDelete() async {
    final ids = _selectedNoteIds.toList();
    for (final id in ids) {
      await ref.read(notesProvider.notifier).deleteNote(id);
    }
    _clearSelection();
  }

  Future<void> _bulkPin() async {
    final ids = _selectedNoteIds.toList();
    for (final id in ids) {
      await ref.read(notesProvider.notifier).togglePin(id);
    }
    _clearSelection();
  }

  void _createNote() {
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EditorScreen()),
    ).then((_) {
      ref.read(notesProvider.notifier).loadNotes();
      _refreshCategories();
      _loadStats();
    });
  }

  List<Note> _getFilteredNotes(List<Note> notes, String? selectedTag) {
    List<Note> filtered;
    if (_selectedCategory == 'All') {
      filtered = List.from(notes);
    } else if (_selectedCategory == '★ Starred') {
      filtered = notes.where((n) => n.isFavorite).toList();
    } else {
      filtered = notes.where((n) => (n.category ?? '').toLowerCase() == _selectedCategory.toLowerCase()).toList();
    }

    if (selectedTag != null) {
      filtered = filtered.where((n) => n.tags.contains(selectedTag)).toList();
    }
    filtered.sort((a, b) {
      // Always prioritize pinned notes at the top
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;

      // Secondary sort based on user preference
      switch (_sortOrder) {
        case _SortOrder.updatedDesc: return b.updatedAt.compareTo(a.updatedAt);
        case _SortOrder.updatedAsc: return a.updatedAt.compareTo(b.updatedAt);
        case _SortOrder.titleAsc: return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case _SortOrder.titleDesc: return b.title.toLowerCase().compareTo(a.title.toLowerCase());
        case _SortOrder.wordCountDesc: return b.wordCount.compareTo(a.wordCount);
      }
    });
    return filtered;
  }

  Map<String, int> _getCategoryCounts(List<Note> notes) {
    final counts = <String, int>{};
    for (final cat in _categories) {
      if (cat == 'All') counts[cat] = notes.length;
      else if (cat == '★ Starred') counts[cat] = notes.where((n) => n.isFavorite).length;
      else counts[cat] = notes.where((n) => (n.category ?? '').toLowerCase() == cat.toLowerCase()).length;
    }
    return counts;
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notesState = ref.watch(notesProvider);
    final filteredNotes = _getFilteredNotes(notesState.notes, notesState.selectedTag);
    final counts = _getCategoryCounts(notesState.notes);

    return Scaffold(
      backgroundColor: NoveColors.bg(context),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: AnimatedContainer(
                  duration: NoveAnimation.fast,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _isSelectionMode ? NoveColors.accent(context).withValues(alpha: 0.1) : NoveColors.cardBg(context),
                    borderRadius: BorderRadius.circular(NoveRadii.xxl),
                    border: Border.all(color: _isSelectionMode ? NoveColors.accent(context) : NoveColors.cardBorder(context), width: _isSelectionMode ? 2 : 1),
                    boxShadow: NoveShadows.cardElevated(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_isSelectionMode ? 'Selection Mode' : _getGreeting(), style: NoveTypography.bodySm(context).copyWith(color: NoveColors.accent(context), fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(_isSelectionMode ? '${_selectedNoteIds.length} Selected' : 'Ready to write?', style: NoveTypography.h1(context)),
                            ],
                          ),
                          if (_isSelectionMode)
                            Row(
                              children: [
                                _IconBtn(icon: Icons.push_pin_rounded, onTap: _bulkPin, isDark: isDark),
                                const SizedBox(width: 8),
                                _IconBtn(icon: Icons.delete_rounded, onTap: _bulkDelete, isDark: isDark),
                                const SizedBox(width: 8),
                                _IconBtn(icon: Icons.close_rounded, onTap: _clearSelection, isDark: isDark),
                              ],
                            )
                          else
                            _IconBtn(icon: _isSearching ? Icons.close_rounded : Icons.search_rounded, onTap: () { setState(() { _isSearching = !_isSearching; if (!_isSearching) { _searchController.clear(); ref.read(notesProvider.notifier).loadNotes(); } }); }, isDark: isDark),
                        ],
                      ),
                      if (!_isSelectionMode) ...[
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(child: _BentoStat(label: 'Notes', value: '${notesState.notes.length}', icon: Icons.description_outlined)),
                            const SizedBox(width: 12),
                            Expanded(child: _BentoStat(label: 'Streak', value: '$_streak', icon: Icons.local_fire_department_rounded)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: AnimatedContainer(
                duration: NoveAnimation.fast,
                height: _isSearching ? 64 : 0,
                child: _isSearching ? Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 16), child: Container(decoration: BoxDecoration(color: NoveColors.inputBg(context), borderRadius: BorderRadius.circular(NoveRadii.lg)), child: TextField(controller: _searchController, autofocus: true, onChanged: _onSearch, decoration: const InputDecoration(hintText: 'Search your thoughts...', prefixIcon: Icon(Icons.search), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14))))) : const SizedBox.shrink(),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _CategoryHeaderDelegate(child: Container(color: NoveColors.bg(context).withValues(alpha: 0.95), child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: CategoryFilterBar(categories: _categories, counts: counts, selectedCategory: _selectedCategory, onSelect: (cat) => setState(() => _selectedCategory = cat))))),
            ),
            if (notesState.allTags.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TagFilterBar(
                    tags: notesState.allTags,
                    selectedTag: notesState.selectedTag,
                    onSelect: (tag) => ref.read(notesProvider.notifier).selectTag(tag),
                  ),
                ),
              ),
            if (notesState.isLoading) const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (notesState.error != null) SliverFillRemaining(child: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error_outline, size: 48, color: NoveColors.error), const SizedBox(height: 16), Text('Failed to load notes', style: NoveTypography.h3(context)), const SizedBox(height: 8), Text(notesState.error!, textAlign: TextAlign.center, style: NoveTypography.bodySm(context).copyWith(color: NoveColors.mutedText(context))), const SizedBox(height: 24), ElevatedButton(onPressed: () => ref.read(notesProvider.notifier).loadNotes(), child: const Text('Try Again'))]))))
            else if (filteredNotes.isEmpty) SliverFillRemaining(child: EnhancedEmptyState(state: _isSearching ? EmptyStateType.search : EmptyStateType.onboarding, onAction: _createNote))
            else SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final note = filteredNotes[index];
                    return NoteCard(
                      note: note,
                      onTap: () => _isSelectionMode ? _toggleNoteSelection(note.id) : _openNote(note),
                      onDelete: () => ref.read(notesProvider.notifier).deleteNote(note.id),
                      onPin: () => ref.read(notesProvider.notifier).togglePin(note.id),
                      onFavorite: () => ref.read(notesProvider.notifier).toggleFavorite(note.id),
                      onColorChange: (color) => ref.read(notesProvider.notifier).updateNote(note.id, colorLabel: color),
                      isSelected: _selectedNoteIds.contains(note.id),
                      onLongPress: () => _toggleNoteSelection(note.id),
                      searchQuery: _searchController.text,
                    );
                  },
                  childCount: filteredNotes.length,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(padding: const EdgeInsets.only(bottom: 84), child: EnhancedFAB(scrollController: _scrollController, onPressed: _createNote)),
    );
  }

  void _showSortSheet(BuildContext context) {
    showModalBottomSheet(context: context, backgroundColor: NoveColors.cardBg(context), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
      for (final entry in [(_SortOrder.updatedDesc, 'Newest first', Icons.update), (_SortOrder.updatedAsc, 'Oldest first', Icons.history), (_SortOrder.titleAsc, 'A-Z', Icons.sort_by_alpha), (_SortOrder.titleDesc, 'Z-A', Icons.sort_by_alpha), (_SortOrder.wordCountDesc, 'Most words', Icons.article)])
        ListTile(leading: Icon(entry.$3), title: Text(entry.$2), onTap: () { setState(() => _sortOrder = entry.$1); Navigator.pop(ctx); }),
    ]));
  }
}

class _CategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _CategoryHeaderDelegate({required this.child});
  @override double get minExtent => 60.0;
  @override double get maxExtent => 60.0;
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;
  @override bool shouldRebuild(_CategoryHeaderDelegate old) => true;
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;
  const _IconBtn({required this.icon, required this.onTap, required this.isDark});
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(width: 36, height: 36, decoration: BoxDecoration(color: NoveColors.cardBg(context), borderRadius: BorderRadius.circular(NoveRadii.full), border: Border.all(color: NoveColors.cardBorder(context), width: 0.5)), child: Icon(icon, size: 18, color: NoveColors.secondaryText(context))));
}

class StatCard extends StatelessWidget {
  final String label;
  final int value;
  const StatCard({super.key, required this.label, required this.value});
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: NoveColors.cardBg(context), borderRadius: BorderRadius.circular(NoveRadii.md), border: Border.all(color: NoveColors.cardBorder(context))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label.toUpperCase(), style: NoveTypography.label(context)), const SizedBox(height: 8), Text('$value', style: NoveTypography.h1(context).copyWith(color: NoveColors.accent(context)))]));
}

class CategoryFilterBar extends StatelessWidget {
  final List<String> categories;
  final Map<String, int> counts;
  final String selectedCategory;
  final ValueChanged<String> onSelect;
  const CategoryFilterBar({super.key, required this.categories, required this.counts, required this.selectedCategory, required this.onSelect});
  @override Widget build(BuildContext context) => SizedBox(
    height: 48, 
    child: ListView.separated(
      scrollDirection: Axis.horizontal, 
      padding: const EdgeInsets.symmetric(horizontal: 24), 
      itemCount: categories.length, 
      separatorBuilder: (_, __) => const SizedBox(width: 10), 
      itemBuilder: (ctx, i) {
        final cat = categories[i];
        final active = selectedCategory == cat;
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onSelect(cat);
          }, 
          child: AnimatedContainer(
            duration: NoveAnimation.fast,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), 
            decoration: BoxDecoration(
              color: active ? NoveColors.accent(context) : NoveColors.cardBg(context), 
              borderRadius: BorderRadius.circular(NoveRadii.full), 
              border: Border.all(color: active ? Colors.transparent : NoveColors.cardBorder(context), width: 1),
              boxShadow: active ? NoveShadows.cardSmall(context) : null,
            ), 
            child: Row(
              children: [
                Text(cat, style: NoveTypography.body(context).copyWith(color: active ? Colors.white : NoveColors.primaryText(context), fontWeight: active ? FontWeight.bold : FontWeight.w500)),
                if (counts[cat] != null && counts[cat]! > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: active ? Colors.white.withOpacity(0.2) : NoveColors.accent(context).withOpacity(0.1), borderRadius: BorderRadius.circular(NoveRadii.full)),
                    child: Text('${counts[cat]}', style: NoveTypography.caption(context).copyWith(color: active ? Colors.white : NoveColors.accent(context), fontWeight: FontWeight.bold, fontSize: 10)),
                  ),
                ],
              ],
            ),
          ),
        );
      }
    ),
  );
}

class TagFilterBar extends StatelessWidget {
  final List<String> tags;
  final String? selectedTag;
  final ValueChanged<String?> onSelect;
  const TagFilterBar({super.key, required this.tags, this.selectedTag, required this.onSelect});
  @override Widget build(BuildContext context) => SizedBox(
    height: 40, 
    child: ListView.separated(
      scrollDirection: Axis.horizontal, 
      padding: const EdgeInsets.symmetric(horizontal: 24), 
      itemCount: tags.length + 1, 
      separatorBuilder: (_, __) => const SizedBox(width: 10), 
      itemBuilder: (ctx, i) {
        if (i == 0) {
          final active = selectedTag == null;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onSelect(null);
            }, 
            child: AnimatedContainer(
              duration: NoveAnimation.fast,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
              decoration: BoxDecoration(
                color: active ? NoveColors.terracotta.withOpacity(0.1) : Colors.transparent, 
                borderRadius: BorderRadius.circular(NoveRadii.full), 
                border: Border.all(color: active ? NoveColors.terracotta : NoveColors.cardBorder(context), width: 1)
              ), 
              child: Text('All Tags', style: NoveTypography.caption(context).copyWith(color: active ? NoveColors.terracotta : NoveColors.secondaryText(context), fontWeight: active ? FontWeight.bold : FontWeight.normal))
            ),
          );
        }
        final tag = tags[i - 1];
        final active = selectedTag == tag;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onSelect(tag);
          }, 
          child: AnimatedContainer(
            duration: NoveAnimation.fast,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
            decoration: BoxDecoration(
              color: active ? NoveColors.amber.withOpacity(0.15) : Colors.transparent, 
              borderRadius: BorderRadius.circular(NoveRadii.full), 
              border: Border.all(color: active ? NoveColors.amberDark : NoveColors.cardBorder(context), width: 1),
              boxShadow: active ? [BoxShadow(color: NoveColors.amber.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))] : null,
            ), 
            child: Text('#$tag', style: NoveTypography.caption(context).copyWith(color: active ? NoveColors.amberDark : NoveColors.secondaryText(context), fontWeight: active ? FontWeight.bold : FontWeight.normal))
          ),
        );
      }
    ),
  );
}

enum EmptyStateType { onboarding, category, search }
class EnhancedEmptyState extends StatelessWidget {
  final EmptyStateType state;
  final VoidCallback onAction;
  const EnhancedEmptyState({super.key, required this.state, required this.onAction});
  @override Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(state == EmptyStateType.search ? Icons.search_off : Icons.edit_document, size: 64, color: NoveColors.terracottaLight), const SizedBox(height: 16), Text(state == EmptyStateType.search ? 'No matches' : 'Start writing', style: NoveTypography.h2(context)), const SizedBox(height: 32), ElevatedButton(onPressed: onAction, child: const Text('New Note'))]));
}

class NoteCard extends StatefulWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  final VoidCallback onFavorite;
  final ValueChanged<String> onColorChange;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final String searchQuery;
  const NoteCard({super.key, required this.note, required this.onTap, required this.onDelete, required this.onPin, required this.onFavorite, required this.onColorChange, this.isSelected = false, this.onLongPress, this.searchQuery = ''});
  @override State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  static String _cleanPreview(String raw) => raw.replaceAll(RegExp(r'[#*`\[\]!()]'), '').trim().replaceAll(RegExp(r'\s+'), ' ');
  Color _getLeftBorderColor(Note note) => note.colorLabel != '#FFFFFF' ? Color(int.parse(note.colorLabel.replaceFirst('#', '0xFF'))) : NoveColors.terracotta;

  @override Widget build(BuildContext context) {
    return Slidable(
      key: Key(widget.note.id),
      startActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => widget.onPin(),
            backgroundColor: NoveColors.terracotta,
            foregroundColor: Colors.white,
            icon: Icons.push_pin,
            label: 'Pin',
            borderRadius: BorderRadius.circular(NoveRadii.lg),
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => widget.onDelete(),
            backgroundColor: NoveColors.error,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Delete',
            borderRadius: BorderRadius.circular(NoveRadii.lg),
          ),
        ],
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: widget.isSelected ? NoveColors.accent(context).withValues(alpha: 0.1) : NoveColors.cardBg(context), 
            borderRadius: BorderRadius.circular(NoveRadii.xl), 
            border: Border.all(color: widget.isSelected ? NoveColors.accent(context) : NoveColors.cardBorder(context), width: widget.isSelected ? 2 : 1),
            boxShadow: NoveShadows.cardLight(context),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20), 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getLeftBorderColor(widget.note).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(NoveRadii.full),
                      ),
                      child: Text(
                        widget.note.category?.toUpperCase() ?? 'GENERAL',
                        style: NoveTypography.label(context).copyWith(color: _getLeftBorderColor(widget.note), fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (widget.note.isPinned) Icon(Icons.push_pin_rounded, size: 16, color: NoveColors.accent(context)),
                  ],
                ),
                const SizedBox(height: 12),
                _HighlightedText(
                  text: widget.note.title.isNotEmpty ? widget.note.title : 'Untitled', 
                  query: widget.searchQuery, 
                  style: NoveTypography.h3(context).copyWith(fontWeight: FontWeight.bold)
                ),
                const SizedBox(height: 6),
                _HighlightedText(
                  text: _cleanPreview(widget.note.content), 
                  query: widget.searchQuery, 
                  style: NoveTypography.body(context).copyWith(color: NoveColors.secondaryText(context)), 
                  maxLines: 2
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 12, color: NoveColors.mutedText(context)),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('MMM d').format(DateTime.fromMillisecondsSinceEpoch(widget.note.updatedAt)),
                      style: NoveTypography.caption(context),
                    ),
                    const Spacer(),
                    if (widget.note.tags.isNotEmpty)
                      Row(
                        children: widget.note.tags.take(2).map((t) => Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text('#$t', style: NoveTypography.caption(context).copyWith(color: NoveColors.accent(context))),
                        )).toList(),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BentoStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _BentoStat({required this.label, required this.value, required this.icon});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: NoveColors.bg(context),
      borderRadius: BorderRadius.circular(NoveRadii.xl),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: NoveColors.accent(context)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: NoveTypography.h3(context).copyWith(fontWeight: FontWeight.bold)),
            Text(label, style: NoveTypography.caption(context)),
          ],
        ),
      ],
    ),
  );
}

class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle style;
  final int maxLines;
  const _HighlightedText({required this.text, required this.query, required this.style, this.maxLines = 1});
  @override Widget build(BuildContext context) {
    if (query.isEmpty || !text.toLowerCase().contains(query.toLowerCase())) return Text(text, style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    final spans = <TextSpan>[];
    int start = 0;
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    int idx;
    while ((idx = lower.indexOf(q, start)) != -1) {
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(text: text.substring(idx, idx + query.length), style: style.copyWith(backgroundColor: Colors.amber.withValues(alpha: 0.4))));
      start = idx + query.length;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
    return RichText(text: TextSpan(style: style, children: spans), maxLines: maxLines, overflow: TextOverflow.ellipsis);
  }
}

class EnhancedFAB extends StatelessWidget {
  final ScrollController scrollController;
  final VoidCallback onPressed;
  const EnhancedFAB({super.key, required this.scrollController, required this.onPressed});
  @override Widget build(BuildContext context) => FloatingActionButton.extended(onPressed: onPressed, icon: const Icon(Icons.add), label: const Text('New Note'), backgroundColor: NoveColors.terracotta);
}