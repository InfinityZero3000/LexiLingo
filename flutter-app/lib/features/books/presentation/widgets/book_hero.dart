import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/widgets/content_kit.dart';
import '../../domain/entities/book_entities.dart';
import 'book_card.dart';

/// Hero card: the cover on a blurred copy of itself, with the reading place
/// when [entry] is given, or an invitation to start when it is not.
///
/// The scrim is black regardless of theme so white text holds contrast on any
/// cover.
class BookHero extends StatelessWidget {
  final Book book;
  final ReadingEntry? entry;
  final VoidCallback onTap;

  const BookHero({
    super.key,
    required this.book,
    required this.onTap,
    this.entry,
  });

  static const _cover = Size(100, 150);

  @override
  Widget build(BuildContext context) {
    final reading = entry;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: SizedBox(
            height: ContentHero.heightOf(context),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ContentBackdrop(
                  url: book.coverUrl,
                  fallback: BookJacket(title: book.title),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      _HeroCover(book: book),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _HeroText(book: book, entry: reading),
                      ),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(onTap: onTap),
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

class _HeroCover extends StatelessWidget {
  final Book book;

  const _HeroCover({required this.book});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox.fromSize(
          size: BookHero._cover,
          child: book.coverUrl.isEmpty
              ? BookJacket(title: book.title)
              : ContentImage(
                  url: book.coverUrl,
                  fallbackIcon: PhosphorIconsBold.bookOpenText,
                ),
        ),
      ),
    );
  }
}

class _HeroText extends StatelessWidget {
  final Book book;
  final ReadingEntry? entry;

  const _HeroText({required this.book, required this.entry});

  @override
  Widget build(BuildContext context) {
    final reading = entry;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (reading != null ? 'books.nowReading' : 'books.featured')
              .tr()
              .toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xCCFFFFFF),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          book.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: contentDisplay(context, size: 20, color: Colors.white),
        ),
        const SizedBox(height: 4),
        Text(
          book.author,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xE6FFFFFF),
            fontSize: 14,
            height: 1.3,
          ),
        ),
        if (reading != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: reading.progress.readingProgress.clamp(0.0, 1.0),
              minHeight: 4,
              color: scheme.primary,
              backgroundColor: const Color(0x40FFFFFF),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'books.percentRead'.tr(
              namedArgs: {'percent': '${reading.percent}'},
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        ContentCta(
          label: (reading != null ? 'books.continueCta' : 'books.startCta')
              .tr(),
          icon: PhosphorIconsBold.bookOpenText,
        ),
      ],
    );
  }
}
