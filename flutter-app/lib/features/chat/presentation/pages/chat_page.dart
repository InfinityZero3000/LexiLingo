import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/chat_provider.dart';
import 'package:lexilingo_app/features/chat/presentation/widgets/message_bubble.dart';
import 'package:lexilingo_app/features/chat/presentation/widgets/session_list_drawer.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/voice_provider.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  // Voice recording state
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _ttsPlayer = AudioPlayer();
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  String? _recordingPath;
  bool _isRecording = false;
  bool _isProcessingVoice = false;
  bool _hasRecorderPermission = false;
  bool _isTtsEnabled = true; // Auto-play TTS for AI responses
  int _lastMessageCount = 0; // Track message count for TTS trigger

  @override
  void initState() {
    super.initState();
    
    // Add scroll listener for lazy loading
    _scrollController.addListener(_onScroll);
    
    // Note: Don't check microphone permission here to avoid auto-triggering
    // Permission will be checked when user tries to record
    
    // Initialize chat session if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final userId = _currentUserId(context);
      if (!chatProvider.hasCurrentSession) {
        chatProvider.createNewSession(userId);
      }
    });
  }
  
  Future<void> _checkRecorderPermission() async {
    final hasPermission = await _recorder.hasPermission();
    if (mounted) {
      setState(() => _hasRecorderPermission = hasPermission);
    }
  }
  
  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _controller.dispose();
    _recorder.dispose();
    _ttsPlayer.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }
  
  void _onScroll() {
    // Load more messages when scrolling to the top
    if (_scrollController.position.pixels <= 100) {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      if (chatProvider.hasMoreMessages && !chatProvider.isLoadingMoreMessages) {
        chatProvider.loadMoreMessages();
      }
    }
  }

  String _currentUserId(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return auth.user?.id ?? 'demo_user_001';
  }

  // Voice Recording Methods
  Future<void> _startRecording() async {
    if (!_hasRecorderPermission) {
      await _checkRecorderPermission();
      if (!_hasRecorderPermission) {
        _showSnackBar('Microphone permission denied');
        return;
      }
    }

    try {
      final directory = await getTemporaryDirectory();
      _recordingPath = '${directory.path}/chat_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: _recordingPath!,
      );
      
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });
      
      // Update recording duration every 100ms
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (mounted) {
          setState(() {
            _recordingDuration += const Duration(milliseconds: 100);
          });
        }
      });
    } catch (e) {
      _showSnackBar('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecordingAndTranscribe() async {
    _recordingTimer?.cancel();
    
    if (!_isRecording || _recordingPath == null) return;
    
    try {
      final path = await _recorder.stop();
      
      setState(() {
        _isRecording = false;
        _isProcessingVoice = true;
      });
      
      if (path != null) {
        // Read audio file
        final file = File(path);
        final audioData = await file.readAsBytes();
        
        // Transcribe using VoiceProvider
        final voiceProvider = context.read<VoiceProvider>();
        final transcription = await voiceProvider.stopRecordingAndTranscribe(
          audioData: audioData,
          filename: 'chat_voice.wav',
          language: 'en',
        );
        
        if (transcription != null && transcription.text.isNotEmpty) {
          // Send transcribed text to chat
          final chatProvider = context.read<ChatProvider>();
          chatProvider.sendMessage(
            transcription.text,
            userId: _currentUserId(context),
          );
        } else {
          _showSnackBar('Could not transcribe audio. Please try again.');
        }
        
        // Clean up temp file
        try {
          await file.delete();
        } catch (_) {}
      }
    } catch (e) {
      _showSnackBar('Failed to process recording: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingVoice = false;
          _recordingDuration = Duration.zero;
        });
      }
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    
    try {
      await _recorder.stop();
      
      if (_recordingPath != null) {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {}
    
    setState(() {
      _isRecording = false;
      _recordingDuration = Duration.zero;
    });
  }

  Future<void> _playTtsResponse(String text) async {
    if (!_isTtsEnabled || text.isEmpty) return;
    
    try {
      final voiceProvider = context.read<VoiceProvider>();
      final result = await voiceProvider.synthesizeAndPlay(text: text);
      
      if (result != null && result.audioData.isNotEmpty) {
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/chat_tts_${DateTime.now().millisecondsSinceEpoch}.wav');
        await file.writeAsBytes(result.audioData);
        
        await _ttsPlayer.setFilePath(file.path);
        await _ttsPlayer.play();
        
        // Clean up after playback
        _ttsPlayer.playerStateStream.firstWhere(
          (state) => state.processingState == ProcessingState.completed,
        ).then((_) {
          try {
            file.deleteSync();
          } catch (_) {}
        });
      }
    } catch (e) {
      debugPrint('TTS playback error: $e');
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final messages = chatProvider.messages;
    final sessions = chatProvider.sessions;

    // Check for new AI message and play TTS
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isTtsEnabled && messages.length > _lastMessageCount) {
        // Find the newest AI message
        final newMessages = messages.skip(_lastMessageCount);
        for (final msg in newMessages) {
          if (msg.isAIMessage && msg.content.isNotEmpty && msg.isSent) {
            _playTtsResponse(msg.content);
            break; // Only play the first new AI message
          }
        }
        _lastMessageCount = messages.length;
      } else if (messages.length != _lastMessageCount) {
        _lastMessageCount = messages.length;
      }
    });

    // Auto scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    return Scaffold(
      key: _scaffoldKey,
      drawer: SessionListDrawer(
        sessions: sessions,
        currentSessionId: chatProvider.currentSession?.id,
        hasMoreSessions: chatProvider.hasMoreSessions,
        isLoadingMoreSessions: chatProvider.isLoadingMoreSessions,
        onLoadMoreSessions: () {
          chatProvider.loadMoreSessions(_currentUserId(context));
        },
        onSessionTap: (sessionId) {
          final session = sessions.firstWhere((s) => s.id == sessionId);
          chatProvider.selectSession(session);
          Navigator.pop(context); // Close drawer
        },
        onNewSession: () {
          chatProvider.createNewSession(_currentUserId(context));
          Navigator.pop(context); // Close drawer
        },
        onDeleteSession: (session) {
          // TODO: Implement delete session in provider and repository
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Delete session feature coming soon')),
          );
        },
        onRenameSession: (session, newTitle) {
          // TODO: Implement rename session in provider and repository
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Rename to "$newTitle" coming soon')),
          );
        },
      ),
      appBar: AppBar(
        title: Column(
          children: [
            const Text('AI Tutor', style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold, fontSize: 18)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('Online | Learning Guide', style: TextStyle(color: AppColors.textDark.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.normal)),
              ],
            )
          ],
        ),
        centerTitle: true,
        backgroundColor: AppColors.accentYellow,
        leading: Builder(
          builder: (context) => GestureDetector(
            onTap: () {
              Scaffold.of(context).openDrawer();
            },
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: const Icon(Icons.menu, color: AppColors.textDark, size: 18),
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.all(8),
            width: 40,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(Icons.info_outline, color: AppColors.textDark),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                // Loading indicator at top when loading more messages
                if (chatProvider.isLoadingMoreMessages)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                
                // Show message if no more messages to load
                if (!chatProvider.hasMoreMessages && messages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Center(
                      child: Text(
                        'Đã tải hết tin nhắn',
                        style: TextStyle(
                          color: AppColors.textGrey.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                
                // Header Image & Topic
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 96, height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.accentYellow, width: 4),
                          image: const DecorationImage(
                              image: NetworkImage("https://lh3.googleusercontent.com/aida-public/AB6AXuB7j08S11fEpUVbsYxQF7dLRe1TbFOIMCXBxdZepnZ4a6XfLsK4MpdIAr--vTv_b_sQRcHo1i7FjivInGLaxT_p4W873AbslxtutlGVoBNLttdGthAJ9bvVXsI_vKboU0hvRr9va6EIk5Y6zRh5iT1-Gumps6V_Y1mYqctJZC6Qj9y9p1bLcn8P2vP-coBy9dH60woBanrMV5gfVLkwqWMIuVEjrGv0w1dZ8rZUWmCXIIxrc3JIyi--dYM2dlX0IePD8wMqbfregMAJ"),
                              fit: BoxFit.cover
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      RichText(
                        text: TextSpan(
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textGrey),
                          children: const [
                            TextSpan(text: "Today's Topic: "),
                            TextSpan(text: "Daily Habits", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Existing messages
                if (messages.isEmpty)
                   _buildWelcomeMessage(context),

                ...messages.map((msg) {
                  return MessageBubble(
                    message: msg,
                    showAvatar: true,
                    showTimestamp: true,
                    onRetry: msg.hasError
                        ? () {
                            // Retry sending the message
                            chatProvider.sendMessage(
                              msg.content,
                              userId: _currentUserId(context),
                            );
                          }
                        : null,
                  );
                }),

                if (chatProvider.isSending)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          
          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
               color: Theme.of(context).scaffoldBackgroundColor,
               border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.1)))
            ),
            child: Column(
              children: [
                // Voice Recording Indicator
                if (_isRecording || _isProcessingVoice) ...[
                  _buildVoiceRecordingUI(),
                  const SizedBox(height: 16),
                ] else ...[
                  // Quick Replies
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildQuickReply("I prefer coffee."),
                        const SizedBox(width: 8),
                        _buildQuickReply("I usually drink tea."),
                        const SizedBox(width: 8),
                        _buildQuickReply("Can you explain why?"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    // TTS Toggle Button
                    IconButton(
                      icon: Icon(
                        _isTtsEnabled ? Icons.volume_up : Icons.volume_off,
                        color: _isTtsEnabled ? AppColors.primary : AppColors.textGrey,
                      ),
                      onPressed: () => setState(() => _isTtsEnabled = !_isTtsEnabled),
                      tooltip: _isTtsEnabled ? 'Disable auto TTS' : 'Enable auto TTS',
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : const Color(0xFFF0F2F4),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                enabled: !_isRecording && !_isProcessingVoice,
                                decoration: InputDecoration(
                                  hintText: _isRecording 
                                      ? 'Recording...' 
                                      : _isProcessingVoice 
                                          ? 'Processing...' 
                                          : 'Type your message...',
                                  border: InputBorder.none,
                                ),
                                onSubmitted: (value) {
                                  if (value.isNotEmpty && !_isRecording && !_isProcessingVoice) {
                                    chatProvider.sendMessage(
                                      value,
                                      userId: _currentUserId(context),
                                    );
                                    _controller.clear();
                                  }
                                },
                              ),
                            ),
                            // Mic button with long press to record
                            GestureDetector(
                              onLongPressStart: (_) => _startRecording(),
                              onLongPressEnd: (_) => _stopRecordingAndTranscribe(),
                              child: IconButton(
                                icon: Icon(
                                  _isRecording ? Icons.mic : Icons.mic_none,
                                  color: _isRecording ? Colors.red : AppColors.textGrey,
                                ),
                                onPressed: () {
                                  _showSnackBar('Hold to record');
                                },
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        if (_isRecording) {
                          _stopRecordingAndTranscribe();
                        } else if (_controller.text.isNotEmpty && !_isProcessingVoice) {
                          chatProvider.sendMessage(
                            _controller.text,
                            userId: _currentUserId(context),
                          );
                          _controller.clear();
                        }
                      },
                      child: Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: _isRecording ? Colors.red : AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: (_isRecording ? Colors.red : AppColors.primary).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))]
                        ),
                        child: Icon(
                          _isRecording ? Icons.stop : Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    )
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildWelcomeMessage(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              image: DecorationImage(
                image: NetworkImage(
                    "https://lh3.googleusercontent.com/aida-public/AB6AXuATpszxo8IDSZGFMcAe7wu3OsLcfmZ-s1g8zqZEZrd1NWWKigT9eaRCBLHYPYrzm_QHWJnz7gDyqvGT8FPffL3SHy4BPngd150uW71CjgCXpokjLtm7-JOo639zGjehA2gx3x0GrWgVn3fQhVJQnFfn53UEibhEVOb1k3gycZzHNg6fSz23m5uyeyR0n2gaM8_-RSKtJ5LPpf8z6c_nvkCPbAeOU-UKQ5RtZOh_4iBwspBMQqLZY3yHpWZ5hYD5Vj3tWnYFB68cxn1E"),
                fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 4),
                  child: Text('AI Tutor',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w500)),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[800]
                        : const Color(0xFFF0F2F4),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                      bottomLeft: Radius.circular(0),
                    ),
                  ),
                  child: Text(
                    "Hello! 👋 Let's practice English together. What is the first thing you usually do when you wake up in the morning?",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildVoiceRecordingUI() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _isRecording 
            ? Colors.red.withValues(alpha: 0.1) 
            : Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Recording indicator
          if (_isRecording) ...[
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _formatDuration(_recordingDuration),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _cancelRecording,
              icon: const Icon(Icons.close, color: Colors.red),
              label: const Text('Cancel', style: TextStyle(color: Colors.red)),
            ),
          ] else if (_isProcessingVoice) ...[
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            const Text(
              'Processing your voice...',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickReply(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3))
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textGrey)),
    );
  }
}
