import 'package:lexilingo_app/core/utils/chat_input_limit.dart';
import 'package:lexilingo_app/core/widgets/tap_target.dart';
import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_config.dart';
import 'package:lexilingo_app/core/services/analytics_service.dart';
import 'package:lexilingo_app/core/services/locale_service.dart';
import 'package:lexilingo_app/core/voice/duplex_voice_client.dart';
import 'package:lexilingo_app/core/voice/duplex_voice_phase.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_chat_provider.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/duplex_voice_panel.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_dialogue_bubble.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_typing_indicator.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_corrections_sheet.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_memory_sheet.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_suggestion_bar.dart';
import 'package:lexilingo_app/features/voice/data/datasources/speech_recognition_service.dart';
import 'package:lexilingo_app/features/voice/domain/usecases/assess_pronunciation_usecase.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Lexi Chat Page — Minimalist design with clean conversation UI.
///
/// Features:
///  - Clean minimalist conversation interface (no avatar)
///  - Voice input (STT via Whisper) and voice output (TTS)
///  - Real-time grammar/word checking with inline corrections
///  - Free-form conversation focused on natural English practice
///  - Dark/light theme support
class LexiChatPage extends StatefulWidget {
  /// False while another bottom-nav tab is showing. The page stays mounted
  /// under the IndexedStack, so dispose() never runs on a tab switch — this
  /// flag is what tells it to stop listening and speaking.
  final bool isActive;

  /// Replaces the title block in the header — the Lexi tab puts its mode
  /// switch here so the page keeps a single header row.
  final Widget? titleSlot;

  const LexiChatPage({super.key, this.isActive = true, this.titleSlot});

  @override
  State<LexiChatPage> createState() => _LexiChatPageState();
}

