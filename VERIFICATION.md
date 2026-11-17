# Verification log — J.A.R.V.I.S. remediation at `b573599`

**Read this first:** nothing here was executed. There is no Flutter SDK, Dart SDK,
Android SDK, Gradle, Kotlin compiler or device on the review machine, and per the
task constraints none could be installed. Every claim below is a *static* result.

| Symbol | Meaning |
|---|---|
| **DONE** | Source change made; call sites traced; global checks pass. Still needs a runtime test. |
| **DONE (mitigated)** | The underlying condition cannot be removed in this scope; the impact was bounded and documented in code. |
| **DONE (scaffold)** | Configuration prepared, but it cannot take effect until a human supplies a secret/material. |
| **DOCUMENTED** | Deliberately not changed; reason recorded in code/docs. |
| **DEFERRED** | Recognised, not implemented; a sketch exists. |
| **PARTIAL** | Part of the finding is fixed, part is not (explained). |

---

## 1. Method

1. Source read from the remote repository through the MCP `git` server (read-only).
2. A local clone at `b573599` was used only to author edits and produce diffs.
3. Every finding was re-read in the original source before any edit, and every
   changed function's call sites were grepped afterwards (`grep -rn` across `lib/`
   and `android/app/src/main/kotlin/`).
4. The combined diff was applied to a pristine `b573599` extraction and compared
   byte-for-byte with the authoring tree.
5. All heavily edited files passed a string/comment-aware bracket-balance scan.

### Tools that were **not** available

`flutter`, `dart`, `gradle`, `./gradlew`, `javac`/`kotlinc`, `adb`, an emulator, a
physical device. Consequently **`flutter analyze`, `flutter test`,
`./gradlew assembleDebug` and every device scenario are unverified.**

---

## 2. Global checks (these did run)

| Check | Command | Result |
|---|---|---|
| Patch reproduces the tree | `git archive HEAD \| tar -x` → `patch -p1 --forward < patches/all.patch` → `diff -r` | **exit 0, 0 rejects, 0 differing files** |
| Diff size | `git diff --stat` | 39 files, +3054 / −514 |
| Bracket/quote balance | custom scanner over 21 edited source files | all `OK`, 0 leftover |
| Fabricated telemetry literals | `grep -rn '192.168.1.105\|pingLatencyMs: 14' lib/` | **0 hits** |
| Secrets still in prefs | `grep -rn "setString('ai_api_key'\|setString('telegram_token'" lib/` | **0 hits** |
| Permission count | `grep -oE 'android.permission.[A-Z_]+' \| sort -u \| wc -l` | **95 → 63** |
| Removed permissions have no call site | grep for the governing API of each of the 32 removed permissions | 0 hits each |
| Every `foregroundServiceType` has its permission | manifest cross-check | 6/6 matched |
| Empty `catch {}` | `grep -rInE 'catch\s*\([^)]*\)\s*\{\s*\}' lib/` | **74 → 57** (67 after the first pass; the 10 `(b)` sites were then resolved: 9 logged, 1 annotated) |
| `PENDING RUNTIME` coverage | `grep -c 'PENDING RUNTIME' tests/*.dart` | 44 + 17 + 19 markers (one per test plus a file header) |

### What each check does **not** prove

- The bracket scanner is a heuristic. It would not catch a type error, a missing
  import, a wrong argument count, or invalid Kotlin.
- `patch` applying cleanly proves the diff is well-formed against `b573599`, not
  that the result compiles.
- Grep evidence proves a symbol is absent/present, not that the surrounding logic
  is correct.

---

## 3. Per-finding status

### User-reported

| ID | Status | Change | Evidence |
|---|---|---|---|
| **U1** mic opens on its own | **DONE** | `_canAutoListen` gate; `onEnterJarvisMode` no longer calls `startListening()` or arms air gestures unconditionally | All 8 `startListening()` call sites traced; the 3 automatic ones are gated, the 5 explicit ones are not |
| **U2** voice cuts out / double audio | **DONE** | 7 s wall-clock timeout → `4 s + 55 ms/char`; `isSpeaking` guard suppresses the local fallback | `EdgeTtsService.isSpeaking` read and confirmed to be a real signal |
| **U3** assistant silences the phone | **DONE** | `\b`-anchored word helpers + anchored `_muteCommandPattern` (mute is no longer a keyword match) | `contains('mute')` removed; pattern accepts only `[please\|jarvis] mute\|silence [the phone…]` |

