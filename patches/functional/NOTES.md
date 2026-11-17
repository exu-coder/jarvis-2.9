# Functional patches — notes, evidence and verification

Scope: **U1, U2, U3**, plus **H1, H2, H3, H6, H7, H8, H10**, **M4, M8, M9**,
**L7 (docs half)** and the lifecycle half of **M3**.

Static verification only. No Flutter/Dart/Kotlin compiler was available; no test
here has been executed. Every test in `tests/functional_fixes_test.dart` is marked
`PENDING RUNTIME`.

---

## Apply

```bash
patch -p1 --forward < patches/all.patch
```

**Cross-slice dependency (important).** This slice alone does not produce a
working fix. Three findings have their code in files owned by another slice:

| Finding | Code actually lives in | Owned by |
|---|---|---|
| H6 | `DeviceControlManager.kt` | security (`07`) |
| H7 | `AgentAccessibilityService.kt` | resources (`09`) |
| H8 | `MainActivity.kt` (`ioExecutor`) + `AgentAccessibilityService.kt` (PNG quality) | security (`08`) + resources (`09`) |

There are **no duplicate hunks**: each of those files appears in exactly one slice.
Use `patches/all.patch`, or whole files from `patches/*/files/`.

---

## U1 — Microphone opens on its own

**Files:** `lib/services/jarvis_service.dart`, `lib/services/air_gesture_service.dart`
**Patches:** `03-jarvis_service.dart.patch`, `04-air_gesture_service.dart.patch`

### Diagnosis

`onEnterJarvisMode()` did two unconditional things:

```dart
startListening();
unawaited(AirGestureService.instance.start());
```

Navigating into the HUD therefore opened the microphone *and* armed the proximity
sensor. Two more automatic `startListening()` calls existed — after TTS finished,
and after a task completed — gated only on `_shouldListenContinuously`
(`isAlwaysOn || _isInJarvisMode`), which is `true` for anyone who opened the HUD,
regardless of the `jarvisAlwaysOn` preference.

### What changed

- New gate: `bool get _canAutoListen => SettingsService.instance.jarvisAlwaysOn;`
- `onEnterJarvisMode()` starts listening only when `_canAutoListen`; it no longer
  arms air gestures at all.
- Both automatic re-arm points are now
  `if (_shouldListenContinuously && _canAutoListen)`.
- Explicit paths (`toggleListening()`, `startListening(manual: true)`, press-to-talk)
  are untouched — a deliberate tap always works even with always-on off.

### Why this shape and not "delete the calls"

Deleting them would break the always-on feature the README advertises. The
preference already existed and defaulted to `false`; the bug was that the code path
ignored it.

### PENDING RUNTIME / open question

