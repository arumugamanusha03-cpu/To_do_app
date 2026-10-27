import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// A speech language the phone can actually recognise.
class VoiceLocale {
  final String id;
  final String label;

  const VoiceLocale({required this.id, required this.label});
}

/// Dictation for the assistant's input field.
///
/// **This is the one part of TaskFlow that is not purely on-device.** The
/// recognising is done by the phone's own speech service — Google's, on most
/// Android phones — which may send the audio to its servers. The app never
/// sees or stores the audio, and holds no INTERNET permission of its own, but
/// the UI says this plainly rather than letting the privacy claim blur.
class VoiceInput {
  VoiceInput._();

  static final SpeechToText _speech = SpeechToText();

  static bool _initialised = false;
  static bool _available = false;

  /// Indian English handles Tanglish — English and Tamil words in the same
  /// sentence — far better than either pure locale.
  static const String defaultLocale = 'en_IN';

  static const List<VoiceLocale> suggestedLocales = [
    VoiceLocale(id: 'en_IN', label: 'Tanglish / Indian English'),
    VoiceLocale(id: 'ta_IN', label: 'Tamil'),
    VoiceLocale(id: 'en_US', label: 'English (US)'),
    VoiceLocale(id: 'en_GB', label: 'English (UK)'),
  ];

  static bool get isListening => _speech.isListening;

  static bool get isAvailable => _available;

  /// Safe to call repeatedly; the plugin only really initialises once.
  static Future<bool> init({void Function(String message)? onError}) async {
    if (_initialised) return _available;

    try {
      _available = await _speech.initialize(
        onError: (error) => onError?.call(error.errorMsg),
        onStatus: (status) => debugPrint('Speech status: $status'),
      );
    } catch (error) {
      debugPrint('Speech init failed: $error');
      _available = false;
    }

    _initialised = true;
    return _available;
  }

  /// Starts dictating. [onResult] fires repeatedly as words are recognised;
  /// `isFinal` marks the last one.
  static Future<bool> start({
    required void Function(String text, bool isFinal) onResult,
    String localeId = defaultLocale,
    void Function(String message)? onError,
  }) async {
    final ready = await init(onError: onError);
    if (!ready) return false;

    // Fall back to the phone's own default if the chosen language is not
    // installed, rather than failing silently.
    final installed = await _speech.locales();
    final resolved = installed.any((l) => l.localeId == localeId)
        ? localeId
        : (await _speech.systemLocale())?.localeId;

    await _speech.listen(
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: resolved,
        partialResults: true,
        // Dictation keeps listening through natural pauses instead of
        // stopping at the first gap.
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 30),
      ),
    );

    return true;
  }

  static Future<void> stop() async {
    if (_speech.isListening) await _speech.stop();
  }

  static Future<void> cancel() async {
    if (_speech.isListening) await _speech.cancel();
  }

  /// The suggested languages the phone actually has installed, so Settings
  /// never offers one that cannot work.
  static Future<List<VoiceLocale>> availableLocales() async {
    final ready = await init();
    if (!ready) return const [];

    final installed = await _speech.locales();
    final ids = installed.map((l) => l.localeId).toSet();

    return suggestedLocales.where((l) => ids.contains(l.id)).toList();
  }
}
