J.A.R.V.I.S. (exu-coder/jarvis-2.9) — Bug & Security Audit Report (Revised)

Repository: https://github.com/exu-coder/jarvis-2.9
Commit reviewed: b573599 (branch main)
Size: 156 files, ~28.6k LOC (Flutter/Dart + Kotlin)
Method: Full static review of build config, manifest, all Dart services/screens, all 10 Kotlin files, tests, CI, README
Not executed: flutter analyze / flutter test (no Flutter/Dart SDK on the review machine) — "test failure" findings are by code inspection
Machine-verified: All relative/package imports resolve (0 missing); every SharedPreferences key that is read is also written (all paired)
Deployment context: Personal use, single trusted user


SEVERITY SUMMARY

Critical: 5 — Path traversal, plaintext secrets, unauthenticated Telegram ownership, debug-signed release, 95 permissions
High: 10 — Broken file-append, double audio, loose wake word, fabricated telemetry, unconfirmed SMS/calls, node leak, failing tests
Medium: 13 — ToS-violating TTS DRM, resource leaks, missing dispose, phantom "enabled" states, main-thread I/O, 74 swallowed exceptions
Low: 12 — README/reality drift, dead assets, duplicated crypto, no analyze/test in CI
User-reported: 3 — Mic auto-start, mic auto-shut after speech, AI auto-silences the phone


USER-REPORTED RUNTIME BUGS

These are bugs actually experienced on the device. They were not in the original report.

U1. Microphone starts automatically the first time the user speaks

Symptom: The TTS model / microphone opens on its own the first time the user speaks, without any press.

Likely cause (to confirm):
- JarvisService.onEnterJarvisMode arms listening unconditionally (same pattern as M4).
- jarvisAlwaysOn defaults to false (settings_service.dart:237), but the voice path may still call startListening() from voice_service.dart on first interaction without checking that flag.
- The wake-word listener in MainActivity.kt (onResults ~656 / onPartialResults ~683) may forward partial results that trigger the Dart-side voice loop.

Impact: Mic is hot when not expected. Privacy surprise + battery drain.

Fix direction: Gate every startListening() behind an explicit action; honor jarvisAlwaysOn everywhere; add a visible "mic on" indicator.

Clarification needed: Mic opens at app launch, at voice-button tap, or at wake word?


U2. Microphone shuts off automatically after the user finishes speaking

Symptom: Every time the user speaks, the microphone closes automatically after speech ends.

Likely cause (to confirm):
- voice_service.dart uses a 7-second timeout (line 286) — the same timeout that causes H2 (double audio). If the user speaks longer than 7 s, the future reports failure while native playback is still running, and the code falls back to _tts.speak(clean) at line 308 — two voices at once.
- The Dart voice loop likely treats "future returned" as "stop listening" and closes the mic regardless of whether speech actually ended.

Impact: Long sentences get cut; or the user hears double audio; either way voice interaction is unreliable.

Fix direction: Replace the 7 s wall-clock timeout with real end-of-speech detection; close the mic only on real end-of-speech or user cancel.

Clarification needed: Does the mic close too early (cutting you off), or close correctly and the bug is the double audio that follows?


U3. AI automatically silences the phone whenever the user speaks to it

Symptom: Whenever the user talks to the AI, the phone goes silent (ringer off / media muted) by itself.

Likely cause (to confirm):
- The keyword intent router in ai_service.dart:341–345, 456, 512, 583 does substring matching on mute (see M8). Ordinary sentences containing "mute", "silence", "quiet" can route to the mute intent.
- The mute action is executed by DeviceControlManager with no confirmation (same code path as H5). With no word boundaries, ordinary speech can hit it.
- Possibly JarvisService.onEnterJarvisMode also mutes media when entering Jarvis mode.

Impact: The phone mutes mid-conversation. Missed calls, missed alarms. Most disruptive of the three.

Fix direction: Do not auto-execute mute — require an exact command phrase or a confirmation; add word boundaries to the keyword router (\bmute\b, \bsilence\b); log every intent match with the matched substring; remove any mute side effect in onEnterJarvisMode.

Clarification needed: Which path fires — (a) keyword router, (b) onEnterJarvisMode side effect, or (c) both?


CRITICAL — SECURITY & DATA LOSS

C1. Path traversal in the file tool

File: android/app/src/main/kotlin/com/jarvis/dev/MainActivity.kt:1527–1595

    val fileName = call.argument<String>("fileName") ?: ""   // 1530 — never sanitized
    val file = File(targetDir, fileName)                     // 1542
    file.writeText(content)

