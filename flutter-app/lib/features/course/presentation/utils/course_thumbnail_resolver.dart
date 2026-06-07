import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';

const _ieltsImages = [
  'https://images.unsplash.com/photo-1588072432836-e10032774350?w=800&q=80',
  'https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=800&q=80',
  'https://images.unsplash.com/photo-1523050854058-8df90110c9f1?w=800&q=80',
];
const _businessImages = [
  'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=800&q=80',
  'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=800&q=80',
  'https://images.unsplash.com/photo-1486312338219-ce68d2c6f44d?w=800&q=80',
];
const _conversationImages = [
  'https://images.unsplash.com/photo-1499750310107-5fef28a66643?w=800&q=80',
  'https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?w=800&q=80',
  'https://images.unsplash.com/photo-1488590528505-98d2b5aba04b?w=800&q=80',
];
const _grammarImages = [
  'https://images.unsplash.com/photo-1471899236350-e3016bf1a395?w=800&q=80',
  'https://images.unsplash.com/photo-1432821596592-e2c18b78144f?w=800&q=80',
  'https://images.unsplash.com/photo-1455390582262-044cdead277a?w=800&q=80',
];
const _vocabularyImages = [
  'https://images.unsplash.com/photo-1512820790803-83ca734da794?w=800&q=80',
  'https://images.unsplash.com/photo-1476275466078-4007374efbbe?w=800&q=80',
  'https://images.unsplash.com/photo-1434030216411-0b793f4b4173?w=800&q=80',
];
const _readingImages = [
  'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?w=800&q=80',
  'https://images.unsplash.com/photo-1524578271613-d550eacf6090?w=800&q=80',
  'https://images.unsplash.com/photo-1497633762265-9d179a990aa6?w=800&q=80',
];
const _listeningImages = [
  'https://images.unsplash.com/photo-1484704849700-f032a568e944?w=800&q=80',
  'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=800&q=80',
  'https://images.unsplash.com/photo-1571330735066-03aaa9429d89?w=800&q=80',
];
const _writingImages = [
  'https://images.unsplash.com/photo-1517842645767-c639042777db?w=800&q=80',
  'https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=800&q=80',
  'https://images.unsplash.com/photo-1455390582262-044cdead277a?w=800&q=80',
];
const _travelImages = [
  'https://images.unsplash.com/photo-1488085061387-422e29b40080?w=800&q=80',
  'https://images.unsplash.com/photo-1469854523086-cc02fe5d8800?w=800&q=80',
  'https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=800&q=80',
];
const _beginnerImages = [
  'https://images.unsplash.com/photo-1427504494785-3a9ca7044f45?w=800&q=80',
  'https://images.unsplash.com/photo-1506880018603-83d5b814b5a6?w=800&q=80',
  'https://images.unsplash.com/photo-1512820790803-83ca734da794?w=800&q=80',
];
const _intermediateImages = [
  'https://images.unsplash.com/photo-1546410531-bb4caa6b424d?w=800&q=80',
  'https://images.unsplash.com/photo-1499750310107-5fef28a66643?w=800&q=80',
  'https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?w=800&q=80',
];
const _advancedImages = [
  'https://images.unsplash.com/photo-1481627834876-b7833e8f5570?w=800&q=80',
  'https://images.unsplash.com/photo-1588072432836-e10032774350?w=800&q=80',
  'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=800&q=80',
];

String courseFallbackThumbnailUrl(CourseEntity course) {
  final tags = course.tags.map((tag) => tag.toLowerCase()).toSet();
  final level = course.level.toLowerCase();
  final pick = course.id.hashCode & 0x7fffffff;

  if (tags.contains('ielts') ||
      tags.contains('test-prep') ||
      tags.contains('exam')) {
    return _pick(_ieltsImages, pick);
  }
  if (tags.contains('business') || tags.contains('business-english')) {
    return _pick(_businessImages, pick);
  }
  if (tags.contains('conversation') || tags.contains('speaking')) {
    return _pick(_conversationImages, pick);
  }
  if (tags.contains('grammar')) return _pick(_grammarImages, pick);
  if (tags.contains('vocabulary') || tags.contains('vocab')) {
    return _pick(_vocabularyImages, pick);
  }
  if (tags.contains('reading')) return _pick(_readingImages, pick);
  if (tags.contains('listening')) return _pick(_listeningImages, pick);
  if (tags.contains('writing')) return _pick(_writingImages, pick);
  if (tags.contains('travel')) return _pick(_travelImages, pick);

  switch (level) {
    case 'beginner':
    case 'elementary':
      return _pick(_beginnerImages, pick);
    case 'intermediate':
    case 'upper-intermediate':
      return _pick(_intermediateImages, pick);
    case 'advanced':
      return _pick(_advancedImages, pick);
    default:
      return _pick(_readingImages, pick);
  }
}

List<String> buildCourseCardThumbnailCandidates(CourseEntity course) {
  final urls = <String>[];
  final primaryUrl = course.thumbnailUrl?.trim();
  if (primaryUrl != null && primaryUrl.isNotEmpty) {
    urls.add(primaryUrl);
  }

  final fallbackUrl = courseFallbackThumbnailUrl(course);
  if (!urls.contains(fallbackUrl)) {
    urls.add(fallbackUrl);
  }
  return urls;
}

String _pick(List<String> images, int pick) => images[pick % images.length];
