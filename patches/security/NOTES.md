# Security patches — notes, evidence and verification

Scope: **C1, C2, C3, C4, C6, H5, H9** plus the H5 Dart wiring and the two
consequential changes they forced (secure-storage dependency, `task_executor`
status messages).

Everything here was written and reviewed **statically**. No Flutter/Dart/Kotlin
compiler or Gradle was available, so:

- No test in `tests/*.dart` has been executed. Each one is marked
  `PENDING RUNTIME`.
- "Verified" below means: read against the original source, call sites traced,
  bracket balance checked, and the whole patch set re-applied to a pristine
  `b573599` tree.

---

## Apply

```bash
# from the repository root, on b573599
patch -p1 --forward < patches/all.patch      # recommended
```

The per-finding `.patch` files are cut per file, not per finding, because several
findings touch the same file (`MainActivity.kt` carries C1, H3 and H8).
`patches/all.patch` is the authoritative artifact:

```
HEAD  +  patches/all.patch  ==  the working tree these notes describe
```

Checked byte-for-byte (`diff -r`, exit 0) after a clean
`git archive HEAD | tar -x` + `patch -p1`.

---

## C1 — Path traversal in the file tool

**File:** `android/app/src/main/kotlin/com/jarvis/dev/MainActivity.kt`
**Patch:** `08-MainActivity.kt.patch`

### Why it mattered

`getTargetFolder(name)` mapped the Dart-supplied `folder` string straight into
`File(base, customName)` with no validation, and the file name went in as
`File(folder, fileName)` unvalidated too. `../../..` therefore escaped Downloads
and could read or overwrite anything the app could reach, including its own
`shared_prefs`. The LLM chooses those strings.

### What changed

