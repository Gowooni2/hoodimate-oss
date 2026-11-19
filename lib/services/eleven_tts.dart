import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// ElevenLabs cloud TTS. The user pastes their own API key + voice ID
/// in the pet's Settings tab; the key is stored only on their Mac.
class ElevenConfig {
  String apiKey = '';
  String voiceId = '';
  String modelId = 'eleven_multilingual_v2';

  bool get isConfigured => apiKey.isNotEmpty && voiceId.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'voiceId': voiceId,
        'modelId': modelId,
      };

  void fromJson(Map<String, dynamic> j) {
    apiKey = (j['apiKey'] ?? '').toString();
    voiceId = (j['voiceId'] ?? '').toString();
    modelId = (j['modelId'] ?? modelId).toString();
  }
}

class ElevenTtsService {
  final AudioPlayer _player = AudioPlayer();
  final ElevenConfig config = ElevenConfig();

  Future<File> _configFile() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/eleven_config.json');
  }

  Future<void> load() async {
    try {
      final f = await _configFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map<String, dynamic>) config.fromJson(j);
      }
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final f = await _configFile();
      await f.writeAsString(jsonEncode(config.toJson()));
    } catch (_) {}
  }

  /// Renders [text] with ElevenLabs and plays it.
  /// Returns true when audio was played.
  Future<bool> speak(String text) async {
    if (!config.isConfigured || text.trim().isEmpty) return false;
    try {
      final res = await http
          .post(
            Uri.parse(
                'https://api.elevenlabs.io/v1/text-to-speech/${config.voiceId}'),
            headers: {
              'xi-api-key': config.apiKey,
              'Content-Type': 'application/json',
              'Accept': 'audio/mpeg',
            },
            body: jsonEncode({
              'text': text,
              'model_id': config.modelId,
              'voice_settings': {
                'stability': 0.5,
                'similarity_boost': 0.75,
              },
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return false;
      await _player.stop();
      await _player.play(BytesSource(res.bodyBytes));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }
}
