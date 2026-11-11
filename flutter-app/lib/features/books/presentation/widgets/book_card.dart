import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/widgets/cefr_badge.dart';
import '../../../../core/widgets/content_kit.dart';
import '../../domain/entities/book_entities.dart';

/// Portrait cover with title and author underneath, for horizontal shelves.
///
/// Phase 5: Book Reading.
class BookCard extends StatelessWidget {
  final Book book;
  final VoidCallback? onTap;

  const BookCard({super.key, required this.book, this.onTap});

  static const coverWidth = 128.0;
  static const coverHeight = 192.0; // 2:3, the proportion of a paperback
  static const _radius = 12.0;

  /// Height a shelf of these needs at the current text scale.
  static double rowHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return coverHeight +
        12 +
        scaler.scale(14) * 1.3 * 2 +
        4 +
        scaler.scale(12) * 1.3 +
        4;
  }

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: SizedBox(
          width: coverWidth,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BookCover(book: book),
                  const SizedBox(height: 12),
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: contentMuted(context),
                    ),
                  ),
                ],
              ),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(_radius),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The cover: artwork (or a typeset jacket when there is none) with a spine
/// shade down the left edge and a soft drop shadow.
class BookCover extends StatelessWidget {
  final Book book;
  final double width;
  final double height;

  const BookCover({
    super.key,
    required this.book,
    this.width = BookCard.coverWidth,
    this.height = BookCard.coverHeight,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BookCard._radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BookCard._radius),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              book.coverUrl.isEmpty
                  ? BookJacket(title: book.title)
                  : ContentImage(
                      url: book.coverUrl,
                      fallbackIcon: PhosphorIconsBold.bookOpenText,
                    ),
              const Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0x40000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: CefrBadge(
                  level: book.cefrLevel,
                  size: CefrBadgeSize.small,
                  onColored: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A cover drawn from the title alone, for books that have no artwork.
class BookJacket extends StatelessWidget {
  final String title;

  const BookJacket({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            Color.lerp(scheme.primaryContainer, scheme.primary, 0.35)!,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 32, 12, 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}
