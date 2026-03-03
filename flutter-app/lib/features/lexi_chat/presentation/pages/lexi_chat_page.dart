import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_chat_provider.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_dialogue_bubble.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_typing_indicator.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_corrections_sheet.dart';

/// Lexi Chat Page — Game-style visual novel dialogue with the parrot mascot.
///
/// Features:
///  - Story-driven conversation with animated parrot avatar
///  - Voice input (STT via Whisper) and voice output (TTS)
///  - Grammar corrections displayed in-line
///  - Knowledge graph concept expansion
///  - Dark/light theme support
class LexiChatPage extends StatefulWidget {
  const LexiChatPage({super.key});

  @override
  State<LexiChatPage> createState() => _LexiChatPageState();
}

class _LexiChatPageState extends State<LexiChatPage>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Voice recording
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  String? _recordingPath;

  // Animation
  late AnimationController _headerAnimController;
  late Animation<double> _headerBounce;

  @override
  void initState() {
    super.initState();
    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _headerBounce = Tween<double>(begin: 0, end: -6).animate(
      CurvedAnimation(parent: _headerAnimController, curve: Curves.easeInOut),
    );

    // Start session
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<LexiChatProvider>();
      if (!provider.hasSession) {
        final userId = _userId;
        provider.startSession(userId);
      }
    });
  }

  String get _userId {
    try {
      return Provider.of<AuthProvider>(context, listen: false).user?.id ??
          'demo_user_001';
    } catch (_) {
      return 'demo_user_001';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _headerAnimController.dispose();
    _recorder.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    final provider = context.read<LexiChatProvider>();
    await provider.sendMessage(text, userId: _userId);
    _scrollToBottom();
  }

  // ── Voice Recording ─────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _showSnack('Microphone permission required');
      return;
    }

    final dir = await getTemporaryDirectory();
    _recordingPath =
        '${dir.path}/lexi_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
      path: _recordingPath!,
    );

    setState(() {
      _isRecording = true;
      _recordingDuration = Duration.zero;
    });

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recordingDuration += const Duration(seconds: 1));
    });
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    final path = await _recorder.stop();
    setState(() => _isRecording = false);

    if (path != null) {
      final bytes = await File(path).readAsBytes();
      final b64 = base64Encode(bytes);
      final provider = context.read<LexiChatProvider>();
      await provider.sendVoiceMessage(b64, userId: _userId);
      _scrollToBottom();
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF0A1628), const Color(0xFF101922)]
                : [const Color(0xFFE3F2FD), const Color(0xFFF6F7F8)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(isDark),
              Expanded(child: _buildMessageList(isDark)),
              _buildInputBar(isDark),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header with animated parrot ──────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C2A38).withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: Icon(
              Icons.arrow_back_ios_rounded,
              color: isDark ? Colors.white : AppColors.textDark,
              size: 20,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          // Animated parrot avatar
          AnimatedBuilder(
            animation: _headerBounce,
            builder: (_, child) {
              return Transform.translate(
                offset: Offset(0, _headerBounce.value),
                child: child,
              );
            },
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF43E97B), Color(0xFF38F9D7)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF43E97B).withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/avatar/avatar-ai-chat.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Text('🦜', style: TextStyle(fontSize: 24)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Title & status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lexi the Parrot',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
                Consumer<LexiChatProvider>(
                  builder: (_, provider, __) {
                    final status = provider.isLexiTyping
                        ? 'is typing...'
                        : 'English Adventure';
                    return Text(
                      status,
                      style: TextStyle(
                        fontSize: 12,
                        color: provider.isLexiTyping
                            ? AppColors.greenSuccess
                            : (isDark ? Colors.white54 : AppColors.textGrey),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // TTS toggle
          Consumer<LexiChatProvider>(
            builder: (_, provider, __) {
              return IconButton(
                icon: Icon(
                  provider.ttsEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  color: provider.ttsEnabled
                      ? AppColors.primary
                      : (isDark ? Colors.white38 : AppColors.textGrey),
                ),
                onPressed: provider.toggleTts,
                tooltip: 'Toggle Lexi\'s voice',
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Message List ─────────────────────────────────────────────────────────
  Widget _buildMessageList(bool isDark) {
    return Consumer<LexiChatProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('🦜', style: TextStyle(fontSize: 48)),
                SizedBox(height: 16),
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text(
                  'Lexi is getting ready...',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          );
        }

        final messages = provider.messages;

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: messages.length + (provider.isLexiTyping ? 1 : 0),
          itemBuilder: (context, index) {
            // Typing indicator at the end
            if (index == messages.length && provider.isLexiTyping) {
              return const LexiTypingIndicator();
            }

            final message = messages[index];
            return LexiDialogueBubble(
              message: message,
              onPlayAudio: message.hasAudio
                  ? () => provider.replayAudio(message)
                  : null,
              onShowCorrections: (message.hasCorrections ||
                      message.vietnameseHint != null ||
                      message.linkedConcepts.isNotEmpty)
                  ? () => LexiCorrectionsSheet.show(context, message)
                  : null,
            );
          },
        );
      },
    );
  }

  // ── Input Bar ────────────────────────────────────────────────────────────
  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C2A38).withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Voice recording button
          _buildVoiceButton(isDark),
          const SizedBox(width: 8),
          // Text input
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0A1628)
                    : const Color(0xFFF6F7F8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF2A3A4A)
                      : AppColors.grey300,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      maxLines: 3,
                      minLines: 1,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Talk to Lexi...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : AppColors.textGrey,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          Consumer<LexiChatProvider>(
            builder: (_, provider, __) {
              return Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: AppColors.primaryGradient,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    provider.isSending
                        ? Icons.hourglass_top_rounded
                        : Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: provider.isSending ? null : _sendMessage,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceButton(bool isDark) {
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopRecording(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isRecording
              ? Colors.red
              : (isDark ? const Color(0xFF2A3A4A) : AppColors.grey200),
          boxShadow: _isRecording
              ? [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isRecording ? Icons.mic : Icons.mic_none_rounded,
              color: _isRecording
                  ? Colors.white
                  : (isDark ? Colors.white54 : AppColors.textGrey),
              size: 20,
            ),
            if (_isRecording)
              Text(
                '${_recordingDuration.inSeconds}s',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