fileName comes straight from the LLM/agent via PhoneStorageService.createFile and is never sanitized. A value such as ../../shared_prefs/ai_api_key.xml reads, overwrites, or deletes anything the app can reach. In a single-user deployment this is not an external attack path, but a typo, a bad agent response, or a confused reply can still destroy app data. The "read" (1558) and "delete" (1588) branches are equally unguarded.

Fix: resolve the canonical path and assert it stays inside targetDir:

    val file = File(targetDir, fileName).canonicalFile
    if (!file.path.startsWith(targetDir.canonicalPath + File.separator)) {
        result.error("INVALID_PATH", "Illegal file name", null); return@setMethodCallHandler
    }


C2. API key and Telegram bot token stored in plaintext

File: lib/services/settings_service.dart:101–103 (and the same pattern for the Telegram token)

Secrets are written with _prefs?.setString('ai_api_key', ...) — plain SharedPreferences, no Keystore/EncryptedSharedPreferences. android:allowBackup is not set to false, so the values are included in Google auto-backup and are readable by any rooted or ADB-enabled device. The Telegram token is additionally embedded in the request URL (lib/services/telegram_service.dart:33), so it leaks into any proxy or log.

Fix: use flutter_secure_storage (Keystore-backed), set android:allowBackup="false", and send the Telegram token in a header/body rather than the path.


C3. Telegram "first chat becomes owner" = unauthenticated remote device control

File: lib/services/telegram_service.dart:104–117

    if (allowed.isEmpty && owner.isEmpty) { /* remember this chat as owner */ }
    final isAuthorized = allowed.contains(chatId) || (allowed.isEmpty && chatId == owner);

Anyone who finds the bot username and sends /start before the legitimate owner becomes the owner, and can then run arbitrary agent tasks — SMS, calls, file writes, screen automation — from anywhere on the internet. There is no pairing code, no on-device confirmation, and no expiry. This is a real risk even for a personal-use deployment, because the bot username is public.

Fix: require a short pairing code displayed on the phone; drop the implicit-ownership path entirely.


C4. Release APK signed with the debug key

File: android/app/build.gradle.kts:36

    signingConfig = signingConfigs.getByName("debug")

The shipped "release" is debug-signed. It cannot be published to Play, and because the Android debug keystore is publicly known, anyone can sign a malicious replacement that installs as an upgrade over the genuine app.


C5. Overlay WebView: JS built by string concatenation

File: android/app/src/main/kotlin/com/jarvis/dev/BubbleOverlayService.kt

deliverReply() builds JavaScript by string concatenation and escapes only \ " \n \r. U+2028 / U+2029 still terminate the literal, and replies containing a single quote break out of single-quoted JS strings — so an agent reply that happens to contain those characters breaks the overlay display. (This is a correctness bug, not an external attack path in a single-user deployment.) The WebView is also never destroy()ed when the service stops, leaking the WebView.

Fix: build the JS with JSON.stringify / a proper encoder; call destroy() in onDestroy().


C6. 95 permissions, cleartext traffic, and exported components

File: android/app/src/main/AndroidManifest.xml

- :142 android:usesCleartextTraffic="true" — all traffic (including API keys) may travel unencrypted.
- 95 unique permissions, including SEND_SMS, READ_SMS, READ/WRITE_CALL_LOG, MANAGE_EXTERNAL_STORAGE, QUERY_ALL_PACKAGES, REQUEST_INSTALL_PACKAGES, SYSTEM_ALERT_WINDOW, WRITE_SETTINGS, ACCESS_BACKGROUND_LOCATION, BODY_SENSORS_BACKGROUND, INTERACT_ACROSS_USERS_FULL, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS.
- Exported components: MainActivity (149), AgentAccessibilityService (209), InboxNotificationListenerService (233), BootReceiver (247), JarvisDeviceAdminReceiver (260).

Play Store would reject the app; sideloaded, the permission set is very broad and should be pruned to what is actually used.


HIGH — REAL FUNCTIONAL BUGS

H1. append: true file writes always fail

Files: lib/services/phone_storage_service.dart -> MainActivity.kt:1537

Dart sends 'action': append ? 'edit' : 'create', but the native handler only accepts "create" | "write" | "read" | "list" | "delete". "edit" falls through to UNKNOWN_ACTION, so every "append to my notes/log" feature is silently broken. The native code already supports appending through the separate append boolean — the Dart side just never reaches that branch.

Fix: send action: 'write' (or 'create') and let the append flag do the work.


H2. Double audio from the 7-second TTS timeout

File: lib/services/voice_service.dart:286

    .timeout(const Duration(seconds: 7), onTimeout: () => false)

For any utterance whose synthesis + playback exceeds 7 s (common for long replies), the future reports failure while native playback is still running, and the code then falls back to _tts.speak(clean) at line 308 — producing two voices at once. The fallback path itself uses a sensible 60 s timeout (line 311). Related to U2.