class _LexiChatPageState extends State<LexiChatPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
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
  DuplexVoiceClient? _duplexVoice;
  StreamSubscription<Map<String, dynamic>>? _duplexVoiceSub;
  final ValueNotifier<String> _voiceCaption = ValueNotifier('');
  late final Listenable _voiceSignals;
  bool _voiceStarting = false;

  bool get _isVoiceActive =>
      _isRecording ||
      _isTranscribing ||
      _isWebSpeechActive ||
      _isDuplexVoiceActive;

  bool get _isDuplexVoiceActive => _duplexVoice?.phase.value.isLive ?? false;

  bool get _showVoicePanel {
    final phase = _duplexVoice?.phase.value ?? DuplexVoicePhase.idle;
    return _voiceStarting || phase.isLive || phase == DuplexVoicePhase.error;
  }

  late LexiChatProvider _chat;

  /// Bumped when the tab is hidden. A mic or transcription that was still
  /// starting when that happened sees a different value and backs out.
  int _voiceEpoch = 0;

  int _lastMessageCount = 0;
  List<String> get _quickReplies => [
    'lexiChat.quickReply1'.tr(),
    'lexiChat.quickReply2'.tr(),
    'lexiChat.quickReply3'.tr(),
  ];

  // Lexi only speaks English: the chips are labelled in the app language but
  // send these.
  static const _quickReplyPrompts = [
    'Hi Lexi, can we practice speaking?',
    'Can you correct my sentence?',
    'Give me a daily conversation challenge.',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (ApiConfig.enableDuplexVoice) _duplexVoice = sl<DuplexVoiceClient>();
    _voiceSignals = Listenable.merge([
      _voiceCaption,
      if (_duplexVoice != null) _duplexVoice!.phase,
    ]);
    // Restore latest session first; create new only when needed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<LexiChatProvider>();
      unawaited(provider.loadVoicePrefs());
      provider.resumeSpeaking();
      provider.syncTtsWithGlobalSound(
        context.read<SettingsProvider>().soundEnabled,
      );
      unawaited(
        provider.restoreLatestSession(_userId).catchError((Object error) {
          debugPrint('restoreLatestSession failed: $error');
        }),
      );
    });

    _scrollController.addListener(_handleTopReached);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs after initState and again whenever the locale or the learner's
    // reply-language choice changes, even while this page stays alive under
    // the bottom-nav IndexedStack.
    _chat = context.read<LexiChatProvider>();
    _chat.setNativeLanguage(_replyLanguage());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Spoken replies must stop too, not only a live duplex call.
      unawaited(_isDuplexVoiceActive ? _stopAllVoice() : _chat.stopSpeaking());
    } else if (state == AppLifecycleState.resumed && widget.isActive) {
      _chat.resumeSpeaking();
    }
  }

  @override
  void didUpdateWidget(covariant LexiChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) unawaited(_stopAllVoice());
    if (!oldWidget.isActive && widget.isActive) _chat.resumeSpeaking();
  }

  /// Ends every mic and speaker path without sending anything. Each step is
  /// guarded so one failing release (a recorder the user already stopped)
  /// cannot leave the other paths — or the UI flags — still on.
  Future<void> _stopAllVoice() async {
    _voiceEpoch++;
    unawaited(_chat.stopSpeaking());
    _recordingTimer?.cancel();
    final wasListening = _isWebSpeechActive;
    _webSpeech?.stopListening();
    _liveTranscript = '';
    if (wasListening) _controller.clear();
    for (final stop in <Future<void> Function()>[
      () async => _webSpeechSub?.cancel(),
      () async {
        if (_isRecording) await _recorder.cancel();
      },
      () async {
        await _duplexVoice?.stop();
        _chat.abortVoiceTurn();
      },
    ]) {
      try {
        await stop();
      } catch (error) {
        debugPrint('stop voice path failed: $error');
      }
    }
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isTranscribing = false;
      _isWebSpeechActive = false;
      _voiceStarting = false;
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

  /// Subscribes to the user, so flipping the setting re-runs
  /// didChangeDependencies.
  String _replyLanguage() {
    final appLanguage = LocaleService.normalizeLanguageCode(
      context.locale.languageCode,
    );
    UserEntity? user;
    try {
      user = Provider.of<AuthProvider>(context).user;
    } on ProviderNotFoundException {
      user = null;
    }
    return LocaleService.normalizeLanguageCode(
      user?.lexiReplyLanguageFor(appLanguage) ?? appLanguage,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceCaption.dispose();
    unawaited(_chat.stopSpeaking());
    _scrollController.removeListener(_handleTopReached);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _recorder.dispose();
    _recordingTimer?.cancel();
    _webSpeechSub?.cancel();
    _webSpeech?.dispose();
    _duplexVoiceSub?.cancel();
    if (_duplexVoice != null) unawaited(_duplexVoice!.dispose());
    super.dispose();
  }

  Future<void> _startDuplexVoice() async {
    if (_voiceStarting) return;
    final epoch = _voiceEpoch;
    setState(() => _voiceStarting = true);
    // The panel shrinks the list; keep the newest message in view.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    unawaited(HapticFeedback.mediumImpact());
    try {
      final provider = context.read<LexiChatProvider>();
      if (!provider.hasSession) await provider.startSession(_userId);
      if (epoch != _voiceEpoch) return;
      final sessionId = provider.session?.sessionId;
      if (sessionId == null) throw StateError('Chat session unavailable');
      final client = _duplexVoice ??= sl<DuplexVoiceClient>();
      _voiceCaption.value = '';
      await _duplexVoiceSub?.cancel();
      _duplexVoiceSub = client.events.stream.listen(_onDuplexEvent);
      await client.start(
        sessionId: sessionId,
        learnerLevel: provider.learnerLevel,
        nativeLanguage: provider.nativeLanguage,
        ttsSpeed: provider.ttsEnabled ? provider.ttsSpeed : 1.0,
      );
      if (epoch != _voiceEpoch) await client.stop();
    } catch (error) {
      debugPrint('duplex voice start failed: $error');
      if (_duplexVoice?.phase.value == DuplexVoicePhase.unavailable) {
        _showSnack('lexiChat.voice.errorUnavailable'.tr());
      }
    } finally {
      if (mounted) setState(() => _voiceStarting = false);
    }
  }

  void _onDuplexEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final type = event['type'];
    if (type == 'stt.partial') {
      _voiceCaption.value = event['text']?.toString() ?? '';
    } else if (type == 'stt.final') {
      _voiceCaption.value = '';
    } else if (type == 'voice.error' && event['code'] == 'SERVER_BUSY') {
      _showSnack('lexiChat.voice.busyBanner'.tr());
    }
    _chat.handleDuplexVoiceEvent(event);
  }

  Future<void> _endDuplexVoice() async {
    _voiceEpoch++;
    await _duplexVoice?.stop();
    _chat.abortVoiceTurn();
    _voiceCaption.value = '';
    if (mounted) setState(() => _voiceStarting = false);
  }

  void _onVoiceOrbTap(DuplexVoicePhase phase) {
    if (phase.canInterrupt) {
      unawaited(HapticFeedback.selectionClick());
      unawaited(_duplexVoice?.interrupt());
    } else if (phase == DuplexVoicePhase.error) {
      unawaited(_startDuplexVoice());
    }
  }

  Future<void> _editMisheard(LexiMessage message) async {
    await _endDuplexVoice();
    if (!mounted) return;
    _controller.text = message.content;
    _controller.selection = TextSelection.collapsed(
      offset: message.content.length,
    );
    _focusNode.requestFocus();
    _showSnack('lexiChat.voice.misheardEditHint'.tr());
  }

  String _voiceErrorText() {
    return switch (_duplexVoice?.lastErrorCode) {
      'MIC_PERMISSION' => 'lexiChat.voice.errorPermission'.tr(),
      'QUOTA_EXCEEDED' => 'lexiChat.voice.errorQuota'.tr(),
      'UNAVAILABLE' => 'lexiChat.voice.errorUnavailable'.tr(),
      'CONNECTION_CLOSED' ||
      'CONNECT_FAILED' ||
      'TICKET_FAILED' => 'lexiChat.voice.errorConnection'.tr(),
      _ => 'lexiChat.voice.retry'.tr(),
    };
  }

  Widget _buildVoicePanelBar() {
    final client = _duplexVoice;
    final phase = client?.phase.value ?? DuplexVoicePhase.connecting;
    final shown = phase == DuplexVoicePhase.idle
        ? DuplexVoicePhase.connecting
        : phase;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: ValueListenableBuilder<double>(
        valueListenable: client?.inputLevel ?? ValueNotifier(0),
        builder: (context, level, _) => DuplexVoicePanel(
          phase: shown,
          level: level,
          caption: shown == DuplexVoicePhase.error
              ? _voiceErrorText()
              : _voiceCaption.value,
          onEnd: () => unawaited(_endDuplexVoice()),
          onOrbTap: () => _onVoiceOrbTap(shown),
          onReplay: client != null && client.canReplay
              ? () => unawaited(client.replayLast())
              : null,
        ),
      ),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted || !_scrollController.hasClients) return;
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
    if (context.read<LexiChatProvider>().isSending) return;
    _controller.clear();

    final provider = context.read<LexiChatProvider>();
    final pending = provider.sendMessageStreaming(text, userId: _userId);
    _scrollToBottom();
    await pending;
    _scrollToBottom();
  }

  Future<void> _sendQuickReply(String text) async {
    if (context.read<LexiChatProvider>().isSending) return;
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
        if (!mounted) return;
        setState(() => _isWebSpeechActive = false);
        _showSnack(
          'lexiChat.sttFailed'.tr(namedArgs: {'error': error.toString()}),
        );
      },
      onDone: () {
        if (mounted && _isWebSpeechActive) {
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
    final epoch = _voiceEpoch;
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!mounted || epoch != _voiceEpoch) return;
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
      if (!mounted || epoch != _voiceEpoch) {
        await _recorder.cancel();
        return;
      }

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
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
    final epoch = _voiceEpoch;

    try {
      final path = await _recorder.stop();
      if (!mounted || epoch != _voiceEpoch) return;
      setState(() {
        _isRecording = false;
        _isTranscribing = true;
      });

      if (path == null) {
        setState(() => _isTranscribing = false);
        return;
      }

      final file = File(path);
      final exists = await file.exists();
      if (!mounted) return;
      if (!exists) {
        _showSnack('lexiChat.audioReadError'.tr());
        setState(() => _isTranscribing = false);
        return;
      }
      final bytes = await file.readAsBytes();

      if (!mounted) return;
      final chatProvider = context.read<LexiChatProvider>();
      final transcript = await chatProvider.transcribeAudio(bytes);
      if (!mounted || epoch != _voiceEpoch) return;
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
      unawaited(_assessAndAttachPronunciation(bytes, transcript));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _isTranscribing = false;
      });
      _showSnack('lexiChat.sttFailed'.tr(namedArgs: {'error': e.toString()}));
    }
  }

  /// Scores pronunciation on the audio the learner just sent, using the STT
  /// transcript itself as the reference text — this is a live speech-quality
  /// signal (did they say the words clearly), not a "was this correct"
  /// check, so it works for free-form conversation instead of only
  /// read-aloud drills. Fire-and-forget: never blocks or fails the send.
  Future<void> _assessAndAttachPronunciation(
    Uint8List bytes,
    String transcript,
  ) async {
    if (transcript.trim().isEmpty) return;

    final result = await sl<AssessPronunciationUseCase>()(
      AssessPronunciationParams(
        audioData: bytes,
        filename: 'lexi_voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        targetText: transcript,
        language: 'en',
      ),
    );
    if (!mounted) return;

    result.fold(
      (_) {}, // Assessment is a bonus signal — silently skip on failure.
      (score) {
        final chatProvider = context.read<LexiChatProvider>();
        LexiMessage? lastUserMessage;
        for (final message in chatProvider.messages.reversed) {
          if (message.isUser) {
            lastUserMessage = message;
            break;
          }
        }
        if (lastUserMessage == null) return;
        chatProvider.attachPronunciationScore(lastUserMessage.id, score);
        trackProductEvent(
          'pronunciation_score_shown',
          source: 'lexi_chat',
          properties: {
            'message_id': lastUserMessage.id,
            'score': score.overallScore,
          },
        );
      },
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
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
              Expanded(
                child: ContentWidth(
                  maxWidth: ContentWidth.reading,
                  child: _buildMessageList(isDark),
                ),
              ),
              ListenableBuilder(
                listenable: _voiceSignals,
                builder: (_, __) => ContentWidth(
                  maxWidth: ContentWidth.reading,
                  child: _buildInputBar(isDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Minimalist Header ────────────────────────────────────────────────────
  Widget _buildHeader(bool isDark) {
    final iconColor = isDark
        ? AppColors.textOnDarkSecondary
        : Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceDark.withValues(alpha: 0.95)
            : Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.surfaceDarkChat : AppColors.chatBgLight,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // A tab in MainScreen, but also pushed as `/lexi` — only then can it pop.
          if (ModalRoute.of(context)?.canPop ?? false)
            AppBackButton(
              color: isDark
                  ? AppColors.textOnDarkSecondary
                  : Theme.of(context).colorScheme.onSurface,
              onPressed: () => Navigator.of(context).pop(),
            ),
          IconButton(
            icon: Icon(Icons.menu_rounded, color: iconColor, size: 22),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            tooltip: 'lexiChat.tooltipSessionHistory'.tr(),
          ),
          const SizedBox(width: AppSpacing.xs),
          // Title
          Expanded(
            child:
                widget.titleSlot ??
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'lexiChat.title'.tr(),
                      style: Theme.of(context).textTheme.heading?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.textOnDarkPrimary
                            : Theme.of(context).colorScheme.onSurface,
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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: isActive
                                    ? AppColorRoles.primary(isDark)
                                    : (isDark
                                          ? AppColors.textOnDarkMuted
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant),
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
              // Voice speed moved to the session drawer: with the mode switch
              // in this row, a fourth control pushed it to icons-only on a
              // 375px phone.
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      provider.ttsEnabled
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      color: provider.ttsEnabled
                          ? AppColorRoles.primary(isDark)
                          : (isDark
                                ? AppColors.textOnDarkMuted
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant),
                      size: 22,
                    ),
                    onPressed: provider.toggleTts,
                    tooltip: 'lexiChat.tooltipToggleVoice'.tr(),
                  ),
                  if (ApiConfig.enableDuplexVoice &&
                      !DuplexVoiceClient.serverUnavailable)
                    IconButton(
                      icon: Icon(
                        provider.captionsVisible
                            ? Icons.closed_caption_rounded
                            : Icons.closed_caption_disabled_rounded,
                        color: provider.captionsVisible
                            ? AppColorRoles.primary(isDark)
                            : (isDark
                                  ? AppColors.textOnDarkMuted
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant),
                        size: 22,
                      ),
                      onPressed: () => provider.setCaptionsVisible(
                        !provider.captionsVisible,
                      ),
                      tooltip: provider.captionsVisible
                          ? 'lexiChat.voice.captionsOff'.tr()
                          : 'lexiChat.voice.captionsOn'.tr(),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.add_comment_outlined, color: iconColor, size: 22),
            onPressed: () =>
                context.read<LexiChatProvider>().createNewSession(_userId),
            tooltip: 'lexiChat.tooltipNewChat'.tr(),
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
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'lexiChat.sessionsDrawerTitle'.tr(),
                          style: Theme.of(context).textTheme.sectionTitle
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.textOnDarkPrimary
                                    : Theme.of(context).colorScheme.onSurface,
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
                                  ? AppColors.textOnDarkMuted
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
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
                                                    style: TextButton.styleFrom(
                                                      minimumSize: const Size(
                                                        kMinTapTarget,
                                                        kMinTapTarget,
                                                      ),
                                                    ),
                                                    onPressed: () =>
                                                        Navigator.pop(context),
                                                    child: Text(
                                                      'lexiChat.cancelButton'
                                                          .tr(),
                                                    ),
                                                  ),
                                                  FilledButton(
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
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.speed_rounded),
                  title: Text('lexiChat.voiceSpeed'.tr()),
                  trailing: Text(
                    provider.ttsSpeedLabel,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColorRoles.primary(isDark),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  enabled: provider.ttsEnabled,
                  onTap: provider.cycleTtsSpeed,
                ),
                ListTile(
                  leading: const Icon(Icons.psychology_alt_rounded),
                  title: Text('lexiChat.memory.entry'.tr()),
                  onTap: () {
                    Navigator.pop(context);
                    LexiMemorySheet.show(this.context);
                  },
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
                const SizedBox(height: AppSpacing.md),
                Text(
                  'lexiChat.startingConversation'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.textOnDarkMuted
                        : Theme.of(context).colorScheme.onSurfaceVariant,
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          itemCount: messages.length + (isResponding ? 1 : 0),
          itemBuilder: (context, index) {
            // Typing indicator at the end
            if (index == messages.length && isResponding) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: LexiTypingIndicator(isThinking: provider.isLexiThinking),
              );
            }

            final message = messages[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: LexiDialogueBubble(
                message: message,
                onPlayAudio: message.hasAudio
                    ? () => provider.replayAudio(message)
                    : null,
                onShowCorrections:
                    (message.hasCorrections ||
                        message.nativeHint != null ||
                        message.linkedConcepts.isNotEmpty)
                    ? () => LexiCorrectionsSheet.show(context, message)
                    : null,
                onPronunciationScoreTap: message.pronunciationScore == null
                    ? null
                    : () => trackProductEvent(
                        'pronunciation_score_tapped',
                        source: 'lexi_chat',
                        properties: {
                          'message_id': message.id,
                          'score': message.pronunciationScore!.overallScore,
                        },
                      ),
                onSuggestedPracticeTap: (practice) =>
                    _sendQuickReply(practice.prompt),
                captionHidden: provider.isCaptionHidden(message),
                onRevealCaption: () => provider.revealCaption(message.id),
                onMisheardTap: message.heardUncertain
                    ? () => unawaited(_editMisheard(message))
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
    if (_showVoicePanel) return _buildVoicePanelBar();
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceDark.withValues(alpha: 0.95)
            : Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
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
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color:
                    (_isWebSpeechActive
                            ? Theme.of(context).colorScheme.primary
                            : _isTranscribing
                            ? AppColors.orange
                            : Theme.of(context).colorScheme.error)
                        .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color:
                      (_isWebSpeechActive
                              ? Theme.of(context).colorScheme.primary
                              : _isTranscribing
                              ? AppColors.orange
                              : Theme.of(context).colorScheme.error)
                          .withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  if (_isTranscribing)
                    const SizedBox(
                      width: AppSpacing.lg,
                      height: AppSpacing.lg,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.orange,
                      ),
                    )
                  else
                    Icon(
                      _isWebSpeechActive
                          ? Icons.graphic_eq
                          : Icons.pause_rounded,
                      color: _isWebSpeechActive
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                      size: 16,
                    ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
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
                            ? Theme.of(context).colorScheme.primary
                            : _isTranscribing
                            ? AppColors.orange
                            : Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (!_isVoiceActive) ...[
            Consumer<LexiChatProvider>(
              builder: (context, chat, _) {
                final last = chat.messages.isEmpty ? null : chat.messages.last;
                if (last != null && last.isLexi && !chat.isLexiResponding) {
                  return LexiSuggestionBar(
                    message: last,
                    nativeLanguage: chat.nativeLanguage,
                    isDark: isDark,
                    onSend: _sendQuickReply,
                  );
                }
                return SizedBox(
                  height: TapTargetBox.applies(context) ? 48 : 34,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _quickReplies.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final text = _quickReplies[index];
                      return ActionChip(
                        label: Text(text, overflow: TextOverflow.ellipsis),
                        onPressed: () =>
                            _sendQuickReply(_quickReplyPrompts[index]),
                        labelStyle: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(
                              color: isDark
                                  ? AppColors.textOnDarkSecondary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
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
                );
              },
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              // Voice recording button
              _buildVoiceButton(isDark),
              const SizedBox(width: AppSpacing.md),
              // Text input
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.surfaceDarkInk
                        : AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
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
                    inputFormatters: chatInputFormatters,
                    buildCounter: buildChatInputCounter,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? AppColors.textOnDarkPrimary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: 'lexiChat.inputHint'.tr(),
                      hintStyle: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(
                            color: isDark
                                ? AppColors.textOnDarkMuted
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Send button
              Consumer<LexiChatProvider>(
                builder: (_, provider, __) {
                  return Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColorRoles.primary(isDark),
                      borderRadius: BorderRadius.circular(AppRadius.md),
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
                            : Theme.of(context).colorScheme.surface,
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
        ? Theme.of(context).colorScheme.primary
        : _isTranscribing
        ? AppColors.orange
        : Theme.of(context).colorScheme.error;

    Widget button = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isActive
            ? activeColor.withValues(alpha: 0.1)
            : (isDark ? AppColors.surfaceDarkChat : AppColors.backgroundLight),
        borderRadius: BorderRadius.circular(AppRadius.md),
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
                  color: AppColors.orange,
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
                  : (isDark
                        ? AppColors.textOnDarkMuted
                        : Theme.of(context).colorScheme.onSurfaceVariant),
              size: 20,
            ),
    );

    if (ApiConfig.enableDuplexVoice && !DuplexVoiceClient.serverUnavailable) {
      return Semantics(
        button: true,
        label: 'lexiChat.voice.startVoice'.tr(),
        child: GestureDetector(
          onTap: () => unawaited(_startDuplexVoice()),
          child: button,
        ),
      );
    }

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
