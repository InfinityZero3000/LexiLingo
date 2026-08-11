// ignore_for_file: constant_identifier_names
/// Domain entities for Story/Topic-based conversation.
/// Pure Dart value objects — no JSON/serialization dependency, no data-layer imports.
library;

/// Difficulty levels matching CEFR standard
enum DifficultyLevel {
  A1('A1', 'Beginner'),
  A2('A2', 'Elementary'),
  B1('B1', 'Intermediate'),
  B2('B2', 'Upper Intermediate'),
  C1('C1', 'Advanced'),
  C2('C2', 'Proficiency');

  final String code;
  final String label;

  const DifficultyLevel(this.code, this.label);

  String get displayName => '$code - $label';
  String get shortName => code;

  static DifficultyLevel fromString(String? value) {
    if (value == null) return DifficultyLevel.A1;
    return DifficultyLevel.values.firstWhere(
      (e) => e.code.toUpperCase() == value.toUpperCase(),
      orElse: () => DifficultyLevel.A1,
    );
  }
}

class LocalizedTitle {
  final String vi;
  final String en;

  const LocalizedTitle({required this.vi, required this.en});
}

class VocabularyItem {
  final String term;
  final String definition;
  final String exampleInStory;
  final String partOfSpeech;
  final String? phonetic;

  const VocabularyItem({
    required this.term,
    required this.definition,
    this.exampleInStory = '',
    this.partOfSpeech = '',
    this.phonetic,
  });
}

class GrammarPoint {
  final String grammarStructure;
  final String explanation;
  final String usageInStory;
  final List<String> examples;

  const GrammarPoint({
    required this.grammarStructure,
    required this.explanation,
    this.usageInStory = '',
    this.examples = const [],
  });
}

class RolePersona {
  final String name;
  final String role;
  final String personality;
  final String speakingStyle;
  final String background;

  const RolePersona({
    required this.name,
    required this.role,
    required this.personality,
    required this.speakingStyle,
    required this.background,
  });
}

class ContextDescription {
  final String setting;
  final String scenario;
  final List<String> objectives;

  const ContextDescription({
    required this.setting,
    required this.scenario,
    this.objectives = const [],
  });
}

class ConversationFlow {
  final String openingPrompt;
  final List<String> keyMilestones;
  final List<String> closingScenarios;

  const ConversationFlow({
    required this.openingPrompt,
    this.keyMilestones = const [],
    this.closingScenarios = const [],
  });
}

/// Full story detail
class Story {
  final String storyId;
  final LocalizedTitle title;
  final DifficultyLevel difficultyLevel;
  final String category;
  final int estimatedMinutes;
  final String? iconKey;
  final String? coverImageUrl;
  final ContextDescription contextDescription;
  final RolePersona rolePersona;
  final List<VocabularyItem> vocabularyList;
  final List<GrammarPoint> grammarPoints;
  final ConversationFlow conversationFlow;
  final bool isPublished;
  final List<String> suggestedPrompts;
  final List<String> tags;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Story({
    required this.storyId,
    required this.title,
    required this.difficultyLevel,
    required this.category,
    this.estimatedMinutes = 15,
    this.iconKey,
    this.coverImageUrl,
    required this.contextDescription,
    required this.rolePersona,
    this.vocabularyList = const [],
    this.grammarPoints = const [],
    required this.conversationFlow,
    this.isPublished = true,
    this.suggestedPrompts = const [],
    this.tags = const [],
    this.createdAt,
    this.updatedAt,
  });
}

/// Story list item for display in story selection.
///
/// Carries its own [toCacheJson]/[fromCacheJson] pair purely for the
/// presentation layer's local "recently used" persistence — this is the
/// entity's own concern (how it survives a restart), not an API contract,
/// so it doesn't pull in the data-layer model.
class StoryListItem {
  final String storyId;
  final LocalizedTitle title;
  final DifficultyLevel difficultyLevel;
  final String category;
  final int estimatedMinutes;
  final String? iconKey;
  final String? coverImageUrl;
  final List<String> suggestedPrompts;
  final List<String> tags;

  const StoryListItem({
    required this.storyId,
    required this.title,
    required this.difficultyLevel,
    required this.category,
    this.estimatedMinutes = 15,
    this.iconKey,
    this.coverImageUrl,
    this.suggestedPrompts = const [],
    this.tags = const [],
  });

  Map<String, dynamic> toCacheJson() => {
    'story_id': storyId,
    'title': {'vi': title.vi, 'en': title.en},
    'category': category,
    'difficulty_level': difficultyLevel.code,
    'estimated_minutes': estimatedMinutes,
    'icon_key': iconKey,
    'cover_image_url': coverImageUrl,
    'suggested_prompts': suggestedPrompts,
    'tags': tags,
  };

  factory StoryListItem.fromCacheJson(Map<String, dynamic> json) {
    return StoryListItem(
      storyId: json['story_id'] as String? ?? '',
      title: LocalizedTitle(
        vi: (json['title'] as Map?)?['vi'] as String? ?? '',
        en: (json['title'] as Map?)?['en'] as String? ?? '',
      ),
      category: json['category'] as String? ?? '',
      difficultyLevel: DifficultyLevel.fromString(
        json['difficulty_level'] as String?,
      ),
      estimatedMinutes: json['estimated_minutes'] as int? ?? 15,
      iconKey: json['icon_key'] as String?,
      coverImageUrl: json['cover_image_url'] as String?,
      suggestedPrompts:
          (json['suggested_prompts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          [],
    );
  }
}
