# Resources / telemetry / TTS / docs patches — notes and verification

Scope: **H4, C5, M1, M2, M5, M6, M7 (deferred), M10–M13, L1–L12**, plus the
Android-side halves of **H7/H8** and the CI half of **L8/L9**.

Static verification only. No Flutter/Dart/Kotlin/Gradle run; no test executed.
Every test in `tests/resource_fixes_test.dart` is `PENDING RUNTIME`.

---

## Apply

```bash
patch -p1 --forward < patches/all.patch
```

This slice is self-contained in terms of files. The one cross-slice dependency is
cosmetic: `MainActivity.kt`'s `ioExecutor` (H8, security slice) and
`AgentAccessibilityService.kt`'s PNG change (this slice) are the two halves of H8;
neither code path depends on the other to compile.

---

## H4 — Fabricated telemetry presented as real data

**Files:** `lib/services/network_audit_service.dart`,
`lib/services/smart_home_service.dart`, `lib/widgets/network_audit_dialog.dart`
**Patches:** `02`, `03`, `14`

### What was wrong

On the failure path the network audit returned a report containing invented values
(`192.168.1.105`, `pingLatencyMs: 14`, a made-up security score) so the dialog
always had something to draw. The smart-home service injected fabricated
`SmartDeviceEntity` rows when Home Assistant was unreachable. Both are worse than
an error, because the user cannot tell real from fake.

### What changed

- `auditNetwork()` returns `NetworkAuditReport?` — `null` on failure — and stores
  the reason in `String? lastError`. `_fail(message)` is the single failure return.
