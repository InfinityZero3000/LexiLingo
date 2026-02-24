/// Podcast entity models for the Podcast feature.
///
/// Phase 4: Podcast.

/// Download state for a podcast episode.
enum DownloadState { notDownloaded, downloading, downloaded }

/// A podcast with metadata and CEFR level grading.
class Podcast {
  final String id;
  final String title;
  final String author;
  final String description;
  final String feedUrl;
  final String artworkUrl;
  final int episodeCount;
  final List<String> categories;
  final String cefrLevel; // A1-C2
  final String language;
  final bool isFollowed; // local state

  const Podcast({
    required this.id,
    required this.title,
    this.author = '',
    this.description = '',
    required this.feedUrl,
    this.artworkUrl = '',
    this.episodeCount = 0,
    this.categories = const [],
    this.cefrLevel = 'B1',
    this.language = 'en',
    this.isFollowed = false,
  });

  factory Podcast.fromJson(Map<String, dynamic> json) {
    return Podcast(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
      feedUrl: json['feed_url'] as String? ?? '',
      artworkUrl: json['artwork_url'] as String? ?? '',
      episodeCount: json['episode_count'] as int? ?? 0,
      categories: (json['categories'] as List<dynamic>?)
              ?.map((c) => c as String)
              .toList() ??
          [],
      cefrLevel: json['cefr_level'] as String? ?? 'B1',
      language: json['language'] as String? ?? 'en',
      isFollowed: json['is_followed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'description': description,
        'feed_url': feedUrl,
        'artwork_url': artworkUrl,
        'episode_count': episodeCount,
        'categories': categories,
        'cefr_level': cefrLevel,
        'language': language,
        'is_followed': isFollowed,
      };

  Podcast copyWith({bool? isFollowed}) {
    return Podcast(
      id: id,
      title: title,
      author: author,
      description: description,
      feedUrl: feedUrl,
      artworkUrl: artworkUrl,
      episodeCount: episodeCount,
      categories: categories,
      cefrLevel: cefrLevel,
      language: language,
      isFollowed: isFollowed ?? this.isFollowed,
    );
  }
}

/// A single podcast episode with playback state.
class PodcastEpisode {
  final String guid;
  final String title;
  final String audioUrl;
  final int durationSeconds; // duration in seconds
  final String publishedAt;
  final String description;
  final int? episodeNumber;
  final String? imageUrl;
  final String? cefrLevel;
  final String feedUrl; // parent podcast's feed URL
  // Playback state (local tracking)
  final int listenProgress; // seconds listened
  final bool isCompleted; // 80%+ listened
  final DownloadState downloadState;
  final String? localPath; // path if downloaded

  const PodcastEpisode({
    required this.guid,
    required this.title,
    required this.audioUrl,
    this.durationSeconds = 0,
    this.publishedAt = '',
    this.description = '',
    this.episodeNumber,
    this.imageUrl,
    this.cefrLevel,
    required this.feedUrl,
    this.listenProgress = 0,
    this.isCompleted = false,
    this.downloadState = DownloadState.notDownloaded,
    this.localPath,
  });

  factory PodcastEpisode.fromJson(Map<String, dynamic> json) {
    DownloadState parseDownloadState(String? raw) {
      switch (raw) {
        case 'downloading':
          return DownloadState.downloading;
        case 'downloaded':
          return DownloadState.downloaded;
        default:
          return DownloadState.notDownloaded;
      }
    }

    return PodcastEpisode(
      guid: json['guid'] as String? ?? '',
      title: json['title'] as String? ?? '',
      audioUrl: json['audio_url'] as String? ?? '',
      durationSeconds: json['duration_seconds'] as int? ?? 0,
      publishedAt: json['published_at'] as String? ?? '',
      description: json['description'] as String? ?? '',
      episodeNumber: json['episode_number'] as int?,
      imageUrl: json['image_url'] as String?,
      cefrLevel: json['cefr_level'] as String?,
      feedUrl: json['feed_url'] as String? ?? '',
      listenProgress: json['listen_progress'] as int? ?? 0,
      isCompleted: json['is_completed'] as bool? ?? false,
      downloadState: parseDownloadState(json['download_state'] as String?),
      localPath: json['local_path'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'guid': guid,
        'title': title,
        'audio_url': audioUrl,
        'duration_seconds': durationSeconds,
        'published_at': publishedAt,
        'description': description,
        'episode_number': episodeNumber,
        'image_url': imageUrl,
        'cefr_level': cefrLevel,
        'feed_url': feedUrl,
        'listen_progress': listenProgress,
        'is_completed': isCompleted,
        'download_state': downloadState.name,
        'local_path': localPath,
      };

  PodcastEpisode copyWith({
    int? listenProgress,
    bool? isCompleted,
    DownloadState? downloadState,
    String? localPath,
  }) {
    return PodcastEpisode(
      guid: guid,
      title: title,
      audioUrl: audioUrl,
      durationSeconds: durationSeconds,
      publishedAt: publishedAt,
      description: description,
      episodeNumber: episodeNumber,
      imageUrl: imageUrl,
      cefrLevel: cefrLevel,
      feedUrl: feedUrl,
      listenProgress: listenProgress ?? this.listenProgress,
      isCompleted: isCompleted ?? this.isCompleted,
      downloadState: downloadState ?? this.downloadState,
      localPath: localPath ?? this.localPath,
    );
  }
}

/// Listening history record for a podcast episode.
class ListeningHistory {
  final String episodeGuid;
  final String feedUrl;
  final int lastPositionSeconds;
  final int totalListenedSeconds;
  final bool completed; // 80%+ listened
  final DateTime? completedAt;
  final DateTime updatedAt;

  const ListeningHistory({
    required this.episodeGuid,
    required this.feedUrl,
    this.lastPositionSeconds = 0,
    this.totalListenedSeconds = 0,
    this.completed = false,
    this.completedAt,
    required this.updatedAt,
  });

  factory ListeningHistory.fromJson(Map<String, dynamic> json) {
    return ListeningHistory(
      episodeGuid: json['episode_guid'] as String? ?? '',
      feedUrl: json['feed_url'] as String? ?? '',
      lastPositionSeconds: json['last_position_seconds'] as int? ?? 0,
      totalListenedSeconds: json['total_listened_seconds'] as int? ?? 0,
      completed: json['completed'] as bool? ?? false,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      updatedAt: DateTime.parse(
          json['updated_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() => {
        'episode_guid': episodeGuid,
        'feed_url': feedUrl,
        'last_position_seconds': lastPositionSeconds,
        'total_listened_seconds': totalListenedSeconds,
        'completed': completed,
        'completed_at': completedAt?.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// A podcast the user is following (stored locally).
class UserPodcastFollow {
  final String feedUrl;
  final String podcastTitle;
  final String artworkUrl;
  final DateTime followedAt;

  const UserPodcastFollow({
    required this.feedUrl,
    required this.podcastTitle,
    this.artworkUrl = '',
    required this.followedAt,
  });

  factory UserPodcastFollow.fromJson(Map<String, dynamic> json) {
    return UserPodcastFollow(
      feedUrl: json['feed_url'] as String? ?? '',
      podcastTitle: json['podcast_title'] as String? ?? '',
      artworkUrl: json['artwork_url'] as String? ?? '',
      followedAt: DateTime.parse(
          json['followed_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() => {
        'feed_url': feedUrl,
        'podcast_title': podcastTitle,
        'artwork_url': artworkUrl,
        'followed_at': followedAt.toIso8601String(),
      };
}

/// A curated category of podcasts grouped by CEFR level.
class PodcastCategory {
  final String id;
  final String label;
  final String cefrLevel;
  final List<Podcast> podcasts;

  const PodcastCategory({
    required this.id,
    required this.label,
    this.cefrLevel = 'B1',
    this.podcasts = const [],
  });

  factory PodcastCategory.fromJson(Map<String, dynamic> json) {
    return PodcastCategory(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      cefrLevel: json['cefr_level'] as String? ?? 'B1',
      podcasts: (json['podcasts'] as List<dynamic>?)
              ?.map((p) => Podcast.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'cefr_level': cefrLevel,
        'podcasts': podcasts.map((p) => p.toJson()).toList(),
      };
}
