# Patch set index — J.A.R.V.I.S. remediation at `b573599`

Repository: `exu-coder/jarvis-2.9` · source commit `b573599` · **static work only**

Nothing was installed, built, run, pushed, committed or merged. GitHub was read
through the MCP `git` server. The local worktree is a clone at `b573599` that
carries the documented edits and was used to generate the diffs.

> **Everything in `tests/` is `PENDING RUNTIME`.** No Flutter/Dart/Kotlin
> compiler, SDK or device was available. A test existing here means the behaviour
> was *specified*, not that it passed.

---

## Start here

| File | What it is |
|---|---|
| `patches/all.patch` | **Authoritative** applyable diff — 39 files, `+3054 / −514`, verified to reproduce the patched tree from a clean `b573599` |
| `VERIFICATION.md` | Per-finding status table + exactly what was and was not checked |
| `OPEN_QUESTIONS.md` | Every question + the owner's A1–A15 answers and where each landed |
| `patches/security/NOTES.md` | C1, C2, C3, C4, C6, H5, H9, A6, A11 — rationale + evidence |
| `patches/functional/NOTES.md` | U1, U2, U3, H1, H2, H3, H6, H7, H8, H10, M4, M8, M9, A1, A7, A12 |
| `patches/resources/NOTES.md` | H4, C5, M1–M13, L1–L12, A13, A14 |
| `patches/resources/EMPTY_CATCHES.md` | M10 inventory — 57 remaining, 0 classified `(b)`; the A13 pass is recorded |
| `patches/regen.sh` | Regenerates `all.patch`, the per-file patches and `files/` copies |

---

## Layout

```
patches/
  all.patch                  apply everything (recommended)
  INDEX.md                   this file
  regen.sh                   regenerates every patch and files/ copy
  security/
    01..15-*.patch           one patch per file
    files/<path>             complete post-fix copy of each file
    NOTES.md
  functional/
    01..07-*.patch
    files/<path>
    NOTES.md
  resources/
    01..17-*.patch
    files/<path>
    NOTES.md
    EMPTY_CATCHES.md
tests/
  security_fixes_test.dart
  functional_fixes_test.dart
  resource_fixes_test.dart
```

The per-area `.patch` files are **cut per file, not per finding**, because several
findings share a file (`MainActivity.kt` carries C1, H3, H5 plumbing and H8;
`DeviceControlManager.kt` carries H5 and H6). `files/<path>` holds the complete
resulting file, so it can be copied over the original for any file whose patch does
not apply cleanly.

### Applying

```bash
git clone https://github.com/exu-coder/jarvis-2.9 && cd jarvis-2.9
git checkout b5735999f54a51de2ce54ea414198b1dbd18064a
patch -p1 --forward < patches/all.patch
```

Verified: `git archive HEAD | tar -x` → `patch -p1 --forward < all.patch`
→ exit 0, no rejects, and `diff -r` against the authoring worktree is empty.

---

## Ownership map — one owner per file, no overlapping diffs

The three streams were merged into a single tree, so **there are no competing
hunks**. Each file below appears in exactly one area directory. Do not hand-mix
a hunk from one area onto a file already patched by another; apply `all.patch`
or replace the whole file from `files/`.

