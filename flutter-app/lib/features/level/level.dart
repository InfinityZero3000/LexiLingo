/// Level Feature
/// Provides level system functionality with CEFR-based progression
///
/// Exports:
/// - LevelEntity: Domain models (LevelTier, LevelStatus, LevelTiers)
/// - ProficiencyEntity: Multi-dimensional skill assessment models
/// - LevelCalculator: Level calculation algorithms
/// - LevelProvider: State management for XP-based level (gamification)
/// - ProficiencyProvider: State management for proficiency assessment
/// - LevelWidgets: UI components for level display

// Domain entities
export 'domain/entities/level_entity.dart';
export 'domain/entities/proficiency_entity.dart';

// Services
export 'services/level_calculator.dart';

// Providers
export 'presentation/providers/level_provider.dart';
export 'presentation/providers/proficiency_provider.dart';

// Data sources
export 'data/datasources/proficiency_data_source.dart';

// Widgets
export 'presentation/widgets/level_widgets.dart';
