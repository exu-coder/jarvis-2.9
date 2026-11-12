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
        const val PREFS_NAME = "jarvis_native"
        const val PREF_AUTOSTART = "agent_autostart"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val supported = listOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON"
        )
        if (action !in supported) return

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