### Critical

| ID | Status | Notes |
|---|---|---|
| **C1** path traversal | **DONE** | `isSafeStorageSegment` + `resolveStorageChild` (canonical containment) + hardened `getTargetFolder`; all four `manageStorageFile` branches return `INVALID_PATH`. Symlink escape is defeated by canonicalisation, not by string checks. |
| **C2** plaintext secrets | **DONE** | `FlutterSecureStorage` (`^11.2.0`, Keystore-wrapped AES), one-time plaintext migration that deletes the old key, backup disabled, cleartext banned except `*.local` + loopback. ⚠️ raw-LAN-IP Home Assistant needs a config entry. |
| **C3** Telegram implicit ownership | **DONE** | `/pair <code>` only; unknown chats silently ignored; 10-min TTL; constant-time compare; single use; **+ 5-attempt cap** added during review so a 6-digit code is not brute-forceable. |
| **C4** debug-signed release | **DONE (scaffold)** | Real signing config from `key.properties`/env; loud `DEBUG-SIGNED` warning on fallback; minify commented out with reasons; `key.properties.example` has placeholders only. **No keystore was created** (out of scope). |
| **C5** overlay JS string concat | **DONE** | Reply encoded as a JSON string literal (`JSONObject.quote`, U+2028/U+2029 escaped) instead of hand-rolled backslash escaping. |
| **C6** 95 permissions / exported components | **DONE** | 32 permissions removed with per-API evidence; `exported` chosen per component (system-bound stay `true`, everything else `false`). Follow-up flagged: the Dart/Kotlin permission catalogs still *name* two removed permissions. |

### High

| ID | Status | Notes |
|---|---|---|
| **H1** append writes fail | **DONE** | `action: 'write'` + `append` flag; the old `'edit'` action had no native branch. |
| **H2** double audio | **DONE** | Same change as U2 — one root cause, one patch. |
| **H3** wake word matches ordinary speech | **PARTIAL (deliberate)** | Whole-word regex; `service`/`google`/`travis`/`davis`/`harvest`/`jarvi` removed; `hasWakeWord` added to the payload. **Deviation:** all hypotheses are still forwarded (filtering them would break press-to-talk). Auto-started sessions should require `hasWakeWord == true` on the Dart side — not wired. |
| **H4** fabricated telemetry | **DONE** | `NetworkAuditReport?` + `lastError` + `_fail`; smart-home only replaces the cache after a successful parse; dialog renders a real error state. |
| **H5** unconfirmed SMS/calls | **DONE + behaviour change** | Native `confirmed` gate, recipient validation (3–15 digits, telephony punctuation). Dart `confirmAction` hook defaults to **refuse**. ⚠️ **SMS and calls do nothing until a confirm UI is wired** — see `OPEN_QUESTIONS.md` #1. |
| **H6** `permissionReport` `any` | **DONE** | `relevant.isNotEmpty() && relevant.all { … }` (the empty guard matters: `[].all{}` is `true` in Kotlin). |
| **H7** node leak / unbounded recursion | **DONE** | `MAX_TRAVERSE_DEPTH = 40`, `recycleQuietly`, `getChild` in a `try`, `finally`-recycle for roots and children. **Caveat:** `recycle()` is a no-op since API 21; the depth bound and the `getChild` guard are the real fixes. |
| **H8** screenshot quality / main-thread capture | **DONE** | `ioExecutor` for the `captureFrame` branch; PNG quality 100. **Report corrected:** the API-30 guard already existed at `b573599` — that bullet was withdrawn from `report.md`. |
| **H9** BootReceiver | **DONE** | `exported="false"` + explicit `ALLOWED_ACTIONS` allow-list. |
| **H10** two failing tests | **DONE** | `test/widget_test.dart` now asserts the real (privacy-safe) defaults, then flips each flag. The implementation was not changed to match the test. |

### Medium

