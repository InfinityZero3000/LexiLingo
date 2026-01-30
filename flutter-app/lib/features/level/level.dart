/// Level Feature
/// Provides level system functionality with CEFR-based progression
///
/// Exports:
/// - LevelEntity: Domain models (LevelTier, LevelStatus, LevelTiers)
/// - LevelCalculator: Level calculation algorithms
/// - LevelProvider: State management for level data
/// - LevelWidgets: UI components for level display

export 'domain/entities/level_entity.dart';
export 'services/level_calculator.dart';
export 'presentation/providers/level_provider.dart';
export 'presentation/widgets/level_widgets.dart';
