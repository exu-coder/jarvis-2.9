// PENDING RUNTIME: not executed — no Flutter/Dart SDK on this machine.
//
// Regression specifications for the security slice (C1, C2, C3, C4, C6, H5, H9).
// Static verification only; every test below is unexecuted.
//
// To run later, from the project root:
//   flutter test tests/security_fixes_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _src(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // C2 — secrets must not live in SharedPreferences
  // ---------------------------------------------------------------------------
  group('C2: secret storage', () {
    test('a legacy plaintext API key is migrated out of SharedPreferences',
        () async {
      // PENDING RUNTIME: not executed.
      SharedPreferences.setMockInitialValues({'ai_api_key': 'legacy-plain-key'});
      final settings = SettingsService.instance;
      await settings.init();

      // The value is available to callers...
      expect(settings.apiKey, 'legacy-plain-key');

      // ...but the plaintext copy is gone from prefs (and therefore from
      // Android auto-backup).
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ai_api_key'), isNull);
    });

    test('setting a key never writes it to SharedPreferences', () async {
      // PENDING RUNTIME: not executed.
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService.instance;
      await settings.init();
      await settings.setApiKey('sk-test-value');
      await settings.setTelegramToken('123:abc');

      expect(settings.apiKey, 'sk-test-value');
      expect(settings.telegramToken, '123:abc');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('ai_api_key'), isNull);
      expect(prefs.getString('telegram_token'), isNull);
    });

    test('settings source uses secure storage, not prefs, for both secrets', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/settings_service.dart');
      expect(src, contains('FlutterSecureStorage'));
      expect(src.contains("setString('ai_api_key'"), isFalse);
      expect(src.contains("setString('telegram_token'"), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // C2/C6 — manifest hardening
  // ---------------------------------------------------------------------------
  group('C6: manifest', () {
    test('backups disabled and cleartext traffic off', () {
      // PENDING RUNTIME: not executed.
      final manifest = _src('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
      expect(manifest, contains('android:networkSecurityConfig'));
    });

    test('local hosts stay reachable through the network security config', () {
      // PENDING RUNTIME: not executed.
      final nsc = _src('android/app/src/main/res/xml/network_security_config.xml');
      // Home Assistant and Ollama are plain-HTTP on the LAN/loopback, so a
      // blanket cleartext ban would silently break them.
      expect(
        nsc,
        contains('<domain includeSubdomains="true">local</domain>'),
      );
      expect(nsc, contains('<domain includeSubdomains="false">127.0.0.1</domain>'));
      expect(nsc, contains('<base-config cleartextTrafficPermitted="false" />'));
    });

    test('backup exclusions cover Android 12+ data extraction', () {
      // PENDING RUNTIME: not executed.
      final manifest = _src('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android:dataExtractionRules'));
      final rules = _src('android/app/src/main/res/xml/data_extraction_rules.xml');
      expect(rules, contains('<cloud-backup>'));
      expect(rules, contains('<device-transfer>'));
      expect(rules, contains('domain="sharedpref"'));
    });

    test('system-bound components keep exported=true, the rest do not', () {
      // PENDING RUNTIME: not executed.
      final manifest = _src('android/app/src/main/AndroidManifest.xml');
      for (final systemBound in const [
        '.AgentAccessibilityService',
        '.InboxNotificationListenerService',
        '.JarvisDeviceAdminReceiver',
      ]) {
        final at = manifest.indexOf(systemBound);
        expect(at, greaterThan(0), reason: '$systemBound missing');
        final window = manifest.substring(at, at + 700);
        expect(window, contains('android:exported="true"'),
            reason: '$systemBound must remain exported — the system binds it');
      }
      final boot = manifest.indexOf('.BootReceiver');
      expect(manifest.substring(boot, boot + 400),
          contains('android:exported="false"'));
    });
  });

  // ---------------------------------------------------------------------------
  // C3 — Telegram pairing replaces implicit ownership
  // ---------------------------------------------------------------------------
  group('C3: Telegram pairing', () {
    test('generated codes are always six digits', () {
      // PENDING RUNTIME: not executed.
      for (var i = 0; i < 200; i++) {
        final code = SettingsService.generateTelegramPairCode();
        expect(code.length, 6);
        expect(RegExp(r'^\d{6}$').hasMatch(code), isTrue);
      }
    });

    test('validator rejects wrong, empty and expired codes', () {
      // PENDING RUNTIME: not executed.
      const now = 1000000;
      expect(
        SettingsService.isTelegramPairCodeValid(
          stored: '123456',
          expiresAtMs: now + 1000,
          candidate: '123457',
          nowMs: now,
        ),
        isFalse,
      );
      expect(
        SettingsService.isTelegramPairCodeValid(
          stored: '123456',
          expiresAtMs: now + 1000,
          candidate: '123456',
          nowMs: now + 1001,
        ),
        isFalse,
        reason: 'expired codes must not work',
      );
      expect(
        SettingsService.isTelegramPairCodeValid(
          stored: '',
          expiresAtMs: now + 1000,
          candidate: '',
          nowMs: now,
        ),
        isFalse,
      );
    });

    test('validator accepts the live code', () {
      // PENDING RUNTIME: not executed.
      const now = 1000000;
      expect(
        SettingsService.isTelegramPairCodeValid(
          stored: '654321',
          expiresAtMs: now + 600000,
          candidate: '654321',
          nowMs: now,
        ),
        isTrue,
      );
    });

    test('a code can be redeemed exactly once', () async {
      // PENDING RUNTIME: not executed.
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService.instance;
      await settings.init();

      final code = await settings.issueTelegramPairCode();
      expect(settings.telegramPairCodeIsActive, isTrue);

      expect(await settings.consumeTelegramPairCode(code), isTrue);
      expect(settings.telegramPairCodeIsActive, isFalse);
      expect(await settings.consumeTelegramPairCode(code), isFalse);
    });

    test('telegram service has no "first chat becomes owner" path', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/telegram_service.dart');
      expect(src, contains('/pair'));
      expect(src.contains('First contact becomes the owner'), isFalse);
      expect(src.contains('allowed.isEmpty && owner.isEmpty'), isFalse);
    });

    test('A6: revoking Telegram clears chats, pairing code and bot token', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/settings_service.dart');
      final start = src.indexOf('Future<void> revokeTelegramAccess()');
      expect(start, greaterThan(0));
      final body = src.substring(start, start + 700);
      expect(body, contains('setTelegramAllowedChats(const [])'));
      expect(body, contains('clearTelegramPairCode()'));
      expect(body, contains("setTelegramToken('')"));
    });

    test('A6: the settings screen exposes pair and revoke, and never calls '
        'the removed owner-chat setter', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/screens/settings/settings_screen.dart');
      expect(src, contains('_showPairCodeDialog'));
      expect(src, contains('_revokeTelegramAccess'));
      // This exact call was a compile break after setTelegramOwnerChatId was
      // deleted; it must not come back.
      expect(src.contains('setTelegramOwnerChatId'), isFalse);
      // The bot token must be revoked through SettingsService, not just
      // unpaired locally.
      expect(src, contains('revokeTelegramAccess'));
    });

    test('A6: a revoked token cannot be resurrected from the UI controllers',
        () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/screens/settings/settings_screen.dart');
      final start = src.indexOf('Future<void> _revokeTelegramAccess()');
      expect(start, greaterThan(0));
      final body = src.substring(start, start + 900);
      expect(body, contains('_tokenController.clear()'));
      expect(body, contains('_chatsController.clear()'));
      expect(body, contains('_telegram.stop()'));
    });

    test('C3: repeated wrong pair codes lock the bridge out', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/settings_service.dart');
      expect(src, contains('maxPairAttempts'));
      expect(src, contains('_pairFailKey'));
    });
  });

  // ---------------------------------------------------------------------------
  // C4 — release signing scaffold
  // ---------------------------------------------------------------------------
  group('C4: release signing', () {
    test('a release signing config exists and is selected when a keystore is '
        'present', () {
      // PENDING RUNTIME: not executed.
      final gradle = _src('android/app/build.gradle.kts');
      expect(gradle, contains('signingConfigs'));
      expect(gradle, contains('create("release")'));
      expect(gradle, contains('hasReleaseSigning'));
      // The debug fallback must be conditional and loud, not unconditional.
      expect(gradle, contains('DEBUG-SIGNED'));
    });

    test('a keystore template ships without secrets', () {
      // PENDING RUNTIME: not executed.
      final example = _src('android/key.properties.example');
      expect(example, contains('storeFile'));
      expect(example, contains('keyAlias'));
      expect(example.contains('storePassword='), isTrue);
      // No real credential is committed.
      expect(example.contains('changeit'), isFalse);
    });
  });
}
