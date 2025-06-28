import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class AiService {
  final String apiKey;
  final String baseUrl;
  final String model;

  AiService({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
  });

  Future<String> getMedicineInfo(String medicineName) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
          'HTTP-Referer': 'https://medisight.app', // Your app URL
          'X-Title': 'MediSight', // Your app name
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content': 'You are a helpful medical assistant that provides accurate, concise information about medications. Focus on providing important details like uses, side effects, warnings, and contraindications. Keep your response brief and well-structured.'
            },
            {
              'role': 'user',
              'content': 'Provide important information about $medicineName. Include what it\'s used for, major side effects, warnings, and any critical information a patient should know.'
            }
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        return 'Error: ${response.statusCode} - ${response.reasonPhrase}';
      }
    } catch (e) {
      return 'Error retrieving information: $e';
    }
  }
}

// Provider for AI service
final aiServiceProvider = Provider<AiService>((ref) {
  return AiService(
    apiKey: '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',
    baseUrl: 'https://openrouter.ai/api/v1',
    model: 'deepseek/deepseek-chat-v3-0324:free',
  );
});

// Provider for medicine info results
final medicineInfoProvider = FutureProvider.family<String, String>(
  (ref, medicineName) async {
    if (medicineName.isEmpty) return '';
    final aiService = ref.read(aiServiceProvider);
    return aiService.getMedicineInfo(medicineName);
  },
);