- Smart home only replaces its entity cache **after** a response parses, and
  reports `lastError` ('Unexpected Home Assistant payload…', 'Home Assistant
  returned HTTP …') instead of inventing devices.
- `network_audit_dialog.dart` renders the error state with a retry affordance
  rather than a fake report.
- The voice summary uses `lastError` when there is no report:
  `'Network audit incomplete, sir. ${lastError ?? …}'`.

### Verification performed

`grep` for the known fabricated literals across `lib/` returns **0 hits**. `_fail`
is called from every `catch` / non-200 branch in the audit.

### PENDING RUNTIME

Real behaviour was not re-observed on a device. The test asserts the literals are
gone and the `null`-returning shape exists (source contracts, not behaviour).

---

## C5 — Overlay WebView: JS built by string concatenation

**File:** `android/app/src/main/kotlin/com/jarvis/dev/BubbleOverlayService.kt`
**Patch:** `08-BubbleOverlayService.kt.patch`

`deliverReply()` interpolated the AI's reply into a JS string with a hand-rolled
`replace("\\","\\\\").replace("\"","\\\"")`. That misses newlines, `\r`, and
U+2028/U+2029 — any of which lets model output break out of the string literal.

Now the reply is encoded as a JSON string literal (`JSONObject.quote`) with
U+2028/U+2029 escaped explicitly, and injected as a value, never as source. Same
fix as M13's encoding half.

---

## M1 — Edge-TTS DRM reimplementation (design / ToS)

**File:** `lib/services/edge_tts_service.dart`
**Patch:** `01-edge_tts_service.dart.patch`

### Why it is not "fixed"

The service reproduces Microsoft's unofficial "read aloud" handshake: a
self-generated `Sec-MS-GEC` token, a hard-pinned Chromium UA (`143.0.3650.75`),
forged `Origin`/`Cookie` headers, and an undocumented WSS endpoint. Removing it
removes the feature. Making it *compliant* means using a licensed endpoint — a
product decision, not a patch.

### What was done instead

- A prominent `UNSUPPORTED / AT RISK` block at the top of the crypto section: this
  is not a documented API, is not licensed for third-party use, almost certainly
  breaches the service terms, and must not be extended.
- **A real fallback ladder**, so the ToS question is not also a reliability
  question:
  - `ensureAvailable()` probes once per process (cached in `_capabilityProbedOk`),
    called from `speak()`;
  - `_recordFailure()` trips after `_failureThreshold = 3` consecutive synthesis
    failures and persists `jarvis_neural_voice_degraded`
    (`SettingsService.neuralVoiceDegraded`);
  - `speak()` short-circuits while the flag is set, so `voice_service.dart`'s
    `useNeuralVoice` path falls straight through to the on-device engine;
  - `resetDowngrade()` clears the probe cache and the flag after a fix.
- Successful synthesis resets the counter.

### The honest summary

Neural voice still works today and will still break the day Microsoft rotates the
token layout — but it now degrades to the local engine instead of failing
silently, and the legal risk is documented where the next person will read it.

---

## M2 — HttpClient and audio cache leaks

**File:** `lib/services/edge_tts_service.dart`
**Patch:** `01-edge_tts_service.dart.patch`

- Every synthesis path closes its client: `client.close(force: true)` (success,
  error, timeout).
- New `pruneAudioCacheSync(dir, {maxAgeDays = 7, maxFiles = 50})`, annotated
  `@visibleForTesting`, called on synthesis start. Two independent bounds: nothing
  older than 7 days, at most 50 files (oldest evicted first). Per-file delete
  failures are logged and do not abort the sweep.

`@visibleForTesting` needs `package:flutter/foundation.dart`, already imported.

---

## M5 — Proactive-agent dedup was memory-only

**File:** `lib/services/proactive_agent_service.dart`
**Patch:** `04-proactive_agent_service.dart.patch`

Dedup ids and the last-spoken timestamp are persisted as JSON in
`proactive_shown_ids` (`dedupPrefsKey`), restored during init and re-written on
every change, capped at `maxRememberedIds = 100`. A restart no longer re-fires
every suggestion already shown.

The format lives in two static helpers (`encodeDedupState` / `decodeDedupState`) so
it is testable without SharedPreferences. Decode is defensive: malformed JSON
yields an empty state, not a throw.

---

## M6 — Notification bodies held in RAM, then sent to a cloud LLM

**File:** `android/app/src/main/kotlin/com/jarvis/dev/InboxNotificationListenerService.kt`
**Patch:** `07-…patch`

Three axes now bound the buffer:

1. `MAX_SAVED = 40` (nothing evicted before),
2. a 15-minute TTL (`purgeExpired`) applied on every insert,
3. `purgeAll()` on `ACTION_SCREEN_OFF`.

`ACTION_SCREEN_OFF` is a protected system broadcast, so the dynamically registered
receiver cannot be spoofed; registration is failure-tolerant (logged, not fatal).

### Honest limit

Bodies still reach the LLM if a task reads the inbox — that is the feature. What
changed is that they are no longer retained indefinitely and not retained at all
once the screen goes off.

---

## M7 — Main-thread file I/O (DEFERRED)

**File:** `android/app/src/main/kotlin/com/jarvis/dev/MainActivity.kt`
**Status:** **not implemented** — documented, not patched.

`manageStorageFile` runs `readText()`, `writeText()`, `length()`, `listFiles()`
directly on the MethodChannel thread. Offloading it correctly means turning the
whole `manageStorageFile` branch into an async structure with a single `result`
settlement on every path — including `create` vs `write` vs `append` vs `delete`
and the permission checks. Doing that blind, with no compiler and no device, is a
good way to ship a double-`result` crash
(`IllegalStateException: Reply already submitted`).

The sketch, for whoever picks this up:

```kotlin
"manageStorageFile" -> {
    val args = call.arguments as? Map<*, *> ?: ... // parse on the channel thread
    ioExecutor.execute {
        val payload = try { doStorageFile(args) } catch (e: Exception) { null }
        mainHandler.post { result.success(payload) }
    }
}
```

`doStorageFile` must be a pure, single-return function. `ioExecutor` already exists
in this file (added for H8), so the plumbing is half done.

---

## M10 — 74 empty `catch {}` blocks

**File:** `patches/resources/EMPTY_CATCHES.md`

The inventory is generated, not hand-written: 67 blocks remain (74 at `b573599`; 7
were in code this patch set rewrote). Each row is classified `(a) safe to leave`
(UI animation, sensor teardown, best-effort cleanup) or `(b) add logging` (hides a
network/storage/voice outcome the user would otherwise see as a silent no-op).

**This is not "fixed".** It is a truthful inventory with a first-pass
classification. Every `(b)` row is a real cleanup task. They were deliberately left
alone rather than edited blind, because each needs a decision about what is safe to
log without leaking user text or secrets.

Five blocks on real failure paths were converted to logging here, because each was
hiding a user-visible no-op:

| File | What was being swallowed |
|---|---|
| `security_alert_service.dart` | a security alert that never reached Telegram |
| `calendar_reminder_service.dart` | a reminder notification that failed to post |
| `hermes_evolution_service.dart` | learned context that silently failed to persist |
| `air_gesture_service.dart` (`stop()`) | sensor release failure |
| `edge_tts_service.dart` (cache prune) | per-file delete failure |

---

## M11 — Sentry mode: covert front-camera capture

**File:** `lib/services/sentry_service.dart`,
`lib/screens/settings/jarvis_settings_screen.dart`
**Patches:** `05-sentry_service.dart.patch`, `13-jarvis_settings_screen.dart.patch`

- `needsConsent` / `grantConsentForSession()` — the first arming in a session
  requires explicit in-app confirmation. **Voice and LLM invocations cannot arm
  it**: the guard sits inside the arm path and refuses with a `lastError` telling
  the user where to confirm.
- `recordingIndicator` (`ValueNotifier<bool>`) is true exactly while capture is
  armed; the Settings → Sentry card renders a red RECORDING banner from it.
- Arming announces itself out loud through `VoiceService.speak`; disarming clears
  the indicator on both the success and the exception path.
- `_lastError` surfaces the failure reason instead of a silent no-op.
- `_confirmSentryRecording()` in `jarvis_settings_screen.dart` is the dialog that
  grants consent.

Consent is per session and never persisted — restarting the app requires
re-confirming.

### PENDING RUNTIME

The dialog and the RECORDING banner are UI; neither was seen rendered. Verify on a
device that cancelling the dialog leaves sentry disarmed and that the banner
appears only while armed.

---

## M12 — Stalkerware permission signature

Addressed by **C6** (permission pruning) plus an explicit disclosure added to
`README.md` under *Android Permissions & Setup Guide* and a comment on the
accessibility service in the manifest. The capability set is legitimate for this
app; what was missing was honesty about it. See the security notes for the
permission evidence table.

---

## M13 — Overlay WebView never destroyed

**File:** `android/app/src/main/kotlin/com/jarvis/dev/BubbleOverlayService.kt`
**Patch:** `08-BubbleOverlayService.kt.patch`

Each expand/collapse cycle built a new `WebView`; detaching it from the
`WindowManager` does **not** free its Chromium renderer. `destroyQuietly(webView)`
is now called on every replaced view and on service teardown, after the view is
removed and outside the existing `try` so a throw on `removeView` cannot skip the
destroy.

### Caveat

`WebView.destroy()` must not be called while the view is still attached; the code
removes it first. That ordering is the whole point of the change — preserve it in
any later edit.

---

## L1 — `ScreenNode.toString()` for prompts

**File:** `lib/models/screen_node.dart`
**Patch:** `06-screen_node.dart.patch`

The old `toString()` was a single interpolation that dumped the raw label
(including newlines and tabs) plus the fully-qualified class name on every line:

```dart
'ScreenNode(#$index "$label" $shortClass @$centerX,$centerY)'
```

Inside a prompt, a 40-node dump was dominated by `android.widget.FrameLayout`
noise, and embedded newlines made it look like several separate entries. Now:

```
ScreenNode(#7 "Send message" [clickable] @50,35)
```

Label whitespace collapses to single spaces, double quotes normalise to `'`, and
the class name is only shown when there is no label. Interactive flags
(`clickable`/`editable`/`scrollable`/`checkable`) are added because those are the
bits the model needs to choose a tap target; coordinates are kept for the same
reason.

---

## L2 / L3 — Docs pointing at files that do not exist

- `README.md` directory map: `screens/home/home_screen.dart` →
  `screens/hud/hud_home_screen.dart`, plus the missing
  `sessions/session_detail_screen.dart` row.
- `permissions_screen.dart` doc comment: `assets/hud/permissions.html` →
  `permission.html`.

Both verified by `ls` and by `File.existsSync()` assertions in the test file.

---

## L4 — "Privacy: 100% Local-First" badge

**File:** `README.md`

The badge and the "Guarantee Complete Privacy" bullet claimed local-only inference
while the default provider is DeepSeek cloud. Now:

- badge: `Privacy: No Trackers · Cloud or Local`;
- bullet renamed **Ship No Telemetry** and states that prompts go to the configured
  provider, that **DeepSeek (cloud) is the default**, and that Ollama is the only
  mode where nothing leaves the phone;
- the always-on listening bullets are marked **opt-in — off by default**, which
  also documents the L7/U1 behaviour.

Nothing true was weakened: there really are no analytics SDKs or crash reporters,
and that is what the bullet now says.

---

## L5 — Version drift

Documented rather than "fixed" (renaming a repository or bumping a badge is the
owner's call):

> Version reality check: `pubspec.yaml` declares `1.1.0+2`, the release badge
> tracks `1.1.0`, and `jarvis-2.9` is just a repository name. Only `pubspec.yaml`
> is authoritative for the built APK.

---

## L6 — `applicationId` TODO comment

**File:** `android/app/build.gradle.kts`
**Patch:** `patches/security/01-build.gradle.kts.patch`

The Flutter boilerplate TODO is replaced with an explanation of why the ID stays:
changing `com.jarvis.dev` changes the installed app identity (breaks in-place
upgrades, loses data) and invalidates every `com.jarvis.dev/...` MethodChannel name
and Kotlin package declaration. Renaming it is a migration, not a comment edit.

---

## L7 — `jarvisAlwaysOn` default vs README

The preference stays `false` (privacy-safe default; see H10 and U1). The README was
corrected to say always-on is opt-in and off by default. The documentation was
wrong; the code was right.

---

## L8 / L9 — CI never analyzed or tested; Flutter pinned

**File:** `.github/workflows/build.yml`, `README.md`

- Added `Analyze` (`flutter analyze`) and `Test` (`flutter test`) steps **before**
  the APK build, so a red analyzer or a failing test blocks the artifact.
- Removed `flutter-version: '3.50.0'`; the workflow uses `channel: stable` and logs
  `flutter --version` for the record. Pinning rots silently when the pinned build
  leaves the channel index.
- README prerequisites updated to match ("stable channel, Dart `^3.12.2`").

### Consequence worth knowing

CI will now fail on pre-existing analyzer findings and on `test/widget_test.dart`
if H10 had not been fixed. H10 **is** fixed, which is why the new `Test` step is not
guaranteed-red. Any *other* currently-failing test will now surface — that is the
point, but it may look like a regression on first run.

---

## L10 — Unused assets shipped

**File:** `pubspec.yaml`
**Patch:** `patches/security/13-pubspec.yaml.patch`

`assets/images/` was a directory entry, so every file in it shipped, including
`jarvis_male_hologram_raw.jpg` — the 679 KB source image for the derived PNGs,
referenced nowhere. The list is now explicit (the four referenced PNGs + the icon +
`assets/hud/`).

`assets/icon/jarvis_logo.png` was never listed, so it was already not shipped; only
the raw JPG was a real regression. Called out so nobody "fixes" it twice.

---

## L11 — Hand-written SHA-256 (NOT changed)

**File:** `lib/services/edge_tts_service.dart`
**Status:** **deliberately not replaced** with `package:crypto`.

The 100-line digest is not a straight SHA-256: it feeds the digest through a
nonstandard layout to build the `Sec-MS-GEC` token (custom initial state, a
per-token adjustment constant, a specific output byte order). Swapping in
`crypto`'s `sha256` would silently produce tokens Microsoft rejects, and the
failure mode is "neural voice stopped working" with no error — the exact class of
bug this patch set exists to remove.

Replacing it correctly requires capturing a working token from a browser and
diffing, which cannot be done statically. Left as-is, under the `AT RISK` block.

---

## L12 — `applicationId` vs Dart package name (NOT renamed)

`applicationId`/`namespace` = `com.jarvis.dev`; the Dart package is
`private_agent`. Renaming either side is a breaking migration:

- `applicationId` → new app identity (uninstall required, data lost, MethodChannel
  prefixes and Kotlin packages all change).
- Dart package name → every `package:private_agent/...` import in ~100 files.

Not a bug for a personal sideload; documented in `build.gradle.kts` instead.

---

## Files touched by this slice

| Patch | File | Findings |
|---|---|---|
| 01 | `lib/services/edge_tts_service.dart` | M1, M2, L11 (documentation) |
| 02 | `lib/services/network_audit_service.dart` | H4, A13 (probe annotated) |
| 03 | `lib/services/smart_home_service.dart` | H4 |
| 04 | `lib/services/proactive_agent_service.dart` | M5 |
| 05 | `lib/services/sentry_service.dart` | M11 |
| 06 | `lib/models/screen_node.dart` | L1 |
| 07 | `.../InboxNotificationListenerService.kt` | M6 |
| 08 | `.../BubbleOverlayService.kt` | C5, M13 |
| 09 | `.../AgentAccessibilityService.kt` | H7, H8 (PNG quality), A14 (recycle comment) |
| 10 | `lib/services/security_alert_service.dart` | M10 (alert delivery failure logged) |
| 11 | `lib/services/calendar_reminder_service.dart` | M10 (reminder post failure logged) |
| 12 | `lib/services/hermes_evolution_service.dart` | M10 (context persist failure logged) |
| 13 | `lib/screens/settings/jarvis_settings_screen.dart` | M11 consent dialog |
| 14 | `lib/widgets/network_audit_dialog.dart` | H4 error state |
| 15 | `README.md` | L2, L4, L5, L7, L9, M12 disclosure |
| 16 | `.github/workflows/build.yml` | L8, L9 |
| 17 | `lib/screens/settings/permissions_screen.dart` | L3, A12 (`nearbyWifi` sector) |

---

## A1–A15 completion pass (this slice)

### A12 — permission catalogs (the `nearbyWifi` half)

Two permissions were requested but never declared in the manifest, so the
permission Hub could only ever show them as permanently denied:

- `BLUETOOTH_ADVERTISE` — the app never advertises; removed from
  `permissionGroups` and from the per-API `minSdk` arms in
  `DeviceControlManager.kt` (security slice owns that file).
- `BODY_SENSORS_BACKGROUND` — removed with its `TIRAMISU` arm. The foreground
  `BODY_SENSORS` declaration stays; the `bodySensors` enum value is still valid.

The same audit found `nearbyWifi` present in the enum and in the
`requestPermission` switch but **absent from the Hub's sector list**, so it could
never be rendered or requested. It now sits in the "Device Control" sector.

Coverage is now complete and enforced by a test: 25/25 enum values have a code
plate (`_codes`), 25/25 have a `case` in `requestPermission`, 25/25 appear in a
sector row. Adding an enum value without wiring it will fail
`tests/functional_fixes_test.dart` loudly instead of silently hiding a row.

File: `17-permissions_screen.dart.patch`.

### A13 — the port probe stays silent, on purpose

`_scanPorts` probes seven ports and catches everything: a closed port throws by
design, six times per scan. Logging each one would bury real errors in noise, so
this is the one `(b)` row that was classified **safe** rather than converted. The
comment in the catch says so, so the next reader knows it was a decision.

File: `02-network_audit_service.dart.patch`.

### A14 — `recycle()` is a no-op

A comment block in `AgentAccessibilityService.kt` records that
`AccessibilityNodeInfo.recycle()` has done nothing since Android 5.0, and that
the real fixes are `MAX_TRAVERSE_DEPTH` and the `getChild` guard. It also names
the actual memory suspect if one is ever observed: the returned
`List<Map<String, Any>>`, which copies every label on every dump.

File: `09-AgentAccessibilityService.kt.patch`.

### A13 — empty-catch inventory refreshed

`EMPTY_CATCHES.md` now ends with the A13 outcome table: 67 → 57 blocks, 0 left
classified `(b)`, and the reproducible `grep` command to confirm it.
