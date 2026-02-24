import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/book_entities.dart';

/// Card widget displaying book cover, title, author, and CEFR badge.
///
/// Phase 5: Book Reading.
class BookCard extends StatelessWidget {
  final Book book;
  final VoidCallback? onTap;

  const BookCard({super.key, required this.book, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cefrColor = _cefrColor(book.cefrLevel);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C2B3A) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: _buildCover(cefrColor),
            ),

            // Info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // CEFR badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cefrColor,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      book.cefrLevel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),

                  // Title
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textDark,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),

                  // Author
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : AppColors.textGrey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(Color cefrColor) {
    if (book.coverUrl.isNotEmpty) {
      return Image.network(
        book.coverUrl,
        width: 140,
        height: 160,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackCover(cefrColor),
      );
    }
    return _buildFallbackCover(cefrColor);
  }

  Widget _buildFallbackCover(Color cefrColor) {
    return Container(
      width: 140,
      height: 160,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cefrColor.withValues(alpha: 0.8),
            cefrColor.withValues(alpha: 0.4),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.menu_book_rounded,
          size: 48,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }

  Color _cefrColor(String level) {
    switch (level) {
      case 'A1':
        return const Color(0xFF4CAF50);
      case 'A2':
        return const Color(0xFF8BC34A);
      case 'B1':
        return const Color(0xFFFFC107);
      case 'B2':
        return const Color(0xFFFF9800);
      case 'C1':
        return const Color(0xFFFF5722);
      case 'C2':
        return const Color(0xFF9C27B0);
      default:
        return AppColors.primary;
    }
  }
}
