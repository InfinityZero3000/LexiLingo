import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/speech_recognition_provider.dart';

/// Speech Recognition Button Widget
/// A microphone button that uses Web Speech API on web platform
class SpeechRecognitionButton extends StatefulWidget {
  /// Called when final transcription is received
  final void Function(String transcript, double confidence)? onResult;
  
  /// Called when listening state changes
  final void Function(bool isListening)? onListeningChanged;
  
  /// Called when an error occurs
  final void Function(String error)? onError;
  
  /// Initial language for recognition
  final String language;
  
  /// Button size
  final double size;
  
  /// Show transcription text below button
  final bool showTranscript;

  const SpeechRecognitionButton({
    super.key,
    this.onResult,
    this.onListeningChanged,
    this.onError,
    this.language = 'en-US',
    this.size = 56,
    this.showTranscript = true,
  });

  @override
  State<SpeechRecognitionButton> createState() => _SpeechRecognitionButtonState();
}

class _SpeechRecognitionButtonState extends State<SpeechRecognitionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late SpeechRecognitionProvider _provider;
  bool _isProviderOwned = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Try to get provider from context, or create one
    try {
      _provider = Provider.of<SpeechRecognitionProvider>(context, listen: false);
    } catch (e) {
      // Create our own provider if not available
      _provider = SpeechRecognitionProvider();
      _isProviderOwned = true;
    }
    _provider.setLanguage(widget.language);
  }

  @override
  void dispose() {
    _animationController.dispose();
    if (_isProviderOwned) {
      _provider.dispose();
    }
    super.dispose();
  }

  void _toggleListening() async {
    if (_provider.isListening) {
      _provider.stopListening();
      _animationController.stop();
      _animationController.reset();
      widget.onListeningChanged?.call(false);
      
      // Return final result
      final transcription = _provider.getTranscription();
      if (transcription != null && transcription.text.isNotEmpty) {
        widget.onResult?.call(transcription.text, transcription.confidence ?? 0.0);
      }
    } else {
      _provider.clearTranscript();
      await _provider.startListening(language: widget.language);
      
      if (_provider.hasError) {
        widget.onError?.call(_provider.errorMessage ?? 'Unknown error');
      } else {
        _animationController.repeat(reverse: true);
        widget.onListeningChanged?.call(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if web speech is supported
    if (!kIsWeb) {
      return _buildUnsupportedWidget('Only available on web');
    }

    if (!_provider.isWebSpeechSupported) {
      return _buildUnsupportedWidget('Browser not supported');
    }

    return ChangeNotifierProvider.value(
      value: _provider,
      child: Consumer<SpeechRecognitionProvider>(
        builder: (context, provider, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Microphone button
              AnimatedBuilder(
                animation: _scaleAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: provider.isListening ? _scaleAnimation.value : 1.0,
                    child: child,
                  );
                },
                child: GestureDetector(
                  onTap: _toggleListening,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: provider.isListening
                          ? Colors.red
                          : Theme.of(context).primaryColor,
                      boxShadow: [
                        BoxShadow(
                          color: (provider.isListening ? Colors.red : Theme.of(context).primaryColor)
                              .withOpacity(0.3),
                          blurRadius: provider.isListening ? 20 : 10,
                          spreadRadius: provider.isListening ? 5 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      provider.isListening ? Icons.stop : Icons.mic,
                      color: Colors.white,
                      size: widget.size * 0.5,
                    ),
                  ),
                ),
              ),
              
              // Status text
              if (widget.showTranscript) ...[
                const SizedBox(height: 12),
                _buildStatusText(provider),
              ],
              
              // Error message
              if (provider.hasError && provider.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    provider.errorMessage!,
                    style: TextStyle(
                      color: Colors.red[400],
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusText(SpeechRecognitionProvider provider) {
    if (provider.isListening) {
      final text = provider.fullTranscript;
      if (text.isEmpty) {
        return Text(
          'Listening...',
          style: TextStyle(
            color: Colors.grey[600],
            fontStyle: FontStyle.italic,
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
    }
    
    if (provider.transcript.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green[200]!),
        ),
        child: Column(
          children: [
            Text(
              provider.transcript,
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (provider.confidence > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Confidence: ${(provider.confidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ),
          ],
        ),
      );
    }
    
    return Text(
      'Tap to speak',
      style: TextStyle(
        color: Colors.grey[500],
        fontSize: 12,
      ),
    );
  }

  Widget _buildUnsupportedWidget(String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[300],
          ),
          child: Icon(
            Icons.mic_off,
            color: Colors.grey[500],
            size: widget.size * 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
