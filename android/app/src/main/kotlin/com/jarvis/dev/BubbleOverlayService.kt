package com.jarvis.dev

import android.annotation.SuppressLint
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * System-wide floating 𝐉.𝐀.𝐑.𝐕.𝐈.𝐒 bubble rendered with the HTML design
 * (`assets/hud/bubble_orb.html` collapsed, `assets/hud/bubble.html` expanded).
 *
 * Contract with the HTML side:
 *   - Collapsed orb: pure visual; drag + tap are handled natively here.
 *   - Expanded panel: `window.BUBBLE_NATIVE` JS interface exposes
 *     `expand()`, `collapse()`, `close()`, `openApp()` and `ask(text)`.
 *     AI answers are delivered back via `window.onBubbleReply(text)`.
 *
 * Requires `Settings.canDrawOverlays()` (checked by the caller on the
 * `com.jarvis.dev/device` channel before starting this service).
 */
class BubbleOverlayService : Service() {

    companion object {
        const val ACTION_START = "com.jarvis.dev.action.START_BUBBLE"
        const val ACTION_STOP = "com.jarvis.dev.action.STOP_BUBBLE"

        private const val PREFS = "bubble_overlay_prefs"
        private const val KEY_X = "x"
        private const val KEY_Y = "y"

        // Collapsed window gives the 64dp orb room for its halo rings.
        private const val ORB_WINDOW_DP = 96
        private const val ORB_DP = 64

        @Volatile
        var isRunning: Boolean = false
            private set

        fun start(context: Context) {
            context.startService(
                Intent(context, BubbleOverlayService::class.java).apply { action = ACTION_START }
            )
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, BubbleOverlayService::class.java).apply { action = ACTION_STOP }
            )
        }
    }

    private lateinit var windowManager: WindowManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private var orbWindow: View? = null
    private var orbParams: WindowManager.LayoutParams? = null
    private var panelWindow: WebView? = null
    private var panelParams: WindowManager.LayoutParams? = null

    private var density = 1f
    private var screenW = 1080
    private var screenH = 1920

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                teardown()
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                if (!Settings.canDrawOverlays(this)) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                if (orbWindow == null && panelWindow == null) setup()
            }
        }
        return START_STICKY
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
    }

    override fun onDestroy() {
        teardown()
        isRunning = false
        super.onDestroy()
    }

    // ------------------------------------------------------------------
    // Window setup
    // ------------------------------------------------------------------

    @SuppressLint("ClickableViewAccessibility")
    private fun setup() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        density = resources.displayMetrics.density
        val metrics = windowManager.currentWindowMetricsCompat()
        screenW = metrics.width
        screenH = metrics.height

        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val savedX = prefs.getInt(KEY_X, Int.MIN_VALUE)
        val savedY = prefs.getInt(KEY_Y, Int.MIN_VALUE)
        val winSize = (ORB_WINDOW_DP * density).toInt()

        val overlayType = WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY

        val params = WindowManager.LayoutParams(
            winSize,
            winSize,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = if (savedX != Int.MIN_VALUE) savedX else screenW - winSize - (12 * density).toInt()
            y = if (savedY != Int.MIN_VALUE) savedY else (screenH * 0.25f).toInt()
        }

        val webView = WebView(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            setLayerType(View.LAYER_TYPE_HARDWARE, null)
            settings.javaScriptEnabled = true
            settings.allowFileAccess = true
            settings.mediaPlaybackRequiresUserGesture = false
            loadUrl("file:///android_asset/hud/bubble_orb.html")
        }

        webView.setOnTouchListener(OrbTouchListener(webView, params))
        orbWindow = webView
        orbParams = params
        windowManager.addView(webView, params)
    }

    // ------------------------------------------------------------------
    // Collapsed drag + tap
    // ------------------------------------------------------------------

    private inner class OrbTouchListener(
        private val view: View,
        private val params: WindowManager.LayoutParams
    ) : View.OnTouchListener {

        private var downX = 0f
        private var downY = 0f
        private var downAt = 0L
        private var startWinX = 0
        private var startWinY = 0
        private var moved = false

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouch(v: View, event: MotionEvent): Boolean {
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    moved = false
                    downX = event.rawX
                    downY = event.rawY
                    downAt = System.currentTimeMillis()
                    startWinX = params.x
                    startWinY = params.y
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downX).toInt()
                    val dy = (event.rawY - downY).toInt()
                    if (!moved && (abs(dx) > 8 || abs(dy) > 8)) moved = true
                    if (moved) {
                        params.x = clampX(startWinX + dx)
                        params.y = clampY(startWinY + dy)
                        windowManager.updateViewLayout(view, params)
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (event.action == MotionEvent.ACTION_UP) {
                        if (moved) {
                            savePosition()
                        } else if (System.currentTimeMillis() - downAt < 400L) {
                            expand() // clean tap → open the copilot panel
                        }
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun clampX(x: Int): Int {
        val win = (ORB_WINDOW_DP * density).toInt()
        val margin = ((ORB_WINDOW_DP - ORB_DP) * density).toInt()
        return min(max(x, -margin), screenW - win + margin)
    }

    private fun clampY(y: Int): Int =
        min(max(y, 0), screenH - (ORB_WINDOW_DP * density).toInt())

    private fun savePosition() {
        orbParams ?: return
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_X, orbParams!!.x)
            .putInt(KEY_Y, orbParams!!.y)
            .apply()
    }

    // ------------------------------------------------------------------
    // Expanded copilot panel
    // ------------------------------------------------------------------

    @SuppressLint("SetJavaScriptEnabled")
    private fun expand() {
        if (panelWindow != null) return
        mainHandler.post {
            try {
                orbWindow?.let { windowManager.removeView(it) }
            } catch (_: Exception) {
            }
            orbWindow = null
            orbParams = null

            val width = min(screenW - (16 * density).toInt(), (390 * density).toInt())
            val height = min((screenH * 0.72f).toInt(), (640 * density).toInt())
            val x = ((screenW - width) / 2)
            val y = screenH - height - (16 * density).toInt()

            val params = WindowManager.LayoutParams(
                width,
                height,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                this.x = x
                this.y = y
                softInputMode =
                    WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE or
                    WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
            }

            val webView = WebView(this).apply {
                setBackgroundColor(Color.TRANSPARENT)
                setLayerType(View.LAYER_TYPE_HARDWARE, null)
                settings.javaScriptEnabled = true
                settings.allowFileAccess = true
                settings.domStorageEnabled = true
                settings.mediaPlaybackRequiresUserGesture = false
                addJavascriptInterface(BubbleNativeBridge(), "BUBBLE_NATIVE")
                webViewClient = WebViewClient()
                loadUrl("file:///android_asset/hud/bubble.html")
            }

            panelWindow = webView
            panelParams = params
            try {
                windowManager.addView(webView, params)
            } catch (_: Exception) {
                panelWindow = null
                panelParams = null
                rebuildOrb()
            }
        }
    }

    private fun collapse() {
        if (panelWindow == null) return
        mainHandler.post {
            try {
                panelWindow?.let { windowManager.removeView(it) }
            } catch (_: Exception) {
            }
            panelWindow = null
            panelParams = null
            rebuildOrb()
        }
    }

    private fun teardown() {
        mainHandler.post {
            try {
                panelWindow?.let { windowManager.removeView(it) }
                orbWindow?.let { windowManager.removeView(it) }
            } catch (_: Exception) {
            }
            panelWindow = null
            panelParams = null
            orbWindow = null
            orbParams = null
        }
    }

    /** Delivers an AI answer into the expanded panel. */
    fun deliverReply(reply: String?) {
        val safe = (reply ?: "My apologies, sir — the uplink is unavailable.")
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "")
        mainHandler.post {
            panelWindow?.evaluateJavascript("window.onBubbleReply(\"$safe\");", null)
        }
    }

    private fun rebuildOrb() {
        if (!Settings.canDrawOverlays(this) || orbWindow != null) return
        setup()
    }

    // ------------------------------------------------------------------
    // JS bridge (window.BUBBLE_NATIVE)
    // ------------------------------------------------------------------

    private inner class BubbleNativeBridge {
        @JavascriptInterface
        fun expand() {
            // Panel window is already full-size; nothing to resize natively.
            // (HTML-side expand() also opens the panel locally.)
        }

        @JavascriptInterface
        fun collapse() {
            this@BubbleOverlayService.collapse()
        }

        @JavascriptInterface
        fun close() {
            stopSelf()
        }

        @JavascriptInterface
        fun openApp() {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this@BubbleOverlayService, MainActivity::class.java)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            startActivity(intent)
            stopSelf()
        }

        @JavascriptInterface
        fun ask(text: String) {
            mainHandler.post {
                MainActivity.dispatchBubbleAsk(text) { reply ->
                    if (reply == null) {
                        // Dart core unreachable → open the full app instead.
                        val intent = packageManager.getLaunchIntentForPackage(packageName)
                            ?: Intent(this@BubbleOverlayService, MainActivity::class.java)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                    } else {
                        deliverReply(reply)
                    }
                }
            }
        }
    }
}

/** API-30+ aware screen metrics. */
private fun WindowManager.currentWindowMetricsCompat(): android.graphics.Point {
    return try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = currentWindowMetrics.bounds
            android.graphics.Point(b.width(), b.height())
        } else {
            @Suppress("DEPRECATION")
            val m = android.util.DisplayMetrics()
            @Suppress("DEPRECATION")
            defaultDisplay.getRealMetrics(m)
            android.graphics.Point(m.widthPixels, m.heightPixels)
        }
    } catch (_: Exception) {
        android.graphics.Point(1080, 1920)
    }
}
