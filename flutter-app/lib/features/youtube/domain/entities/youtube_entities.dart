/// YouTube Video entity — represents a single YouTube video.
///
/// Phase 1: YouTube Video Integration.
class YouTubeVideo {
  final String videoId;
  final String title;
  final String description;
  final String channelTitle;
  final String channelId;
  final String publishedAt;
  final String thumbnailUrl;
  final String thumbnailMedium;
  final String cefrLevel; // e.g. 'A1', 'B1', 'C2'; empty if not yet graded

  const YouTubeVideo({
    required this.videoId,
    required this.title,
    required this.description,
    required this.channelTitle,
    required this.channelId,
    required this.publishedAt,
    required this.thumbnailUrl,
    this.thumbnailMedium = '',
    this.cefrLevel = '',
  });

  factory YouTubeVideo.fromJson(Map<String, dynamic> json) {
    return YouTubeVideo(
      videoId: json['video_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      channelTitle: json['channel_title'] as String? ?? '',
      channelId: json['channel_id'] as String? ?? '',
      publishedAt: json['published_at'] as String? ?? '',
      thumbnailUrl: json['thumbnail_url'] as String? ?? '',
      thumbnailMedium: json['thumbnail_medium'] as String? ?? '',
      cefrLevel: json['cefr_level'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'video_id': videoId,
    'title': title,
    'description': description,
    'channel_title': channelTitle,
    'channel_id': channelId,
    'published_at': publishedAt,
    'thumbnail_url': thumbnailUrl,
    'thumbnail_medium': thumbnailMedium,
    'cefr_level': cefrLevel,
  };
}

/// YouTube Channel entity — curated learning channel.
class YouTubeChannel {
  final String id;
  final String name;
  final String description;
  final String level;
  final String thumbnail;
  final String category;

  const YouTubeChannel({
    required this.id,
    required this.name,
    required this.description,
    required this.level,
    required this.thumbnail,
    required this.category,
  });

  factory YouTubeChannel.fromJson(Map<String, dynamic> json) {
    return YouTubeChannel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      level: json['level'] as String? ?? '',
      thumbnail: json['thumbnail'] as String? ?? '',
      category: json['category'] as String? ?? '',
    );
  }
}

/// Caption segment — a single subtitle line with timing.
class CaptionSegment {
  final int startMs;
  final int endMs;
  final String text;

  const CaptionSegment({
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  factory CaptionSegment.fromJson(Map<String, dynamic> json) {
    return CaptionSegment(
      startMs: json['start_ms'] as int? ?? 0,
      endMs: json['end_ms'] as int? ?? 0,
      text: json['text'] as String? ?? '',
    );
  }

  /// Duration in seconds.
  double get durationSeconds => (endMs - startMs) / 1000.0;

  /// Check if this segment is active at the given playback position.
  bool isActiveAt(int positionMs) =>
      positionMs >= startMs && positionMs < endMs;
}

/// Word translation — result of a lookup triggered during video playback.
class WordTranslation {
  final String word;
  final String translation;    // Vietnamese (or target-lang) translation
  final String phonetic;       // IPA: /spæk/
  final String partOfSpeech;   // noun, verb, adjective…
  final String definition;     // English definition
  final List<String> examples; // example sentences from dictionary
  final String? contextSentence; // the caption line the word was tapped in

  const WordTranslation({
    required this.word,
    this.translation = '',
    this.phonetic = '',
    this.partOfSpeech = '',
    this.definition = '',
    this.examples = const [],
    this.contextSentence,
  });

  factory WordTranslation.fromJson(Map<String, dynamic> json) {
    return WordTranslation(
      word: json['word'] as String? ?? '',
      translation: json['translation'] as String? ?? '',
      phonetic: json['phonetic'] as String? ?? '',
      partOfSpeech: json['part_of_speech'] as String? ?? '',
      definition: json['definition'] as String? ?? '',
      examples: (json['examples'] as List<dynamic>? ?? [])
          .map((e) => e as String)
          .toList(),
    );
  }

  bool get hasTranslation => translation.isNotEmpty;
  bool get hasPhonetic => phonetic.isNotEmpty;
  bool get hasDefinition => definition.isNotEmpty;

  WordTranslation copyWith({String? contextSentence}) {
    return WordTranslation(
      word: word,
      translation: translation,
      phonetic: phonetic,
      partOfSpeech: partOfSpeech,
      definition: definition,
      examples: examples,
      contextSentence: contextSentence ?? this.contextSentence,
    );
  }
}

/// A video bookmarked/saved by the user for offline reference.
class SavedVideo {
  final String videoId;
  final String title;
  final String channelTitle;
  final String thumbnailUrl;
  final String cefrLevel;
  final DateTime savedAt;

  const SavedVideo({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    required this.thumbnailUrl,
    required this.cefrLevel,
    required this.savedAt,
  });

  factory SavedVideo.fromVideo(YouTubeVideo video) => SavedVideo(
        videoId: video.videoId,
        title: video.title,
        channelTitle: video.channelTitle,
        thumbnailUrl: video.thumbnailUrl,
        cefrLevel: video.cefrLevel,
        savedAt: DateTime.now(),
      );

  factory SavedVideo.fromJson(Map<String, dynamic> json) => SavedVideo(
        videoId: json['videoId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        channelTitle: json['channelTitle'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
        cefrLevel: json['cefrLevel'] as String? ?? '',
        savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'channelTitle': channelTitle,
        'thumbnailUrl': thumbnailUrl,
        'cefrLevel': cefrLevel,
        'savedAt': savedAt.toIso8601String(),
      };
}

/// Search result response from YouTube API.
class YouTubeSearchResult {
  final List<YouTubeVideo> videos;
  final String? nextPageToken;
  final String? prevPageToken;
  final int totalResults;

  const YouTubeSearchResult({
    required this.videos,
    this.nextPageToken,
    this.prevPageToken,
    required this.totalResults,
  });

  factory YouTubeSearchResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return YouTubeSearchResult(
      videos: (data['videos'] as List<dynamic>? ?? [])
          .map((v) => YouTubeVideo.fromJson(v as Map<String, dynamic>))
          .toList(),
      nextPageToken: data['next_page_token'] as String?,
      prevPageToken: data['prev_page_token'] as String?,
      totalResults: data['total_results'] as int? ?? 0,
    );
  }
}
