import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/voice_provider.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/tts_settings_provider.dart';

/// Speak Button Widget
/// A reusable button that uses TTS to speak text
/// Can be used in flashcards, vocabulary lists, lesson content, etc.
class SpeakButton extends StatefulWidget {
  final String text;
  final double size;
  final Color? color;
  final Color? iconColor;
  final bool mini;

  const SpeakButton({
    super.key,
    required this.text,
    this.size = 48,
    this.color,
    this.iconColor,
    this.mini = false,
  });

  @override
  State<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<SpeakButton> {
  final AudioPlayer _player = AudioPlayer();
  bool _isLoading = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _isPlaying = false;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _speak() async {
    if (_isLoading || widget.text.isEmpty) return;

    if (_isPlaying) {
      await _player.stop();
      setState(() => _isPlaying = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final voiceProvider = context.read<VoiceProvider>();
      final ttsSettings = context.read<TtsSettingsProvider>();
      final result = await voiceProvider.synthesizeAndPlay(text: widget.text);

      if (result != null && result.audioData.isNotEmpty) {
        // Save to temp file and play
        final directory = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final file = File('${directory.path}/speak_$timestamp.wav');
        await file.writeAsBytes(result.audioData);

        await _player.setFilePath(file.path);
        // Apply playback speed from settings
        await _player.setSpeed(ttsSettings.playbackSpeed);
        await _player.play();
        
        // Clean up temp file after playback
        _player.playerStateStream.firstWhere(
          (state) => state.processingState == ProcessingState.completed,
        ).then((_) {
          try {
            file.deleteSync();
          } catch (_) {}
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonColor = widget.color ?? theme.primaryColor;
    final iconColor = widget.iconColor ?? Colors.white;

    if (widget.mini) {
      return _buildMiniButton(buttonColor, iconColor);
    }

    return _buildStandardButton(buttonColor, iconColor);
  }

  Widget _buildMiniButton(Color buttonColor, Color iconColor) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _speak,
        borderRadius: BorderRadius.circular(widget.size / 2),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: buttonColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: _buildIcon(buttonColor),
        ),
      ),
    );
  }

  Widget _buildStandardButton(Color buttonColor, Color iconColor) {
    return Material(
      color: buttonColor,
      borderRadius: BorderRadius.circular(widget.size / 2),
      elevation: 2,
      child: InkWell(
        onTap: _speak,
        borderRadius: BorderRadius.circular(widget.size / 2),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
          ),
          child: _buildIcon(iconColor),
        ),
      ),
    );
  }

  Widget _buildIcon(Color color) {
    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: widget.size * 0.4,
          height: widget.size * 0.4,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      );
    }

    return Icon(
      _isPlaying ? Icons.stop : Icons.volume_up,
      color: color,
      size: widget.size * 0.5,
    );
  }
}

/// Speak Icon Button
/// A simpler icon-only variant for inline use
class SpeakIconButton extends StatefulWidget {
  final String text;
  final double size;
  final Color? color;

  const SpeakIconButton({
    super.key,
    required this.text,
    this.size = 24,
    this.color,
  });

  @override
  State<SpeakIconButton> createState() => _SpeakIconButtonState();
}

class _SpeakIconButtonState extends State<SpeakIconButton> {
  final AudioPlayer _player = AudioPlayer();
  bool _isLoading = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          if (state.processingState == ProcessingState.completed) {
            _isPlaying = false;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _speak() async {
    if (_isLoading || widget.text.isEmpty) return;

    if (_isPlaying) {
      await _player.stop();
      setState(() => _isPlaying = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final voiceProvider = context.read<VoiceProvider>();
      final ttsSettings = context.read<TtsSettingsProvider>();
      final result = await voiceProvider.synthesizeAndPlay(text: widget.text);

      if (result != null && result.audioData.isNotEmpty) {
        final directory = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final file = File('${directory.path}/speak_icon_$timestamp.wav');
        await file.writeAsBytes(result.audioData);

        await _player.setFilePath(file.path);
        // Apply playback speed from settings
        await _player.setSpeed(ttsSettings.playbackSpeed);
        await _player.play();
        
        _player.playerStateStream.firstWhere(
          (state) => state.processingState == ProcessingState.completed,
        ).then((_) {
          try {
            file.deleteSync();
          } catch (_) {}
        });
      }
    } catch (e) {
      // Silent fail for icon button
      debugPrint('SpeakIconButton error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).primaryColor;

    return IconButton(
      onPressed: _speak,
      icon: _isLoading
          ? SizedBox(
              width: widget.size,
              height: widget.size,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          : Icon(
              _isPlaying ? Icons.stop : Icons.volume_up,
              size: widget.size,
              color: color,
            ),
      tooltip: _isPlaying ? 'Stop' : 'Listen',
      splashRadius: widget.size * 0.8,
    );
  }
}