The exact trigger point is still unconfirmed (`OPEN_QUESTIONS.md` #2). The fix
covers every *code* path that can open the mic. The remaining suspect is the native
`SpeechRecognizer` restart loop in `MainActivity`, which is driven by
`isContinuousListening` — controlled from Dart, so the gate should cover it, but
that was not observed on a device.

---

## U2 — Voice cuts out / double audio

**File:** `lib/services/voice_service.dart`
**Patch:** `02-voice_service.dart.patch`

### Diagnosis

`speak()` wrapped neural TTS in a fixed 7-second wall-clock timeout:

```dart
.timeout(const Duration(seconds: 7), onTimeout: () => false)
```

Any utterance whose synthesis + playback exceeded 7 s reported "not played", and
the code then ran `_tts.speak(clean)` **while the native player was still
speaking**. That is both reported symptoms at once: the neural voice appears to
stop, and the user hears two voices.

### What changed

- Fixed 7 s budget → length-derived: `4000 ms + 55 ms per character`
  (≈ 2 minutes for a 2 000-character reply).
- After a timeout the code checks `EdgeTtsService.instance.isSpeaking`; if the
  engine still reports playback it returns **without** starting the local engine,
  so double audio cannot occur.
- If nothing is playing, the fallback proceeds — correct for a genuinely dead
  endpoint.
- The persisted `neuralVoiceDegraded` flag (resources / M1) makes the neural
  attempt skip instantly once the endpoint has failed repeatedly, so the long
  budget is not paid on every sentence.

### Verification performed

- `EdgeTtsService.isSpeaking` exists (`edge_tts_service.dart:99`) and is set true
  before playback, false in `stop()` — a real signal, not a constant.
- `speak()` callers: `jarvis_service.dart` (reply path) and `voice_service.dart`.
  No other caller depends on the 7 s figure.

### Caveat

`EdgeTtsService.speak()` clears `_isSpeaking` when the `playAudioFile` channel call
returns. If that call returns before audio finishes on some device, the guard
degrades to "no double audio protection" for that platform — not to a false
positive (it never *starts* a second voice, it may just not detect one). Verify on
device with a long reply.

---

## U3 — The assistant silences the phone while you talk to it

**File:** `lib/services/ai_service.dart`
**Patch:** `01-ai_service.dart.patch`

### Diagnosis

`JarvisIntent.fallback()` matched with `String.contains`:

```dart
if (lower.contains('mute') || lower.contains('silence')) { ... systemCommand: 'mute' }
```

"Could you **mute** the TV later", "the **silence** in this library", "my
**commute**" — all produced a system mute. The same substring bug hit sports
(`score` → "under**score**"), news, weather (`temperature` → "CPU temperature") and
screenshot.

### What changed

- `_hasWord(text, word)` / `_hasAnyWord(text, words)` — `\b`-anchored,
  case-insensitive, `RegExp.escape`d so punctuation in a keyword is literal.
- The mute branch is no longer a keyword match: it uses `_muteCommandPattern`, an
  anchored pattern that accepts only an actual command —
  `([please|jarvis|hey jarvis] )? (mute|silence) [the phone|audio|sound|volume|media|everything]?`
- Sports / news / screenshot / weather use the whole-word helpers.
- Weather additionally refuses when the sentence is about device temperature:
  `temperature` + any of `cpu, gpu, battery, device, phone, processor` routes to
  conversation instead of a weather lookup.
- `debugPrint('[Intent] keyword match -> …')` added so routing is observable.

### Deliberate narrowing

Utterances that *mention* muting but are not a command now fall through to the
LLM. An assistant should not change phone state because a sentence contained a
word.

### PENDING RUNTIME

`tests/functional_fixes_test.dart` covers `commute`, `silence of the lambs`,
`matching contacts`, `temperature of the cpu`, plus positives (`mute`,
`please mute the phone`, `silence`, real weather, real news). None executed.

---

## H1 — `append: true` writes always fail

**File:** `lib/services/phone_storage_service.dart`
**Patch:** `05-phone_storage_service.dart.patch`

### Diagnosis

Dart sent `'action': append ? 'edit' : 'create'`. The Kotlin handler has no `edit`
branch — it knows `create` / `write` / `read` / `list` / `delete` — so every append
hit `UNKNOWN_ACTION` and nothing was written.

### What changed

The call now always sends `'action': 'write'` and passes the real `append` flag,
which is what the native `write` branch reads. Minimal contract fix: no new native
action, no behaviour change for non-append writes.

### PENDING RUNTIME

The test mocks the channel and asserts `action == 'write' && append == true` for
append, `append == false` otherwise. On a device, append to `notes.txt` twice and
confirm both lines survive.

---

## H2 — Double audio

Same change as U2. The report lists H2 and U2 as one root cause, so they are one
patch, not two.

---

## H3 — Wake word matches ordinary speech

**File:** `android/app/src/main/kotlin/com/jarvis/dev/MainActivity.kt`
**Patch:** `08-MainActivity.kt.patch` (security slice — same file as C1)

### Diagnosis

The wake-word test was a pile of `lower.contains(...)` calls including `"service"`,
`"google"`, `"travis"`, `"davis"`, `"davies"`, `"harvest"`, `"jarvi"`. "Customer
**service**", "**Google** it", "**Travis**" all armed the microphone during normal
conversation.

### What changed

- One compiled pattern at file scope:
  ```kotlin
  private val WAKE_WORD_PATTERN = Regex(
      "\\b(?:jarvis|jervis|javis|jarves|jarvice|charvis|j\\.a\\.r\\.v\\.i\\.s)\\b",
      RegexOption.IGNORE_CASE)
  ```
  Whole-word on both sides, phonetic look-alikes kept (recognisers do mangle
  "jarvis"), ordinary-English look-alikes removed.
- `containsWakeWord()` is now `WAKE_WORD_PATTERN.containsMatchIn(text)`.
- `onResults` / `onPartialResults` now include `"hasWakeWord"` so Dart can branch
  without re-parsing the text.

### Deviation from the report's suggested fix

The report hinted at forwarding **only** hypotheses containing the wake word. That
was **not** done: `onResults` is also the final transcript for a press-to-talk
utterance, and filtering it would break push-to-talk. Instead the full candidate
list is still forwarded, with the extra boolean. If the goal becomes "never act on
ambient speech", the Dart side should require `hasWakeWord == true` for
*auto-started* sessions only — see `OPEN_QUESTIONS.md` #7.

### PENDING RUNTIME

Needs a real recogniser. Say "customer service" and "google it" with always-on
enabled and confirm nothing arms.

---

## H4 — Fabricated telemetry

Delivered by the **resources** slice (`02-network_audit_service.dart.patch`,
`03-smart_home_service.dart.patch`, `14-network_audit_dialog.dart.patch`). Listed
here only so the test file can cover it; see `patches/resources/NOTES.md`.

---

## H6 — `permissionReport` used `any` instead of `all`

**File:** `android/app/src/main/kotlin/com/jarvis/dev/DeviceControlManager.kt`
**Patch:** `patches/security/07-DeviceControlManager.kt.patch`

`report[key] = relevant.any { c.isGranted(it) }` reported a capability as ready
when a single sibling permission was granted (e.g. SMS "available" with only
`READ_SMS` held), so the feature then threw `SecurityException` on first use. Now
`relevant.isNotEmpty() && relevant.all { c.isGranted(it) }`.

The empty-group guard matters: `[].all {}` is `true` in Kotlin, which would have
reported a capability with no permissions as available.

---

## H7 — Accessibility node leak + unbounded recursion

**File:** `android/app/src/main/kotlin/com/jarvis/dev/AgentAccessibilityService.kt`
**Patch:** `patches/resources/09-AgentAccessibilityService.kt.patch`

- `MAX_TRAVERSE_DEPTH = 40`; `traverse(..., depth)` returns immediately when
  exceeded.
- `recycleQuietly(node)` swallows the double-recycle/detached exception.
- `traverseAll` recycles every root in a `finally`; the child loop wraps
  `getChild(i)` in a `try` (it can throw on detached nodes) and recycles each child
  in a `finally`.

### Caveat worth knowing

Explicit `recycle()` on `AccessibilityNodeInfo` has been a no-op since Android 5
and the framework owns the reference lifetime; calling it is harmless but is not
what fixes a leak on modern Android. The real fixes here are the depth bound and
the `getChild` guard. Kept `recycle()` because it is still correct where it matters
and costs nothing.

---

## H8 — Screenshot quality ignored, capture on the platform thread

**Patches:** `patches/security/08-MainActivity.kt.patch`,
`patches/resources/09-AgentAccessibilityService.kt.patch`

- `MainActivity` gained a single-thread `ioExecutor`; the `captureFrame` branch
  does decode/encode/base64 there and posts `result.success(payload)` back to
  `mainHandler`. Exceptions are caught on the worker, so a failed capture returns
  `null` instead of hanging the call.
- `soft.compress(PNG, 100, …)` — PNG is lossless, so 85 was silently ignored; 100
  stops the code implying a quality knob exists.

### Correction to the report

The report claimed the screenshot path was "unusable on Android < 11". That was
wrong: `takeScreenshotBase64` already returned an `UNSUPPORTED` error for
`SDK_INT < R` at `b573599`. The claim has been withdrawn from `report.md`; only the
quality and threading issues were real.

---

## H10 — Two tests guaranteed to fail

**File:** `test/widget_test.dart`
**Patch:** `06-widget_test.dart.patch`

The test asserted `jarvisAlwaysOn == true` and `useNeuralVoice == true` after a
fresh `init()`, while the implementation defaults both to `false`. The
implementation is the privacy-safe behaviour and was kept; the test was corrected
to assert the real defaults, then flip each flag and assert the flip. Without this,
`flutter test` can never pass — part of why CI never ran it.

---

## M4 — Air gestures claim "enabled" when the sensor never armed

**File:** `lib/services/air_gesture_service.dart`
**Patch:** `04-air_gesture_service.dart.patch`

The `start()` catch path set `_isEnabled = true` ("allow software simulation"). That
lied in the HUD, and the software path is what toggled media from a pocketed phone.
It now logs, clears `_isEnabled`, sets
`'Proximity sensor unavailable — air gestures inactive.'` and returns `false`.
`stop()`'s empty catch gained a `debugPrint`, and `_bannerTimer` is cancelled.

---

## M8 — Naive keyword intent router

Same patch as U3 (`01-ai_service.dart.patch`): word-boundary helpers, anchored mute
command, device-temperature guard.

---

## M9 — Unhandled `Uri.parse` on the user-editable base URL

**File:** `lib/services/ai_service.dart`
**Patch:** `01-ai_service.dart.patch`

`Uri.parse('$base/chat/completions')` was called directly from the request path; a
typo (`htp://…`), a stray space or a broken IPv6 literal threw `FormatException`
out of the chat path as an unhandled crash. Now `_chatCompletionsUri(base)` trims,
parses inside a `try`, and converts any failure into `AiException` — which every
caller already handles and shows to the user.

---

## M3 — Timers not cancelled

**Files:** `lib/services/jarvis_service.dart`, `lib/services/air_gesture_service.dart`

`_cancelAllTimers()` cancels all four lifecycle timers in one place and is called
from `_standDown()`, `dispose()` and the mode-exit path. `dispose()` also detaches
the four listeners, nulls `onSpeechStatus` and resets `_initialized` so `init()` can
re-arm the singleton. `AirGestureService._bannerTimer` is cancelled too.

The report cited five timer line numbers; after this change there are four `Timer?`
fields plus `_bannerTimer`. The original numbers were `Timer(...)` construction
sites, not distinct fields — worth knowing if someone diffs the report against the
code.

---

## Files touched by this slice

| Patch | File | Findings |
|---|---|---|
| 01 | `lib/services/ai_service.dart` | U3, M8, M9, A13 (intent/JSON logging) |
| 02 | `lib/services/voice_service.dart` | U2, H2, A7 (origin flags), A13 |
| 03 | `lib/services/jarvis_service.dart` | U1, M3, M4 (call site), A1 (choice entry), A7 (ambient gate), A13 |
| 04 | `lib/services/air_gesture_service.dart` | M4, M3 (`_bannerTimer`) |
| 05 | `lib/services/phone_storage_service.dart` | H1 |
| 06 | `test/widget_test.dart` | H10 |
| 07 | `lib/services/contact_disambiguation_service.dart` (new) | A1 (digit chain) |

`H3`, `H6`, `H7`, `H8` are implemented in files listed in the security and
resources notes; see the dependency table at the top.

---

## A1–A15 completion pass (this slice)

### A1 — `contact_disambiguation_service.dart` (new)

The whole digit chain is pure logic in one file, so it can be tested without a
device, a microphone or a contacts provider:

| Function | Contract |
|---|---|
| `digitsOnly` | drop everything that is not `0-9` |
| `spokenDigits` | numerals **and** spoken digits, in order: `"ending in four three two" -> "432"` |
| `ordinalIndex` | 1-based position **only** for explicit ordinals (`"number two"`, `"the second one"`); `"the one ending in 4 3 2" -> null`, because "one" there is a pronoun |
| `narrow` | ordinal first, otherwise digit-suffix; returns 1 / >1 / 0 so the caller resolves, re-asks or asks for a repeat |
| `buildPrompt` | "I found 3 numbers for Jarvis… Number one, ending in 4-3-2… Which one do you want to call, sir?" |
| `isCancellation` | only an explicit refusal cancels the question |
| `looksLikeNewCommand` | an unrelated sentence (4+ words, no digits) drops the stale question instead of looping |

Known, documented limit: a bare "two" is read as the digit `2`, not as option 2.
That follows the owner's rule 6 ("the last digit, the last three digits, or any
unique portion"). Ordinal intent must be phrased "number two" or "the second
one".

### A1 — voice bridge

`JarvisService.processCommand` consumes the pending answer **before** intent
routing. That matters: `"4-3-2"` would otherwise be classified as chat and sent
to the LLM. While a choice is outstanding the mic is kept open with
`_startFollowUpListening()`; once the call is placed or the message sent, the
assistant stands down.

The device-control branch also needed its own arm: an ambiguity result is
`success=false` with a non-empty `spoken`, which the old code treated as "blocked
// permission" and answered with a **security alert**. It is a question, not a
blocked permission, so it now gets its own status line and no alert.

Files: `03-jarvis_service.dart.patch`, `07-contact_disambiguation_service.dart.patch`.

### A7 — ambient gating

The gate moved out of the `onResult` closure into
`JarvisService.acceptAmbientTranscript`, a static function:

```dart
fromManualSession || isAwake || hasWakeWord
```

The old inline expression omitted the session origin entirely, which is exactly
the reported bug ("the mic opens when I just talk near the phone"): the native
recogniser restarted forever and every hypothesis became a command. Four tests
cover the truth table.

`VoiceService` records `lastResultHadWakeWord` and `lastSessionWasManual` *before*
invoking the callback, so a listener can read them synchronously. Native value
wins; the Dart-side `_manualRequested` flag is the fallback when the payload
omits the field (older APK / reloaded engine).

Files: `02-voice_service.dart.patch`, `03-jarvis_service.dart.patch`.

### A13 — logging on real failure paths

`ai_service.dart`, `voice_service.dart` and `jarvis_service.dart` lost their last
silent `catch {}` blocks. The interesting one is `stopListening`: a failed native
stop leaves the microphone running, which is the most privacy-relevant silent
failure in the codebase. No log line prints user text, contact data, tokens or
message bodies — only the exception.

Files: `01-ai_service.dart.patch`, `02-voice_service.dart.patch`,
`03-jarvis_service.dart.patch`.
