import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/chat_provider.dart';
import 'package:lexilingo_app/features/chat/domain/entities/chat_message.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final messages = chatProvider.messages;

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
        leading: GestureDetector(
          onTap: () {}, // Back
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_ios_new, color: AppColors.textDark, size: 18),
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
                   _buildAiMessage(context, "Hello! Let's practice. What is the first thing you usually do when you wake up in the morning?"),

                ...messages.map((msg) {
                  return msg.role == MessageRole.user
                    ? _buildUserMessage(context, msg.content)
                    : _buildAiMessage(context, msg.content);
                }),

                if (chatProvider.isLoading)
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
               border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.1)))
            ),
            child: Column(
              children: [
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
                Row(
                  children: [
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
                                decoration: const InputDecoration(
                                  hintText: 'Type your message...',
                                  border: InputBorder.none,
                                ),
                                onSubmitted: (value) {
                                  if (value.isNotEmpty) {
                                    chatProvider.sendMessage(value);
                                    _controller.clear();
                                  }
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.mic, color: AppColors.textGrey),
                              onPressed: () {},
                            )
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                         if (_controller.text.isNotEmpty) {
                           chatProvider.sendMessage(_controller.text);
                           _controller.clear();
                         }
                      },
                      child: Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
                        ),
                        child: const Icon(Icons.send, color: Colors.white, size: 20),
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

  Widget _buildQuickReply(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.withOpacity(0.3))
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textGrey)),
    );
  }

  Widget _buildAiMessage(BuildContext context, String text) {
     return Padding(
       padding: const EdgeInsets.only(bottom: 16.0),
       child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 32, height: 32,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
               image: DecorationImage(
                  image: NetworkImage("https://lh3.googleusercontent.com/aida-public/AB6AXuATpszxo8IDSZGFMcAe7wu3OsLcfmZ-s1g8zqZEZrd1NWWKigT9eaRCBLHYPYrzm_QHWJnz7gDyqvGT8FPffL3SHy4BPngd150uW71CjgCXpokjLtm7-JOo639zGjehA2gx3x0GrWgVn3fQhVJQnFfn53UEibhEVOb1k3gycZzHNg6fSz23m5uyeyR0n2gaM8_-RSKtJ5LPpf8z6c_nvkCPbAeOU-UKQ5RtZOh_4iBwspBMQqLZY3yHpWZ5hYD5Vj3tWnYFB68cxn1E"),
                  fit: BoxFit.cover
              ),
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints:   BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 4),
                  child: Text('AI Tutor', style: TextStyle(fontSize: 11, color: AppColors.textGrey, fontWeight: FontWeight.w500)),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[800] : const Color(0xFFF0F2F4),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                      bottomLeft: Radius.circular(0),
                    ),
                  ),
                  child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
                ),
              ],
            ),
          )
        ],
           ),
     );
  }

  Widget _buildUserMessage(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
           ConstrainedBox(
            constraints:   BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 4, bottom: 4),
                  child: Text('You', style: TextStyle(fontSize: 11, color: AppColors.textGrey, fontWeight: FontWeight.w500)),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(0),
                      bottomLeft: Radius.circular(16),
                    ),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))]
                  ),
                  child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 32, height: 32,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
               image: DecorationImage(
                  image: NetworkImage("https://lh3.googleusercontent.com/aida-public/AB6AXuAqMp7eP7f5P4Ys18yc-E2dnnaw5O7k3GdkVfBbgduka0-lSnnuafKYdSIhNa0ucEcwR8FYlqi4tGeY6zlKkeQfbHxK81S6DL8GCqzbfDuQuzCXfNDtFo2GQSlFA6shionhvtBJWYsfzD5pSUIGzGrkD-_RAWA4z9gv9LMJagNna4AXQLzAgzuR1rjoPZsJ9bLTf8lnpt2zqy0ci4DNsE-yENDdWJHqLksWIGdA1M8dWXyxE1WvgvCcG6q3vxMZsBhdKeNFw00UmXOK"),
                  fit: BoxFit.cover
              ),
            ),
          ),
        ],
      ),
    );
  }
}

