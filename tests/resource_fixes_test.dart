// PENDING RUNTIME: not executed — no Flutter/Dart SDK on this machine.
//
// Regression specifications for the resources / telemetry / TTS / CI / docs
// slice (H4, M1..M13, L1..L12). Static verification only; nothing ran.
//
// To run later, from the project root:
//   flutter test tests/resource_fixes_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/models/screen_node.dart';

String _src(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // H4 — no fabricated telemetry
  // ---------------------------------------------------------------------------
  group('H4: telemetry honesty', () {
    test('network audit contains no invented IP, latency or score', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/network_audit_service.dart');
      expect(src.contains('192.168.1.105'), isFalse);
      expect(src.contains('192.168.1.1 '), isFalse);
      expect(src.contains('pingLatencyMs: 14'), isFalse);
    });

    test('network audit exposes failure instead of a fake report', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/network_audit_service.dart');
      expect(src, contains('NetworkAuditReport?'));
      expect(src, contains('String? get lastError'));
      expect(src, contains('NetworkAuditReport? _fail('));
    });

    test('smart home never injects invented devices on failure', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/smart_home_service.dart');
      expect(src.contains('_entities.addAll(['), isFalse,
          reason: 'failure path must clear/keep real entities, not fabricate');
      expect(src, contains('String? get lastError'));
    });
  });

  // ---------------------------------------------------------------------------
  // M2 — HTTP client and audio cache lifecycle
  // ---------------------------------------------------------------------------
  group('M2: Edge TTS resources', () {
    test('the HttpClient is closed after every synthesis', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/edge_tts_service.dart');
      expect(src, contains('client.close(force: true)'));
    });

    test('the audio cache is bounded by age and file count', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/edge_tts_service.dart');
      expect(src, contains('pruneAudioCacheSync'));
      expect(src, contains('maxAgeDays = 7'));
      expect(src, contains('maxFiles = 50'));
    });
  });

  // ---------------------------------------------------------------------------
  // M3 / M5 / M6 / M11 / M13 — lifecycle, persistence, privacy
  // ---------------------------------------------------------------------------
  group('Lifecycle and privacy', () {
    test('M3: JarvisService cancels all five timers in one place', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/jarvis_service.dart');
      expect(src, contains('_cancelAllTimers'));
      expect(src, contains('void dispose()'));
      for (final timer in const [
        '_awakeTimer',
        '_speechSilenceTimer',
        '_followUpSilenceTimer',
        '_proactiveConfirmationTimer',
      ]) {
        expect(src, contains(timer));
      }
    });

    test('M5: proactive dedup is persisted', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/proactive_agent_service.dart');
      expect(src, contains('proactive_shown_ids'));
      expect(src, contains('SharedPreferences.getInstance()'));
      expect(src, contains('_persistDedupState'));
    });

    test('M6: notification bodies have a TTL and a screen-off purge', () {
      // PENDING RUNTIME: not executed.
      final src =
          _src('android/app/src/main/kotlin/com/jarvis/dev/InboxNotificationListenerService.kt');
      expect(src, contains('MAX_SAVED'));
      expect(src, contains('Intent.ACTION_SCREEN_OFF'));
      expect(src, contains('purgeAll'));
      expect(src, contains('purgeExpired'));
    });

    test('M11: sentry requires per-session consent', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/sentry_service.dart');
      expect(src, contains('needsConsent'));
      expect(src, contains('grantConsentForSession'));
    });

    test('M13: overlay destroys its WebView and JSON-encodes replies', () {
      // PENDING RUNTIME: not executed.
      final src =
          _src('android/app/src/main/kotlin/com/jarvis/dev/BubbleOverlayService.kt');
      expect(src, contains('destroyQuietly'));
      expect(src, contains('JSONObject.quote'));
      expect(src, contains('\\u2028'));
    });
  });

  // ---------------------------------------------------------------------------
  // L1 — prompt-friendly node rendering
  // ---------------------------------------------------------------------------
  group('L1: ScreenNode.toString', () {
    test('is compact and keeps the useful fields', () {
      // PENDING RUNTIME: not executed.
      final node = ScreenNode.fromMap(<String, dynamic>{
        'index': 7,
        'text': 'Send message',
        'contentDescription': '',
        'className': 'android.widget.Button',
        'viewId': 'com.app:id/send',
        'isClickable': true,
        'isEditable': false,
        'isScrollable': false,
        'isCheckable': false,
        'isEnabled': true,
        'left': 0,
        'top': 10,
        'right': 100,
        'bottom': 60,
        'centerX': 50,
        'centerY': 35,
      });
      final rendered = node.toString();
      expect(rendered.length, lessThan(120));
      expect(rendered, contains('Send message'));
      expect(rendered.contains('Instance of'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // L2..L9 — docs and CI honesty
  // ---------------------------------------------------------------------------
  group('Docs and CI', () {
    test('L8: CI runs analyze and test before building', () {
      // PENDING RUNTIME: not executed.
      final yml = _src('.github/workflows/build.yml');
      final analyze = yml.indexOf('flutter analyze');
      final test = yml.indexOf('flutter test');
      final build = yml.indexOf('flutter build apk');
      expect(analyze, greaterThan(0));
      expect(test, greaterThan(analyze));
      expect(build, greaterThan(test));
    });

    test('L9: the Flutter version is no longer hard-pinned', () {
      // PENDING RUNTIME: not executed.
      final yml = _src('.github/workflows/build.yml');
      expect(yml.contains('flutter-version'), isFalse);
      expect(yml, contains('channel: stable'));
    });

    test('L4: README does not claim 100% local-first by default', () {
      // PENDING RUNTIME: not executed.
      final readme = _src('README.md');
      expect(readme.contains('100%25%20Local--First'), isFalse);
      expect(readme, contains('DeepSeek (cloud) is the default'));
    });

    test('L2/L3: docs point at files that exist', () {
      // PENDING RUNTIME: not executed.
      final readme = _src('README.md');
      expect(readme.contains('screens/home/home_screen.dart'), isFalse);
      expect(File('lib/screens/hud/hud_home_screen.dart').existsSync(), isTrue);

      final perms = _src('lib/screens/settings/permissions_screen.dart');
      expect(perms.contains('permissions.html'), isFalse);
      expect(perms, contains('permission.html'));
    });

    test('L6: the Flutter TODO comment is gone from applicationId', () {
      // PENDING RUNTIME: not executed.
      final gradle = _src('android/app/build.gradle.kts');
      expect(gradle.contains('TODO: Specify your own unique Application ID'),
          isFalse);
    });
  });
}
