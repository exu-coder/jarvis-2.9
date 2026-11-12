package com.jarvis.dev

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder

/**
 * Foreground service (type `location`) that continuously tracks the device
 * position while a location-aware task runs ("where am I", commute checks,
 * proactive reminders, …).
 *
 * Rules enforced here:
 *  - Refuses to start unless ACCESS_FINE_LOCATION (or coarse) is already granted.
 *  - Never requests permissions itself; the UI layer does that first.
 *  - Publishes the latest fix through [lastLocation] and [listener] so any
 *    component (including the Flutter bridge) can read it.
 */
class LocationService : Service() {

    companion object {
        const val CHANNEL_ID = "jarvis_location_tracking"
        const val NOTIFICATION_ID = 4102
        const val ACTION_START = "com.jarvis.dev.action.START_LOCATION"
        const val ACTION_STOP = "com.jarvis.dev.action.STOP_LOCATION"

        /** Latest known fix, published for the Dart bridge. */
        @Volatile
        var lastLocation: Location? = null
            private set

        /** Optional external listener (set by MainActivity before the fix arrives). */
        @Volatile
        var listener: LocationListener? = null

        @Volatile
        var isRunning: Boolean = false
            private set

        fun start(context: Context) {
            if (!hasLocationPermission(context)) return
            val intent = Intent(context, LocationService::class.java).apply {
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
                Intent(context, LocationService::class.java).apply { action = ACTION_STOP }
            )
        }

        fun hasLocationPermission(context: Context): Boolean {
            return context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED ||
                context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    private val locationManager: LocationManager?
        get() = getSystemService(Context.LOCATION_SERVICE) as? LocationManager

    private val internalListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            lastLocation = location
            listener?.onLocationChanged(location)
        }

        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        ensureChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        startTracking()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
        }
        if (intent?.action == ACTION_START) startTracking()
        return START_STICKY
    }

    override fun onDestroy() {
        try {
            locationManager?.removeUpdates(internalListener)
        } catch (_: Exception) {
        }
        isRunning = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startTracking() {
        val manager = locationManager ?: return
        if (!hasLocationPermission(this)) {
            stopSelf()
            return
        }
        try {
            val enabled = manager.allProviders.filter { manager.isProviderEnabled(it) }
            if (enabled.isEmpty()) {
                stopSelf()
                return
            }
            val listenerHandler = android.os.Handler(android.os.Looper.getMainLooper())
            if (enabled.contains(LocationManager.NETWORK_PROVIDER)) {
                manager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER, 10_000L, 15f, internalListener, listenerHandler.looper
                )
            }
            if (enabled.contains(LocationManager.GPS_PROVIDER)) {
                manager.requestLocationUpdates(
                    LocationManager.GPS_PROVIDER, 5_000L, 8f, internalListener, listenerHandler.looper
                )
            }
        } catch (_: SecurityException) {
            stopSelf()
        }
    }

    private fun ensureChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.location_service_channel_name),
                NotificationManager.IMPORTANCE_LOW
            )
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            1,
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.location_service_title))
            .setContentText(getString(R.string.location_service_text))
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(openApp)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setShowWhen(false)
            .build()
    }
}
