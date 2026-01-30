import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/tts_settings_provider.dart';

/// TTS Speed Selector Widget
/// Allows users to select playback speed for Text-to-Speech
class TtsSpeedSelector extends StatelessWidget {
  final bool showLabel;
  final bool compact;

  const TtsSpeedSelector({
    super.key,
    this.showLabel = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<TtsSettingsProvider>(
      builder: (context, settings, child) {
        if (compact) {
          return _buildCompactSelector(context, settings);
        }
        return _buildFullSelector(context, settings);
      },
    );
  }

  Widget _buildCompactSelector(BuildContext context, TtsSettingsProvider settings) {
    return InkWell(
      onTap: () => settings.cycleSpeed(),
      onLongPress: () => _showSpeedDialog(context, settings),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.speed,
              size: 16,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(width: 4),
            Text(
              settings.speedLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullSelector(BuildContext context, TtsSettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Playback Speed',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: TtsSettingsProvider.speedOptions.map((speed) {
            final isSelected = settings.playbackSpeed == speed;
            return ChoiceChip(
              label: Text(_getSpeedLabel(speed)),
              selected: isSelected,
              onSelected: (_) => settings.setPlaybackSpeed(speed),
              selectedColor: Theme.of(context).primaryColor,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : null,
                fontWeight: isSelected ? FontWeight.bold : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _getSpeedLabel(double speed) {
    if (speed == 0.5) return '0.5x Slow';
    if (speed == 0.75) return '0.75x';
    if (speed == 1.0) return '1x Normal';
    if (speed == 1.25) return '1.25x';
    if (speed == 1.5) return '1.5x Fast';
    if (speed == 2.0) return '2x Fast';
    return '${speed}x';
  }

  void _showSpeedDialog(BuildContext context, TtsSettingsProvider settings) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed, size: 24),
                const SizedBox(width: 12),
                Text(
                  'TTS Playback Speed',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Adjust the speed of text-to-speech audio playback',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 24),
            ...TtsSettingsProvider.speedOptions.map((speed) {
              final isSelected = settings.playbackSpeed == speed;
              return ListTile(
                leading: Icon(
                  _getSpeedIcon(speed),
                  color: isSelected ? Theme.of(context).primaryColor : null,
                ),
                title: Text(
                  _getSpeedLabel(speed),
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : null,
                    color: isSelected ? Theme.of(context).primaryColor : null,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check_circle,
                        color: Theme.of(context).primaryColor)
                    : null,
                onTap: () {
                  settings.setPlaybackSpeed(speed);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  IconData _getSpeedIcon(double speed) {
    if (speed < 1.0) return Icons.slow_motion_video;
    if (speed > 1.0) return Icons.fast_forward;
    return Icons.play_arrow;
  }
}

/// TTS Speed Button
/// A simple button that cycles through speed options
class TtsSpeedButton extends StatelessWidget {
  final double size;

  const TtsSpeedButton({
    super.key,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<TtsSettingsProvider>(
      builder: (context, settings, child) {
        return Tooltip(
          message: 'TTS Speed: ${settings.speedLabel}\nTap to change, long-press for options',
          child: InkWell(
            onTap: () => settings.cycleSpeed(),
            onLongPress: () => _showSpeedBottomSheet(context, settings),
            borderRadius: BorderRadius.circular(size / 2),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  settings.speedLabel,
                  style: TextStyle(
                    fontSize: size * 0.3,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSpeedBottomSheet(BuildContext context, TtsSettingsProvider settings) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Select Playback Speed',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: TtsSettingsProvider.speedOptions.map((speed) {
                final isSelected = settings.playbackSpeed == speed;
                return GestureDetector(
                  onTap: () {
                    settings.setPlaybackSpeed(speed);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Text(
                      speed == 1.0 ? 'Normal' : '${speed}x',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
