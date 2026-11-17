import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'edge_tts_service.dart';
import 'system_control_service.dart';

/// 🖐️ Iron Man Zero-Touch Air Gestures Service
///
/// Enables touch-free phone control using the device's optical proximity
/// and front sensory matrix. Allows mid-air hand waves, double-waves, and
/// palm hovers to control media playback, wake J.A.R.V.I.S., and trigger actions.
class AirGestureService extends ChangeNotifier {
  AirGestureService._();

  static final AirGestureService instance = AirGestureService._();
  static const MethodChannel _channel = MethodChannel('com.jarvis.dev/accessibility');

  bool _isEnabled = false;
  String _lastGesture = 'none';
  DateTime? _lastGestureTime;
  int _gestureCount = 0;
  String _statusMessage = 'Air Gestures offline';
  bool _voiceFeedback = true;

  final ValueNotifier<String?> activeGestureBanner = ValueNotifier<String?>(null);
  Timer? _bannerTimer;

  bool get isEnabled => _isEnabled;
  String get lastGesture => _lastGesture;
  DateTime? get lastGestureTime => _lastGestureTime;
  int get gestureCount => _gestureCount;
  String get statusMessage => _statusMessage;
  bool get voiceFeedback => _voiceFeedback;

  set voiceFeedback(bool val) {
    _voiceFeedback = val;
    notifyListeners();
  }

  /// Handles native air gesture call dispatched by [NativeBridgeService].
  Future<void> handleNativeCall(MethodCall call) async {
    if (call.method == 'onAirGesture') {
      final args = call.arguments;
      if (args is Map) {
        final gesture = (args['gesture'] ?? 'wave').toString();
        final duration = (args['durationMs'] as num?)?.toInt() ?? 100;
        await processGesture(gesture, durationMs: duration);
      }
    }
  }

  /// Toggles Air Gestures active state.
  Future<bool> toggleAirGestures() async {
    if (_isEnabled) {
      return stop();
    } else {
      return start();
    }
  }

  /// Arms optical proximity sensor for mid-air gesture monitoring.
  Future<bool> start() async {
    try {
      final res = await _channel.invokeMethod<bool>('startAirGestures');
      _isEnabled = res ?? true;
      _statusMessage = _isEnabled
          ? 'Optical proximity matrix active. Wave or hover hand to control.'
          : 'Proximity sensor unavailable. Simulated gestures ready.';
      notifyListeners();
      if (_voiceFeedback) {
        unawaited(EdgeTtsService.instance.speak(
          'Zero-touch air gestures engaged, sir. Sensors monitoring overhead space.',
        ));
      }
      return _isEnabled;
    } catch (e) {
      // M4/U1: a dead sensor is NOT "enabled". Reporting software mode here
      // made the HUD claim gestures were live while nothing was armed, and the
      // "software simulation" path is what toggled media in a pocket.
      debugPrint('[AirGestureService] startAirGestures failed: $e');
      _isEnabled = false;
      _statusMessage = 'Proximity sensor unavailable — air gestures inactive.';
      notifyListeners();
      return false;
    }
  }

  /// Disarms air gesture sensors.
  Future<bool> stop() async {
    try {
      await _channel.invokeMethod<bool>('stopAirGestures');
    } catch (e) {
      // Sensor may already be released by the OS; the software state below is
      // still the source of truth, but the reason is worth one line.
      debugPrint('[AirGestureService] stopAirGestures failed: $e');
    }
    _bannerTimer?.cancel();
    _bannerTimer = null;
    _isEnabled = false;
    _statusMessage = 'Air Gestures offline';
    notifyListeners();
    if (_voiceFeedback) {
      unawaited(EdgeTtsService.instance.speak(
        'Air gesture sensors disengaged, sir.',
      ));
    }
    return false;
  }

  /// Releases the banner timer and the gesture notifier.
  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    activeGestureBanner.dispose();
    super.dispose();
  }

  /// Processes an incoming gesture (native sensor or user simulation).
  Future<String> processGesture(String gesture, {int durationMs = 150}) async {
    _lastGesture = gesture;
    _lastGestureTime = DateTime.now();
    _gestureCount++;
    HapticFeedback.heavyImpact();

    String resultAction = '';

    switch (gesture.toLowerCase()) {
      case 'wave':
      case 'swipe_left':
      case 'swipe':
        resultAction = 'Next Media Track';
        await SystemControlService.instance.nextTrack();
        break;

      case 'swipe_right':
        resultAction = 'Previous Media Track';
        await SystemControlService.instance.previousTrack();
        break;

      case 'palm_hover':
      case 'hover':
        resultAction = 'Play / Pause Toggled';
        await SystemControlService.instance.togglePlayPause();
        break;

      case 'double_wave':
      case 'double':
        resultAction = 'Take Screenshot';
        await SystemControlService.instance.takeScreenshot();
        break;

      default:
        resultAction = 'Proximity Pulse Registered';
    }

    _statusMessage = 'Detected $gesture: $resultAction';
    activeGestureBanner.value = '🖐️ AIR GESTURE: ${gesture.toUpperCase().replaceAll('_', ' ')} ($resultAction)';
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(milliseconds: 2500), () {
      activeGestureBanner.value = null;
    });
    notifyListeners();
    return resultAction;
  }

  /// Allows interactive simulation from the Air Gestures HUD.
  Future<String> simulateGesture(String gesture) async {
    return processGesture(gesture);
  }
}

