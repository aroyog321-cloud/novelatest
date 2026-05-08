import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/sticky_note.dart';
import '../providers/sticky_notes_provider.dart';
import '../theme/tokens.dart';
import 'overlay_sticky_provider.dart';

/// Wrap your entire app scaffold with this widget.
/// It sits on top of everything and renders all floating sticky overlays.
class StickyOverlayLayer extends ConsumerWidget {
  final Widget child;
  const StickyOverlayLayer({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(overlayStickyProvider);

    return Stack(
      children: [
        child,
        // Render every floating sticky on top
        ...entries.map((entry) => entry.isMinimized
            ? _MinimizedPill(entry: entry)
            : _FullStickyCard(entry: entry)),
      ],
    );
  }
}

// ─── Color helpers ────────────────────────────────────────────────────────────
Color _bgColorForSticky(StickyColor c) {
  switch (c) {
    case StickyColor.yellow:
      return const Color(0xFFF5C842);
    case StickyColor.pink:
      return const Color(0xFFF2C2D8);
    case StickyColor.green:
      return const Color(0xFFC5EDBE);
    case StickyColor.blue:
      return const Color(0xFFB3E5FC);
  }
}

Color _textColorForSticky(StickyColor c) {
  switch (c) {
    case StickyColor.yellow:
      return const Color(0xFF412402);
    case StickyColor.pink:
      return const Color(0xFF4B1528);
    case StickyColor.green:
      return const Color(0xFF173404);
    case StickyColor.blue:
      return const Color(0xFF042C53);
  }
}

String _emojiForSticky(StickyColor c) {
  switch (c) {
    case StickyColor.yellow:
      return '📝';
    case StickyColor.pink:
      return '🌸';
    case StickyColor.green:
      return '🌿';
    case StickyColor.blue:
      return '💧';
  }
}

// ─── Minimized Pill Button ────────────────────────────────────────────────────
class _MinimizedPill extends ConsumerStatefulWidget {
  final OverlayStickyEntry entry;
  const _MinimizedPill({required this.entry});

  @override
  ConsumerState<_MinimizedPill> createState() => _MinimizedPillState();
}

class _MinimizedPillState extends ConsumerState<_MinimizedPill>
    with SingleTickerProviderStateMixin {
  late double _x;
  late double _y;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _x = widget.entry.posX;
    _y = widget.entry.posY;
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    HapticFeedback.mediumImpact();
    ref.read(overlayStickyProvider.notifier).expand(widget.entry.note.id);
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _bgColorForSticky(widget.entry.note.color);
    final textColor = _textColorForSticky(widget.entry.note.color);
    final emoji = _emojiForSticky(widget.entry.note.color);

    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    return Positioned(
      left: _x.clamp(0, screenW - 120),
      top: _y.clamp(60, screenH - 100),
      child: GestureDetector(
        onDoubleTap: _onDoubleTap,
        onPanUpdate: (d) {
          setState(() {
            _x = (_x + d.delta.dx).clamp(0, screenW - 120);
            _y = (_y + d.delta.dy).clamp(60, screenH - 100);
          });
          ref.read(overlayStickyProvider.notifier)
              .updatePosition(widget.entry.note.id, _x, _y);
        },
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) => Transform.scale(
            scale: _pulseAnim.value,
            child: child,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: bgColor.withValues(alpha: 0.55),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.entry.note.title.isNotEmpty
                        ? widget.entry.note.title
                        : widget.entry.note.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Full Sticky Card Overlay ─────────────────────────────────────────────────
class _FullStickyCard extends ConsumerStatefulWidget {
  final OverlayStickyEntry entry;
  const _FullStickyCard({required this.entry});

  @override
  ConsumerState<_FullStickyCard> createState() => _FullStickyCardState();
}

class _FullStickyCardState extends ConsumerState<_FullStickyCard>
    with SingleTickerProviderStateMixin {
  late double _x;
  late double _y;
  bool _isDragging = false;
  late AnimationController _enterCtrl;
  late Animation<double> _enterScale;
  late Animation<double> _enterOpacity;

  @override
  void initState() {
    super.initState();
    _x = widget.entry.posX;
    _y = widget.entry.posY;
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _enterScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutBack),
    );
    _enterOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut),
    );
    _enterCtrl.forward();
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    super.dispose();
  }

  void _minimize() {
    HapticFeedback.lightImpact();
    ref.read(overlayStickyProvider.notifier)
        .minimize(widget.entry.note.id);
  }

