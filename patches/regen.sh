#!/usr/bin/env bash
# Regenerate patches/all.patch, the per-area per-file patches and files/ copies.
# Run from the authoring worktree root (jarvis-2.9 at b573599).
set -euo pipefail

# Audit baseline: every patch is expressed relative to this commit.
BASE=b5735999f54a51de2ce54ea414198b1dbd18064a

cd "$(dirname "$0")/.."

SEC=(
  android/app/build.gradle.kts
  android/app/src/main/AndroidManifest.xml
  android/app/src/main/res/xml/network_security_config.xml
  android/app/src/main/res/xml/data_extraction_rules.xml
  android/key.properties.example
  android/app/src/main/kotlin/com/jarvis/dev/BootReceiver.kt
  android/app/src/main/kotlin/com/jarvis/dev/DeviceControlManager.kt
  android/app/src/main/kotlin/com/jarvis/dev/MainActivity.kt
  lib/services/settings_service.dart
  lib/services/telegram_service.dart
  lib/services/device_control_service.dart
  lib/services/task_executor.dart
  pubspec.yaml
  lib/screens/settings/settings_screen.dart
  .gitignore
)

FUN=(
  lib/services/ai_service.dart
  lib/services/voice_service.dart
  lib/services/jarvis_service.dart
  lib/services/air_gesture_service.dart
  lib/services/phone_storage_service.dart
  test/widget_test.dart
  lib/services/contact_disambiguation_service.dart
  # Agent-mode-by-default: the HUD ask path and the task executor route device
  # actions instead of answering "switch to Agent mode".
  lib/services/agent_router_service.dart
  lib/screens/hud/hud_home_screen.dart
  lib/services/app_launcher_service.dart
)

RES=(
  lib/services/edge_tts_service.dart
  lib/services/network_audit_service.dart
  lib/services/smart_home_service.dart
  lib/services/proactive_agent_service.dart
  lib/services/sentry_service.dart
  lib/models/screen_node.dart
  android/app/src/main/kotlin/com/jarvis/dev/InboxNotificationListenerService.kt
  android/app/src/main/kotlin/com/jarvis/dev/BubbleOverlayService.kt
  android/app/src/main/kotlin/com/jarvis/dev/AgentAccessibilityService.kt
  lib/services/security_alert_service.dart
  lib/services/calendar_reminder_service.dart
  lib/services/hermes_evolution_service.dart
  lib/screens/settings/jarvis_settings_screen.dart
  lib/widgets/network_audit_dialog.dart
  lib/widgets/brain_dump_dialog.dart
  README.md
  .github/workflows/build.yml
  lib/screens/settings/permissions_screen.dart
  analysis_options.yaml
)

emit_area() {
  local area="$1"; shift
  local -a files=("$@")
  local n=0
  rm -rf "patches/$area/files"
  mkdir -p "patches/$area/files"
  # Numbering shifts when a file is inserted, so drop the old set first —
  # otherwise `15-README.md.patch` lingers next to `16-README.md.patch`.
  rm -f patches/"$area"/*.patch
  for f in "${files[@]}"; do
    n=$((n+1))
    local base
    base="$(basename "$f")"
    local out
    out="$(printf 'patches/%s/%02d-%s.patch' "$area" "$n" "$base")"
    # Diffed against the audit baseline, not HEAD: the patch set must describe
    # the complete remediation from a pristine b573599.
    git diff "$BASE" -- "$f" > "$out"
    if [ ! -s "$out" ]; then
      echo "WARN: empty patch for $f" >&2
    fi
    mkdir -p "patches/$area/files/$(dirname "$f")"
    cp "$f" "patches/$area/files/$f"
  done
  echo "$area: $n files"
}

emit_area security "${SEC[@]}"
emit_area functional "${FUN[@]}"
emit_area resources "${RES[@]}"

# Authoritative combined diff: source changes only, against the audit baseline.
git diff "$BASE" -- \
  . ':!patches' ':!tests' ':!report.md' ':!VERIFICATION.md' ':!OPEN_QUESTIONS.md' \
  > patches/all.patch

echo "all.patch: $(git apply --numstat patches/all.patch | wc -l) files"
git apply --numstat patches/all.patch | awk '{a+=$1; d+=$2} END {print "all.patch: +" a " -" d}'
