/// Story models for Topic-Based Conversation
/// Defines story/topic data structures for language learning scenarios

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

/// Localized title with Vietnamese and English
class LocalizedTitle {
  final String vi;
  final String en;

  const LocalizedTitle({required this.vi, required this.en});

  factory LocalizedTitle.fromJson(Map<String, dynamic> json) {
    return LocalizedTitle(
      vi: json['vi'] as String? ?? '',
      en: json['en'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'vi': vi, 'en': en};
}

/// Vocabulary item for learning
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

  factory VocabularyItem.fromJson(Map<String, dynamic> json) {
    return VocabularyItem(
      term: json['term'] as String? ?? json['word'] as String? ?? '',
      definition: json['definition'] as String? ?? json['meaning'] as String? ?? '',
      exampleInStory: json['example_in_story'] as String? ?? 
                      json['exampleInStory'] as String? ?? '',
      partOfSpeech: json['part_of_speech'] as String? ?? 
                    json['partOfSpeech'] as String? ?? '',
      phonetic: json['phonetic'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'term': term,
    'definition': definition,
    'example_in_story': exampleInStory,
    'part_of_speech': partOfSpeech,
    'phonetic': phonetic,
  };
}

/// Grammar point for learning
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

  factory GrammarPoint.fromJson(Map<String, dynamic> json) {
    return GrammarPoint(
      grammarStructure: json['grammar_structure'] as String? ?? 
                        json['grammarStructure'] as String? ?? 
                        json['pattern'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
      usageInStory: json['usage_in_story'] as String? ?? 
                    json['usageInStory'] as String? ?? '',
      examples: (json['examples'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'grammar_structure': grammarStructure,
    'explanation': explanation,
    'usage_in_story': usageInStory,
    'examples': examples,
  };
}

/// Role persona for conversation
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

  factory RolePersona.fromJson(Map<String, dynamic> json) {
    return RolePersona(
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? json['description'] as String? ?? '',
      personality: json['personality'] as String? ?? '',
      speakingStyle: json['speaking_style'] as String? ?? 
                     json['speakingStyle'] as String? ?? 
                     json['language_style'] as String? ?? '',
      background: json['background'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'role': role,
    'personality': personality,
    'speaking_style': speakingStyle,
    'background': background,
  };
}

/// Context description for story
class ContextDescription {
  final String setting;
  final String scenario;
  final List<String> objectives;

  const ContextDescription({
    required this.setting,
    required this.scenario,
    this.objectives = const [],
  });

  factory ContextDescription.fromJson(Map<String, dynamic> json) {
    return ContextDescription(
      setting: json['setting'] as String? ?? '',
      scenario: json['scenario'] as String? ?? json['situation'] as String? ?? '',
      objectives: (json['objectives'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'setting': setting,
    'scenario': scenario,
    'objectives': objectives,
  };
}

/// Conversation flow guidance
class ConversationFlow {
  final String openingPrompt;
  final List<String> keyMilestones;
  final List<String> closingScenarios;

  const ConversationFlow({
    required this.openingPrompt,
    this.keyMilestones = const [],
    this.closingScenarios = const [],
  });

  factory ConversationFlow.fromJson(Map<String, dynamic> json) {
    return ConversationFlow(
      openingPrompt: json['opening_prompt'] as String? ?? 
                     json['openingPrompt'] as String? ?? 
                     json['suggested_opening'] as String? ?? '',
      keyMilestones: (json['key_milestones'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ?? 
              (json['keyMilestones'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ?? [],
      closingScenarios: (json['closing_scenarios'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ?? 
              (json['closingScenarios'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'opening_prompt': openingPrompt,
    'key_milestones': keyMilestones,
    'closing_scenarios': closingScenarios,
  };
}

/// Full story detail
class Story {
  final String storyId;
  final LocalizedTitle title;
  final DifficultyLevel difficultyLevel;
  final String category;
  final int estimatedMinutes;
  final String? coverImageUrl;
  final ContextDescription contextDescription;
  final RolePersona rolePersona;
  final List<VocabularyItem> vocabularyList;
  final List<GrammarPoint> grammarPoints;
  final ConversationFlow conversationFlow;
  final bool isPublished;
  final List<String> tags;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Story({
    required this.storyId,
    required this.title,
    required this.difficultyLevel,
    required this.category,
    this.estimatedMinutes = 15,
    this.coverImageUrl,
    required this.contextDescription,
    required this.rolePersona,
    this.vocabularyList = const [],
    this.grammarPoints = const [],
    required this.conversationFlow,
    this.isPublished = true,
    this.tags = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory Story.fromJson(Map<String, dynamic> json) {
    return Story(
      storyId: json['story_id'] as String? ?? json['id'] as String? ?? '',
      title: json['title'] is Map 
          ? LocalizedTitle.fromJson(json['title'] as Map<String, dynamic>)
          : LocalizedTitle(vi: '', en: json['title']?.toString() ?? ''),
      category: json['category'] as String? ?? '',
      difficultyLevel: DifficultyLevel.fromString(
          json['difficulty_level'] as String? ?? json['difficulty'] as String?),
      estimatedMinutes: json['estimated_minutes'] as int? ?? 
                        json['estimatedMinutes'] as int? ?? 15,
      coverImageUrl: json['cover_image_url'] as String? ?? 
                     json['coverImageUrl'] as String?,
      contextDescription: json['context_description'] != null
          ? ContextDescription.fromJson(json['context_description'] as Map<String, dynamic>)
          : json['contextDescription'] != null
              ? ContextDescription.fromJson(json['contextDescription'] as Map<String, dynamic>)
              : const ContextDescription(setting: '', scenario: ''),
      rolePersona: json['role_persona'] != null
          ? RolePersona.fromJson(json['role_persona'] as Map<String, dynamic>)
          : json['rolePersona'] != null
              ? RolePersona.fromJson(json['rolePersona'] as Map<String, dynamic>)
              : const RolePersona(name: '', role: '', personality: '', speakingStyle: '', background: ''),
      vocabularyList: (json['vocabulary_list'] as List<dynamic>?)
              ?.map((e) => VocabularyItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          (json['vocabularyList'] as List<dynamic>?)
              ?.map((e) => VocabularyItem.fromJson(e as Map<String, dynamic>))
              .toList() ?? [],
      grammarPoints: (json['grammar_points'] as List<dynamic>?)
              ?.map((e) => GrammarPoint.fromJson(e as Map<String, dynamic>))
              .toList() ??
          (json['grammarPoints'] as List<dynamic>?)
              ?.map((e) => GrammarPoint.fromJson(e as Map<String, dynamic>))
              .toList() ?? [],
      conversationFlow: json['conversation_flow'] != null
          ? ConversationFlow.fromJson(json['conversation_flow'] as Map<String, dynamic>)
          : json['conversationFlow'] != null
              ? ConversationFlow.fromJson(json['conversationFlow'] as Map<String, dynamic>)
              : const ConversationFlow(openingPrompt: ''),
      isPublished: json['is_published'] as bool? ?? 
                   json['isPublished'] as bool? ?? true,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ?? [],
      createdAt: json['created_at'] != null 
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null 
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'story_id': storyId,
    'title': title.toJson(),
    'category': category,
    'difficulty_level': difficultyLevel.code,
    'estimated_minutes': estimatedMinutes,
    'cover_image_url': coverImageUrl,
    'context_description': contextDescription.toJson(),
    'role_persona': rolePersona.toJson(),
    'vocabulary_list': vocabularyList.map((v) => v.toJson()).toList(),
    'grammar_points': grammarPoints.map((g) => g.toJson()).toList(),
    'conversation_flow': conversationFlow.toJson(),
    'is_published': isPublished,
    'tags': tags,
  };
}

/// Story list item for display in story selection
class StoryListItem {
  final String storyId;
  final LocalizedTitle title;
  final DifficultyLevel difficultyLevel;
  final String category;
  final int estimatedMinutes;
  final String? coverImageUrl;
  final List<String> tags;

  const StoryListItem({
    required this.storyId,
    required this.title,
    required this.difficultyLevel,
    required this.category,
    this.estimatedMinutes = 15,
    this.coverImageUrl,
    this.tags = const [],
  });

  factory StoryListItem.fromJson(Map<String, dynamic> json) {
    return StoryListItem(
      storyId: json['story_id'] as String? ?? json['id'] as String? ?? '',
      title: json['title'] is Map 
          ? LocalizedTitle.fromJson(json['title'] as Map<String, dynamic>)
          : LocalizedTitle(vi: '', en: json['title']?.toString() ?? ''),
      category: json['category'] as String? ?? '',
      difficultyLevel: DifficultyLevel.fromString(
          json['difficulty_level'] as String? ?? json['difficulty'] as String?),
      estimatedMinutes: json['estimated_minutes'] as int? ?? 
                        json['estimatedMinutes'] as int? ?? 15,
      coverImageUrl: json['cover_image_url'] as String? ?? 
                     json['coverImageUrl'] as String?,
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'story_id': storyId,
    'title': title.toJson(),
    'category': category,
    'difficulty_level': difficultyLevel.code,
    'estimated_minutes': estimatedMinutes,
    'cover_image_url': coverImageUrl,
    'tags': tags,
  };
}
