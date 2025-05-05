import 'dart:convert';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatService {
  final String _apiBase = 'https://api.bybl.dev/api';

  final List<Map<String, String>> _conversationHistory = [];
  final List<Map<String, String>> _summaryHistory = [];

  Stream<String> streamResponse(String userMessage) async* {
    _conversationHistory.add({'role': 'user', 'content': userMessage});
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    final request = http.Request(
      'POST',
      Uri.parse('$_apiBase/chat/stream'),
    )
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      })
      ..body =
          jsonEncode({'messages': _buildMessagePayload(_conversationHistory)});

    http.Client client = http.Client();
    http.StreamedResponse response;

    try {
      response = await client.send(request);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      // network error → fall back to non-stream endpoint
      yield* _fallbackResponse(userMessage);
      return;
    }

    if (response.statusCode != 200) {
      yield* _fallbackResponse(userMessage);
      return;
    }

    String buffer = '';
    final lines =
        response.stream.transform(utf8.decoder).transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data: ')) continue;
      final chunk = line.substring(6);
      if (chunk == '[DONE]') break;

      buffer += chunk;
      yield chunk; // ← live update to UI
    }

    _conversationHistory.add({'role': 'assistant', 'content': buffer});
  }

  Stream<String> _fallbackResponse(String userMessage) async* {
    final reply = await getResponse(userMessage); // already cleans prefix
    yield reply;
  }

  Future<String> getResponse(String userMessage) async {
    _summaryHistory.add({'role': 'user', 'content': userMessage});
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final response = await http.post(
      Uri.parse('$_apiBase/chat'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'messages': _buildMessagePayload(_summaryHistory)}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get response: ${response.body}');
    }

    final data = json.decode(response.body);
    final reply = data['response'] as String;

    _summaryHistory.add({'role': 'assistant', 'content': reply});

    return reply.replaceFirst(RegExp(r'^Archie:?\s*'), '');
  }

  List<Map<String, String>> _buildMessagePayload(
      List<Map<String, String>> history) {
    return [
      {
        'role': 'system',
        'content':
            "Your name is archie. You are a Christian AI pink angel/blob thing that lives inside of a bible app called bybl. Answer the user's questions from a Christian perspective. Never curse.  Cite Bible books/chapters/verses (use lesser‑known ones when possible). Don't repeat the user's request at the top of your reply, don't label the response, and don't repeat your own answers."
      },
      ...history
    ];
  }
}
