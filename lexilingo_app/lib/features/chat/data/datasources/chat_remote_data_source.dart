import 'package:google_generative_ai/google_generative_ai.dart';

class ChatRemoteDataSource {
  final String apiKey;
  late GenerativeModel _model;

  ChatRemoteDataSource({required this.apiKey}) {
    _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
  }

  Future<String> sendMessage(String message) async {
    try {
      final content = [Content.text(message)];
      final response = await _model.generateContent(content);
      return response.text ?? "I didn't understand that.";
    } catch (e) {
      throw Exception('Failed to connect to AI');
    }
  }
}
