# Open questions — every item below is now closed

Ordered by how much they block. Each item says what is ambiguous, what the
patches currently assume, and what to do about it.

---

## Resolutions (owner answers A1–A15, 2026-11-17)

Every question in this file was answered. Nothing here is waiting on the owner
any more; what remains is runtime testing, which is out of scope for this
patch set. The table is the authoritative record.

| # | Subject | Answer | Where it landed |
|---|---|---|---|
| A1 | Same-name contacts | Digit chain, never guess (option b); call history included | `contact_disambiguation_service.dart`, `resolveContact` (Kotlin), `device_control_service.dart`, `task_executor.dart`, `jarvis_service.dart` |
| A2 | What opens the mic | Ambient speech near the phone; fix the native restart loop + `hasWakeWord` filter | `MainActivity.kt` (`isManualSession`), `jarvis_service.dart` gate |
| A3 | Mic closes after each reply | By design when always-on is off; already gated by U1 | unchanged (verified) |
| A4 | Phone goes silent on its own | Word-boundary router (M8/U3) is the fix | `ai_service.dart` |
| A5 | Home Assistant | Not used — no IP allowlist, C2 cleartext block stays | `network_security_config.xml` (unchanged) |
| A6 | Telegram revoke | Revoke also rotates the bot token | `settings_service.dart` `revokeTelegramAccess`, settings UI pair/revoke buttons |
| A7 | Wake word in auto sessions | Required for auto-started sessions, never for taps | `MainActivity.kt`, `voice_service.dart`, `jarvis_service.dart` |
| A8 | Main-thread storage I/O | Follow-up PR; correctness first because the source is public | sketched in `patches/functional/NOTES.md` (M7) |
| A9 | Hand-rolled SHA-256 | Verify byte-for-byte before any replacement | not replaced (see Q9) |
| A10 | Edge-TTS | Keep it, degrade gracefully, document the risk in the file | `edge_tts_service.dart` comment |
| A11 | Keystore | Not mandatory; scaffold + instructions + ignore rules ship | `android/key.properties.example`, `.gitignore`, `android/.gitignore` |
| A12 | Permission catalogs | Delete `BLUETOOTH_ADVERTISE` and `BODY_SENSORS_BACKGROUND`, fix `AppPermissionType` coverage | `DeviceControlManager.kt`, `permissions_screen.dart` |
| A13 | 67 empty catches | Follow-up pass, classify safe vs unsafe | this patch set: 9 converted, 1 annotated, 57 remain `(a)` — see `patches/resources/EMPTY_CATCHES.md` |
| A14 | `recycle()` is a no-op | Comment the truth; the real fix is depth bound + `getChild` guard | `AgentAccessibilityService.kt` |
| A15 | CI green | `flutter analyze` stays blocking; fix the lint backlog | `.github/workflows/build.yml` (unchanged policy) |

Per-question status:

| Question below | Closed by |
|---|---|
| 1. H5 confirmation | H5 hook + "needs confirmation" messaging; behaviour change accepted |
| 2. U1 mic opener | A2, A3 |
| 3. U2 double audio | A10 (Edge-TTS kept with the double-audio guard) |
| 4. U3 mute trigger | A4 |
| 5. C2 Home Assistant | A5 |
| 6. C3 pairing / revocation | A6 |
| 7. H3 `hasWakeWord` | A7 |
| 8. M7 main-thread I/O | A8 |
| 9. L11 SHA-256 | A9 |
| 10. M1 Edge-TTS | A10 |
| 11. C4 keystore | A11 |
| 12. Permission catalogs | A12 |
| 13. M10 empty catches | A13 |
| 14. H7 `recycle()` | A14 |
| 15. CI | A15 |


---

## 1. H5 makes SMS and calls inert — wire the confirmation, or accept that?

**Blocking severity: high (functional regression).**

The native side now refuses to send an SMS or place a direct call unless it is
told `confirmed = true`. The Dart side exposes:

```dart
DeviceControlService.instance.confirmAction =
    (String action, String preview) async => showMyDialog(preview);
```

While `confirmAction` is `null`, `sendSms`/`placeCall` return the native preview
(`requiresConfirmation: true`) and nothing is sent. `task_executor.dart` reports
"needs your confirmation" instead of "failed", so it is not a silent failure.

**Three options:**

| Option | Effect | Risk |
|---|---|---|
| A. Wire a dialog in the HUD/Task UI (recommended) | Assistant can text/call after a tap | Needs UI work + a device test |
| B. Pass `confirmed: true` from a call site that is itself a user tapping a button | Same, less code | Must be provably a button press; easy to abuse later |
| C. Leave it refusing | Nothing is ever sent or dialled by the assistant | Feature regression vs `b573599`; user will notice |

