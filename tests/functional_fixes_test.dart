// PENDING RUNTIME: not executed — no Flutter/Dart SDK on this machine.
//
// Regression specifications for the functional fixes (U1, U2, U3, H1, H2, H3,
// H6, H7, H8, H10, M4). Every test describes behaviour that was verified
// statically against the patched source; none of them has been run.
//
// To execute later, from the project root:
//   flutter test tests/functional_fixes_test.dart
//
// The file lives in `tests/` rather than `test/` because it was produced as a
// deliverable for review; move it into `test/` to have `flutter test` pick it
// up automatically.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:private_agent/services/ai_service.dart';
import 'package:private_agent/services/contact_disambiguation_service.dart';
import 'package:private_agent/services/jarvis_service.dart';
import 'package:private_agent/services/phone_storage_service.dart';

const String _kotlinRoot = 'android/app/src/main/kotlin/com/jarvis/dev';

String _src(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // U3 + M8 — the intent router must not act on substrings
  // ---------------------------------------------------------------------------
  group('U3/M8: whole-word intent routing', () {
    test('a sentence that merely contains "commute" never mutes the phone', () {
      // PENDING RUNTIME: not executed.
      final intent = JarvisIntent.fallback('my commute took an hour today');
      expect(intent.type, isNot(JarvisIntentType.system));
      expect(intent.systemCommand, isNot('mute'));
    });

    test('"silence of the lambs" is not a mute command', () {
      // PENDING RUNTIME: not executed.
      final intent = JarvisIntent.fallback('silence of the lambs');
      expect(intent.systemCommand, isNot('mute'));
    });

    test('an explicit mute command still mutes', () {
      // PENDING RUNTIME: not executed.
      expect(JarvisIntent.fallback('mute').systemCommand, 'mute');
      expect(
        JarvisIntent.fallback('please mute the phone').systemCommand,
        'mute',
      );
      expect(JarvisIntent.fallback('silence').systemCommand, 'mute');
    });

    test('"matching contacts" is not a sports request', () {
      // PENDING RUNTIME: not executed.
      final intent = JarvisIntent.fallback('find matching contacts for me');
      expect(intent.type, isNot(JarvisIntentType.sports));
    });

    test('device temperature is not a weather request', () {
      // PENDING RUNTIME: not executed.
      final intent = JarvisIntent.fallback('what is the temperature of the cpu');
      expect(intent.type, isNot(JarvisIntentType.weather));
    });

    test('a real weather question still routes to weather', () {
      // PENDING RUNTIME: not executed.
      expect(
        JarvisIntent.fallback('what is the weather in paris').type,
        JarvisIntentType.weather,
      );
    });

    test('news still routes to news', () {
      // PENDING RUNTIME: not executed.
      expect(
        JarvisIntent.fallback('read me the latest news').type,
        JarvisIntentType.news,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // H1 — the storage bridge contract
  // ---------------------------------------------------------------------------
  group('H1: PhoneStorageService append contract', () {
    const channel = MethodChannel('com.jarvis.dev/accessibility');
    late Map<String, dynamic> captured;

    setUp(() {
      captured = <String, dynamic>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        captured = Map<String, dynamic>.from(call.arguments as Map);
        return <String, dynamic>{'success': true};
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('append:true sends action "write" plus append:true', () async {
      // PENDING RUNTIME: not executed.
      await PhoneStorageService.instance.createFile(
        fileName: 'notes.txt',
        content: 'more',
        append: true,
      );
      expect(captured['action'], 'write');
      expect(captured['append'], true);
      expect(captured['action'], isNot('edit'));
    });

    test('append:false also sends action "write" with append:false', () async {
      // PENDING RUNTIME: not executed.
      await PhoneStorageService.instance.createFile(
        fileName: 'notes.txt',
        content: 'fresh',
      );
      expect(captured['action'], 'write');
      expect(captured['append'], false);
    });
  });

  // ---------------------------------------------------------------------------
  // Source contracts — these assert that the native side really changed.
  // ---------------------------------------------------------------------------
  group('Native source contracts', () {
    test('H3: MainActivity uses a whole-word wake-word regex and drops the '
        'old look-alikes', () {
      // PENDING RUNTIME: not executed.
      final src = _src('$_kotlinRoot/MainActivity.kt');
      expect(src, contains('WAKE_WORD_PATTERN'));
      expect(src, contains('hasWakeWord'));
      for (final bad in const ['"service"', '"google"', '"travis"', '"harvest"']) {
        expect(src.contains('contains($bad)'), isFalse,
            reason: '$bad must no longer be a wake word');
      }
    });

    test('H6: permissionReport requires every member of a capability group', () {
      // PENDING RUNTIME: not executed.
      final src = _src('$_kotlinRoot/DeviceControlManager.kt');
      expect(src, contains('relevant.all { c.isGranted(it) }'));
    });

    test('H7: the accessibility dump recycles nodes and is depth bounded', () {
      // PENDING RUNTIME: not executed.
      final src = _src('$_kotlinRoot/AgentAccessibilityService.kt');
      expect(src, contains('MAX_TRAVERSE_DEPTH'));
      expect(src, contains('recycleQuietly'));
      expect(src, contains('node?.recycle()'));
    });

    test('H8: frame capture is off the platform thread', () {
      // PENDING RUNTIME: not executed.
      final src = _src('$_kotlinRoot/MainActivity.kt');
      expect(src, contains('ioExecutor.execute'));
      expect(src, contains('mainHandler.post { result.success(payload) }'));
    });

    test('C1: storage paths are canonicalised before use', () {
      // PENDING RUNTIME: not executed.
      final src = _src('$_kotlinRoot/MainActivity.kt');
      expect(src, contains('resolveStorageChild'));
      expect(src, contains('canonicalFile'));
      expect(src, contains('INVALID_PATH'));
    });

    test('H5: SMS and calls require explicit confirmation', () {
      // PENDING RUNTIME: not executed.
      final src = _src('$_kotlinRoot/DeviceControlManager.kt');
      expect(src, contains('requiresConfirmation'));
      expect(src, contains('confirmed'));
    });

    test('H9: BootReceiver is not exported', () {
      // PENDING RUNTIME: not executed.
      final manifest = _src('android/app/src/main/AndroidManifest.xml');
      final bootIndex = manifest.indexOf('.BootReceiver');
      expect(bootIndex, greaterThan(0));
      final window = manifest.substring(bootIndex, bootIndex + 400);
      expect(window, contains('android:exported="false"'));
    });
  });

  // ---------------------------------------------------------------------------
  // U1 / U2 — voice lifecycle source contracts
  // ---------------------------------------------------------------------------
  group('Voice lifecycle contracts', () {
    test('U1: automatic mic restarts are gated on always-on', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/jarvis_service.dart');
      expect(src, contains('_canAutoListen'));
      expect(src, contains('_shouldListenContinuously && _canAutoListen'));
    });

    test('U1/M4: opening the HUD no longer arms gestures unconditionally', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/jarvis_service.dart');
      final onEnter = src.indexOf('void onEnterJarvisMode()');
      expect(onEnter, greaterThan(0));
      final body = src.substring(onEnter, onEnter + 900);
      expect(body.contains('AirGestureService.instance.start()'), isFalse);
    });

    test('U2/H2: the fixed 7 s timeout is gone and double audio is guarded', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/voice_service.dart');
      expect(src.contains('Duration(seconds: 7)'), isFalse);
      expect(src, contains('EdgeTtsService.instance.isSpeaking'));
    });

    test('M4: a failed sensor reports disabled, not "software mode"', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/air_gesture_service.dart');
      expect(src.contains('_isEnabled = true; // allow software simulation'),
          isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // A1 — same-name contacts are resolved by digit chain, never by guessing
  // ---------------------------------------------------------------------------
  group('A1: same-name contacts', () {
    // The three numbers from the reported example.
    const jarvis = [
      ContactCandidate(name: 'Jarvis', number: '+1 555 010 4432'),
      ContactCandidate(name: 'Jarvis', number: '+1 555 010 9917'),
      ContactCandidate(name: 'Jarvis', number: '0555 010 5550'),
    ];

    test('last three digits are extracted for the read-back', () {
      // PENDING RUNTIME: not executed.
      expect(jarvis[0].lastThree, '432');
      expect(jarvis[1].lastThree, '917');
      expect(jarvis[2].lastThree, '550');
      expect(const ContactCandidate(name: 'x', number: '12').lastThree, '12');
      expect(const ContactCandidate(name: 'x', number: '--').lastThree, '');
    });

    test('digits are read from numerals, separators and spoken words', () {
      // PENDING RUNTIME: not executed.
      expect(ContactDisambiguationService.spokenDigits('4-3-2'), '432');
      expect(
        ContactDisambiguationService.spokenDigits('ending in four three two'),
        '432',
      );
      expect(
        ContactDisambiguationService.spokenDigits('nine, one, seven'),
        '917',
      );
      expect(
        ContactDisambiguationService.spokenDigits('the last digit is oh'),
        '0',
      );
      expect(
        ContactDisambiguationService.spokenDigits('which one do you want'),
        '1',
      );
    });

    test('ordinals are only read when the user picks by position', () {
      // PENDING RUNTIME: not executed.
      expect(ContactDisambiguationService.ordinalIndex('number two'), 2);
      expect(ContactDisambiguationService.ordinalIndex('option 3'), 3);
      expect(ContactDisambiguationService.ordinalIndex('the second one'), 2);
      // "one" here is a pronoun, not a choice — the digits carry the intent.
      expect(
        ContactDisambiguationService.ordinalIndex('the one ending in 4 3 2'),
        isNull,
      );
      expect(ContactDisambiguationService.ordinalIndex('4 3 2'), isNull);
    });

    test('a unique digit tail resolves the choice', () {
      // PENDING RUNTIME: not executed.
      final resolved = ContactDisambiguationService.narrow(
        'ending in four three two',
        jarvis,
      );
      expect(resolved, hasLength(1));
      expect(resolved.single.number, '+1 555 010 4432');
    });

    test('an ordinal resolves the choice', () {
      // PENDING RUNTIME: not executed.
      final resolved =
          ContactDisambiguationService.narrow('number three', jarvis);
      expect(resolved, hasLength(1));
      expect(resolved.single.number, '0555 010 5550');
    });

    test('a shared digit tail stays ambiguous instead of picking one', () {
      // PENDING RUNTIME: not executed.
      const pair = [
        ContactCandidate(name: 'A', number: '111 32'),
        ContactCandidate(name: 'B', number: '222 32'),
      ];
      final narrowed =
          ContactDisambiguationService.narrow('ending in three two', pair);
      expect(narrowed, hasLength(2));
      expect(narrowed.map((c) => c.name), ['A', 'B']);
    });

    test('zero matches yields an empty list, never a guess', () {
      // PENDING RUNTIME: not executed.
      expect(
        ContactDisambiguationService.narrow('ending in 0 0 0', jarvis),
        isEmpty,
      );
      expect(ContactDisambiguationService.narrow('', jarvis), isEmpty);
    });

    test('a spoken digit chain longer than the number never matches', () {
      // PENDING RUNTIME: not executed.
      expect(
        ContactDisambiguationService.narrow(
          '1 2 3 4 5 6 7 8 9 0 1 2',
          jarvis,
        ),
        isEmpty,
      );
    });

    test('the read-back names every candidate by position and last digits', () {
      // PENDING RUNTIME: not executed.
      final prompt = ContactDisambiguationService.buildPrompt('Jarvis', jarvis);
      expect(prompt, contains('I found 3 numbers for Jarvis'));
      expect(prompt, contains('Number one, ending in 4-3-2.'));
      expect(prompt, contains('Number two, ending in 9-1-7.'));
      expect(prompt, contains('Number three, ending in 5-5-0.'));
      expect(prompt, contains('Which one do you want to call, sir?'));
    });

    test('only an explicit refusal cancels the question', () {
      // PENDING RUNTIME: not executed.
      expect(ContactDisambiguationService.isCancellation('never mind'), isTrue);
      expect(ContactDisambiguationService.isCancellation('Cancel.'), isTrue);
      expect(ContactDisambiguationService.isCancellation('ending in 4 3 2'),
          isFalse);
      expect(ContactDisambiguationService.isCancellation('number two'),
          isFalse);
    });

    test('an unrelated sentence drops the pending question', () {
      // PENDING RUNTIME: not executed.
      expect(
        ContactDisambiguationService.looksLikeNewCommand(
          'what is the weather tomorrow',
        ),
        isTrue,
      );
      expect(
        ContactDisambiguationService.looksLikeNewCommand('ending in 4 3 2'),
        isFalse,
      );
      expect(
        ContactDisambiguationService.looksLikeNewCommand('number two'),
        isFalse,
      );
    });

    test('native matches are parsed and blanks dropped', () {
      // PENDING RUNTIME: not executed.
      final result = <String, dynamic>{
        'success': false,
        'requiresChoice': true,
        'count': 3,
        'matches': [
          {'name': 'Jarvis', 'number': '+1 555 010 4432', 'source': 'contact'},
          {'name': 'Jarvis', 'number': '+1 555 010 9917', 'source': 'callHistory'},
          {'name': '', 'number': '+1 555 010 0000'},
          {'name': 'NoNumber', 'number': ''},
        ],
      };
      final parsed =
          ContactDisambiguationService.candidatesFromResult(result);
      expect(parsed, hasLength(2));
      expect(parsed[1].source, 'callHistory');
    });

    test('the Kotlin resolver returns every match and never a best guess', () {
      // PENDING RUNTIME: not executed.
      final src = _src(
        'android/app/src/main/kotlin/com/jarvis/dev/DeviceControlManager.kt',
      );
      expect(src, contains('"requiresChoice" to true'));
      expect(src, contains('CallLog.Calls.CACHED_NAME'));
      // The old "break on the first exact match" behaviour must be gone.
      expect(src.contains('if (exact != null) break'), isFalse);
      expect(src.contains('val match = exact ?: fuzzy'), isFalse);
    });

    test('the agent pipeline refuses ambiguous contacts instead of dialling', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/task_executor.dart');
      expect(src, contains("contact['requiresChoice'] == true"));
      expect(src, contains('_ambiguousContactText'));
      // Two call sites: SMS recipient and call number.
      expect(
        RegExp(r"contact\['requiresChoice'\] == true").allMatches(src).length,
        2,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // A7 — auto-started sessions need the wake word; taps never do
  // ---------------------------------------------------------------------------
  group('A7: session origin gating', () {
    test('ambient speech in an auto session is rejected without the wake word',
        () {
      // PENDING RUNTIME: not executed.
      expect(
        JarvisService.acceptAmbientTranscript(
          fromManualSession: false,
          isAwake: false,
          hasWakeWord: false,
        ),
        isFalse,
      );
    });

    test('a tapped session is always accepted', () {
      // PENDING RUNTIME: not executed.
      expect(
        JarvisService.acceptAmbientTranscript(
          fromManualSession: true,
          isAwake: false,
          hasWakeWord: false,
        ),
        isTrue,
      );
    });

    test('an awake assistant accepts follow-up speech', () {
      // PENDING RUNTIME: not executed.
      expect(
        JarvisService.acceptAmbientTranscript(
          fromManualSession: false,
          isAwake: true,
          hasWakeWord: false,
        ),
        isTrue,
      );
    });

    test('the wake word alone is enough in an auto session', () {
      // PENDING RUNTIME: not executed.
      expect(
        JarvisService.acceptAmbientTranscript(
          fromManualSession: false,
          isAwake: false,
          hasWakeWord: true,
        ),
        isTrue,
      );
    });

    test('native payload carries the session origin on every result', () {
      // PENDING RUNTIME: not executed.
      final src = _src('$_kotlinRoot/MainActivity.kt');
      expect(src, contains('private var isManualSession = false'));
      expect(src, contains('isManualSession = manual'));
      // An auto restart must clear the flag, or one tap disables the wake-word
      // filter for the rest of the continuous session.
      expect(src, contains('isManualSession = false'));
      expect(
        RegExp(r'"manualSession" to isManualSession').allMatches(src).length,
        3,
        reason: 'partial, final and error payloads must all carry the origin',
      );
    });

    test('Dart records both flags before the speech callback fires', () {
      // PENDING RUNTIME: not executed.
      final src = _src('lib/services/voice_service.dart');
      final handler = src.indexOf("case 'onSpeechResult':");
      expect(handler, greaterThan(0));
      final body = src.substring(handler, handler + 1200);
      expect(body, contains('lastResultHadWakeWord'));
      expect(body, contains("args?['manualSession']"));
      expect(
        body.indexOf('lastSessionWasManual'),
        lessThan(body.indexOf('onSpeechResult?.call')),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // A12 — the two permission catalogs must describe the same app
  // ---------------------------------------------------------------------------
  group('A12: permission catalogs', () {
    test('undeclared permissions are no longer requested', () {
      // PENDING RUNTIME: not executed.
      final kotlin =
          _src('$_kotlinRoot/DeviceControlManager.kt');
      final manifest = _src('android/app/src/main/AndroidManifest.xml');
      for (final permission in const [
        'BLUETOOTH_ADVERTISE',
        'BODY_SENSORS_BACKGROUND',
      ]) {
        expect(kotlin.contains('Manifest.permission.$permission'), isFalse,
            reason: '$permission is not declared in the manifest');
        expect(manifest.contains('android.permission.$permission'), isFalse);
      }
    });

    test('every AppPermissionType has a code plate and a request branch', () {
      // PENDING RUNTIME: not executed.
      final service = _src('lib/services/permission_manager_service.dart');
      final screen = _src('lib/screens/settings/permissions_screen.dart');
      final enumMatch =
          RegExp(r'enum AppPermissionType \{([\s\S]*?)\}').firstMatch(service);
      expect(enumMatch, isNotNull);
      final values = enumMatch!
          .group(1)!
          .split('\n')
          .map((line) => line.trim().replaceAll(',', ''))
          .where((line) => line.isNotEmpty && !line.startsWith('//'))
          .toList();
      expect(values, hasLength(25));
      for (final value in values) {
        expect(service, contains('case AppPermissionType.$value:'),
            reason: 'requestPermission() has no branch for $value');
        expect(screen, contains('AppPermissionType.$value:'),
            reason: 'the Hub has no code plate for $value');
      }
    });

    test('every AppPermissionType is reachable from a Hub sector', () {
      // PENDING RUNTIME: not executed.
      final service = _src('lib/services/permission_manager_service.dart');
      final screen = _src('lib/screens/settings/permissions_screen.dart');
      final values = RegExp(r'enum AppPermissionType \{([\s\S]*?)\}')
          .firstMatch(service)!
          .group(1)!
          .split('\n')
          .map((line) => line.trim().replaceAll(',', ''))
          .where((line) => line.isNotEmpty && !line.startsWith('//'));
      final sectorsStart =
          screen.indexOf('List<(String, List<AppPermissionType>)> _sectors = [');
      expect(sectorsStart, greaterThan(0));
      final sectors = screen.substring(sectorsStart);
      for (final value in values) {
        expect(sectors, contains('AppPermissionType.$value,'),
            reason: 'no sector row renders $value');
      }
    });
  });
}
