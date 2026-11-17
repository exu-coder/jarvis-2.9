package com.jarvis.dev

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restarts the agent core after the device boots so scheduled protocols and
 * proactive routines survive reboots.
 *
 * Autostart is opt-in: the user enables it once from the JARVIS settings
 * (stored in the `jarvis_native` preferences file by the Dart bridge via the
 * `com.jarvis.dev/device` channel).
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "JARVIS_BOOT"

        const val PREFS_NAME = "jarvis_native"
        const val PREF_AUTOSTART = "agent_autostart"

        /**
         * H9: the only actions this receiver reacts to. Every other action is
         * dropped before any work happens.
         *
         * The receiver is declared `android:exported="false"` in the manifest,
         * so third-party apps cannot deliver these intents either. Boot
         * broadcasts are protected system broadcasts: they are delivered by the
         * system to non-exported receivers, so `exported="false"` does not stop
         * BOOT_COMPLETED from arriving.
         */
        private val ALLOWED_ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON"
        )
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action !in ALLOWED_ACTIONS) {
            android.util.Log.w(TAG, "Ignoring unexpected action: $action")
            return
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(PREF_AUTOSTART, false)) return

        try {
            AgentService.start(context)
        } catch (_: Exception) {
            // Foreground-service start may be restricted on some OEMs; silently
            // degrade — the user can start the agent manually.
        }
    }
}
