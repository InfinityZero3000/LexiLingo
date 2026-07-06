import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_chat_provider.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_dialogue_bubble.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_typing_indicator.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_corrections_sheet.dart';
import 'package:lexilingo_app/features/voice/data/datasources/speech_recognition_service.dart';

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

  // Voice recording (mobile/desktop)
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isTranscribing = false;
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;

  // Web Speech Recognition (web platform)
  WebSpeechRecognition? _webSpeech;
  StreamSubscription<WebSpeechResult>? _webSpeechSub;
  bool _isWebSpeechActive = false;
  String _liveTranscript = '';

  bool get _isVoiceActive =>
      _isRecording || _isTranscribing || _isWebSpeechActive;

  int _lastMessageCount = 0;
  List<String> get _quickReplies => [
    'lexiChat.quickReply1'.tr(),
    'lexiChat.quickReply2'.tr(),
    'lexiChat.quickReply3'.tr(),
  ];

  @override
  void initState() {
    super.initState();
    // Restore latest session first; create new only when needed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<LexiChatProvider>();
      provider.setNativeLanguage(_nativeLanguage);
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

  String get _nativeLanguage {
    try {
      return Provider.of<AuthProvider>(
            context,
            listen: false,
          ).user?.nativeLanguage ??
          'vi';
    } catch (_) {
      return 'vi';
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
    _webSpeechSub?.cancel();
    _webSpeech?.dispose();
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
    final pending = provider.sendMessageStreaming(text, userId: _userId);
    _scrollToBottom();
    await pending;
    _scrollToBottom();
  }

  Future<void> _sendQuickReply(String text) async {
    _controller.text = text;
    await _sendMessage();
  }

  // ── Web: Real-time STT via Browser Speech API ─────────────────────────────
  void _startWebSpeech() {
    _webSpeech?.dispose();
    _webSpeech = WebSpeechRecognition();
    _liveTranscript = '';
    _controller.clear();

    setState(() => _isWebSpeechActive = true);

    final stream = _webSpeech!.startListening(
      language: 'en-US',
      continuous: true,
    );

    _webSpeechSub?.cancel();
    _webSpeechSub = stream.listen(
      (result) {
        if (result.isFinal) {
          _liveTranscript += result.transcript;
        }
        // Show accumulated + current interim text in input field live
        final display =
            _liveTranscript + (result.isFinal ? '' : result.transcript);
        _controller.text = display;
        _controller.selection = TextSelection.collapsed(offset: display.length);
      },
      onError: (error) {
        setState(() => _isWebSpeechActive = false);
        _showSnack(
          'lexiChat.sttFailed'.tr(namedArgs: {'error': error.toString()}),
        );
      },
      onDone: () {
        if (_isWebSpeechActive) {
          setState(() => _isWebSpeechActive = false);
        }
      },
    );
  }

  void _stopWebSpeech() {
    _webSpeech?.stopListening();
    _webSpeechSub?.cancel();
    setState(() => _isWebSpeechActive = false);
    // Text is already in _controller — send if non-empty
    if (_controller.text.trim().isNotEmpty) {
      unawaited(_sendMessage());
    }
  }

  // ── Mobile/Desktop: Record → REST STT → send as text ─────────────────────
  Future<void> _startMobileRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        _showSnack('lexiChat.micPermissionRequired'.tr());
        return;
      }

      final recordingPath =
          '${Directory.systemTemp.path}/lexi_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

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
      _showSnack(
        'lexiChat.failedStartRecording'.tr(namedArgs: {'error': e.toString()}),
      );
    }
  }

  Future<void> _stopMobileRecordingAndTranscribe() async {
    _recordingTimer?.cancel();

    try {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _isTranscribing = true;
      });

      if (path == null) {
        setState(() => _isTranscribing = false);
        return;
      }

      final file = File(path);
      if (!await file.exists()) {
        _showSnack('lexiChat.audioReadError'.tr());
        setState(() => _isTranscribing = false);
        return;
      }
      final bytes = await file.readAsBytes();

      if (!mounted) {
        setState(() => _isTranscribing = false);
        return;
      }
      final chatProvider = context.read<LexiChatProvider>();
      final transcript = await chatProvider.transcribeAudio(bytes);
      if (!mounted) return;
      setState(() => _isTranscribing = false);

      if (transcript.isEmpty) {
        _showSnack('lexiChat.noSpeechDetected'.tr());
        return;
      }

      _controller.text = transcript;
      _controller.selection = TextSelection.collapsed(
        offset: transcript.length,
      );

      if (!mounted) return;
      await _sendMessage();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _isTranscribing = false;
      });
      _showSnack('lexiChat.sttFailed'.tr(namedArgs: {'error': e.toString()}));
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
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                children: [
                  _buildHeader(isDark),
                  Expanded(child: _buildMessageList(isDark)),
                  _buildInputBar(isDark),
                ],
              ),
            ),
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
              tooltip: 'lexiChat.tooltipSessionHistory'.tr(),
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
                  'lexiChat.title'.tr(),
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
                        ? 'lexiChat.statusThinking'.tr()
                        : (provider.isLexiTyping
                              ? 'lexiChat.statusTyping'.tr()
                              : 'lexiChat.statusIdle'.tr());
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
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (provider.ttsEnabled) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surfaceDarkChat
                            : AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        onTap: provider.cycleTtsSpeed,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: Text(
                            provider.ttsSpeedLabel,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColorRoles.primary(isDark),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Container(
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
                      tooltip: 'lexiChat.tooltipToggleVoice'.tr(),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                ],
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
              tooltip: 'lexiChat.tooltipNewChat'.tr(),
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
                          'lexiChat.sessionsDrawerTitle'.tr(),
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
                        tooltip: 'lexiChat.tooltipNewSession'.tr(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: provider.sessions.isEmpty
                      ? Center(
                          child: Text(
                            'lexiChat.noSessions'.tr(),
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
                                        final controller =
                                            TextEditingController(
                                              text: s.title,
                                            );
                                        final renamed =
                                            await showDialog<String>(
                                              context: context,
                                              builder: (_) => AlertDialog(
                                                title: Text(
                                                  'lexiChat.renameSessionTitle'
                                                      .tr(),
                                                ),
                                                content: TextField(
                                                  controller: controller,
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                    child: Text(
                                                      'lexiChat.cancelButton'
                                                          .tr(),
                                                    ),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          controller.text
                                                              .trim(),
                                                        ),
                                                    child: Text(
                                                      'lexiChat.saveButton'
                                                          .tr(),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                        if (renamed != null &&
                                            renamed.isNotEmpty) {
                                          await provider.renameSession(
                                            s.sessionId,
                                            renamed,
                                          );
                                        }
                                      }
                                      if (value == 'delete') {
                                        await provider.deleteSession(
                                          s.sessionId,
                                        );
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        value: 'rename',
                                        child: Text(
                                          'lexiChat.renameAction'.tr(),
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text(
                                          'lexiChat.deleteAction'.tr(),
                                        ),
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
                  'lexiChat.startingConversation'.tr(),
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : AppColors.textGrey,
                  ),
                ),
              ],
            ),
          );
        }

        final messages = provider.messages
            .where((message) => !_isEmptyStreamingLexiMessage(message))
            .toList(growable: false);
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

  bool _isEmptyStreamingLexiMessage(LexiMessage message) {
    return message.isLexi &&
        message.syncStatus == 'streaming' &&
        message.content.trim().isEmpty;
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
          if (_isVoiceActive)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color:
                    (_isWebSpeechActive
                            ? Colors.blue
                            : _isTranscribing
                            ? Colors.orange
                            : Colors.red)
                        .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      (_isWebSpeechActive
                              ? Colors.blue
                              : _isTranscribing
                              ? Colors.orange
                              : Colors.red)
                          .withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  if (_isTranscribing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.orange,
                      ),
                    )
                  else
                    Icon(
                      _isWebSpeechActive
                          ? Icons.graphic_eq
                          : Icons.pause_rounded,
                      color: _isWebSpeechActive
                          ? Colors.blue
                          : AppColors.errorBright,
                      size: 16,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _isTranscribing
                        ? 'lexiChat.transcribingStatus'.tr()
                        : _isWebSpeechActive
                        ? 'lexiChat.webSpeechRecording'.tr()
                        : 'lexiChat.recordingStatus'.tr(
                            namedArgs: {
                              'seconds': _recordingDuration.inSeconds
                                  .toString(),
                            },
                          ),
                    style: TextStyle(
                      color: _isWebSpeechActive
                          ? Colors.blue
                          : _isTranscribing
                          ? Colors.orange
                          : AppColors.errorBright,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (!_isVoiceActive) ...[
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
                      hintText: 'lexiChat.inputHint'.tr(),
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
    final isActive = _isVoiceActive;
    final isWebSpeech = kIsWeb && WebSpeechRecognition.isSupported;

    // Active color depends on mode
    final activeColor = _isWebSpeechActive
        ? Colors.blue
        : _isTranscribing
        ? Colors.orange
        : Colors.red;

    Widget button = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isActive
            ? activeColor.withValues(alpha: 0.1)
            : (isDark ? AppColors.surfaceDarkChat : AppColors.backgroundLight),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? activeColor.withValues(alpha: 0.3)
              : (isDark ? AppColors.surfaceDarkChat : AppColors.chatBgLight),
          width: 1,
        ),
      ),
      child: _isTranscribing
          ? const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.orange,
                ),
              ),
            )
          : Icon(
              isActive
                  ? (_isWebSpeechActive
                        ? Icons.graphic_eq_rounded
                        : Icons.stop_rounded)
                  : Icons.mic_none_rounded,
              color: isActive
                  ? activeColor
                  : (isDark ? Colors.white54 : AppColors.textGrey),
              size: 20,
            ),
    );

    if (isWebSpeech) {
      // Web: tap to toggle on/off
      return GestureDetector(
        onTap: () {
          if (_isWebSpeechActive) {
            _stopWebSpeech();
          } else if (!_isTranscribing) {
            _startWebSpeech();
          }
        },
        child: button,
      );
    }

    // Mobile/Desktop: hold to record
    return GestureDetector(
      onLongPressStart: (_) {
        if (!isActive) {
          unawaited(_startMobileRecording());
        }
      },
      onLongPressEnd: (_) {
        if (_isRecording) {
          unawaited(_stopMobileRecordingAndTranscribe());
        }
      },
      onTap: () {
        if (_isRecording) {
          unawaited(_stopMobileRecordingAndTranscribe());
        } else if (!_isTranscribing) {
          _showSnack('lexiChat.holdToRecord'.tr());
        }
      },
      child: button,
    );
  }
}