| File | Findings | Area |
|---|---|---|
| `android/app/build.gradle.kts` | C4, L6, L12 (doc) | security |
| `android/app/src/main/AndroidManifest.xml` | C2, C6, H9, M12 (doc) | security |
| `android/app/src/main/res/xml/network_security_config.xml` | C2, C6 | security |
| `android/app/src/main/res/xml/data_extraction_rules.xml` | C2 | security |
| `android/key.properties.example` | C4 | security |
| `.gitignore` (new, root) | C4, A11 | security |
| `.../BootReceiver.kt` | H9 | security |
| `.../DeviceControlManager.kt` | H5, H6, A1 (multi-match + call history), A12 | security |
| `.../MainActivity.kt` | C1, H3, H5 plumbing, H8 (`ioExecutor`), A7 (`isManualSession`) | security |
| `lib/services/settings_service.dart` | C2, C3 (brute-force cap), A6 (`revokeTelegramAccess`), M1 flag | security |
| `lib/services/telegram_service.dart` | C3 | security |
| `lib/services/device_control_service.dart` | H5 (Dart gate), A1 (pending choice) | security |
| `lib/services/task_executor.dart` | H5 (honest status), A1 (refuse ambiguous) | security |
| `lib/screens/settings/settings_screen.dart` | A6 (pair / revoke UI), C3 | security |
| `pubspec.yaml` | C2 (secure storage), L10 (assets) | security |
| `lib/services/ai_service.dart` | U3, M8, M9, A13 (intent/JSON logging) | functional |
| `lib/services/voice_service.dart` | U2, H2, A7 (origin flags), A13 (voice logging) | functional |
| `lib/services/jarvis_service.dart` | U1, M3, M4 call site, A1 (choice entry), A7 (ambient gate) | functional |
| `lib/services/contact_disambiguation_service.dart` (new) | A1 (digit chain) | functional |
| `lib/services/air_gesture_service.dart` | M4, M3 | functional |
| `lib/services/phone_storage_service.dart` | H1 | functional |
| `test/widget_test.dart` | H10 | functional |
| `lib/services/edge_tts_service.dart` | M1, M2, L11 (doc) | resources |
| `lib/services/network_audit_service.dart` | H4, A13 (port probe) | resources |
| `lib/services/smart_home_service.dart` | H4 | resources |
| `lib/services/proactive_agent_service.dart` | M5 | resources |
| `lib/services/sentry_service.dart` | M11 | resources |
| `lib/models/screen_node.dart` | L1 | resources |
| `.../InboxNotificationListenerService.kt` | M6 | resources |
| `.../BubbleOverlayService.kt` | C5, M13 | resources |
| `.../AgentAccessibilityService.kt` | H7, H8 (PNG), A14 (recycle comment) | resources |
| `lib/services/security_alert_service.dart` | M10 | resources |
| `lib/services/calendar_reminder_service.dart` | M10 | resources |
| `lib/services/hermes_evolution_service.dart` | M10 | resources |
| `lib/screens/settings/jarvis_settings_screen.dart` | M11 dialog | resources |
| `lib/widgets/network_audit_dialog.dart` | H4 | resources |
| `README.md` | L2, L4, L5, L7, L9, M12 | resources |
| `.github/workflows/build.yml` | L8, L9 | resources |
| `lib/screens/settings/permissions_screen.dart` | L3, A12 (`nearbyWifi` sector) | resources |

---

## Status at a glance

- **Fixed and statically verified:** C1, C2, C3, C4 (scaffold), C5, C6, H1, H2,
  H3, H4, H5, H6, H7, H8, H9, H10, U1, U2, U3, M1 (mitigated + documented), M2,
  M3, M4, M5, M6, M8, M9, M11, M13, L1, L2, L3, L4, L6, L8, L9, L10, A1, A6, A12.
- **Documented instead of changed (deliberate):** L5, L11, L12, M12, A8, A9, A10,
  A15.
- **Deferred with a sketch:** M7 (main-thread storage I/O).
- **Closed by the A13 pass:** all 10 `(b)` empty catches — 9 now log, 1 is
  documented as intentionally silent. 57 `(a)` blocks remain inventoried.
- **Behaviour changes to approve:** H5 (SMS/calls now refuse without a confirm
  hook), U3 (sentences that merely mention "mute" no longer mute), H3 (wake-word
  list narrowed), A7 (auto sessions require the wake word), A1 (an ambiguous
  contact now asks instead of dialling).

See `VERIFICATION.md` for the per-item evidence and `OPEN_QUESTIONS.md` for the
decisions.

---

## What was *not* done

- No keystore generated (C4 ships the scaffold and the loud warning only).
- No `flutter pub get` / `analyze` / `test` / `gradlew` — nothing was executed.
- No remote writes: no branch, commit, PR, release, issue or file deletion.
- No claim that any test passes.