| ID | Status | Notes |
|---|---|---|
| **M1** Edge-TTS DRM | **DONE (mitigated)** | Cannot be made compliant without a product decision. Probe `ensureAvailable()` → 3-strike `_recordFailure()` → persisted `neuralVoiceDegraded` → on-device TTS, plus a prominent `AT RISK` block. |
| **M2** HttpClient / cache leaks | **DONE** | `close(force: true)` on every path; `pruneAudioCacheSync(maxAgeDays: 7, maxFiles: 50)` on synthesis start. |
| **M3** missing dispose / timers | **DONE** | `_cancelAllTimers()` (4 timers) used by `_standDown`, `dispose`, mode exit; 4 listeners detached; `_initialized` reset. `AirGestureService._bannerTimer` cancelled. |
| **M4** "software mode" lie | **DONE** | Failure now sets `_isEnabled = false`, an honest status message, and returns `false`. |
| **M5** dedup memory-only | **DONE** | Persisted as JSON (`proactive_shown_ids`), capped at 100, defensive decode. |
| **M6** notification bodies retained | **DONE** | 40-entry cap + 15-min TTL + `purgeAll()` on `ACTION_SCREEN_OFF`. Bodies still reach the LLM when a task reads the inbox — that is the feature. |
| **M7** main-thread file I/O | **DEFERRED** | Offloading correctly needs the whole `manageStorageFile` branch restructured with single-`result` settlement on every path. Doing that without a compiler risks `Reply already submitted`. `ioExecutor` already exists; sketch in the resources notes. |
| **M8** naive intent router | **DONE** | Same patch as U3. |
| **M9** unhandled `Uri.parse` | **DONE** | `_chatCompletionsUri()` normalises to `AiException`. |
| **M10** empty catches | **PARTIAL** | 74 → 67; 5 blocks on real failure paths now log; the remaining 67 are **classified** in `EMPTY_CATCHES.md`, not fixed. |
| **M11** covert sentry capture | **DONE** | Per-session consent gate (voice/LLM cannot arm), `recordingIndicator`, spoken announcement, consent dialog in Settings. |
| **M12** stalkerware signature | **DOCUMENTED** | Permission pruning (C6) + README disclosure + manifest comment. The capability set is legitimate for this app; the gap was honesty. |
| **M13** overlay WebView leak | **DONE** | `destroyQuietly` after `removeView`, on every expand/collapse cycle and on teardown. |

### Low

| ID | Status | Notes |
|---|---|---|
| **L1** `ScreenNode.toString()` | **DONE** | Compact one-liner: whitespace collapsed, quotes normalised, flags added, class only when unlabelled. |
| **L2** README path that does not exist | **DONE** | `home/home_screen.dart` → `hud/hud_home_screen.dart`. |
| **L3** wrong HTML filename in a doc comment | **DONE** | `permissions.html` → `permission.html`. |
| **L4** "100% Local-First" badge | **DONE** | Badge + bullet rewritten; states DeepSeek cloud is the default. |
| **L5** version drift | **DOCUMENTED** | Explicit "only `pubspec.yaml` is authoritative" note. |
| **L6** applicationId TODO | **DONE** | Replaced with the reason it must not be renamed. |
| **L7** `jarvisAlwaysOn` README mismatch | **DONE** | Docs corrected; the safe default was kept. |
| **L8** CI never ran analyze/test | **DONE** | `flutter analyze` then `flutter test` before the build step. |
| **L9** Flutter hard-pinned | **DONE** | `channel: stable`, `flutter --version` logged. |
| **L10** unused assets | **DONE** | Explicit asset list; the 679 KB raw JPG no longer ships. |
| **L11** duplicated SHA-256 | **DOCUMENTED** | The digest is *not* standard SHA-256 — it builds a `Sec-MS-GEC` token with a custom layout. A blind `crypto` swap would silently break neural voice. |
| **L12** applicationId vs Dart package | **DOCUMENTED** | Renaming either side is a migration (app identity / ~100 imports), not a fix. |

---

## 4. Cross-cutting risks introduced by these patches

1. **H5 makes SMS and calls inert** until `DeviceControlService.confirmAction` is
   set or a caller passes `confirmed: true`. This is the safe default and the
   single biggest behaviour change in the set.
2. **C2's network security config blocks cleartext to raw LAN IPs.** Anyone
   running Home Assistant at `http://192.168.x.x:8123` must add that host to
   `res/xml/network_security_config.xml`. Ollama on `127.0.0.1` and `*.local` mDNS
   still work.
