package com.jarvis.dev

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder

/**
 * Foreground service (type `connectedDevice`) that watches Bluetooth /
 * connected-device state so the assistant can reason about wearables,
 * headphones and car kits while it is running.
 */
class ConnectedDeviceService : Service() {

    companion object {
        const val CHANNEL_ID = "jarvis_connected_devices"
        const val NOTIFICATION_ID = 4104
        const val ACTION_START = "com.jarvis.dev.action.START_CONNECTED_DEVICE"
        const val ACTION_STOP = "com.jarvis.dev.action.STOP_CONNECTED_DEVICE"

        /** Bluetooth state map for the Dart bridge: {enabled, connected}. */
        @Volatile
        var bluetoothEnabled: Boolean = false
            private set

        @Volatile
        var isRunning: Boolean = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, ConnectedDeviceService::class.java).apply {
                action = ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, ConnectedDeviceService::class.java).apply { action = ACTION_STOP }
            )
        }
    }

    private val btStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                val state = intent.getIntExtra(
                    BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR
                )
                bluetoothEnabled = state == BluetoothAdapter.STATE_ON
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        ensureChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        registerReceiver(btStateReceiver, filter)
        refreshBluetoothState()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
        }
        refreshBluetoothState()
        return START_STICKY
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(btStateReceiver)
        } catch (_: Exception) {
        }
        isRunning = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun refreshBluetoothState() {
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothEnabled = manager?.adapter?.isEnabled == true
    }

    private fun ensureChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.connected_device_channel_name),
                NotificationManager.IMPORTANCE_LOW
            )
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            3,
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.connected_device_title))
            .setContentText(getString(R.string.connected_device_text))
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(openApp)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setShowWhen(false)
            .build()
    }
}
