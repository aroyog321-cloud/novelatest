import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/tokens.dart';

class MarkdownEditingController extends TextEditingController {
  final BuildContext context;

  MarkdownEditingController({required this.context, super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final TextStyle baseStyle = style ?? const TextStyle();
    final List<InlineSpan> children = [];
    final String text = this.text;

    // A unified regex to match markdown elements.
    // 1: Image
    // 2: Bold (**...** or __...__)
    // 4: Italic (*...* or _..._)
    // 6: Header (#...)
    // 9: Quote (> ...)
    // 11: Checkbox (☑|☐)
    // 14: Bullet (•|-)
    // 17: Inline code (`...`)
    // 19: Wiki link ([[...]])
    // 21: Tag (#tag)
    // 22: Strikethrough (~~...~~)
    final regex = RegExp(
      r'(!\[(.*?)\]\((.*?)\))|(\*\*([\s\S]*?)\*\*|__([\s\S]*?)__)|(\*([\s\S]*?)\*|_([\s\S]*?)_)|(^(#+) +(.*)$)|(^> +(.*)$)|(^(☑|☐) +(.*)$)|(^(•|-) +(.*)$)|(`([\s\S]*?)`)|(\[\[(.*?)\]\])|(#(\w+))|(~~([\s\S]*?)~~)',
      multiLine: true,
    );

    int lastMatchEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        children.add(TextSpan(text: text.substring(lastMatchEnd, match.start), style: baseStyle));
      }

      // We make the markdown markers subtly visible but minimize their horizontal footprint.
      final markerStyle = baseStyle.copyWith(
        color: NoveColors.mutedText(context).withValues(alpha: 0.2),
        fontWeight: FontWeight.normal,
        fontStyle: FontStyle.normal,
        fontSize: 1, 
        letterSpacing: -1,
      );

      // Match 1: Image
      if (match.group(1) != null) {
        final fullMatch = match.group(0)!;
        final path = match.group(3)!;
        
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NoveRadii.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (ctx, err, stack) => Container(
                    height: 100,
                    width: 200,
                    decoration: BoxDecoration(
                      color: NoveColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(NoveRadii.md),
                    ),
                    child: const Center(
                      child: Icon(Icons.broken_image_rounded, color: NoveColors.error, size: 32),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ));
        
        if (fullMatch.length > 1) {
          children.add(TextSpan(text: fullMatch.substring(1), style: markerStyle));
        }
      }
      // Match 4: Bold
      else if (match.group(4) != null) {
        final marker = text.substring(match.start, match.start + 2);
        final content = match.group(5) ?? match.group(6);
        children.add(TextSpan(text: marker, style: markerStyle));
        children.add(TextSpan(text: content, style: baseStyle.copyWith(fontWeight: FontWeight.bold)));
        children.add(TextSpan(text: marker, style: markerStyle));
      }
      // Match 7: Italic
      else if (match.group(7) != null) {
        final marker = text.substring(match.start, match.start + 1);
        final content = match.group(8) ?? match.group(9);
        children.add(TextSpan(text: marker, style: markerStyle));
        children.add(TextSpan(text: content, style: baseStyle.copyWith(fontStyle: FontStyle.italic)));
        children.add(TextSpan(text: marker, style: markerStyle));
      }
      // Match 10: Header
      else if (match.group(10) != null) {
        final hashes = match.group(11)!;
        final content = match.group(12)!;
        double size = 24;
        if (hashes.length == 2) size = 20;
        if (hashes.length >= 3) size = 17;
        
        children.add(TextSpan(
          children: [
            TextSpan(text: hashes, style: markerStyle),
            const TextSpan(text: ' '),
            TextSpan(
              text: content,
              style: GoogleFonts.lora(
                fontSize: size,
                fontWeight: FontWeight.bold,
                color: NoveColors.primaryText(context),
                height: 1.3,
              ),
            ),
          ],
        ));
      }
      // Match 13: Quote
      else if (match.group(13) != null) {
        children.add(TextSpan(text: '> ', style: markerStyle));
        children.add(TextSpan(
          text: match.group(14),
          style: GoogleFonts.lora(
            fontSize: 16,
            fontStyle: FontStyle.italic,
            color: NoveColors.secondaryText(context),
          ),
        ));
      }
      // Match 15: Checkbox
      else if (match.group(15) != null) {
        final fullMatch = match.group(0)!;
        final isDone = match.group(16) == '☑';
        final content = match.group(17)!;
        
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: () {
              final newText = text.replaceRange(match.start, match.end, '${isDone ? "☐" : "☑"} $content');
              final sel = selection;
              value = TextEditingValue(
                text: newText,
                selection: sel.isValid ? sel : TextSelection.collapsed(offset: newText.length),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 2),
              child: Icon(
                isDone ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20,
                color: isDone ? NoveColors.accent(context) : NoveColors.warmGray400,
              ),
            ),
          ),
        ));
        
        final spacePart = fullMatch.substring(1, fullMatch.length - content.length);
        if (spacePart.isNotEmpty) {
          children.add(TextSpan(text: spacePart, style: markerStyle));
        }
        
        children.add(TextSpan(
          text: content,
          style: baseStyle.copyWith(
            decoration: isDone ? TextDecoration.lineThrough : null,
            color: isDone ? NoveColors.mutedText(context) : null,
          ),
        ));
      }
      // Match 18: Bullet
      else if (match.group(18) != null) {
        final bulletStr = match.group(19)!;
        final content = match.group(20)!;
        
        children.add(TextSpan(
          text: '$bulletStr ',
          style: baseStyle.copyWith(color: NoveColors.accent(context), fontWeight: FontWeight.bold),
        ));
        children.add(TextSpan(
          text: content,
          style: baseStyle,
        ));
      }
      // Match 21: Inline code
      else if (match.group(21) != null) {
        children.add(TextSpan(text: '`', style: markerStyle));
        children.add(TextSpan(
          text: match.group(22),
          style: GoogleFonts.firaCode(
            backgroundColor: NoveColors.warmGray300.withValues(alpha: 0.3),
            fontSize: 14,
            color: NoveColors.terracotta,
          ),
        ));
        children.add(TextSpan(text: '`', style: markerStyle));
      }
      // Match 23: Wiki link [[link]]
      else if (match.group(23) != null) {
        children.add(TextSpan(text: '[[', style: markerStyle));
        children.add(TextSpan(
          text: match.group(24),
          style: baseStyle.copyWith(
            color: NoveColors.deepBlue,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ));
        children.add(TextSpan(text: ']]', style: markerStyle));
      }
      // Match 25: Tag #tag
      else if (match.group(25) != null) {
        children.add(TextSpan(
          text: match.group(25),
          style: baseStyle.copyWith(
            color: NoveColors.amberDark,
            fontWeight: FontWeight.bold,
          ),
        ));
      }
      // Match 26: Strikethrough
      else if (match.group(26) != null) {
        children.add(TextSpan(text: '~~', style: markerStyle));
        children.add(TextSpan(
          text: match.group(27),
          style: baseStyle.copyWith(decoration: TextDecoration.lineThrough, color: NoveColors.mutedText(context)),
        ));
        children.add(TextSpan(text: '~~', style: markerStyle));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      children.add(TextSpan(text: text.substring(lastMatchEnd), style: baseStyle));
    }

    return TextSpan(style: baseStyle, children: children);
  }
}
