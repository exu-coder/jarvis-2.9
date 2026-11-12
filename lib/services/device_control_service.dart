import 'dart:convert';

import 'package:flutter/services.dart';

/// Result of a natural-language device command.
class DeviceControlResult {
  final bool success;
  final String spoken;
  final Map<String, dynamic> raw;

  const DeviceControlResult({
    required this.success,
    required this.spoken,
    this.raw = const {},
  });
}

/// Typed bridge to the native `com.jarvis.dev/device` channel.
///
/// This is the single entry point the AI core uses to exercise every
/// permission and service declared in the manifest:
///
///  - Foreground services: AgentService, LocationService,
///    ScreenCaptureService, ConnectedDeviceService
///  - Runtime permissions: microphone, camera, location, contacts, calendar,
///    SMS, phone, call log, media, bluetooth, nearby Wi-Fi, sensors,
///    activity, notifications
///  - Special access: overlay, notification listener, usage stats,
///    write settings, all files, install packages, exact alarms,
///    battery optimization, DND policy, device admin
///  - Device actions: SMS, calls, contact lookup, calendar reads, alarms,
///    volume, brightness, torch, screen lock, storage/media snapshots
///  - Screen awareness: MediaProjection frames for the vision pipeline
class DeviceControlService {
  DeviceControlService._();
  static final DeviceControlService instance = DeviceControlService._();

  static const MethodChannel _channel = MethodChannel('com.jarvis.dev/device');

  // ------------------------------------------------------------------
  // Permission surface
  // ------------------------------------------------------------------

  /// Complete logical permission report (runtime + special access).
  Future<Map<String, dynamic>> permissionReport() async =>
      _safeMap(await _channel.invokeMethod('getPermissionReport'));

  /// Requests a batch of runtime permission groups in one dialog sequence.
  Future<bool> requestPermissions(List<String> groups) async {
    final res = await _channel.invokeMethod('requestPermissions', {
      'groups': groups,
    });
    return res is Map ? (res['granted'] as bool? ?? true) : true;
  }

  /// Navigates to the settings page governing a special-access permission.
  Future<bool> openSettingsPage(String page) async =>
      await _channel.invokeMethod('openSettingsPage', {'page': page}) == true;

  /// Opens a quick-settings panel (wifi / bluetooth / internet / nfc / volume).
  Future<bool> openPanel(String panel) async =>
      await _channel.invokeMethod('openPanel', {'panel': panel}) == true;

  // ------------------------------------------------------------------
  // Service surface
  // ------------------------------------------------------------------

  Future<Map<String, dynamic>> serviceStatus() async =>
      _safeMap(await _channel.invokeMethod('getServiceStatus'));

  Future<bool> startService(String service) async {
    final res = _safeMap(await _channel.invokeMethod('startService', {'service': service}));
    return res['success'] == true;
  }

  Future<bool> stopService(String service) async {
    final res = _safeMap(await _channel.invokeMethod('stopService', {'service': service}));
    return res['success'] == true;
  }

  /// Reboots the background agent core after device restarts (opt-in).
  Future<void> setAutostart(bool enabled) =>
      _channel.invokeMethod('setAutostart', {'enabled': enabled});

  // ------------------------------------------------------------------
  // Floating bubble overlay (HTML orb + copilot panel)
  // ------------------------------------------------------------------

  /// Starts the system-wide floating 𝐉.𝐀.𝐑.𝐕.𝐈.𝐒 bubble. Returns `false`
  /// (and opens the overlay settings) if the permission is missing.
  Future<bool> startBubble() async {
    final res = _safeMap(await _channel.invokeMethod('startBubble'));
    if (res['success'] != true) return false;
    return true;
  }

  Future<bool> stopBubble() async {
    final res = _safeMap(await _channel.invokeMethod('stopBubble'));
    return res['success'] == true;
  }

  Future<bool> isBubbleRunning() async {
    final res = _safeMap(await _channel.invokeMethod('isBubbleRunning'));
    return res['running'] == true;
  }

  // ------------------------------------------------------------------
  // Screen capture surface
  // ------------------------------------------------------------------

