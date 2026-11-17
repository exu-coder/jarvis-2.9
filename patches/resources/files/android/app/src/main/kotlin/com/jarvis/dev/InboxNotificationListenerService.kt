package com.jarvis.dev

import android.app.Notification
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Captures email and SMS notifications from Gmail, Outlook, Yahoo, and native messengers
 * so J.A.R.V.I.S. can triage and read inboxes in real-time.
 *
 * PRIVACY NOTE (design concern, wiring intentionally unchanged): the bodies held
 * here are forwarded to a cloud LLM by `InboxService` for triage, so these lists
 * are the app's main PII path off the device. Retention is therefore bounded on
 * three axes: a 15-minute TTL, a 40-entry cap, and an explicit purge whenever the
 * screen turns off.
 */
class InboxNotificationListenerService : NotificationListenerService() {

    companion object {
        @Volatile
        var isConnected: Boolean = false
            private set

        val capturedEmailNotifications = CopyOnWriteArrayList<Map<String, Any>>()
        val capturedSmsNotifications = CopyOnWriteArrayList<Map<String, Any>>()

        private const val MAX_SAVED = 40

        /** Captured bodies expire 15 minutes after the notification was posted. */
        private const val MAX_AGE_MS = 15 * 60 * 1000L

        fun getRecentEmails(): List<Map<String, Any>> {
            purgeExpired(capturedEmailNotifications)
            return capturedEmailNotifications.toList()
        }

        fun getRecentSms(): List<Map<String, Any>> {
            purgeExpired(capturedSmsNotifications)
            return capturedSmsNotifications.toList()
        }

        /** Drops every captured body immediately. */
        fun purgeAll() {
            capturedEmailNotifications.clear()
            capturedSmsNotifications.clear()
        }

        /** Applies the TTL and then the count cap, newest first. */
        private fun retain(list: CopyOnWriteArrayList<Map<String, Any>>) {
            purgeExpired(list)
            while (list.size > MAX_SAVED) {
                list.removeAt(list.size - 1)
            }
        }

        private fun purgeExpired(list: CopyOnWriteArrayList<Map<String, Any>>) {
            val cutoff = System.currentTimeMillis() - MAX_AGE_MS
            list.removeIf { (it["timestamp"] as? Number)?.toLong()?.let { t -> t < cutoff } ?: true }
        }
    }

    private var screenOffRegistered = false

    private val screenOffReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF) {
                // Screen-off is a natural privacy boundary — drop everything the
                // listener is holding instead of keeping bodies in RAM overnight.
                purgeAll()
            }
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        isConnected = true
        registerScreenOffPurge()
        try {
            val active = activeNotifications
            if (active != null) {
                for (sbn in active) {
                    processNotification(sbn)
                }
            }
        } catch (_: Exception) {}
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        isConnected = false
        unregisterScreenOffPurge()
    }

    override fun onDestroy() {
        unregisterScreenOffPurge()
        super.onDestroy()
    }

    private fun registerScreenOffPurge() {
        if (screenOffRegistered) return
        try {
            // ACTION_SCREEN_OFF is a protected system broadcast, so no
            // RECEIVER_EXPORTED/NOT_EXPORTED flag is required on API 34+.
            registerReceiver(screenOffReceiver, IntentFilter(Intent.ACTION_SCREEN_OFF))
            screenOffRegistered = true
        } catch (e: Exception) {
            android.util.Log.w("INBOX_LISTENER", "screen-off purge receiver unavailable: $e")
        }
    }

    private fun unregisterScreenOffPurge() {
        if (!screenOffRegistered) return
        try {
            unregisterReceiver(screenOffReceiver)
        } catch (e: Exception) {
            android.util.Log.w("INBOX_LISTENER", "screen-off purge receiver unregister failed: $e")
        }
        screenOffRegistered = false
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return
        processNotification(sbn)
    }

    private fun processNotification(sbn: StatusBarNotification) {
        val pkg = sbn.packageName ?: ""
        val extras = sbn.notification?.extras ?: return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
            ?: extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""
        val postTime = sbn.postTime

        if (title.isBlank() && text.isBlank()) return

        val item = mapOf(
            "package" to pkg,
            "title" to title,
            "text" to text,
            "subText" to subText,
            "timestamp" to postTime,
            "id" to sbn.id.toString()
        )

        val isEmail = pkg.contains("mail", ignoreCase = true) ||
                pkg.contains("outlook", ignoreCase = true) ||
                pkg == "com.google.android.gm" ||
                pkg == "com.microsoft.office.outlook" ||
                pkg == "com.yahoo.mobile.client.android.mail" ||
                pkg == "com.samsung.android.email.provider"

        val isSms = pkg.contains("messaging", ignoreCase = true) ||
                pkg.contains("mms", ignoreCase = true) ||
                pkg == "com.google.android.apps.messaging" ||
                pkg == "com.samsung.android.messaging"

        if (isEmail) {
            capturedEmailNotifications.removeIf { it["title"] == title && it["text"] == text }
            capturedEmailNotifications.add(0, item)
            retain(capturedEmailNotifications)
        } else if (isSms) {
            capturedSmsNotifications.removeIf { it["title"] == title && it["text"] == text }
            capturedSmsNotifications.add(0, item)
            retain(capturedSmsNotifications)
        }
    }
}