**Question for the owner:** should the assistant be able to text/call at all
without a tap? If yes, option A. If "only when I press something", option B. If
"never", option C and this is working as intended.

---

## 2. U1 — which precise action opens the microphone?

The patches gate every *code* path that can call `startListening()`
automatically. What remains unverified is the **native** recogniser loop in
`MainActivity`: it restarts recognition while `isContinuousListening` is true.
That flag is driven from Dart, so the gate should cover it — but the report's
original question was never answered:

- Does the mic open **at app launch**?
- At the **first voice-button tap**?
- At a **wake word** / ambient speech?

**Why it matters:** if the user's complaint is "it opens at launch", the fix in
`onEnterJarvisMode` is the right one. If it is "it opens while I'm just talking
near the phone", the remaining suspect is the native restart loop plus the
`hasWakeWord` filtering that was deliberately *not* wired (see #7).

**To answer:** run with always-on off, leave the HUD open, say nothing for a
minute, then check whether `SpeechRecognizer` is active (`adb shell dumpsys audio`
or the mic privacy indicator).

---

## 3. U2 — "mic shuts off too early" or "double audio"?

The report's own wording is ambiguous, and the two have different causes:

| Reading | Cause | Fixed? |
|---|---|---|
| "The voice stops / switches mid-sentence" | 7 s timeout fired early and the local engine took over | **Yes** — length-derived budget + `isSpeaking` guard |
| "Recognition cuts me off while I'm still speaking" | end-of-speech detection in the recogniser, unrelated to TTS | **No** |
| "The mic closes after each reply" | by design when always-on is off | **Yes**, now explicitly gated by U1's `_canAutoListen` |

**Question:** which of these is it? If it is the middle one, a different fix is
needed in `MainActivity` (silence timeout / `EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS`),
and this patch set does not address it.

---

## 4. U3 — is narrowing the mute trigger enough?

The router no longer mutes on sentences that merely contain "mute"/"silence":
only an actual command (`mute`, `please mute the phone`, `silence`) does.

**Unresolved:** the *first* cause of the reported symptom may not be the router at
all. If the phone went silent because the assistant was **speaking** and the mic
was still open (feedback), or because a `system` intent was executed from a
partial transcript, this patch does not fix that path.

**Question:** after this change, does the phone still go silent on its own? If
yes, capture a logcat around the event and look for the `[Intent] exact command
match -> system.mute` line — its presence/absence splits "router" from "something
else executing mute".

---

## 5. C2 — Home Assistant on a raw LAN IP will stop working

Cleartext HTTP is now denied except for `*.local` and `127.0.0.1`. If Home
Assistant is configured as `http://192.168.1.50:8123`, the integration breaks.

**Question:** how is your Home Assistant addressed? If by IP, either
(a) add `<domain includeSubdomains="false">192.168.1.50</domain>` to
`res/xml/network_security_config.xml`, or
(b) move it to HTTPS. Option (a) is one line; do not add a broad
`cleartextTrafficPermitted="true"` base config.

---

## 6. C3 — pairing UX and revocation

Works as designed (code on device, `/pair <code>`, 10-min TTL, single use,
5-attempt cap). Two things to confirm by clicking through:

1. Does the Settings screen show the code, its remaining validity, and a
   regenerate button? (`issueTelegramPairCode` exists; the UI was not reviewed
   beyond the consent dialog.)
2. Is removing a chat from `telegramAllowedChats` presented as "revoke"? That is
   the only revoke path now that the implicit-owner concept is gone.

**Question:** should revoking also rotate the bot token? Right now it does not —
a revoked chat just stops being authorised, but the token itself is unchanged.
For a real compromise, rotate the token in BotFather.

---

## 7. H3 — should auto-started sessions require `hasWakeWord`?

The native side now sends `hasWakeWord` alongside each transcript/candidate list,
but **all hypotheses are still forwarded**. Filtering them would break
press-to-talk (the user's sentence usually does not contain "jarvis").

**The open decision:** in `jarvis_service.dart`, should a transcript that arrived
from an *auto-started* (always-on) session be discarded unless
`hasWakeWord == true`, while a transcript from an explicit tap is always
accepted?

- **Yes** → strictest privacy; needs the native payload to be distinguished by
  session origin, which is not currently sent.
- **No (current)** → the recogniser's own wake-word check remains the only filter,
  which is exactly what H3 was about.

Recommendation: if U1's real complaint is ambient speech waking the assistant,
this is the next fix, and it needs one extra field (`sessionOrigin`) from
`MainActivity`.

---

## 8. M7 — main-thread storage I/O is still there

Deferred on purpose. Correct offloading means restructuring the entire
`manageStorageFile` branch so `result` settles exactly once on every path
(create / write / append / read / list / delete / permission denied / exception).
Without a compiler, that is how you ship `IllegalStateException: Reply already
submitted`.

`ioExecutor` already exists in `MainActivity` (added for H8), so the change is
mechanical for whoever has a build environment. Sketch is in
`patches/resources/NOTES.md` (M7).

**Question:** is this worth a follow-up PR, or is file I/O fast enough on the
target device that it can stay? (A 50 MB read on slow storage is an ANR; a 4 KB
README is not.)

---

## 9. L11 — the hand-rolled SHA-256 stays

Not replaced with `package:crypto`. The digest is **not** standard SHA-256: it
feeds a custom initial state and an adjustment constant into the `Sec-MS-GEC`
token. A blind swap would produce tokens Microsoft rejects, and the failure mode
is "neural voice silently stopped working" — the exact class of bug this patch set
removes.

**To resolve:** capture a known-good token from the browser build, and verify a
replacement implementation reproduces it byte-for-byte before deleting the
hand-rolled one. Then also re-evaluate #10.

---

## 10. M1 — should Edge-TTS stay at all?

It works today and will break when Microsoft rotates the token layout and the
pinned Chromium build. It also almost certainly violates the service terms. The
patch set makes the failure graceful (3 strikes → persisted downgrade → on-device
TTS) and documents the risk in the file, but the product decision is open:

| Option | Consequence |
|---|---|
| Keep + degrade (current) | Best voice quality, recurring breakage, ToS exposure |
| Replace with a licensed TTS | Cost, or a worse voice |
| Remove and use `flutter_tts` only | Reliable, offline, noticeably robotic |

**Question:** which trade-off does the owner want?

---

## 11. C4 — who holds the keystore, and where do the passwords live?

The scaffold reads `android/key.properties` or `JARVIS_KEYSTORE_*` environment
variables. Nothing was generated, and `.gitignore` should contain
`android/key.properties` and `*.jks` — **verify this before the first real
keystore exists in the tree.**

**Question:** is this APK ever shared with another person? If yes, a real
keystore is mandatory (a debug-signed build cannot be safely updated); if it is
strictly personal sideload, the loud warning is sufficient.

---

## 12. Permission catalogs now disagree with the manifest

C6 removed `BLUETOOTH_ADVERTISE` and `BODY_SENSORS_BACKGROUND` from the manifest,
but `DeviceControlManager.permissionGroups` and the Dart
`permission_manager_service.dart` catalog still **name** them. Requesting an
undeclared permission just returns "denied" (no crash), but the Permissions Hub
can display a row that can never be granted.

Not changed here because it alters the Permissions Hub UI, which is outside this
patch set's blast radius.

**Question:** should those two entries be deleted from the catalogs, or does the
UI rely on them existing for layout/completeness? If deleted, also check
`AppPermissionType` exhaustiveness in `permissions_screen.dart`.

---

## 13. M10 — 67 empty catches remain, classified

`patches/resources/EMPTY_CATCHES.md` lists every one, tagged
`(a) safe to leave` or `(b) add logging`. Five `(b)` blocks on real failure paths
were converted in this set. The rest need a judgement call per site about what is
safe to log without leaking user text or secrets (the app handles SMS bodies,
screen dumps and API keys, so "just log the exception" is not always safe).

**Question:** is a follow-up pass wanted, or is the inventory enough?

---

## 14. H7 — `recycle()` is a no-op on modern Android

The depth bound and the `getChild` guard are the real fixes. `recycle()` is kept
because it is correct where it still matters and costs nothing, but it is **not**
what fixes a leak on API 21+.

**Question:** if a memory regression is observed in the accessibility service, the
next suspect is holding `AccessibilityNodeInfo` references in the returned maps —
not the missing `recycle()`. Worth knowing before someone "optimises" this.

---

## 15. Does CI going green matter?

`flutter analyze` and `flutter test` now run before the build. On a 28 kLOC tree
that has never been analyzed in CI, `flutter analyze` will very likely report
pre-existing lints. `test/widget_test.dart` should pass after H10; any other
currently-failing test will now surface.

**Question:** is the first red CI run acceptable as a starting point, or should
`flutter analyze` start non-blocking (`|| true`) until the lint backlog is cleared?
Recommendation: keep it blocking, and fix the backlog — a non-blocking gate is how
this repo got here.