  /// Opens the MediaProjection consent dialog. The native side starts
  /// [ScreenCaptureService] automatically when the user consents.
  Future<bool> requestScreenCapture() async {
    final res = await _channel.invokeMethod('requestScreenCapture');
    if (res is Map && res['granted'] != null) return res['granted'] == true;
    return true; // consent dialog shown; result arrives via onScreenCaptureReady
  }

  /// Latest captured screen frame as base64 JPEG (vision pipeline input).
  Future<Map<String, dynamic>?> captureFrame({int quality = 85}) async {
    final res = await _channel.invokeMethod('captureFrame', {'quality': quality});
    return res is Map ? Map<String, dynamic>.from(res) : null;
  }

  Future<bool> stopScreenCapture() async =>
      await _channel.invokeMethod('stopScreenCapture') == true;

  // ------------------------------------------------------------------
  // Communication surface
  // ------------------------------------------------------------------

  Future<Map<String, dynamic>> sendSms({
    required String address,
    required String body,
  }) async =>
      _safeMap(await _channel.invokeMethod('sendSms', {
        'address': address,
        'body': body,
      }));

  Future<Map<String, dynamic>> placeCall(String number) async =>
      _safeMap(await _channel.invokeMethod('placeCall', {'number': number}));

  Future<Map<String, dynamic>> resolveContact(String query) async =>
      _safeMap(await _channel.invokeMethod('resolveContact', {'query': query}));

