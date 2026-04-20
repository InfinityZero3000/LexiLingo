import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:http/http.dart' as http;
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Voice recording
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  int _lastMessageCount = 0;
  final List<String> _quickReplies = const [
    'Hi Lexi, can we practice speaking?',
    'Can you correct my sentence?',
    'Give me a daily conversation challenge.',
  ];

  @override
  void initState() {
    super.initState();
    // Restore latest session first; create new only when needed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<LexiChatProvider>();
      unawaited(
        provider.restoreLatestSession(_userId).catchError((Object error) {
          debugPrint('restoreLatestSession failed: $error');
        }),
      );
    });

    _scrollController.addListener(_handleTopReached);
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
    _scrollController.removeListener(_handleTopReached);
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

  void _handleTopReached() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels <= 30) {
      final provider = context.read<LexiChatProvider>();
      if (!provider.isLoadingMoreMessages && provider.hasMoreMessages) {
        unawaited(provider.loadOlderMessages());
      }
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

  Future<void> _sendQuickReply(String text) async {
    _controller.text = text;
    await _sendMessage();
  }

  // ── Voice Recording ─────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        _showSnack('Microphone permission required');
        return;
      }

      String recordingPath;
      if (kIsWeb) {
        recordingPath =
            'lexi_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      } else {
        recordingPath =
            '${Directory.systemTemp.path}/lexi_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
        path: recordingPath,
      );

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordingDuration += const Duration(seconds: 1));
      });
    } catch (e) {
      _showSnack('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();

    try {
      final path = await _recorder.stop();
      setState(() => _isRecording = false);

      if (path == null) return;

      final bytes = await _readRecordedAudio(path);
      if (bytes == null || bytes.isEmpty) {
        _showSnack('Recorded audio could not be read');
        return;
      }

      if (!mounted) return;
      final b64 = base64Encode(bytes);
      final provider = context.read<LexiChatProvider>();
      final pending = provider.sendVoiceMessage(b64, userId: _userId);
      _scrollToBottom();
      await pending;
      _scrollToBottom();
    } catch (e) {
      _showSnack('Failed to stop recording: $e');
    }
  }

  Future<List<int>?> _readRecordedAudio(String path) async {
    if (kIsWeb) {
      final uri = Uri.tryParse(path);
      if (uri == null) return null;
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    }

    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final provider = context.watch<LexiChatProvider>();
    final currentCount = provider.messages.length;
    if (currentCount != _lastMessageCount) {
      _lastMessageCount = currentCount;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildSessionDrawer(isDark),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [AppColors.surfaceDarkInk, AppColors.backgroundDark]
                : [AppColors.backgroundLight, AppColors.grey50],
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
            ? AppColors.surfaceDark.withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.surfaceDarkChat : AppColors.chatBgLight,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceDarkChat
                  : AppColors.backgroundLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(
                Icons.menu_rounded,
                color: isDark ? Colors.white70 : AppColors.textDark,
                size: 20,
              ),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              tooltip: 'Session history',
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
                            ? AppColorRoles.primary(isDark)
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
                      ? AppColors.surfaceDarkChat
                      : AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: Icon(
                    provider.ttsEnabled
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    color: provider.ttsEnabled
                        ? AppColorRoles.primary(isDark)
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
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceDarkChat
                  : AppColors.backgroundLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(
                Icons.add_comment_outlined,
                color: isDark ? Colors.white70 : AppColors.textDark,
                size: 20,
              ),
              onPressed: () =>
                  context.read<LexiChatProvider>().createNewSession(_userId),
              tooltip: 'New chat',
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionDrawer(bool isDark) {
    return Drawer(
      child: SafeArea(
        child: Consumer<LexiChatProvider>(
          builder: (context, provider, _) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Lexi Sessions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_rounded),
                        onPressed: () async {
                          Navigator.pop(context);
                          await provider.createNewSession(_userId);
                        },
                        tooltip: 'New session',
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: provider.sessions.isEmpty
                      ? Center(
                          child: Text(
                            'No previous sessions',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white54
                                  : AppColors.textGrey,
                            ),
                          ),
                        )
                      : Builder(
                          builder: (_) {
                            final sessions = provider.sessions;
                            return ListView.builder(
                          itemCount: sessions.length,
                          itemBuilder: (context, index) {
                            final s = sessions[index];
                            final selected =
                                provider.session?.sessionId == s.sessionId;
                            return ListTile(
                              selected: selected,
                              selectedTileColor: AppColorRoles.primary(
                                isDark,
                              ).withValues(alpha: 0.08),
                              title: Text(
                                s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                s.updatedAt.toLocal().toString().substring(
                                  0,
                                  16,
                                ),
                              ),
                              onTap: () async {
                                Navigator.pop(context);
                                await provider.selectSession(s);
                              },
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'rename') {
                                    final controller = TextEditingController(
                                      text: s.title,
                                    );
                                    final renamed = await showDialog<String>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Rename session'),
                                        content: TextField(
                                          controller: controller,
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('Cancel'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(
                                              context,
                                              controller.text.trim(),
                                            ),
                                            child: const Text('Save'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (renamed != null && renamed.isNotEmpty) {
                                      await provider.renameSession(
                                        s.sessionId,
                                        renamed,
                                      );
                                    }
                                  }
                                  if (value == 'delete') {
                                    await provider.deleteSession(s.sessionId);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text('Rename'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                          },
                        ),
                ),
              ],
            );
          },
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
                LottieLoadingWidget.medium(),
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
            ? AppColors.surfaceDark.withValues(alpha: 0.95)
            : Colors.white.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.surfaceDarkChat : AppColors.chatBgLight,
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isRecording)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.mic, color: AppColors.errorBright, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Recording ${_recordingDuration.inSeconds}s',
                    style: const TextStyle(
                      color: AppColors.errorBright,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (!_isRecording) ...[
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _quickReplies.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final text = _quickReplies[index];
                  return ActionChip(
                    label: Text(text, overflow: TextOverflow.ellipsis),
                    onPressed: () => _sendQuickReply(text),
                    labelStyle: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white70 : AppColors.textGrey,
                    ),
                    side: BorderSide(
                      color: isDark
                          ? AppColors.surfaceDarkChat
                          : AppColors.chatBgLight,
                    ),
                    backgroundColor: isDark
                        ? AppColors.surfaceDarkInk
                        : AppColors.backgroundLight,
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              // Voice recording button
              _buildVoiceButton(isDark),
              const SizedBox(width: 12),
              // Text input
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.surfaceDarkInk
                        : AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? AppColors.surfaceDarkChat
                          : AppColors.chatBgLight,
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
                      color: AppColorRoles.primary(isDark),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColorRoles.primary(
                            isDark,
                          ).withValues(alpha: 0.25),
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
                        color: isDark
                            ? AppColors.slate900
                            : AppColors.surfaceLight,
                        size: 20,
                      ),
                      onPressed: provider.isSending ? null : _sendMessage,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceButton(bool isDark) {
    return GestureDetector(
      onLongPressStart: (_) {
        if (!_isRecording) {
          _startRecording();
        }
      },
      onLongPressEnd: (_) {
        if (_isRecording) {
          _stopRecording();
        }
      },
      onTap: () {
        if (_isRecording) {
          _stopRecording();
        } else {
          _showSnack('Hold to record or tap to toggle');
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _isRecording
              ? Colors.red.withValues(alpha: 0.1)
              : (isDark
                    ? AppColors.surfaceDarkChat
                    : AppColors.backgroundLight),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isRecording
                ? Colors.red.withValues(alpha: 0.3)
                : (isDark ? AppColors.surfaceDarkChat : AppColors.chatBgLight),
            width: 1,
          ),
        ),
        child: Icon(
          _isRecording ? Icons.stop_rounded : Icons.mic_none_rounded,
          color: _isRecording
              ? AppColors.errorBright
              : (isDark ? Colors.white54 : AppColors.textGrey),
          size: 20,
        ),
      ),
    );
  }
}
