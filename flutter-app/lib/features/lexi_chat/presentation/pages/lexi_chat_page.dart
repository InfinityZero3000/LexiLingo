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
///  - Topic-based conversation with elegant topic display
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

  // Current topic
  String _currentTopic = 'Free Conversation';

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
                : [const Color(0xFFFAFBFC), const Color(0xFFF8F9FA)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(isDark),
              _buildTopicBar(isDark),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          // Back button
          IconButton(
            icon: Icon(
              Icons.arrow_back_ios_rounded,
              color: isDark ? Colors.white : AppColors.textDark,
              size: 18,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lexi',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppColors.textDark,
                    letterSpacing: -0.3,
                  ),
                ),
                Consumer<LexiChatProvider>(
                  builder: (_, provider, __) {
                    final status = provider.isLexiTyping
                        ? 'typing...'
                        : 'Online';
                    return Text(
                      status,
                      style: TextStyle(
                        fontSize: 12,
                        color: provider.isLexiTyping
                            ? AppColors.primary
                            : (isDark ? Colors.white54 : AppColors.textGrey),
                        fontWeight: provider.isLexiTyping ? FontWeight.w500 : FontWeight.normal,
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
                  color: isDark ? const Color(0xFF2A3A4A) : const Color(0xFFF6F7F8),
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

  // ── Topic Display Bar ────────────────────────────────────────────────────
  Widget _buildTopicBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C2A38).withValues(alpha: 0.6)
            : Colors.white.withValues(alpha: 0.6),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF2A3A4A) : const Color(0xFFF0F2F4),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 16,
            color: isDark ? Colors.white54 : AppColors.textGrey,
          ),
          const SizedBox(width: 8),
          Text(
            'Topic:',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : AppColors.textGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTopicChip('Free Conversation', isDark),
                  const SizedBox(width: 6),
                  _buildTopicChip('Daily Life', isDark),
                  const SizedBox(width: 6),
                  _buildTopicChip('Travel', isDark),
                  const SizedBox(width: 6),
                  _buildTopicChip('Work', isDark),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopicChip(String topic, bool isDark) {
    final isSelected = _currentTopic == topic;
    return GestureDetector(
      onTap: () => setState(() => _currentTopic = topic),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF2A3A4A) : const Color(0xFFF0F2F4))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? (isDark ? const Color(0xFF3A4A5A) : AppColors.primary.withValues(alpha: 0.3))
                : (isDark ? const Color(0xFF2A3A4A) : const Color(0xFFE8ECEF)),
            width: 1,
          ),
        ),
        child: Text(
          topic,
          style: TextStyle(
            fontSize: 12,
            color: isSelected
                ? (isDark ? Colors.white : AppColors.textDark)
                : (isDark ? Colors.white54 : AppColors.textGrey),
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
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

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: messages.length + (provider.isLexiTyping ? 1 : 0),
          itemBuilder: (context, index) {
            // Typing indicator at the end
            if (index == messages.length && provider.isLexiTyping) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: LexiTypingIndicator(),
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
                  color: isDark ? const Color(0xFF2A3A4A) : const Color(0xFFE8ECEF),
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
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopRecording(),
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
          _isRecording ? Icons.mic_rounded : Icons.mic_none_rounded,
          color: _isRecording
              ? Colors.red
              : (isDark ? Colors.white54 : AppColors.textGrey),
          size: 20,
        ),
      ),
    );
  }
}
