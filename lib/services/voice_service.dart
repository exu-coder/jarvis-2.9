import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

import 'edge_tts_service.dart';
import 'settings_service.dart';

/// Voice interaction: native continuous speech-to-text for commands,
/// and high-quality studio text-to-speech for vocal responses.
class VoiceService {
  VoiceService._() {
    _initNativeSpeechChannel();
  }
  static final VoiceService instance = VoiceService._();

  static const MethodChannel _nativeSpeechChannel =
      MethodChannel('com.jarvis.dev/speech');
  final FlutterTts _tts = FlutterTts();

  bool _speechReady = false;
  bool _ttsReady = false;
  bool _listening = false;
  Completer<void>? _speakCompleter;

  final ValueNotifier<bool> isSpeaking = ValueNotifier<bool>(false);
  final ValueNotifier<double> soundLevel = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> listeningNotifier = ValueNotifier<bool>(false);

  void Function(bool isListening)? onListeningChanged;
  void Function(String status)? onSpeechStatus;
  void Function(String words, bool isFinal, List<String> candidates)? onSpeechResult;

  /// A7: true when the transcript that produced the last [onSpeechResult] call
  /// contained the wake word. Set immediately before the callback fires, so a
  /// listener can read it synchronously.
  bool lastResultHadWakeWord = false;

  /// A7: true when the last session was started by an explicit user action
  /// (button tap) rather than by the always-on loop. Native value wins; the
  /// Dart-side flag is the fallback when the payload omits the field.
  bool lastSessionWasManual = false;

  bool _manualRequested = false;

  bool get isListening => _listening;
  bool get isAvailable => _speechReady;

