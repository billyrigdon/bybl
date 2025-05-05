import 'package:TheWord/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<String> _messages = [];
  final ChatService _chatService = ChatService();
  String _streamingReply = '';
  bool _isStreaming = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() async {
    final originalMessage = _controller.text.trim();
    if (originalMessage.isEmpty || _isStreaming) return;

    _controller.clear();

    setState(() {
      _messages.add('**You**: $originalMessage');
      _streamingReply = '';
      _isStreaming = true;
    });

    bool success = await _tryStreamResponse(originalMessage);

    if (!success) {
      setState(() {
        _isStreaming = false;
      });

      _controller.text = originalMessage;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send message. Please try again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<bool> _tryStreamResponse(String message) async {
    try {
      final stream = _chatService.streamResponse(message);

      await for (final chunk in stream) {
        setState(() {
          _streamingReply += chunk;
        });
        _scrollToBottom();
      }

      setState(() {
        _messages.add('**Archie**: $_streamingReply');
        _streamingReply = '';
        _isStreaming = false;
      });

      return true;
    } catch (e) {
      // Retry once
      try {
        final retryStream = _chatService.streamResponse(message);

        await for (final chunk in retryStream) {
          setState(() {
            _streamingReply += chunk;
          });
          _scrollToBottom();
        }

        setState(() {
          _messages.add('**Archie**: $_streamingReply');
          _streamingReply = '';
          _isStreaming = false;
        });

        return true;
      } catch (e2) {
        return false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    final allMessages = List<String>.from(_messages);
    if (_streamingReply.isNotEmpty) {
      allMessages.add('**Archie**: $_streamingReply');
    }

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: allMessages.isEmpty
                ? Center(
                    child: Image.asset(
                      'assets/icon/archie.png',
                      width: 200,
                      height: 200,
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: allMessages.length,
                    itemBuilder: (context, index) {
                      final message = allMessages[index];
                      final isUser = message.startsWith('**You**:');
                      final content =
                          message.replaceFirst(RegExp(r'^\*\*.*?\*\*:\s*'), '');

                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 300),
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 14),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: isUser
                                ? settings.currentColor
                                : Colors.grey[900],
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isUser ? 16 : 0),
                              bottomRight: Radius.circular(isUser ? 0 : 16),
                            ),
                          ),
                          child: MarkdownBody(
                            data: content,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(
                                color:
                                    isUser ? settings.fontColor : Colors.white,
                                fontSize: 16,
                              ),
                              strong: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:
                                    isUser ? settings.fontColor : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_isStreaming && _streamingReply.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: ThinkingIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150.0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      reverse: true,
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'Ask something...',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.multiline,
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({Key? key}) : super(key: key);

  @override
  _ThinkingIndicatorState createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _dot1, _dot2, _dot3;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(duration: const Duration(seconds: 1), vsync: this)
          ..repeat();

    _dot1 = Tween(begin: 0.0, end: 8.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.3)),
    );
    _dot2 = Tween(begin: 0.0, end: 8.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.3, 0.6)),
    );
    _dot3 = Tween(begin: 0.0, end: 8.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.6, 1.0)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _dot(Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: Container(
            width: 8,
            height: 8 + animation.value,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [_dot(_dot1), _dot(_dot2), _dot(_dot3)],
    );
  }
}