H3. Wake-word list matches ordinary speech

File: MainActivity.kt:529–545

    lower.contains("travis") || lower.contains("service") || lower.contains("davis") ||
    lower.contains("davies") || lower.contains("harvest") || lower.contains("google") ||
    lower.contains("jarvi")

"Customer service", "Google it", "Harvest festival" all arm the microphone. Worse, onResults (656) and onPartialResults (683) forward every hypothesis even when no wake word matched (?: matches?.firstOrNull()), so the Dart layer receives all ambient speech and is the only filter.


H4. Fabricated telemetry presented as real data

- lib/services/network_audit_service.dart:181–206 — on any exception the service returns a hardcoded "report": localIp 192.168.1.105, fake gateway 192.168.1.1, pingLatencyMs: 14. _ping() (222–235) returns synthetic latency and the security score is clamped rather than computed. The UI presents this as a live network audit.
- lib/services/smart_home_service.dart:141–156 — on failure three invented SmartDeviceEntity rows (lights/thermostat) are injected into the device list, so users toggle phantom devices.

Fix: surface the error; never substitute invented data for telemetry.


H5. SMS and phone calls executed with no confirmation

File: android/app/src/main/kotlin/com/jarvis/dev/DeviceControlManager.kt:458–490

sendSms() calls smsManager.sendTextMessage(...) directly; line 481 fires Intent.ACTION_CALL. Both are reachable from voice, from Telegram (see C3), and from LLM tool calls, with no confirmation dialog and no recipient re-read. A misheard name can text or call anyone.


H6. permissionReport groups permissions as any-of

File: DeviceControlManager.kt:106

A capability group is reported true if any member is granted, so the UI claims SMS/contacts/camera are ready when only one sibling permission is held. Features then throw SecurityException at first use.


H7. Accessibility node leak + unbounded recursion

File: android/app/src/main/kotlin/com/jarvis/dev/AgentAccessibilityService.kt

dumpScreen / traverse never call node.recycle() (the string recycle does not appear anywhere in the file) and recurse with no depth cap. On deep or complex screens this leaks AccessibilityNodeInfo objects and risks stack overflow. The service also runs typeAllMask with flagIncludeNotImportantViews, dumping far more than the agent needs on every loop iteration.


H8. Screenshot quality parameter ignored, capture runs on the platform thread

Files: AgentAccessibilityService.kt, MainActivity.kt, DeviceControlManager.kt

- CORRECTION: the API-30 guard is NOT a finding. `takeScreenshotBase64` already
  returns an `UNSUPPORTED` error for `SDK_INT < R` at b573599, so pre-Android-11
  devices get an explicit error rather than a silent failure. An earlier draft of
  this report claimed otherwise; that bullet is withdrawn.
- The PNG quality parameter is ignored (PNG is lossless), so the value passed by
  the caller silently has no effect.
- ScreenCaptureService.grabFrame() decodes a full-screen Bitmap on the MethodChannel main thread — jank and ANR risk under the agent loop.


H9. BootReceiver accepts unprotected broadcasts

Files: BootReceiver.kt, AndroidManifest.xml:247 (exported="true")

Custom actions such as com.htc.intent.action.QUICKBOOT_POWERON are handled without any permission check, so any installed app can trigger the boot path (start services, arm listening).


H10. Two tests are guaranteed to fail

File: test/widget_test.dart:186,189

    expect(settings.jarvisAlwaysOn, isTrue);
    expect(settings.useNeuralVoice, isTrue);

Both defaults are false in lib/services/settings_service.dart:237 and :260. test/jarvis_features_test.dart contains similar contradictions. CI never runs flutter test, which is why this stays hidden.


MEDIUM

M1. Microsoft Edge-TTS DRM reimplementation. Hand-rolled Sec-MS-GEC token, hard-pinned Chromium 143.0.3650.75, forged Origin/Cookie headers, undocumented endpoint. Breaks whenever Microsoft rotates the version; almost certainly violates the service terms. — lib/services/edge_tts_service.dart:24–29, 511–528

M2. HttpClient never closed — a new instance per synthesis with no close(force: true), and the audio cache under getTemporaryDirectory()/jarvis_audio is never pruned -> socket/FD and disk leak over days of use. — edge_tts_service.dart:511, 528

