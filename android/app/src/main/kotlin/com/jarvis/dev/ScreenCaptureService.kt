package com.jarvis.dev

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

/**
 * Foreground service (type `mediaProjection`) that owns the screen-capture
 * session granted through the system MediaProjection consent dialog.
 *
 * Lifecycle:
 *  1. The UI asks the user for consent (`MediaProjectionManager.createScreenCaptureIntent`).
 *  2. `MainActivity.onActivityResult` hands `resultCode` + the result [Intent] to [start].
 *  3. This service starts foreground FIRST (mandatory on Android 14+), then
 *     creates the projection, virtual display and frame reader.
 *  4. `MainActivity`/`DeviceControlManager` pull frames through [captureFrame].
 *
 * The consent token is single-use: the service keeps it only while alive and
 * releases everything on stop.
 */
class ScreenCaptureService : Service() {

    companion object {
        private const val TAG = "JARVIS_SCREEN"
        const val CHANNEL_ID = "jarvis_screen_capture"
        const val NOTIFICATION_ID = 4103
        const val ACTION_START = "com.jarvis.dev.action.START_SCREEN_CAPTURE"
        const val ACTION_STOP = "com.jarvis.dev.action.STOP_SCREEN_CAPTURE"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"

        @Volatile
        var isRunning: Boolean = false
            private set

        private var instance: ScreenCaptureService? = null
        private var latestBitmap: Bitmap? = null

        /** Starts the capture session using a freshly granted consent result. */
        fun start(activity: Activity, resultCode: Int, data: Intent) {
            val intent = Intent(activity, ScreenCaptureService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_RESULT_CODE, resultCode)
                .putExtra(EXTRA_RESULT_DATA, data)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.startForegroundService(intent)
            } else {
                activity.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, ScreenCaptureService::class.java).apply {
                action = ACTION_STOP
            }
            if (isRunning) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            }
        }

        /** Latest captured screen frame, or null when no session is active. */
        fun captureFrame(): Bitmap? = instance?.grabFrame() ?: latestBitmap
    }

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var width = 0
    private var height = 0
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        instance = this
        ensureChannel()
        // MUST start foreground before touching the projection on Android 14+.
        startForeground(NOTIFICATION_ID, buildNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_START) {
            val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, -1)
            val data: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(EXTRA_RESULT_DATA)
            }
            if (resultCode == -1 || data == null) {
                stopSelf()
            } else {
                setUpProjection(resultCode, data)
            }
        }
        return START_STICKY
    }

    private fun setUpProjection(resultCode: Int, data: Intent) {
        val manager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        try {
            val projection = manager.getMediaProjection(resultCode, data)

            val callback = object : MediaProjection.Callback() {
                override fun onStop() {
                    releaseResources()
                    stopSelf()
                }
            }
            projection.registerCallback(callback, mainHandler)

            val metrics = resources.displayMetrics
            width = metrics.widthPixels
            height = metrics.heightPixels
            val density = metrics.densityDpi

            val reader = ImageReader.newInstance(width, height, android.graphics.PixelFormat.RGBA_8888, 2)
            imageReader = reader

            val display = projection.createVirtualDisplay(
                "JarvisScreenCapture",
                width,
                height,
                density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface,
                null,
                mainHandler
            )
            virtualDisplay = display
            mediaProjection = projection
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set up screen capture: $e")
            releaseResources()
            stopSelf()
        }
    }

    fun grabFrame(): Bitmap? {
        val reader = imageReader ?: return latestBitmap
        var image: Image? = null
        return try {
            image = reader.acquireLatestImage()
            if (image == null) {
                latestBitmap
            } else {
                val plane = image.planes[0]
                val buffer = plane.buffer
                val pixelStride = plane.pixelStride
                val rowStride = plane.rowStride
                val rowPadding = rowStride - pixelStride * width
                val raw = Bitmap.createBitmap(
                    width + rowPadding / pixelStride,
                    height,
                    Bitmap.Config.ARGB_8888
                )
                raw.copyPixelsFromBuffer(buffer)
                val frame = Bitmap.createBitmap(raw, 0, 0, width, height)
                if (raw !== frame) raw.recycle()
                latestBitmap = frame
                frame
            }
        } catch (e: Exception) {
            Log.e(TAG, "grabFrame failed: $e")
            latestBitmap
        } finally {
            try {
                image?.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun releaseResources() {
        try {
            virtualDisplay?.release()
        } catch (_: Exception) {
        }
        virtualDisplay = null
        try {
            imageReader?.close()
        } catch (_: Exception) {
        }
        imageReader = null
        try {
            mediaProjection?.stop()
        } catch (_: Exception) {
        }
        mediaProjection = null
        latestBitmap = null
    }

    override fun onDestroy() {
        releaseResources()
        isRunning = false
        instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun ensureChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                getString(R.string.screen_capture_channel_name),
                NotificationManager.IMPORTANCE_LOW
            )
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            2,
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            ),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.screen_capture_title))
            .setContentText(getString(R.string.screen_capture_text))
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(openApp)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setShowWhen(false)
            .build()
    }
}