  void _initNativeSpeechChannel() {
    _nativeSpeechChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onSpeechResult':
          final args = call.arguments as Map?;
          final text = (args?['text'] ?? '').toString();
          final isFinal = args?['isFinal'] == true;
          final candidates = (args?['candidates'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              (text.isNotEmpty ? [text] : <String>[]);
          // A7: origin + wake-word flag travel with the transcript. Set before
          // the callback so listeners can read them synchronously.
          lastResultHadWakeWord = args?['hasWakeWord'] == true ||
              candidates.any((c) => c.toLowerCase().contains('jarvis'));
          lastSessionWasManual =
              (args?['manualSession'] as bool?) ?? _manualRequested;
          if (text.isNotEmpty || candidates.isNotEmpty) {
            onSpeechResult?.call(text, isFinal, candidates);
          }
          break;
        case 'onSpeechStatus':
          final status = call.arguments.toString();
          onSpeechStatus?.call(status);
          if (status == 'listening') {
            _listening = true;
            listeningNotifier.value = true;
            onListeningChanged?.call(true);
          } else if (status == 'notListening') {
            _listening = false;
            listeningNotifier.value = false;
            onListeningChanged?.call(false);
          }
          break;
        case 'onSoundLevel':
          final level = (call.arguments as num?)?.toDouble() ?? 0.0;
          soundLevel.value = level;
          break;
      }
    });
  }

  Future<bool> _ensureMicPermission() async {
    try {
      final status = await Permission.microphone.request();
      return status.isGranted;
    } catch (_) {
      // Gracefully allow mock/headless testing environments where permission channel is unmocked
      return true;
    }
  }

  Future<bool> initSpeech() async {
    if (_speechReady) return true;
    if (!await _ensureMicPermission()) return false;
    try {
      final available =
          await _nativeSpeechChannel.invokeMethod<bool>('isAvailable') ?? true;
      _speechReady = available;
    } catch (_) {
      _speechReady = true;
    }
    return _speechReady;
  }

  Future<void> initTts({String? voiceProfile}) async {
    final profile = voiceProfile ?? SettingsService.instance.jarvisVoice;
    try {
      switch (profile) {
        case 'friday':
          await _tts.setLanguage('en-IE');
          await _tts.setPitch(1.05);
          await _tts.setSpeechRate(0.52);
          break;
        case 'stark':
          await _tts.setLanguage('en-US');
          await _tts.setPitch(0.95);
          await _tts.setSpeechRate(0.55);
          break;
        case 'kip':
          await _tts.setLanguage('en-GB');
          await _tts.setPitch(0.78);
          await _tts.setSpeechRate(0.48);
          break;
        case 'cortana':
          await _tts.setLanguage('en-US');
          await _tts.setPitch(1.10);
          await _tts.setSpeechRate(0.52);
          break;
        case 'paul':
        default:
          await _tts.setLanguage('en-GB');
          await _tts.setPitch(0.86);
          await _tts.setSpeechRate(0.48);

          try {
            final dynamic voices = await _tts.getVoices;
            if (voices is List && voices.isNotEmpty) {
              for (final v in voices) {
                if (v is Map) {
                  final name = (v['name'] ?? '').toString().toLowerCase();
                  final locale = (v['locale'] ?? '').toString().toLowerCase();
                  if (locale.contains('en-gb') || locale.contains('en_gb')) {
                    if (name.contains('gbd') ||
                        name.contains('gbb') ||
                        name.contains('male') ||
                        name.contains('-r-') ||
                        name.contains('language') && name.contains('b')) {
                      await _tts.setVoice({
                        'name': v['name'].toString(),
                        'locale': v['locale'].toString(),
                      });
                      break;
                    }
                  }
                }
              }
            }
          } catch (e) {
            // A13: the profile voice could not be applied — TTS still works,
            // just with the platform default voice. Worth knowing about.
            debugPrint('[VoiceService] initTts voice selection failed: $e');
          }
          break;
      }

      await _tts.awaitSpeakCompletion(true);
      await _tts.setVolume(1.0);
      await _tts.setQueueMode(0);
      await _tts.setSharedInstance(true);

      _tts.setStartHandler(() {
        isSpeaking.value = true;
      });
      _tts.setCompletionHandler(() {
        isSpeaking.value = false;
        if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
          _speakCompleter!.complete();
        }
      });
      _tts.setErrorHandler((_) {
        isSpeaking.value = false;
        if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
          _speakCompleter!.complete();
        }
      });
      _tts.setCancelHandler(() {
        isSpeaking.value = false;
        if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
          _speakCompleter!.complete();
        }
      });

      _ttsReady = true;
    } catch (_) {
      try {
        await _tts.setLanguage('en-US');
        _ttsReady = true;
      } catch (_) {
        _ttsReady = false;
      }
    }
  }

  /// Forces re-initialization of TTS with a new voice profile.
  Future<void> reconfigureVoice([String? profile]) async {
    _ttsReady = false;
    await initTts(voiceProfile: profile);
  }

  /// Starts native continuous speech recognition.
  /// [onResult] receives primary recognized words, isFinal, and N-best candidates.
  Future<bool> startListening({
    required void Function(String words, bool isFinal, List<String> candidates) onResult,
    bool continuous = true,
    bool manual = false,
  }) async {
    if (!await initSpeech()) return false;
    onSpeechResult = onResult;
    _manualRequested = manual;
    lastSessionWasManual = manual;
    if (_listening && continuous && !manual) {
      // Already running continuous listening loop
      return true;
    }
    try {
      await _nativeSpeechChannel.invokeMethod('startListening', {
        'continuous': continuous,
        'manual': manual,
      });
      _listening = true;
      listeningNotifier.value = true;
      onListeningChanged?.call(true);
      return true;
    } catch (e) {
      debugPrint('[VoiceService] startListening error: $e');
      _listening = false;
      listeningNotifier.value = false;
      onListeningChanged?.call(false);
      return false;
    }
  }

  /// Notifies the native audio engine that media/music playback has started
  /// so that speech recognition yields audio focus to YouTube/Spotify.
  Future<void> notifyMediaPlaybackStarted({Duration duration = const Duration(seconds: 45)}) async {
    try {
      await _nativeSpeechChannel.invokeMethod('notifyMediaStarted', {
        'durationMs': duration.inMilliseconds,
      });
    } catch (e) {
      // A13: without this the recogniser can steal audio focus from media and
      // the user hears YouTube/Spotify pause for no apparent reason.
      debugPrint('[VoiceService] notifyMediaPlaybackStarted failed: $e');
    }
  }

  /// Stops speech recognition immediately.
  Future<void> stopListening() async {
    _listening = false;
    listeningNotifier.value = false;
    onListeningChanged?.call(false);
    try {
      await _nativeSpeechChannel.invokeMethod('stopListening');
    } catch (e) {
      // A13: a failed stop leaves the microphone running — the single most
      // privacy-relevant silent failure in this service.
      debugPrint('[VoiceService] stopListening native call failed: $e');
    }
  }

  /// Sanitizes text so speech synthesizers pronounce acronyms like Jarvis naturally
  /// instead of spelling out letters like "J dot A dot R dot V dot I dot S".
  String sanitizeForSpeech(String text) {
    return text
        .replaceAll(RegExp(r'J\.A\.R\.V\.I\.S\.?', caseSensitive: false), 'Jarvis')
        .replaceAll(RegExp(r'\bJ\.A\.R\.V\.I\.S\b', caseSensitive: false), 'Jarvis')
        .replaceAll(RegExp(r'J\s*\.\s*A\s*\.\s*R\s*\.\s*V\s*\.\s*I\s*\.\s*S\.?', caseSensitive: false), 'Jarvis')
        .replaceAll(RegExp(r'\bJARVIS\b'), 'Jarvis')
        .replaceAll('*', '')
        .replaceAll('#', '')
        .replaceAll('`', '')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
  }

  Future<void> speak(String text) async {
    final clean = sanitizeForSpeech(text);
    if (clean.isEmpty) return;

    // Temporarily pause microphone while speaking to eliminate echo and feedback
    final wasListening = _listening;
    if (wasListening) {
      await stopListening();
      // Let the recognizer release the audio session before TTS claims it.
      await Future<void>.delayed(const Duration(milliseconds: 140));
    }

    await stopSpeaking();
    isSpeaking.value = true;

    try {
      // 1. Try Ultra-Realistic Studio Neural Voice if enabled
      if (SettingsService.instance.useNeuralVoice) {
        try {
          // U2/H2: a fixed 7 s wall-clock timeout used to expire *while the
          // native player was still speaking*, and the fallback below then
          // started FlutterTts on top of it — two voices at once. Budget by
          // utterance length instead, and never speak twice: if the engine
          // still reports playback after the budget, stay silent.
          final budget = Duration(
            milliseconds: 4000 + (clean.length * 55),
          );
          final played = await EdgeTtsService.instance
              .speak(clean)
              .timeout(budget, onTimeout: () => false);
          if (played) {
            return;
          }
          if (EdgeTtsService.instance.isSpeaking) {
            debugPrint(
              '[VoiceService] Neural voice still playing after $budget; '
              'suppressing the local fallback to avoid double audio.',
            );
            return;
          }
          debugPrint(
            '[VoiceService] Neural voice produced no audio within $budget; '
            'falling back to local TTS.',
          );
        } catch (e) {
          debugPrint('[VoiceService] Neural voice error, falling back to local TTS: $e');
        }
      }

      // 2. Fall back to local FlutterTts (offline safe)
      await initTts();
      if (!_ttsReady) {
        // One clean retry — engines occasionally fail on the first bind.
        await initTts();
      }
      if (!_ttsReady) {
        debugPrint('[VoiceService] TTS engine unavailable — staying silent.');
        return;
      }
      await _tts.setVolume(1.0);
      try {
        _speakCompleter = Completer<void>();
        await _tts.speak(clean);
        // Wait for playback, but never hang forever if the engine stalls.
        await _speakCompleter?.future
            .timeout(const Duration(seconds: 60), onTimeout: () {});
      } catch (e) {
        // A silent TTS failure used to look like a successful (silent) reply.
        debugPrint('[VoiceService] flutter_tts speak failed: $e');
      } finally {
        _speakCompleter = null;
      }
    } finally {
      isSpeaking.value = false;
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await EdgeTtsService.instance.stop();
      await _tts.stop();
      isSpeaking.value = false;
      if (_speakCompleter != null && !_speakCompleter!.isCompleted) {
        _speakCompleter!.complete();
      }
    } catch (e) {
      // A13: a stuck TTS engine would otherwise keep the HUD in "speaking"
      // with no diagnostics. Playback state is still reset by the finally.
      debugPrint('[VoiceService] stopSpeaking failed: $e');
    }
  }
}