  Future<void> _sendToBoard() async {
    HapticFeedback.mediumImpact();

    // Remove from overlay
    ref.read(overlayStickyProvider.notifier)
        .removeFromOverlay(widget.entry.note.id);

    // The note already exists on the board (it was popped out from there),
    // so no need to re-add it. Just show a snackbar confirmation.
    // If you want to "send" a NEW note to the board, call createNote here.
    final ctx = _scaffoldContext;
    if (ctx != null && ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.dashboard_rounded,
                  size: 16, color: Colors.white70),
              const SizedBox(width: 8),
              Text(
                'Sent back to Sticky Board',
                style: GoogleFonts.dmSans(fontSize: 13),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          backgroundColor: NoveColors.warmGray900,
        ),
      );
    }
  }

  BuildContext? get _scaffoldContext {
    try {
      return _scaffoldKey.currentContext;
    } catch (_) {
      return null;
    }
  }

  final GlobalKey _scaffoldKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final bgColor = _bgColorForSticky(widget.entry.note.color);
    final textColor = _textColorForSticky(widget.entry.note.color);
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final cardW = screenW * 0.72;

    return Positioned(
      left: _x.clamp(0, screenW - cardW),
      top: _y.clamp(60, screenH - 340),
      child: AnimatedBuilder(
        animation: _enterCtrl,
        builder: (_, child) => Opacity(
          opacity: _enterOpacity.value,
          child: Transform.scale(
            scale: _enterScale.value,
            alignment: Alignment.topLeft,
            child: child,
          ),
        ),
        child: GestureDetector(
          onPanStart: (_) => setState(() => _isDragging = true),
          onPanUpdate: (d) {
            setState(() {
              _x = (_x + d.delta.dx).clamp(0, screenW - cardW);
              _y = (_y + d.delta.dy).clamp(60, screenH - 340);
            });
            ref.read(overlayStickyProvider.notifier)
                .updatePosition(widget.entry.note.id, _x, _y);
          },
          onPanEnd: (_) => setState(() => _isDragging = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: cardW,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: _isDragging
                      ? bgColor.withValues(alpha: 0.55)
                      : Colors.black.withValues(alpha: 0.18),
                  blurRadius: _isDragging ? 28 : 18,
                  offset: Offset(0, _isDragging ? 10 : 6),
                  spreadRadius: _isDragging ? 2 : 0,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Drag handle + action buttons ───────────────────
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.07),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Drag indicator dots
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              3,
                              (_) => Container(
                                margin: const EdgeInsets.only(right: 3),
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: textColor.withValues(alpha: 0.35),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(
                              3,
                              (_) => Container(
                                margin: const EdgeInsets.only(right: 3),
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: textColor.withValues(alpha: 0.35),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Floating sticky',
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: textColor.withValues(alpha: 0.55),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      // ── Minimize button ─────────────────────────
                      _ActionBtn(
                        icon: Icons.remove_rounded,
                        tooltip: 'Minimize',
                        color: textColor,
                        bgColor: Colors.black.withValues(alpha: 0.08),
                        onTap: _minimize,
                      ),
                      const SizedBox(width: 6),
                      // ── Send to board (close) button ─────────────
                      _ActionBtn(
                        icon: Icons.dashboard_customize_rounded,
                        tooltip: 'Send to Board',
                        color: textColor,
                        bgColor: Colors.black.withValues(alpha: 0.08),
                        onTap: _sendToBoard,
                      ),
                    ],
                  ),
                ),

                // ── Note content ───────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.entry.note.title.isNotEmpty) ...[
                        Text(
                          widget.entry.note.title,
                          style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (widget.entry.note.content.isNotEmpty)
                        Text(
                          widget.entry.note.content,
                          style: GoogleFonts.caveat(
                            fontSize: 22,
                            color: textColor.withValues(alpha: 0.85),
                            height: 1.4,
                          ),
                          maxLines: 8,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),

                // ── Bottom hint ────────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.only(left: 16, right: 16, bottom: 10),
                  child: Row(
                    children: [
                      Icon(Icons.open_with_rounded,
                          size: 11, color: textColor.withValues(alpha: 0.4)),
                      const SizedBox(width: 4),
                      Text(
                        'Drag to move',
                        style: GoogleFonts.dmSans(
                          fontSize: 10,
                          color: textColor.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Small action button ──────────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}