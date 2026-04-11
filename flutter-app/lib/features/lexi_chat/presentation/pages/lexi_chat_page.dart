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

/// Lexi Chat Page — Minimalist design with clean conversation UI.
///
/// Features:
///  - Clean minimalist conversation interface (no avatar)
///  - Voice input (STT via Whisper) and voice output (TTS)
///  - Real-time grammar/word checking with inline corrections
///  - Free-form conversation focused on natural English practice
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

  @override
  void initState() {
    super.initState();
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
    final pending = provider.sendMessage(text, userId: _userId);
    _scrollToBottom();
    await pending;
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
      if (!mounted) return;
      final b64 = base64Encode(bytes);
      final provider = context.read<LexiChatProvider>();
      final pending = provider.sendVoiceMessage(b64, userId: _userId);
      _scrollToBottom();
      await pending;
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
                : [const Color(0xFFFAFBFC), const Color(0xFFF8F9FA)],
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

  // ── Minimalist Header ────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C2A38).withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF2A3A4A) : const Color(0xFFE8ECEF),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          // Title
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lexi',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textDark,
                    letterSpacing: -0.3,
                  ),
                ),
                Consumer<LexiChatProvider>(
                  builder: (_, provider, __) {
                    final status = provider.isLexiThinking
                        ? 'Lexi is thinking...'
                        : (provider.isLexiTyping
                              ? 'Lexi is typing...'
                              : 'English speaking companion');
                    final isActive =
                        provider.isLexiThinking || provider.isLexiTyping;
                    return Text(
                      status,
                      style: TextStyle(
                        fontSize: 12,
                        color: isActive
                            ? AppColors.primary
                            : (isDark ? Colors.white54 : AppColors.textGrey),
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w500,
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
              return Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A3A4A)
                      : const Color(0xFFF6F7F8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: Icon(
                    provider.ttsEnabled
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    color: provider.ttsEnabled
                        ? AppColors.primary
                        : (isDark ? Colors.white38 : AppColors.textGrey),
                    size: 20,
                  ),
                  onPressed: provider.toggleTts,
                  tooltip: 'Toggle voice',
                  padding: const EdgeInsets.all(8),
                ),
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
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2,
                ),
                const SizedBox(height: 12),
                Text(
                  'Starting conversation...',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : AppColors.textGrey,
                  ),
                ),
              ],
            ),
          );
        }

        final messages = provider.messages;
        final isResponding = provider.isLexiResponding;

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: messages.length + (isResponding ? 1 : 0),
          itemBuilder: (context, index) {
            // Typing indicator at the end
            if (index == messages.length && isResponding) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: LexiTypingIndicator(isThinking: provider.isLexiThinking),
              );
            }

            final message = messages[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LexiDialogueBubble(
                message: message,
                onPlayAudio: message.hasAudio
                    ? () => provider.replayAudio(message)
                    : null,
                onShowCorrections:
                    (message.hasCorrections ||
                        message.vietnameseHint != null ||
                        message.linkedConcepts.isNotEmpty)
                    ? () => LexiCorrectionsSheet.show(context, message)
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  // ── Minimalist Input Bar ────────────────────────────────────────────────
  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C2A38).withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF2A3A4A) : const Color(0xFFE8ECEF),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Voice recording button
          _buildVoiceButton(isDark),
          const SizedBox(width: 12),
          // Text input
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0A1628)
                    : const Color(0xFFF6F7F8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF2A3A4A)
                      : const Color(0xFFE8ECEF),
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                maxLines: 4,
                minLines: 1,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
                decoration: InputDecoration(
                  hintText: 'Message Lexi...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : AppColors.textGrey,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Send button
          Consumer<LexiChatProvider>(
            builder: (_, provider, __) {
              return Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    provider.isSending
                        ? Icons.hourglass_empty_rounded
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
      onTap: () {
        if (_isRecording) {
          _stopRecording();
        } else {
          _startRecording();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _isRecording
              ? Colors.red.withValues(alpha: 0.1)
              : (isDark ? const Color(0xFF2A3A4A) : const Color(0xFFF6F7F8)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isRecording
                ? Colors.red.withValues(alpha: 0.3)
                : (isDark ? const Color(0xFF2A3A4A) : const Color(0xFFE8ECEF)),
            width: 1,
          ),
        ),
        child: Icon(
          _isRecording ? Icons.stop_rounded : Icons.mic_none_rounded,
          color: _isRecording
              ? Colors.red
              : (isDark ? Colors.white54 : AppColors.textGrey),
          size: 20,
        ),
      ),
    );
  }
}