  Future<List<Map<String, dynamic>>> readContacts({int limit = 30}) async {
    final res = _safeMap(await _channel.invokeMethod('readContacts', {'limit': limit}));
    if (res['contacts'] is List) {
      return (res['contacts'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> readCalendar({int limit = 20}) async {
    final res = _safeMap(await _channel.invokeMethod('readCalendar', {'limit': limit}));
    if (res['events'] is List) {
      return (res['events'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> setAlarm({
    required int hour,
    int minute = 0,
    String label = '',
  }) async =>
      _safeMap(await _channel.invokeMethod('setAlarm', {
        'hour': hour,
        'minute': minute,
        'label': label,
      }));

  // ------------------------------------------------------------------
  // Hardware surface
  // ------------------------------------------------------------------

  Future<Map<String, dynamic>> getLocation() async {
    final res = await _channel.invokeMethod('getLocation');
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  Future<Map<String, dynamic>> setVolumePercent(double percent) async =>
      _safeMap(await _channel.invokeMethod('setVolume', {'percent': percent}));

  Future<Map<String, dynamic>> getVolume() async =>
      _safeMap(await _channel.invokeMethod('getVolume'));

  Future<Map<String, dynamic>> setBrightness(double value) async =>
      _safeMap(await _channel.invokeMethod('setBrightness', {'value': value}));

  Future<Map<String, dynamic>> setTorch(bool on) async =>
      _safeMap(await _channel.invokeMethod('setTorch', {'on': on}));

  Future<Map<String, dynamic>> lockScreen() async =>
      _safeMap(await _channel.invokeMethod('lockScreen'));

  Future<Map<String, dynamic>> storageSnapshot() async =>
      _safeMap(await _channel.invokeMethod('getStorageSnapshot'));

  Future<Map<String, dynamic>> mediaSnapshot() async =>
      _safeMap(await _channel.invokeMethod('getMediaSnapshot'));

  // ------------------------------------------------------------------
  // Natural-language device command router (AI core hook)
  // ------------------------------------------------------------------

  /// Parses and executes free-form device commands such as:
  ///  - "call mom" / "dial +1 555 010 2030"
  ///  - "text Sarah saying I'm on my way"
  ///  - "send an SMS to John saying meeting at five"
  ///  - "set an alarm for 7:30 am" / "alarm at 06:45 for the gym"
  ///  - "where am I"
  ///  - "set volume to 70%" / "brightness to 40%"
  ///  - "turn on the flashlight"
  ///  - "turn on wifi" / "turn on bluetooth" (opens the panel; Android 10+)
  ///  - "lock the phone"
  ///  - "start/stop the background agent", "start location tracking",
  ///    "stop screen capture"
  Future<DeviceControlResult> executeCommand(String raw) async {
    final text = raw.trim();
    final lower = text.toLowerCase();

    try {
      // ---- Screen lock -------------------------------------------------
      if (lower.contains('lock the phone') ||
          lower.contains('lock my phone') ||
          lower.contains('lock the screen') ||
          lower.contains('lock my screen')) {
        final res = await lockScreen();
        return DeviceControlResult(
          success: res['success'] == true,
          spoken: res['message']?.toString() ??
              'I could not lock the screen, sir. Device administrator access is required.',
        );
      }

      // ---- Calls -------------------------------------------------------
      if (RegExp(r'^(call|dial|ring)\b').hasMatch(lower) ||
          lower.startsWith('make a call')) {
        final target = text
            .replaceFirst(RegExp(r'^(call|dial|ring|make a call)\b', caseSensitive: false), '')
            .replaceFirst(RegExp(r'^(to)\s+', caseSensitive: false), '')
            .trim();
        if (target.isEmpty) {
          return const DeviceControlResult(
            success: false,
            spoken: 'Who should I call, sir?',
          );
        }
        final number = RegExp(r'^[\d\s()+\-]+$').hasMatch(target) ? target : null;
        if (number != null) {
          final res = await placeCall(number);
          return DeviceControlResult(
            success: res['success'] == true,
            spoken: res['message']?.toString() ?? 'Calling $number, sir.',
          );
        }
        final contact = await resolveContact(target);
        if (contact['success'] == true) {
          final c = Map<String, dynamic>.from(contact['contact'] as Map);
          final res = await placeCall(c['number']?.toString() ?? '');
          return DeviceControlResult(
            success: res['success'] == true,
            spoken: res['success'] == true
                ? 'Calling ${c['name']}, sir.'
                : res['message']?.toString() ?? 'The call did not go through, sir.',
            raw: contact,
          );
        }
        return DeviceControlResult(
          success: false,
          spoken: contact['message']?.toString() ?? 'I could not find that contact, sir.',
          raw: contact,
        );
      }

      // ---- SMS ---------------------------------------------------------
      final smsMatch = RegExp(
        r'^(?:text|send(?:\s+an?\s+)?(?:sms|text|message)|message)\s+(.+?)(?:\s+(?:saying|that|with the message|message:)\s+([\s\S]+))?$',
        caseSensitive: false,
      ).firstMatch(text);
      if (smsMatch != null) {
        final target = (smsMatch.group(1) ?? '').trim();
        var body = (smsMatch.group(2) ?? '').trim();
        if (body.isEmpty && lower.contains(' saying ')) {
          body = text.split(RegExp(r' saying ', caseSensitive: false)).last.trim();
          body = body.replaceFirst(RegExp(r'^(saying\s*)', caseSensitive: false), '');
        }
        if (body.isEmpty) {
          return const DeviceControlResult(
            success: false,
            spoken: 'What should the message say, sir?',
          );
        }
        String? address;
        String? displayName;
        if (RegExp(r'^[\d\s()+\-]+$').hasMatch(target)) {
          address = target;
        } else {
          final contact = await resolveContact(target);
          if (contact['success'] == true) {
            final c = Map<String, dynamic>.from(contact['contact'] as Map);
            address = c['number']?.toString();
            displayName = c['name']?.toString();
          }
        }
        if (address == null || address.isEmpty) {
          return DeviceControlResult(
            success: false,
            spoken: 'I could not resolve "$target" to a contact, sir.',
          );
        }
        final res = await sendSms(address: address, body: body);
        return DeviceControlResult(
          success: res['success'] == true,
          spoken: res['success'] == true
              ? 'Message sent to ${displayName ?? address}, sir.'
              : res['message']?.toString() ?? 'The message failed to send, sir.',
          raw: res,
        );
      }

      // ---- Alarms ------------------------------------------------------
      if (lower.contains('alarm')) {
        final time = _parseTime(text);
        if (time != null) {
          final label = _alarmLabel(text);
          final res = await setAlarm(hour: time.$1, minute: time.$2, label: label);
          return DeviceControlResult(
            success: res['success'] == true,
            spoken: res['message']?.toString() ??
                'Alarm set for ${time.$1}:${time.$2.toString().padLeft(2, '0')}, sir.',
          );
        }
        return const DeviceControlResult(
          success: false,
          spoken: 'What time should I set the alarm for, sir?',
        );
      }

      // ---- Location ----------------------------------------------------
      if (lower.contains('where am i') ||
          lower.contains('my location') ||
          lower.contains('current location') ||
          lower.contains('my coordinates')) {
        final res = await getLocation();
        if (res['success'] == true) {
          final lat = (res['latitude'] as num? ?? 0).toStringAsFixed(4);
          final lon = (res['longitude'] as num? ?? 0).toStringAsFixed(4);
          final accuracy = (res['accuracy'] as num? ?? 0).toStringAsFixed(0);
          return DeviceControlResult(
            success: true,
            spoken: 'Your current position is latitude $lat, longitude $lon, '
                'with roughly $accuracy meters of accuracy, sir.',
            raw: res,
          );
        }
        return DeviceControlResult(
          success: false,
          spoken: 'I cannot get a position fix right now, sir. '
              'Location services or the location permission may be disabled.',
        );
      }

      // ---- Volume ------------------------------------------------------
      final volumeMatch =
          RegExp(r'volume\s*(?:to|at)?\s*(\d{1,3})\s*%?', caseSensitive: false)
              .firstMatch(lower);
      if (volumeMatch != null) {
        final percent = int.tryParse(volumeMatch.group(1) ?? '')?.clamp(0, 100);
        if (percent != null) {
          final res = await setVolumePercent(percent.toDouble());
          return DeviceControlResult(
            success: res['success'] == true,
            spoken: res['message']?.toString() ?? 'Volume set to $percent percent, sir.',
          );
        }
      }
      if (lower.contains('volume up') || lower.contains('louder')) {
        final cur = await getVolume();
        final v = ((cur['volume'] as num? ?? 0.5).toDouble() + 0.15)
            .clamp(0.0, 1.0);
        final res = await setVolumePercent(v * 100);
        return DeviceControlResult(
          success: res['success'] == true,
          spoken: res['message']?.toString() ?? 'Volume increased, sir.',
        );
      }
      if (lower.contains('volume down') || lower.contains('quieter')) {
        final cur = await getVolume();
        final v = ((cur['volume'] as num? ?? 0.5).toDouble() - 0.15)
            .clamp(0.0, 1.0);
        final res = await setVolumePercent(v * 100);
        return DeviceControlResult(
          success: res['success'] == true,
          spoken: res['message']?.toString() ?? 'Volume reduced, sir.',
        );
      }

      // ---- Brightness --------------------------------------------------
      final brightnessMatch =
          RegExp(r'brightness\s*(?:to|at)?\s*(\d{1,3})\s*%?', caseSensitive: false)
              .firstMatch(lower);
      if (brightnessMatch != null) {
        final pct = int.tryParse(brightnessMatch.group(1) ?? '')?.clamp(0, 100);
        if (pct != null) {
          final res = await setBrightness(pct / 100.0);
          return DeviceControlResult(
            success: res['success'] == true,
            spoken: res['message']?.toString() ?? 'Brightness set to $pct percent, sir.',
            raw: res,
          );
        }
        return const DeviceControlResult(
          success: false,
          spoken: 'I need the "modify system settings" special access for that, sir.',
        );
      }

      // ---- Torch -------------------------------------------------------
      if (lower.contains('flashlight') || lower.contains('torch')) {
        final on = !lower.contains('off');
        final res = await setTorch(on);
        return DeviceControlResult(
          success: res['success'] == true,
          spoken: res['message']?.toString() ?? (on ? 'Torch on, sir.' : 'Torch off, sir.'),
        );
      }

      // ---- Wi-Fi / Bluetooth panels ------------------------------------
      if (lower.contains('wifi') || lower.contains('wi-fi')) {
        final panelOpened = await openPanel('wifi');
        return DeviceControlResult(
          success: panelOpened,
          spoken: panelOpened
              ? 'Android restricts apps from toggling Wi-Fi directly, so I opened the Wi-Fi panel for you, sir.'
              : 'I could not open the Wi-Fi panel, sir.',
        );
      }
      if (lower.contains('bluetooth')) {
        final panelOpened = await openPanel('bluetooth');
        return DeviceControlResult(
          success: panelOpened,
          spoken: panelOpened
              ? 'Bluetooth settings panel is open, sir.'
              : 'I could not open the Bluetooth panel, sir.',
        );
      }

      // ---- Service control ---------------------------------------------
      if (lower.contains('start location tracking') ||
          lower.contains('track my location')) {
        final ok = await startService('location');
        return DeviceControlResult(
          success: ok,
          spoken: ok
              ? 'Location tracking service is running, sir.'
              : 'I could not start location tracking — the location permission may be missing, sir.',
        );
      }
      if (lower.contains('stop location tracking')) {
        await stopService('location');
        return const DeviceControlResult(
          success: true,
          spoken: 'Location tracking stopped, sir.',
        );
      }
      if (lower.contains('start the background agent') ||
          lower.contains('activate the agent core') ||
          lower.contains('stay awake')) {
        final ok = await startService('agent');
        return DeviceControlResult(
          success: ok,
          spoken: ok
              ? 'Background agent core engaged, sir.'
              : 'I could not engage the background agent, sir.',
        );
      }
      if (lower.contains('stop the background agent')) {
        await stopService('agent');
        return const DeviceControlResult(
          success: true,
          spoken: 'Background agent core stood down, sir.',
        );
      }

      return const DeviceControlResult(
        success: false,
        spoken: '',
      );
    } on PlatformException catch (e) {
      return DeviceControlResult(
        success: false,
        spoken: 'Device bridge error: ${e.message ?? e.code}',
      );
    } catch (e) {
      return DeviceControlResult(success: false, spoken: 'Device command failed: $e');
    }
  }

  /// "7:30 am", "06:45", "quarter past nine" is NOT supported — explicit times only.
  (int, int)? _parseTime(String text) {
    final m = RegExp(
      r'(\d{1,2})\s*[:.]\s*(\d{2})\s*(a\.?m\.?|p\.?m\.?)?',
      caseSensitive: false,
    ).firstMatch(text.toLowerCase());
    if (m == null) {
      final hourOnly = RegExp(r'alarm for (\d{1,2}) (am|pm)').firstMatch(text);
      if (hourOnly != null) {
        final h = int.tryParse(hourOnly.group(1) ?? '') ?? -1;
        if (h >= 1 && h <= 12) {
          final pm = hourOnly.group(2)?.toLowerCase() == 'pm';
          return ((h % 12) + (pm ? 12 : 0), 0);
        }
      }
      return null;
    }
    var hour = int.tryParse(m.group(1) ?? '') ?? -1;
    final minute = int.tryParse(m.group(2) ?? '') ?? 0;
    if (hour < 0 || hour > 23 || minute > 59) return null;
    final meridiem = m.group(3);
    if (meridiem != null) {
      final isPm = meridiem.replaceAll('.', '').startsWith('p');
      final isAm = meridiem.replaceAll('.', '').startsWith('a');
      if ((isAm || isPm) && hour >= 1 && hour <= 12) {
        hour = (hour % 12) + (isPm ? 12 : 0);
      }
    }
    return (hour, minute);
  }

  String _alarmLabel(String text) {
    final forMatch = RegExp(r'\bfor\s+(.+)$', caseSensitive: false).firstMatch(text);
    if (forMatch != null) {
      final label = forMatch.group(1)!.trim();
      if (label.isNotEmpty && !RegExp(r'^\d').hasMatch(label)) return label;
    }
    return '';
  }

  Map<String, dynamic> _safeMap(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  /// JSON debug helper for the AI core and tests.
  String encodeResult(DeviceControlResult result) =>
      jsonEncode({'success': result.success, 'spoken': result.spoken});
}
