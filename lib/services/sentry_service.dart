import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'personality_service.dart';
import 'settings_service.dart';
import 'telegram_service.dart';
import 'voice_service.dart';

/// Tactical Sentry Mode Anti-Theft Watchdog:
/// Uses device motion sensors to detect unauthorized phone handling,
/// captures silent front-camera telemetry, alerts the room,
/// and dispatches the intruder snapshot to the user's paired Telegram terminal.
///
/// CONSENT MODEL (M11): sentry captures the front camera and ships the frame to
/// Telegram, so arming it is gated. The first arming in a session requires an
/// explicit in-app confirmation ([needsConsent] / [grantConsentForSession]);
/// voice and LLM invocations cannot arm it silently. Arming is also announced
/// out loud and through [recordingIndicator] rather than being covert.
class SentryService extends ChangeNotifier {
  SentryService._();
  static final SentryService instance = SentryService._();

  static const MethodChannel _channel = MethodChannel('com.jarvis.dev/accessibility');

  bool _isArmed = false;
  bool get isArmed => _isArmed;

  bool _breachDetected = false;
  bool get breachDetected => _breachDetected;

  String? _lastBreachPhotoBase64;
  String? get lastBreachPhotoBase64 => _lastBreachPhotoBase64;

  DateTime? _lastBreachTime;
  DateTime? get lastBreachTime => _lastBreachTime;

  /// True while the front camera may capture without further prompting.
  ///
  /// Any UI that can show a persistent indicator should bind to this; the
  /// Settings → Sentry card renders a red RECORDING banner from it.
  final ValueNotifier<bool> recordingIndicator = ValueNotifier<bool>(false);

  /// Consent granted for the current app session only (never persisted).
  bool _consentGrantedForSession = false;

  /// True when arming needs an explicit confirmation first.
  bool get needsConsent => !_consentGrantedForSession;

  String? _lastError;
  String? get lastError => _lastError;

  /// Records explicit user consent for the rest of this session.
  void grantConsentForSession() {
    _consentGrantedForSession = true;
    _lastError = null;
    notifyListeners();
  }

  /// Handles incoming native sentry call dispatched by [NativeBridgeService].
  Future<void> handleNativeCall(MethodCall call) async {
    if (call.method == 'onSentryMovementDetected') {
      final args = call.arguments as Map?;
      final b64 = args?['base64']?.toString() ?? '';
      await _handleBreach(b64);
    }
  }

  Future<bool> armSentry() async {
    if (!_consentGrantedForSession) {
      // Refusing here is the point: a voice command or an agent tool call must
      // not be able to start covert camera capture.
      _lastError =
          'Sentry mode needs confirmation. Open Settings → Tactical Sentry and '
          'confirm that the front camera may record.';
      debugPrint('[SentryService] Arm blocked: per-session consent missing.');
      notifyListeners();
      return false;
    }

    try {
      final success = await _channel.invokeMethod<bool>('startSentryMode') ?? false;
      _isArmed = success;
      _breachDetected = false;
      _lastError = success ? null : 'Native sentry sensor could not be armed.';
      recordingIndicator.value = success;
      notifyListeners();

      if (success) {
        // Audible, not silent: the user (and anyone in the room) can tell the
        // watchdog is recording.
        final msg = PersonalityService.instance.getSentryAck(arm: true);
        await VoiceService.instance.speak(msg);
        await VoiceService.instance.speak(
          'Recording indicator active. Front camera capture is armed.',
        );
      }
      return success;
    } catch (e) {
      debugPrint('[SentryService] Arm failed: $e');
      _isArmed = false;
      _lastError = 'Sentry mode failed to arm: $e';
      recordingIndicator.value = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> disarmSentry() async {
    try {
      await _channel.invokeMethod('stopSentryMode');
    } catch (e) {
      debugPrint('[SentryService] stopSentryMode channel warning: $e');
    }
    _isArmed = false;
    _breachDetected = false;
    recordingIndicator.value = false;
    notifyListeners();

    final msg = PersonalityService.instance.getSentryAck(arm: false);
    await VoiceService.instance.speak(msg);
    return true;
  }

  Future<void> toggleSentry() async {
    if (_isArmed) {
      await disarmSentry();
    } else {
      await armSentry();
    }
  }

  Future<void> _handleBreach(String photoBase64) async {
    if (!_isArmed) return;
    _breachDetected = true;
    _lastBreachPhotoBase64 = photoBase64.isNotEmpty ? photoBase64 : null;
    _lastBreachTime = DateTime.now();
    notifyListeners();

    HapticFeedback.heavyImpact();

    // 1. Imposing vocal deterrence
    const alertSpeech = 'Security violation detected. Spatial coordinates and facial telemetry logged and dispatched.';
    unawaited(VoiceService.instance.speak(alertSpeech));

    // 2. Dispatch photo & breach coordinates to connected Telegram terminal
    final settings = SettingsService.instance;
    final ownerChat = settings.telegramOwnerChatId;
    if (ownerChat.isNotEmpty) {
      final timeFormatted = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final caption = '🚨 *J.A.R.V.I.S. SENTRY ALERT*\n'
          '⚠️ *Unauthorized Movement Detected!*\n'
          '⏱ *Timestamp*: $timeFormatted\n'
          '🛡 *Status*: Intruder snapshot acquired & logged.';

      if (photoBase64.isNotEmpty) {
        await TelegramService.instance.sendPhoto(ownerChat, photoBase64, caption: caption);
      } else {
        await TelegramService.instance.sendMessage(ownerChat, caption);
      }
    }
  }
}

