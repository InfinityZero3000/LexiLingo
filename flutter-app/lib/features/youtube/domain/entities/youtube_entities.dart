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

  const YouTubeVideo({
    required this.videoId,
    required this.title,
    required this.description,
    required this.channelTitle,
    required this.channelId,
    required this.publishedAt,
    required this.thumbnailUrl,
    this.thumbnailMedium = '',
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
  bool isActiveAt(int positionMs) => positionMs >= startMs && positionMs < endMs;
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