3. **C2 adds a dependency** (`flutter_secure_storage`), so `pubspec.lock` changes
   on the first `flutter pub get`. The lockfile is not in this patch set.
   ⚠️ **CI caught this one for real:** `^9.2.4` and `share_plus ^13.3.0` cannot
   resolve (win32 `^5` vs `^6`). Bumped to `^11.2.0`, which also removed
   `AndroidOptions.encryptedSharedPreferences`.
4. **L8 makes CI honest, which means it can now go red.** `flutter analyze` on
   this 28 kLOC tree will very likely report pre-existing info/warning lints. The
   test step should pass for `widget_test.dart` after H10; any other currently
   failing test will now surface.
5. **U3 narrows intent routing.** "Mute the TV later" now goes to the LLM instead
   of muting. That is the intent, but it is a behaviour change users will notice.
6. **H3 narrows the wake word.** Anyone (or any accent) that used to be caught by
   the `service`/`google`/`travis` entries will no longer trigger it.

---

## 5. Test inventory (all `PENDING RUNTIME`)

| File | Groups | Tests |
|---|---|---|
| `tests/security_fixes_test.dart` | C2 secret storage, C6 manifest, C3 pairing + A6 revoke, C4 signing | 18 |
| `tests/functional_fixes_test.dart` | U3/M8 routing, H1 channel contract, native source contracts, voice lifecycle, A1 digit chain, A7 session origin, A12 catalogs | 43 |
| `tests/resource_fixes_test.dart` | H4 telemetry, M2 TTS resources, lifecycle/privacy, L1 `toString`, docs & CI | 16 |

These are **specifications**: they encode the behaviour the patches intend. Two
kinds appear:

- **behavioural** (e.g. `JarvisIntent.fallback('my commute took an hour').systemCommand != 'mute'`) — needs a real Dart VM;
- **source contracts** (e.g. `MainActivity.kt` contains `ioExecutor.execute`) — needs only file access, and will pass trivially once run, since the file is right there. They exist to fail loudly *if someone reverts the fix later*.

They live in `tests/`, a directory `flutter test` does **not** scan by default, so
they cannot affect CI until someone moves them into `test/`. That is intentional:
an unexecuted test must not be able to look like a passing suite.

---

## 6. Honest summary

Every finding in `report.md` has either a source change, a documented rationale,
or an explicit deferral. Nothing is claimed to compile, and nothing is claimed to
pass a test. The highest-confidence results are the mechanical ones (patch
re-application, permission removal with per-API evidence, grep-verified removal of
fabricated literals and plaintext secret writes). The lowest-confidence results
are the Kotlin behavioural edits (H5 confirmation, H7 traversal, H8 threading),
for which only call-site tracing was possible.

---

## 7. A1–A15 completion pass

All fifteen open questions were answered by the owner. This section records what
each answer produced, and what is still only static.

### A1 — same-name contacts (new work)

| Piece | File | What it does |
|---|---|---|
| Multi-match resolver | `DeviceControlManager.kt` `resolveContact` | Returns **all** exact matches (falling back to fuzzy only when there are none); adds call-history numbers when `READ_CALL_LOG` is held; dedupes on digits; replies `requiresChoice=true, matches=[…], count=N` instead of the first match. The old `break` on first exact hit and `exact ?: fuzzy` pick are gone. |
| Chain logic | `lib/services/contact_disambiguation_service.dart` | Pure functions: last-three extraction, digit/word-digit parsing, ordinal detection, suffix narrowing, read-back text, cancellation, "is this a new command" guard. |
| Voice bridge | `DeviceControlService` | Holds the pending shortlist, answers the follow-up utterance, resumes the call/SMS with exactly one match. Re-asks on >1, asks to repeat on 0, never dials a guess. |
| Conversation entry | `JarvisService.processCommand` | Consumes the answer before intent routing, so "4-3-2" never reaches the LLM router; keeps the mic open while a question is outstanding. |
| Agent pipeline | `task_executor.dart` | Refuses an ambiguous contact with an explicit log line rather than picking one (no conversation context exists in that path). |