1. `isSafeStorageSegment(segment)` — rejects empty, `.`/`..`, anything containing
   `/`, `\`, NUL, or the substring `..`.
2. `resolveStorageChild(dir, name)` — canonicalises **both** the root and the
   candidate, then requires `child.path.startsWith(root.path + File.separator)`.
   Canonicalisation is what defeats symlinks: a path that *looks* contained but
   resolves outside is rejected. Returns `null` on any exception.
3. `getTargetFolder(name)` — only the known collection names (Downloads,
   Documents, Pictures, Music, Movies, DCIM, …) are accepted; a custom name is
   resolved *inside* shared storage and must therefore also pass
   `isSafeStorageSegment`.
4. Every `manageStorageFile` branch (`read`, `write`/`create`, `list`, `delete`)
   returns `INVALID_PATH` when resolution fails instead of silently using a
   surprising directory.

### Deliberate behaviour change

`folder: "../../etc"` used to write outside storage and maybe succeed. It now
returns a hard error. Nothing in `lib/` sends such a value, so no legitimate flow
regresses.

### Residual risk

`requestLegacyExternalStorage="true"` is still set (needed by the write path on
API 29). On API 30+ scoped storage limits the blast radius anyway. Not new, and
not made worse here.

---

## C2 — API key and Telegram token in plaintext

**Files:** `lib/services/settings_service.dart`, `pubspec.yaml`,
`android/app/src/main/AndroidManifest.xml`, `res/xml/*`
**Patches:** `09-settings_service.dart.patch`, `13-pubspec.yaml.patch`,
`02-AndroidManifest.xml.patch`, `03`, `04`

### Why it mattered

`ai_api_key` and `telegram_token` were `SharedPreferences` strings. With
`allowBackup` at its default, those were also eligible for Android auto-backup and
therefore uploaded to the user's Google account.

### What changed

- New dependency `flutter_secure_storage: ^11.2.0`, used with the default
  `AndroidOptions()` — the plugin's own encrypted file with the AES key wrapped
  in the Android KeyStore. **v11, not 9.x:** 9.x pins `win32 ^5` and cannot
  resolve against `share_plus ^13` (`win32 ^6`); CI failed on exactly that
  conflict at `flutter pub get`. v11 also dropped
  `AndroidOptions.encryptedSharedPreferences` (and `sharedPreferencesName`), so
  the old option would not have compiled.
- Both secrets read/write through `FlutterSecureStorage`; the getters stay
  synchronous because the values are cached in memory after `init()`.
- One-time migration `_migratePlaintextSecret()`: if secure storage is empty and a
  plaintext value exists, copy it into secure storage, then **always** remove the
  plaintext key. The first launch after upgrade cleans up an old install.
- Manifest: `allowBackup="false"`, `fullBackupContent="false"`,
  `dataExtractionRules="@xml/data_extraction_rules"`,
  `usesCleartextTraffic="false"`,
  `networkSecurityConfig="@xml/network_security_config"`.
- `network_security_config.xml` keeps the two legitimate plaintext endpoints
  reachable (`*.local` for Home Assistant mDNS, `127.0.0.1` for Ollama) and
  forbids cleartext everywhere else. **This can break a working setup:** Home
  Assistant addressed by raw LAN IP (`http://192.168.1.50:8123`) is now blocked.
  Add that IP to the config, or move Home Assistant to HTTPS. Also noted in the XML
  header.
- `data_extraction_rules.xml` excludes `sharedpref`/`database`/`file` domains from
  both cloud backup and device-to-device transfer (API 31+).

### Verification performed

- No remaining direct `prefs.getString('ai_api_key')` / `setString(...)` in
  `lib/` (grep: 0 hits outside `settings_service.dart`, which uses them only for
  migration).
- Every reader of `apiKey`/`telegramToken` uses the synchronous getter, so none
  needed to become `async`.
- `setApiKey`/`setTelegramToken` callers: `onboarding_screen.dart:124`,
  `settings_screen.dart:130,162` — all already `await`.

### PENDING RUNTIME

- `flutter pub get` has not been run on a device, but **CI has now run it and it
  failed**: `flutter_secure_storage ^9.2.4` + `share_plus ^13.3.0` is an
  unsatisfiable `win32` constraint (`^5.0.0` vs `^6.0.1`). Fixed by moving to
  `^11.2.0` (see above). `pubspec.lock` is not committed, so the resolved set is
  whatever the CI runner resolves on the day.
- Migration must be exercised on a device that already has a plaintext key: first
  launch should log `Migrated "ai_api_key" to secure storage.` and the key must
  survive a restart.
- **An existing cloud backup from a previous install is not deleted by this
  change.** Rotate the API key and the bot token.

---

## C3 — Telegram "first chat becomes owner"

**Files:** `lib/services/telegram_service.dart`, `lib/services/settings_service.dart`
**Patches:** `10-telegram_service.dart.patch`, `09-settings_service.dart.patch`

### Why it mattered

```dart
if (allowed.isEmpty && owner.isEmpty) { /* remember this chat as owner */ }
final isAuthorized = allowed.contains(chatId) || (allowed.isEmpty && chatId == owner);
```

The first chat to message the bot became the owner with full agent control (SMS,
calls, file writes, UI automation). The bot username is public, so this was remote
unauthenticated device control.

### What changed

- The implicit-ownership path is **gone**. `_handleUpdate` now:
  1. handles `/pair <code>` for any chat,
  2. silently ignores every chat not in `telegramAllowedChats` (silence, not an
     error reply — an error reply confirms the bot is live).
- `/pair <code>` is the only path that adds a chat. It redeems a 6-digit code
  generated **on the device** (`Settings → Telegram Remote Bridge`), valid 10
  minutes, single use, compared in constant time.
- `issueTelegramPairCode()` / `consumeTelegramPairCode()` live in
  `SettingsService` so the rules are testable without a device.
- **Brute-force cap (added during review):** five wrong guesses destroy the
  displayed code, so the odds of a blind guess are 5-in-a-million per code instead
  of 1-in-a-million per attempt for ten minutes. The counter resets whenever a new
  code is issued.

### Verification performed

- Every `telegramAllowedChats` reader traced: `jarvis_settings_screen.dart:784`,
  `settings_screen.dart:858`, `security_alert_service.dart:77`,
  `sentry_service.dart:150`. All read the list; only pairing and the settings UI
  write it, so removing the owner path leaves no dangling reader.
- `telegramOwnerChatId` still exists and now returns `telegramAllowedChats.first`.
- No `debugPrint` of the token or the code anywhere in the service.

### PENDING RUNTIME

- Pair a second chat and confirm the first is not displaced.
- Send `/pair 000000` six times and confirm the on-device code is invalidated.

---

## C4 — Release APK signed with the debug key

**Files:** `android/app/build.gradle.kts`, `android/key.properties.example`
**Patches:** `01-build.gradle.kts.patch`, `05-key.properties.example.patch`

### Why it mattered

`buildTypes.release` used `signingConfig = signingConfigs.getByName("debug")`.
A debug-signed release is signed with the publicly known AOSP test key, so anyone
can produce an "update" that installs over it.

### What changed

- A real `release` signing config is created from `android/key.properties` (or
  `JARVIS_KEYSTORE_*` environment variables, which is what CI should use).
- `hasReleaseSigning` gates the choice. Without a keystore the build still falls
  back to the debug key — a personal sideload must not break — but it logs a `WARN`
  stating the APK is **DEBUG-SIGNED** and not publishable.
- The R8/minify block is present but **commented out**, with the reason: Flutter's
  `GeneratedPluginRegistrant`, `webview_flutter`, `permission_handler`,
  `shizuku_api` and `android_intent_plus` resolve classes reflectively, so blind
  shrinking is a runtime-crash generator. Enabling it needs keep-rules and a device
  test pass.
- `android/key.properties.example` documents the fields with `<REDACTED>`
  placeholders (no real secret, no `changeit`).

### PENDING RUNTIME

- `./gradlew assembleRelease` was never run (no Android SDK).
- Without `key.properties` → warning appears and APK installs; with a real
  keystore → `apksigner verify --print-certs` shows the user's key.
- `.gitignore` must contain `android/key.properties` and `*.jks`. Check before the
  first real keystore lands.

---

## C6 — 95 permissions, cleartext traffic, exported components

**File:** `android/app/src/main/AndroidManifest.xml` (+ the two new `res/xml` files)
**Patch:** `02-AndroidManifest.xml.patch`

### What changed

- **95 → 63** `uses-permission` entries. The 32 removed ones are all APIs the code
  never calls:

  ```
  ACCESS_LOCATION_EXTRA_COMMANDS  ACCESS_MEDIA_LOCATION   ADD_VOICEMAIL
  BLUETOOTH_ADVERTISE             BODY_SENSORS_BACKGROUND CHANGE_WIFI_MULTICAST_STATE
  DETECT_SCREEN_CAPTURE           DISABLE_KEYGUARD        EXPAND_STATUS_BAR
  FOREGROUND_SERVICE_CAMERA       FOREGROUND_SERVICE_HEALTH
  FOREGROUND_SERVICE_MEDIA_PLAYBACK  FOREGROUND_SERVICE_MEDIA_PROCESSING
  FOREGROUND_SERVICE_MICROPHONE   FOREGROUND_SERVICE_PHONE_CALL
  FOREGROUND_SERVICE_REMOTE_MESSAGING  FOREGROUND_SERVICE_SHORT_SERVICE
  GET_ACCOUNTS                    HIDE_OVERLAY_WINDOWS    KILL_BACKGROUND_PROCESSES
  MANAGE_OWN_CALLS                NFC                     RECEIVE_MMS
  RECEIVE_WAP_PUSH                REORDER_TASKS           REQUEST_DELETE_PACKAGES
  SET_WALLPAPER                   TRANSMIT_IR             TURN_SCREEN_ON
  USE_BIOMETRIC                   USE_FULL_SCREEN_INTENT  UWB_RANGING
  ```

  Each was checked against the source by grepping for the governing API
  (`setFullScreenIntent`, `BiometricPrompt`, `NfcAdapter`, `setWallpaper`,
  `killBackgroundProcesses`, `KeyguardManager`, `expandNotificationsPanel`,
  `reorderTasks`, `AccountManager`, `ConsumerIrManager`, `setTurnScreenOn`,
  `addVoicemail`) — **all zero hits**. `BODY_SENSORS` itself is retained; only the
  *background* variant was dropped, and the app only samples while a screen is open.
- Every declared `foregroundServiceType` still has its matching
  `FOREGROUND_SERVICE_*` permission (`dataSync`, `mediaProjection`, `location`,
  `connectedDevice`, `specialUse` ×2). Removing one would have thrown
  `SecurityException` from `startForeground` — checked explicitly.
- `exported` reviewed component by component:
  - `MainActivity` `true` — required by the LAUNCHER intent-filter; exposes no
    other filter and reads nothing from the intent.
  - `AgentAccessibilityService`, `InboxNotificationListenerService`,
    `JarvisDeviceAdminReceiver` `true` — **required**: the system binds them, and
    only the system holds the matching `BIND_*` permission. Setting these to
    `false` silently disables the feature.
  - `BootReceiver` `false` (see H9), all other receivers/services `false`.
- `allowBackup`, `usesCleartextTraffic`, `dataExtractionRules`,
  `networkSecurityConfig` — see C2.

### Deliberate non-changes

- `MANAGE_EXTERNAL_STORAGE` stays. It is Play-policy-restricted, but the file tool
  writes to real Downloads/Documents paths and this is a personal sideload.
  Flagged in the README (M12 disclosure).
- `requestLegacyExternalStorage="true"` stays for the same reason.

### Follow-up (not done, needs a decision)

`DeviceControlManager.permissionGroups` and the Dart
`permission_manager_service.dart` catalog still *name* `BLUETOOTH_ADVERTISE` and
`BODY_SENSORS_BACKGROUND`, which are no longer in the manifest. Requesting an
undeclared permission just returns "denied" — no crash — but the Permissions Hub
can show a row that can never be granted. Syncing those catalogs changes the
Permissions Hub UI, which is outside this patch set's blast radius.

---

## H5 — SMS and calls with no confirmation

**Files:** `android/app/src/main/kotlin/com/jarvis/dev/DeviceControlManager.kt`,
`.../MainActivity.kt`, `lib/services/device_control_service.dart`,
`lib/services/task_executor.dart`
**Patches:** `07`, `08`, `11-device_control_service.dart.patch`,
`12-task_executor.dart.patch`

### Why it mattered

`sendSms` and `placeCall` were plain MethodChannel calls. Anything that could
produce a tool call — the LLM, a Telegram message, a voice command, a scheduled
task — could text or dial with no human in the loop. Combined with C3 that is
remote SMS/call capability.

### What changed (native)

- `requiresConfirmation(action, preview)` returns
  `{success: false, requiresConfirmation: true, action, preview, message}`.
- `sendSms(context, address, body, confirmed = false)`:
  - permission check, non-blank body check, **recipient validation**
    (`validatedNumber`: telephony punctuation allowed, 3–15 digits) so an
    unresolvable contact cannot be "sent" to garbage,
  - then, unless `confirmed == true`, returns the preview and sends nothing.
- `placeCall(context, number, confirmed = false)`:
  - validates the number,
  - when `CALL_PHONE` is granted and `confirmed == false` → preview only,
  - when `CALL_PHONE` is **not** granted it opens `ACTION_DIAL`, which needs a
    final tap and is therefore safe on its own.
- `MainActivity` reads `confirmed` from the call arguments (default `false`) and
  passes it through.

### What changed (Dart)

- `DeviceControlService.sendSms` / `placeCall` take `confirmed` and send it.
- New optional hook:
  ```dart
  Future<bool> Function(String action, String preview)? confirmAction;
  ```
  While it is `null` (the default) the first call returns the native preview and
  the second call is **never made** — the action is refused, which is the safe
  default. Wiring a real dialog is one assignment; see `OPEN_QUESTIONS.md` #1.
- `task_executor.dart` no longer prints "SMS failed: Send SMS to …" for a preview.
  It says the action *needs confirmation*, which is the truth.

### ⚠️ Behaviour change / regression risk

**Until a UI supplies `confirmAction`, SMS and calls do not happen at all.** That
is intentional and the only safe default, but it is a functional change from
`b573599`. To enable them: set `DeviceControlService.instance.confirmAction` to a
function that shows a real dialog and returns the answer, or pass
`confirmed: true` from a call site that genuinely has a human present.

### Verification performed

- Both channel handlers read `call.argument<Boolean>("confirmed") ?: false`.
- All Dart call sites traced: only `task_executor.dart:595,632` and the service
  itself; both handle `requiresConfirmation`.
- No other `sendSms`/`placeCall` caller exists (grep, whole `lib/`).

### PENDING RUNTIME

- On device: confirm the preview text, confirm a `confirmed: true` call actually
  sends, and confirm `ACTION_DIAL` still opens when `CALL_PHONE` is denied.

---

## H9 — BootReceiver accepts unprotected broadcasts

**Files:** `.../BootReceiver.kt`, `AndroidManifest.xml`
**Patches:** `06-BootReceiver.kt.patch`, `02-AndroidManifest.xml.patch`

### What changed

- `exported="false"`. Boot broadcasts are protected system broadcasts, so the
  system still delivers them to a non-exported receiver; third-party apps can no
  longer deliver a spoofed `BOOT_COMPLETED` (which used to start the agent core).
- The receiver has an explicit `ALLOWED_ACTIONS` set (`BOOT_COMPLETED`,
  `LOCKED_BOOT_COMPLETED`, `QUICKBOOT_POWERON`, HTC's variant) and drops anything
  else before touching preferences or starting anything.
- Autostart stays opt-in via the `agent_autostart` preference.

### PENDING RUNTIME

- Reboot once with autostart on and once with it off.

---

## Files touched by this slice

| Patch | File | Findings |
|---|---|---|
| 01 | `android/app/build.gradle.kts` | C4, L6 (comment), L12 (documented non-change) |
| 02 | `android/app/src/main/AndroidManifest.xml` | C2, C6, H9, M12 (comment) |
| 03 | `android/app/src/main/res/xml/network_security_config.xml` | C2, C6 |
| 04 | `android/app/src/main/res/xml/data_extraction_rules.xml` | C2 |
| 05 | `android/key.properties.example` | C4 |
| 06 | `.../BootReceiver.kt` | H9 |
| 07 | `.../DeviceControlManager.kt` | H5, H6, A1 (multi-match resolver), A12 |
| 08 | `.../MainActivity.kt` | C1, H3 (wake word), H5 (arg plumbing), H8 (`ioExecutor`), A7 (`isManualSession`) |
| 09 | `lib/services/settings_service.dart` | C2, C3, A6 (`revokeTelegramAccess`), M1 (`neuralVoiceDegraded`) |
| 10 | `lib/services/telegram_service.dart` | C3 |
| 11 | `lib/services/device_control_service.dart` | H5 (Dart gate), A1 (pending choice) |
| 12 | `lib/services/task_executor.dart` | H5 (honest status message), A1 (refuse ambiguous) |
| 13 | `pubspec.yaml` | C2 (`flutter_secure_storage`), L10 (explicit asset list) |
| 14 | `lib/screens/settings/settings_screen.dart` | A6 (pair / revoke UI), C3 |
| 15 | `.gitignore` | C4, A11 (signing material) |

`DeviceControlManager.kt` and `MainActivity.kt` also carry H6 / H8 edits that the
functional slice depends on. They are **not** duplicated in
`patches/functional/`. Apply `patches/all.patch`, or whole files from
`patches/*/files/` — never mix hunks across slices.

---

## A1–A15 completion pass (this slice)

The owner answered every open question. Three answers changed files owned by the
security slice; two of them are security-relevant on their own.

### A6 — Telegram revocation (C3 follow-through)

`SettingsService.revokeTelegramAccess()` clears the allowed-chat list, the
outstanding `/pair` code **and** the bot token. The settings screen gained
**Pair a chat** and **Revoke access** buttons; the revoke button is styled with
`AppTheme.danger` through a new `destructive:` flag on `_actionButton`.

Telegram has no token-rotation API, so the snackbar tells the user to send
`/revoke` to @BotFather. Local state is already safe by then: with no token the
bridge cannot poll and cannot send.

`settings_screen.dart` was carrying a **compile break** — it still called
`setTelegramOwnerChatId('')`, removed during C3. It now calls
`_revokeTelegramAccess`. All 61 `SettingsService` members used from `lib/` were
re-checked; only `addListener`/`removeListener` (inherited) are not declared in
that file.

Files: `09-settings_service.dart.patch`, `14-settings_screen.dart.patch`.

### A11 — signing material cannot be committed

New root `.gitignore` hides `android/key.properties`, `*.jks` and `*.keystore`;
`android/.gitignore` already covered the subtree. Verified with
`git check-ignore -v android/key.properties android/app/release.jks`, which
reports the `android/.gitignore` rules.

File: `15-.gitignore.patch`.

### A1 — same-name contact resolution

`DeviceControlManager.resolveContact` no longer returns the first match. It now:

- collects **every** exact match, falling back to loose matches only when there
  are none (a substring hit on a different contact is not a candidate);
- adds call-history numbers when `READ_CALL_LOG` is held, so a name that was
  never saved can still be called back;
- dedupes on the digits, not the formatting, so `+91 98765 43210` and
  `09876543210` count once;
- returns `requiresChoice=true, matches=[…], count=N` when several remain.

That last shape is deliberately **`success=false`**: every pre-existing caller
then fails closed (refuses) instead of dialling a guess, and only the new voice
bridge reads `matches`. `device_control_service.dart` and `task_executor.dart`
handle the flag explicitly; `task_executor` (no conversation context) logs the
candidate tails and returns `false`.

Files: `07-DeviceControlManager.kt.patch`, `11-device_control_service.dart.patch`,
`12-task_executor.dart.patch`.

### A7 — session origin carried through the native payload

`MainActivity` records `isManualSession` when a recogniser session starts and
ships `"manualSession"` in all three `onSpeechResult` payloads. Without it the
Dart layer cannot tell a button tap from an always-on restart, and A7's rule
("auto sessions need the wake word") is unenforceable.

File: `08-MainActivity.kt.patch`.