M3. Missing dispose() — 18 State<...> classes vs 17 dispose implementations; timers in jarvis_service.dart (175, 246, 289, 506, 633) and air_gesture_service.dart:141 are not consistently cancelled, so callbacks fire after teardown. — lib/services/*

M4. Air gestures report "enabled" when the sensor never armed. The start() catch path sets _isEnabled = true ("software mode"); JarvisService.onEnterJarvisMode arms proximity gestures unconditionally -> media toggles fire in a pocket or during a call. Related to U1. — air_gesture_service.dart, jarvis_service.dart:409

M5. Proactive-agent dedup/cooldown is in-memory only — a restart re-fires every suggestion already shown. — proactive_agent_service.dart

M6. Notification bodies kept in RAM indefinitely (MAX_SAVED = 40, no purge on screen-off) and then sent to a cloud LLM — silent PII exfiltration surface. — InboxNotificationListenerService.kt

M7. Main-thread file I/O — readText() / writeText() / length() / listFiles() run directly in the MethodChannel handler; large files or slow storage block the UI thread. — MainActivity.kt:1542–1592

M8. Naive keyword intent router. Substring matching on score, match, news, temperature, mute, screenshot — "find matching contacts" routes to sports, "temperature of the CPU" to weather, "silence of the lambs" to mute. No word boundaries. Likely cause of U3. — lib/services/ai_service.dart:341–345, 456, 512, 583

M9. Unhandled Uri.parse on the user-editable base URL — a malformed value throws out of the chat path instead of raising AiException. — ai_service.dart:884, 1343

M10. 74 empty catch {} blocks in lib/ swallow failures — the reason M2 and H4 go unnoticed at runtime. — repo-wide

M11. Sentry mode: silent front-camera capture auto-sent to Telegram with no visible indicator or per-use consent; several jurisdictions treat this as unlawful covert recording. — sentry_service.dart, MainActivity.kt:300–360

M12. Device admin + accessibility + notification listener requested together, all justified as "productivity" — stalkerware signature; Play Protect flags it. — device_admin_policies.xml, manifest

M13. No dispose() for WebView in BubbleOverlayService — the overlay WebView is never destroyed when the service stops (see C5). — BubbleOverlayService.kt


LOW / CORRECTNESS POLISH

L1. List<ScreenNode> interpolated into an LLM prompt without a compact toString() -> huge, low-value dumps that burn tokens. — proactive_agent_service.dart, lib/models/screen_node.dart

L2. README directory map lists lib/screens/home/home_screen.dart, which does not exist. — README.md

L3. Doc comment points at assets/hud/permissions.html; the file is permission.html. — lib/screens/settings/permissions_screen.dart:9

L4. Badge claims "Privacy: 100% Local-First", but the default provider is DeepSeek cloud and the Ollama toggle is opt-in. — README.md, settings_service.dart:81

L5. Version drift: repo name 2.9, README badge v1.1.0, pubspec.yaml 1.1.0+2. — multiple

L6. applicationId = "com.jarvis.dev" still carries the Flutter TODO comment; generic, collision-prone ID. — android/app/build.gradle.kts:22

L7. jarvisAlwaysOn defaults to false, so main.dart:36 never starts always-on mode even though the README advertises it. Related to U1. — lib/main.dart:36, settings_service.dart:237

L8. CI runs only flutter build apk --debug — no flutter analyze, no flutter test. — .github/workflows/build.yml

L9. flutter-version: '3.50.0' is hard-pinned in CI — will rot and diverge from local builds. — .github/workflows/build.yml

L10. Unused assets shipped in the APK: assets/icon/jarvis_logo.png, assets/images/jarvis_male_hologram_raw.jpg. — pubspec.yaml, assets/

L11. Hand-written SHA-256 implementation inlines ~100 lines of crypto despite crypto already being imported — duplicated, unaudited code. — edge_tts_service.dart:300–400

L12. applicationId/namespace use com.jarvis.dev while Dart package is private_agent — inconsistent identity across the build. — build.gradle.kts, pubspec.yaml


RECOMMENDED FIX ORDER

1. Sanitize fileName (C1) — a one-line change closes the worst data-loss hole.
2. Move secrets to Keystore, set android:allowBackup="false", stop putting the Telegram token in the URL (C2).
3. Replace Telegram first-contact auth with an explicit on-device pairing code (C3).
4. Real release signing config; disable cleartext traffic; prune permissions to those actually used (C4, C6).
5. Add a confirmation step to SMS/call/delete and to any LLM-issued destructive tool call (H5).
6. Fix the concrete bugs: 'edit' -> 'write' + append (H1), TTS timeout vs. playback (H2), wake-word list (H3), permissionReport (H6), node.recycle() (H7), test defaults (H10).
7. Fix the three user-reported bugs: U3 auto-mute first (M8 word boundaries), U1 mic auto-start (M4 / L7 gating), U2 mic timing + H2 timeout.
8. Make CI run flutter analyze + flutter test on every push (L8).
9. Make the "local-first" claim honest in the UI, or drop it (L4).


Report generated from a static review of commit b573599, revised to remove prompt-injection framing and add three user-reported runtime bugs (U1–U3). No code was modified during the audit.