Known limit, recorded rather than hidden: a bare "two" is interpreted as the
digit `2` (rule 6), not as ordinal 2. Explicit ordinals must be phrased as
"number two" / "the second one". This is deliberate — the digit rule is the one
the owner specified — and it is documented in the file header. WhatsApp
recipients are not implemented anywhere in this codebase, so that part of A1 has
no code to change.

### A2/A7 — session origin

`MainActivity` now records `isManualSession` and ships it in all three
`onSpeechResult` payloads; `VoiceService` stores `lastResultHadWakeWord` and
`lastSessionWasManual` before invoking the callback; `JarvisService` rejects
ambient transcripts when the session was auto-started, the assistant is not
awake, and no wake word was heard. The rule lives in
`JarvisService.acceptAmbientTranscript`, a static function, so the truth table is
covered by four tests.

### A6 — Telegram revocation

`SettingsService.revokeTelegramAccess()` clears allowed chats, the outstanding
pair code and the bot token; the settings screen exposes **Pair a chat** and
**Revoke access** and its destructive styling. The message tells the user to
`/revoke` in @BotFather, because Telegram has no token-rotation API.

This also fixed a real compile break: `settings_screen.dart` still called
`setTelegramOwnerChatId('')`, which no longer exists. A scan of all 61
`SettingsService` members used from `lib/` found only `addListener` /
`removeListener` (inherited from `ChangeNotifier`) outside the declarations.

### A12 — permission catalogs

`BLUETOOTH_ADVERTISE` and `BODY_SENSORS_BACKGROUND` are gone from both the Kotlin
`permissionGroups` and the per-API `minSdk` arms. `nearbyWifi` gained the Hub
sector row it was missing. Coverage is now 25/25 in `_codes`, 25/25 in the
`requestPermission` switch and 25/25 in the sector list; a test asserts all
three, so adding an enum value without wiring it fails loudly.

### A13 — empty catches

Nine of the ten `(b)` rows now log via `debugPrint`; the port probe is documented
as intentionally silent (a closed port throws by design, six times per scan).
Net: 67 → 57 empty catches, none of them hiding a network/storage/voice outcome.
No log line contains user text, contact data, tokens or message bodies.

### A14 — `recycle()`

A long comment in `AgentAccessibilityService` states that `recycle()` has been a
no-op since API 21 and that the real fixes are `MAX_TRAVERSE_DEPTH` and the
`getChild` guard, so nobody "optimises" the wrong line later.

### Still unverified

- Everything above is a source-level claim. No Dart or Kotlin compiler ran.
- The A1 flow has never been exercised against a real contacts provider, and the
  read-back has never been heard through a TTS engine.
- The new settings buttons have never been rendered.
- The `_ambiguousContactText` path in `task_executor` has never run inside an
  agent task.


---

## 8. CI verification (post-merge)

After merging PR #1, `Build APK` ran on `main` (`2bfd82b`) and **failed at step 6,
`Install dependencies` — `flutter pub get`**:

```
Because flutter_secure_storage >=9.1.1 <10.0.0-beta.1 depends on
flutter_secure_storage_windows ^3.1.2 which depends on win32 ^5.0.0,
flutter_secure_storage >=9.1.1 <10.0.0-beta.1 requires win32 ^5.0.0.
And because share_plus >=13.1.0 depends on win32 ^6.0.1, ... is incompatible.
So, because private_agent depends on both flutter_secure_storage ^9.2.4 and
share_plus ^13.3.0, version solving failed.
```

This was a real defect in the patch set: **C2 introduced a dependency whose
transitive constraint conflicts with `share_plus ^13.3.0`.** The local
bracket-scan / grep / patch-reapplication checks could not catch it — only a
resolver could.

Fix (second follow-up commit): `flutter_secure_storage: ^11.2.0` with the
default `AndroidOptions()`. v11 is not merely a version bump: it dropped
`AndroidOptions.encryptedSharedPreferences` and `sharedPreferencesName`, so the
previous call site would not have compiled. `read` / `write` / `delete` /
`readAll` are unchanged, so `settings_service.dart` needed only the constructor
argument.

Lesson recorded: the "static only" claim in §1 is exactly as strong as the checks
listed there. Dependency resolution, compilation and lint were outside them —
and one of them bit immediately.
