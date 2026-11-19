import 'package:speech_to_text/speech_to_text.dart';

/// Voice input via the macOS speech recognizer (Korean).
/// The first use triggers the system microphone + speech permission prompts.
class SpeechInput {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  String lastError = '';

  // Current session: called exactly once with the best transcript we have,
  // whether recognition finished normally, timed out, or errored.
  void Function(String text)? _finish;
  String _partial = '';

  bool get isListening => _stt.isListening;

  Future<bool> _ensure() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(
        onError: (e) {
          lastError = e.errorMsg;
          _complete(_partial);
        },
        onStatus: (s) {
          if (s == SpeechToText.doneStatus ||
              s == SpeechToText.notListeningStatus) {
            _complete(_partial);
          }
        },
      );
    } catch (e) {
      lastError = e.toString();
      _ready = false;
    }
    return _ready;
  }

  void _complete(String text) {
    final f = _finish;
    _finish = null;
    f?.call(text);
  }

  /// Starts listening. [onPartial] gets live text; [onFinal] fires once
  /// with the transcript when the user stops talking or [stop] is called.
  Future<bool> start({
    required void Function(String text) onPartial,
    required void Function(String text) onFinal,
  }) async {
    if (!await _ensure()) return false;
    _partial = '';
    _finish = onFinal;
    try {
      await _stt.listen(
        onResult: (r) {
          _partial = r.recognizedWords;
          if (r.finalResult) {
            _complete(_partial);
          } else {
            onPartial(_partial);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: 'ko_KR',
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (e) {
      lastError = e.toString();
      _finish = null;
      return false;
    }
    return true;
  }

  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
    // Some engines never send a final result after stop(); don't hang.
    Future.delayed(const Duration(seconds: 2), () => _complete(_partial));
  }
}
