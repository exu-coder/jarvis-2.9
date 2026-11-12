package com.jarvis.dev

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.AppOpsManager
import android.app.NotificationManager
import android.app.admin.DevicePolicyManager
import android.bluetooth.BluetoothManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.location.Location
import android.location.LocationManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.provider.Settings
import android.telephony.SmsManager
import android.provider.MediaStore
import android.util.Base64
import java.io.ByteArrayOutputStream

/**
 * Central permission + device-control gateway.
 *
 * Every capability the JARVIS core AI can invoke (calling, messaging, alarms,
 * locations, screen capture, storage, volume/brightness, torch, screen lock…)
 * is routed through this object so permission checks and special-access states
 * live in exactly one place.
 */
object DeviceControlManager {

    // ------------------------------------------------------------------
    // Runtime permission catalog
    // ------------------------------------------------------------------

    /** All dangerous permissions the manifest declares, grouped by logical key. */
    val permissionGroups: Map<String, List<String>> = mapOf(
        "microphone" to listOf(Manifest.permission.RECORD_AUDIO),
        "camera" to listOf(Manifest.permission.CAMERA),
        "location" to listOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ),
        "backgroundLocation" to listOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
        "contacts" to listOf(
            Manifest.permission.READ_CONTACTS,
            Manifest.permission.WRITE_CONTACTS
        ),
        "calendar" to listOf(
            Manifest.permission.READ_CALENDAR,
            Manifest.permission.WRITE_CALENDAR
        ),
        "sms" to listOf(
            Manifest.permission.SEND_SMS,
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_SMS,
            Manifest.permission.RECEIVE_MMS,
            Manifest.permission.RECEIVE_WAP_PUSH
        ),
        "phone" to listOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_PHONE_NUMBERS,
            Manifest.permission.CALL_PHONE,
            Manifest.permission.ANSWER_PHONE_CALLS
        ),
        "callLog" to listOf(
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.WRITE_CALL_LOG
        ),
        "media" to listOf(
            Manifest.permission.READ_MEDIA_IMAGES,
            Manifest.permission.READ_MEDIA_VIDEO,
            Manifest.permission.READ_MEDIA_AUDIO,
            Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
        ),
        "bluetooth" to listOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_ADVERTISE
        ),
        "nearbyWifi" to listOf(Manifest.permission.NEARBY_WIFI_DEVICES),
        "bodySensors" to listOf(Manifest.permission.BODY_SENSORS),
        "activity" to listOf(Manifest.permission.ACTIVITY_RECOGNITION),
        "notifications" to listOf(Manifest.permission.POST_NOTIFICATIONS)
    )

    // ------------------------------------------------------------------
    // Permission report
    // ------------------------------------------------------------------

    private fun Context.isGranted(permission: String): Boolean =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    /** Logical permission name -> granted (runtime + special-access combined). */
    fun permissionReport(context: Context): Map<String, Boolean> {
        val c = context.applicationContext
        val report = mutableMapOf<String, Boolean>()
        permissionGroups.forEach { (key, perms) ->
            val relevant = if (key == "media" && Build.VERSION.SDK_INT < 33) {
                listOf(Manifest.permission.READ_EXTERNAL_STORAGE)
            } else if (key == "media" && Build.VERSION.SDK_INT >= 34) {
                perms
            } else {
                perms
            }
            report[key] = relevant.any { c.isGranted(it) }
        }
        report["overlay"] = Settings.canDrawOverlays(c)
        report["accessibility"] = AgentAccessibilityService.isConnected
        report["notificationListener"] = isNotificationListenerEnabled(c)
        report["usageStats"] = hasUsageStatsAccess(c)
        report["writeSettings"] = Settings.System.canWrite(c)
        report["allFiles"] = hasAllFilesAccess(c)
        report["installPackages"] = hasInstallPackagesAccess(c)
        report["exactAlarm"] = hasExactAlarmAccess(c)
        report["batteryOptimization"] = isIgnoringBattery(c)
        report["dndPolicy"] = hasDndPolicyAccess(c)
        report["deviceAdmin"] = isDeviceAdminActive(c)
        report["wakeWord"] = c.isGranted(Manifest.permission.RECORD_AUDIO)
        report["syncSettings"] = true // manifest-level, always true once declared
        return report
    }

    private fun isNotificationListenerEnabled(c: Context): Boolean {
        val listeners = Settings.Secure.getString(
            c.contentResolver, "enabled_notification_listeners"
        ) ?: return false
        return listeners.split(":").any {
            it.contains(c.packageName)
        }
    }

    private fun hasUsageStatsAccess(c: Context): Boolean {
        return try {
            val appOps = c.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    c.packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    c.packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (_: Exception) {
            false
        }
    }

    private fun hasAllFilesAccess(c: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.R || Environment.isExternalStorageManager()

    private fun hasInstallPackagesAccess(c: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            c.packageManager.canRequestPackageInstalls()

    private fun hasExactAlarmAccess(c: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarm = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarm.canScheduleExactAlarms()
        } else {
            true
        }

    private fun isIgnoringBattery(c: Context): Boolean {
        val pm = c.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(c.packageName)
    }

    private fun hasDndPolicyAccess(c: Context): Boolean {
        return try {
            val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.isNotificationPolicyAccessGranted
        } catch (_: Exception) {
            false
        }
    }

    private fun isDeviceAdminActive(c: Context): Boolean {
        return try {
            val dpm = c.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            dpm.isAdminActive(ComponentName(c, JarvisDeviceAdminReceiver::class.java))
        } catch (_: Exception) {
            false
        }
    }

    // ------------------------------------------------------------------
    // Runtime permission request (batch)
    // ------------------------------------------------------------------

    /** Flattens logical group keys into the exact permission strings to request. */
    fun permissionsFor(groups: List<String>): List<String> {
        val requested = mutableSetOf<String>()
        for (group in groups) {
            permissionGroups[group]?.let { requested.addAll(it) }
        }
        return requested.filter { perm ->
            val minSdk = when (perm) {
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE,
                Manifest.permission.NEARBY_WIFI_DEVICES -> Build.VERSION_CODES.S
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_AUDIO -> Build.VERSION_CODES.TIRAMISU
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED -> Build.VERSION_CODES.UPSIDE_DOWN_CAKE
                Manifest.permission.POST_NOTIFICATIONS -> Build.VERSION_CODES.TIRAMISU
                Manifest.permission.BODY_SENSORS_BACKGROUND -> Build.VERSION_CODES.TIRAMISU
                else -> 0
            }
            Build.VERSION.SDK_INT >= minSdk
        }
    }

    // ------------------------------------------------------------------
    // Settings navigation
    // ------------------------------------------------------------------

    /** Opens the system settings page that governs a special-access permission. */
    fun openSettingsPage(activity: Activity, page: String): Boolean {
        val intent = when (page) {
            "overlay" -> Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${activity.packageName}")
            )
            "notificationListener" -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            "battery" -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:${activity.packageName}")
            }
            "writeSettings" -> Intent(
                Settings.ACTION_MANAGE_WRITE_SETTINGS,
                Uri.parse("package:${activity.packageName}")
            )
            "installPackages" -> Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:${activity.packageName}")
            }
            "allFiles" -> Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION).apply {
                data = Uri.parse("package:${activity.packageName}")
            }
            "exactAlarm" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                    data = Uri.parse("package:${activity.packageName}")
                }
            } else {
                Intent(Settings.ACTION_SETTINGS)
            }
            "dndPolicy" -> Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            "deviceAdmin" -> Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                putExtra(
                    DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                    ComponentName(activity, JarvisDeviceAdminReceiver::class.java)
                )
                putExtra(
                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    "Required for 𝐉.𝐀.𝐑.𝐕.𝐈.𝐒 screen-lock and Sentry anti-theft actions."
                )
            }
            "location" -> Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            "usageStats" -> Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            "appInfo" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${activity.packageName}")
            }
            "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "wireless" -> Intent(Settings.ACTION_WIRELESS_SETTINGS)
            "display" -> Intent(Settings.ACTION_DISPLAY_SETTINGS)
            "sound" -> Intent(Settings.ACTION_SOUND_SETTINGS)
            "nfc" -> Intent("android.settings.NFC_SETTINGS")
            "storage" -> Intent(Settings.ACTION_INTERNAL_STORAGE_SETTINGS)
            else -> return false
        }
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /** Opens an Android 10+ quick settings panel (wifi / bluetooth / internet…). */
    fun openPanel(context: Context, panel: String): Boolean {
        val action = when (panel) {
            "wifi" -> if (Build.VERSION.SDK_INT >= 29) Settings.Panel.ACTION_WIFI else null
            "bluetooth" -> if (Build.VERSION.SDK_INT >= 29) "android.settings.BLUETOOTH_SETTINGS" else null
            "internet" -> if (Build.VERSION.SDK_INT >= 29) Settings.Panel.ACTION_INTERNET_CONNECTIVITY else null
            "nfc" -> if (Build.VERSION.SDK_INT >= 29) Settings.Panel.ACTION_NFC else null
            "volume" -> if (Build.VERSION.SDK_INT >= 29) Settings.Panel.ACTION_VOLUME else null
            else -> null
        }
        return try {
            if (action != null) {
                context.startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } else {
                context.startActivity(
                    Intent(Settings.ACTION_WIRELESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    // ------------------------------------------------------------------
    // Service control
    // ------------------------------------------------------------------

    fun serviceStatus(context: Context): Map<String, Any> {
        val location = LocationService.lastLocation
        return mapOf<String, Any>(
            "agent" to AgentService.isRunning,
            "screenCapture" to ScreenCaptureService.isRunning,
            "location" to LocationService.isRunning,
            "connectedDevice" to ConnectedDeviceService.isRunning,
            "bluetooth" to ConnectedDeviceService.bluetoothEnabled,
            "locationPermission" to LocationService.hasLocationPermission(context),
            "hasFix" to (location != null)
        )
    }

    fun startService(context: Context, service: String): Map<String, Any> {
        return try {
            when (service) {
                "agent" -> AgentService.start(context)
                "location" -> LocationService.start(context)
                "connectedDevice" -> ConnectedDeviceService.start(context)
                "screenCapture" -> return mapOf<String, Any>(
                    "success" to false,
                    "message" to "Screen capture needs MediaProjection consent first (requestScreenCapture)."
                )
                else -> return mapOf<String, Any>(
                    "success" to false,
                    "message" to "Unknown service: $service"
                )
            }
            mapOf<String, Any>("success" to true, "message" to "Started $service service.")
        } catch (e: Exception) {
            mapOf<String, Any>("success" to false, "message" to (e.message ?: "start failed"))
        }
    }

    fun stopService(context: Context, service: String): Map<String, Any> {
        return try {
            when (service) {
                "agent" -> AgentService.stop(context)
                "location" -> LocationService.stop(context)
                "connectedDevice" -> ConnectedDeviceService.stop(context)
                "screenCapture" -> ScreenCaptureService.stop(context)
                else -> return mapOf<String, Any>(
                    "success" to false,
                    "message" to "Unknown service: $service"
                )
            }
            mapOf<String, Any>("success" to true, "message" to "Stopped $service service.")
        } catch (e: Exception) {
            mapOf<String, Any>("success" to false, "message" to (e.message ?: "stop failed"))
        }
    }

    fun setAutostart(context: Context, enabled: Boolean) {
        context.getSharedPreferences(BootReceiver.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(BootReceiver.PREF_AUTOSTART, enabled)
            .apply()
    }

    // ------------------------------------------------------------------
    // Screen capture
    // ------------------------------------------------------------------

    /** Latest screen frame as JPEG bytes (for the vision pipeline), or null. */
    fun captureFrameJpeg(context: Context, quality: Int = 85): Map<String, Any>? {
        val bitmap = ScreenCaptureService.captureFrame() ?: return null
        val stream = ByteArrayOutputStream()
        bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, quality, stream)
        val bytes = stream.toByteArray()
        return mapOf<String, Any>(
            "base64" to Base64.encodeToString(bytes, Base64.NO_WRAP),
            "size" to bytes.size,
            "path" to (saveToCache(context, bytes) ?: "")
        )
    }

    private fun saveToCache(context: Context, bytes: ByteArray): String? {
        return try {
            val dir = java.io.File(context.cacheDir, "jarvis_frames")
            dir.mkdirs()
            val file = java.io.File(dir, "frame_${System.currentTimeMillis()}.jpg")
            file.writeBytes(bytes)
            file.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    // ------------------------------------------------------------------
    // Location
    // ------------------------------------------------------------------

    fun getLocation(context: Context): Map<String, Any>? {
        val location = LocationService.lastLocation ?: lastKnown(context) ?: return null
        return locationToMap(location)
    }

    private fun lastKnown(context: Context): Location? {
        if (!LocationService.hasLocationPermission(context)) return null
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return null
        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER
        )
        var best: Location? = null
        for (provider in providers) {
            try {
                if (!manager.isProviderEnabled(provider)) continue
                @Suppress("DEPRECATION")
                val fix = manager.getLastKnownLocation(provider) ?: continue
                if (best == null || fix.time > best.time) best = fix
            } catch (_: SecurityException) {
            }
        }
        return best
    }

    private fun locationToMap(location: Location): Map<String, Any> = mapOf<String, Any>(
        "latitude" to location.latitude,
        "longitude" to location.longitude,
        "altitude" to (if (location.hasAltitude()) location.altitude else 0.0),
        "accuracy" to location.accuracy.toDouble(),
        "speed" to location.speed.toDouble(),
        "timestamp" to location.time,
        "provider" to (location.provider ?: "unknown")
    )

    // ------------------------------------------------------------------
    // Messaging / calls / contacts / calendar
    // ------------------------------------------------------------------

    fun sendSms(context: Context, address: String, body: String): Map<String, Any> {
        if (!context.isGranted(Manifest.permission.SEND_SMS)) {
            return mapOf<String, Any>("success" to false, "message" to "SEND_SMS permission not granted.")
        }
        return try {
            @Suppress("DEPRECATION")
            val smsManager = SmsManager.getDefault()
            val parts = smsManager.divideMessage(body)
            if (parts.size <= 1) {
                smsManager.sendTextMessage(address, null, body, null, null)
            } else {
                smsManager.sendMultipartTextMessage(address, null, parts, null, null)
            }
            mapOf<String, Any>("success" to true, "message" to "SMS sent to $address.")
        } catch (e: Exception) {
            mapOf<String, Any>("success" to false, "message" to (e.message ?: "SMS failed"))
        }
    }

    fun placeCall(context: Context, number: String): Map<String, Any> {
        val uri = Uri.parse("tel:${Uri.encode(number)}")
        return try {
            val action = if (context.isGranted(Manifest.permission.CALL_PHONE)) {
                Intent.ACTION_CALL
            } else {
                Intent.ACTION_DIAL
            }
            context.startActivity(
                Intent(action, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            val mode = if (action == Intent.ACTION_CALL) "Call placed" else "Dialer opened"
            mapOf<String, Any>("success" to true, "message" to "$mode for $number.")
        } catch (e: Exception) {
            mapOf<String, Any>("success" to false, "message" to (e.message ?: "call failed"))
        }
    }

    fun readContacts(context: Context, limit: Int): Map<String, Any> {
        if (!context.isGranted(Manifest.permission.READ_CONTACTS)) {
            return mapOf<String, Any>("success" to false, "message" to "READ_CONTACTS permission not granted.")
        }
        return try {
            val contacts = mutableListOf<Map<String, String>>()
            val cursor = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER
                ),
                null,
                null,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC"
            )
            cursor?.use {
                val nameIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val numberIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                while (it.moveToNext() && contacts.size < limit) {
                    val name = if (nameIdx >= 0) it.getString(nameIdx) else null
                    val number = if (numberIdx >= 0) it.getString(numberIdx) else null
                    if (!name.isNullOrBlank() && !number.isNullOrBlank()) {
                        contacts.add(mapOf("name" to name, "number" to number))
                    }
                }
            }
            mapOf<String, Any>(
                "success" to true,
                "contacts" to contacts,
                "count" to contacts.size
            )
        } catch (e: Exception) {
            mapOf<String, Any>("success" to false, "message" to (e.message ?: "contacts read failed"))
        }
    }

    /** Resolves a spoken name like "mom" to the best matching contact number. */
    fun resolveContact(context: Context, query: String): Map<String, Any> {
        if (!context.isGranted(Manifest.permission.READ_CONTACTS)) {
            return mapOf<String, Any>("success" to false, "message" to "READ_CONTACTS permission not granted.")
        }
        return try {
            val needle = query.trim().lowercase()
            val cursor = context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER
                ),
                null,
                null,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC"
            )
            var exact: Map<String, String>? = null
            var fuzzy: Map<String, String>? = null
            cursor?.use {
                val nameIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                val numberIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
                while (it.moveToNext()) {
                    val name = if (nameIdx >= 0) (it.getString(nameIdx) ?: "") else ""
                    val number = if (numberIdx >= 0) (it.getString(numberIdx) ?: "") else ""
                    val lowerName = name.lowercase()
                    when {
                        lowerName == needle -> {
                            exact = mapOf("name" to name, "number" to number)
                        }
                        fuzzy == null &&
                            (lowerName.startsWith(needle) || lowerName.contains(needle) ||
                                needle.contains(lowerName)) -> {
                            fuzzy = mapOf("name" to name, "number" to number)
                        }
                    }
                    if (exact != null) break
                }
            }
            val match = exact ?: fuzzy
            if (match != null) {
                mapOf<String, Any>("success" to true, "contact" to match)
            } else {
                mapOf<String, Any>("success" to false, "message" to "No contact matched \"$query\".")
            }
        } catch (e: Exception) {
            mapOf<String, Any>("success" to false, "message" to (e.message ?: "contact lookup failed"))
        }
    }

    fun readCalendar(context: Context, limit: Int): Map<String, Any> {
        if (!context.isGranted(Manifest.permission.READ_CALENDAR)) {
            return mapOf<String, Any>("success" to false, "message" to "READ_CALENDAR permission not granted.")
        }
        return try {
            val now = System.currentTimeMillis()
            val weekOut = now + 7L * 24 * 60 * 60 * 1000
            val events = mutableListOf<Map<String, Any>>()
            val cursor = context.contentResolver.query(
                CalendarContract.Instances.CONTENT_URI,
                arrayOf(
                    CalendarContract.Instances.TITLE,
                    CalendarContract.Instances.BEGIN,
                    CalendarContract.Instances.END,
                    CalendarContract.Instances.EVENT_LOCATION,
                    CalendarContract.Instances.ALL_DAY
                ),
                "${CalendarContract.Instances.BEGIN} >= ? AND ${CalendarContract.Instances.BEGIN} <= ?",
                arrayOf(now.toString(), weekOut.toString()),
                "${CalendarContract.Instances.BEGIN} ASC"
            )
            cursor?.use {
                val titleIdx = it.getColumnIndex(CalendarContract.Instances.TITLE)
                val beginIdx = it.getColumnIndex(CalendarContract.Instances.BEGIN)
                val endIdx = it.getColumnIndex(CalendarContract.Instances.END)
                val locIdx = it.getColumnIndex(CalendarContract.Instances.EVENT_LOCATION)
                while (it.moveToNext() && events.size < limit) {
                    events.add(
                        mapOf<String, Any>(
                            "title" to (if (titleIdx >= 0) (it.getString(titleIdx) ?: "") else ""),
                            "begin" to (if (beginIdx >= 0) it.getLong(beginIdx) else 0L),
                            "end" to (if (endIdx >= 0) it.getLong(endIdx) else 0L),
                            "location" to (if (locIdx >= 0) (it.getString(locIdx) ?: "") else "")
                        )
                    )
                }
            }
            mapOf<String, Any>("success" to true, "events" to events, "count" to events.size)
        } catch (e: Exception) {
            mapOf<String, Any>("success" to false, "message" to (e.message ?: "calendar read failed"))
        }
    }

    fun setAlarm(context: Context, hour: Int, minute: Int, label: String): Map<String, Any> {
        return try {
            val intent = Intent(android.provider.AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(android.provider.AlarmClock.EXTRA_HOUR, hour)
                putExtra(android.provider.AlarmClock.EXTRA_MINUTES, minute)
                if (label.isNotBlank()) {
                    putExtra(android.provider.AlarmClock.EXTRA_MESSAGE, label)
                }
                putExtra(android.provider.AlarmClock.EXTRA_SKIP_UI, false)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            mapOf<String, Any>("success" to true, "message" to "Alarm set for ${"%02d".format(hour)}:${"%02d".format(minute)}.")
        } catch (e: Exception) {
            mapOf<String, Any>("success" to false, "message" to (e.message ?: "alarm failed"))
        }
    }

    // ------------------------------------------------------------------
    // Hardware controls
    // ------------------------------------------------------------------

    fun setVolume(context: Context, percent: Double): Map<String, Any> {
        return try {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val target = (percent.coerceIn(0.0, 1.0) * max).toInt().coerceIn(0, max)
            audio.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
            mapOf<String, Any>("success" to true, "message" to "Media volume set to ${(percent * 100).toInt()}%.")
        } catch (e: SecurityException) {
            mapOf<String, Any>(
                "success" to false,
                "message" to "Volume blocked (Do Not Disturb active?): ${e.message}"
            )
        } catch (e: Exception) {
            mapOf<String, Any>("success" to false, "message" to (e.message ?: "volume failed"))
        }
    }

    fun getVolume(context: Context): Map<String, Any> {
        return try {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val current = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
            mapOf<String, Any>(
                "success" to true,
                "volume" to if (max > 0) current.toDouble() / max else 0.0,
                "ringerMode" to audio.ringerMode
            )
        } catch (e: Exception) {
            mapOf<String, Any>("success" to false, "message" to (e.message ?: "volume read failed"))
        }
    }

    fun setBrightness(context: Context, value: Double): Map<String, Any> {
        if (!Settings.System.canWrite(context)) {
            return mapOf<String, Any>(
                "success" to false,
                "message" to "WRITE_SETTINGS special access not granted."
            )
        }
        return try {
            val clamped = value.coerceIn(0.0, 1.0)
            val target = (clamped * 255).toInt().coerceIn(1, 255)
            Settings.System.putInt(
                context.contentResolver,
                Settings.System.SCREEN_BRIGHTNESS_MODE,
                Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL
            )
            Settings.System.putInt(
                context.contentResolver,
                Settings.System.SCREEN_BRIGHTNESS,
                target
            )
            mapOf<String, Any>(
                "success" to true,
                "message" to "Brightness set to ${(clamped * 100).toInt()}%."
            )
        } catch (e: Exception) {
            mapOf<String, Any>("success" to false, "message" to (e.message ?: "brightness failed"))
        }
    }

    fun setTorch(context: Context, on: Boolean): Map<String, Any> {
        return try {
            val camera = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val id = camera.cameraIdList.firstOrNull { cid ->
                val characteristics = camera.getCameraCharacteristics(cid)
                characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true &&
                    characteristics.get(CameraCharacteristics.LENS_FACING) ==
                    CameraCharacteristics.LENS_FACING_BACK
            } ?: return mapOf<String, Any>("success" to false, "message" to "No flashlight unit found.")
            camera.setTorchMode(id, on)
            mapOf<String, Any>("success" to true, "message" to if (on) "Torch on." else "Torch off.")
        } catch (e: Exception) {
            mapOf<String, Any>("success" to false, "message" to (e.message ?: "torch failed"))
        }
    }

    fun lockScreen(context: Context): Map<String, Any> {
        return try {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            if (!isDeviceAdminActive(context)) {
                return mapOf<String, Any>(
                    "success" to false,
                    "message" to "Device administrator not active; enable it in settings first."
                )
            }
            dpm.lockNow()
            mapOf<String, Any>("success" to true, "message" to "Screen locked.")
        } catch (e: Exception) {
            mapOf<String, Any>("success" to false, "message" to (e.message ?: "lock failed"))
        }
    }

    // ------------------------------------------------------------------
    // Media / storage snapshots
    // ------------------------------------------------------------------

    fun storageSnapshot(context: Context): Map<String, Any> {
        return try {
            val stat = StatFs(Environment.getDataDirectory().absolutePath)
            val total = stat.totalBytes
            val free = stat.availableBytes
            mapOf<String, Any>(
                "totalBytes" to total,
                "freeBytes" to free,
                "usedPercent" to ((total - free) * 100.0 / total)
            )
        } catch (e: Exception) {
            mapOf<String, Any>("error" to (e.message ?: "stat failed"))
        }
    }

    fun mediaCountSnapshot(context: Context): Map<String, Any> {
        return try {
            val images = countMedia(context, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
            val videos = countMedia(context, MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
            val audio = countMedia(context, MediaStore.Audio.Media.EXTERNAL_CONTENT_URI)
            mapOf<String, Any>(
                "images" to images,
                "videos" to videos,
                "audio" to audio
            )
        } catch (e: Exception) {
            mapOf<String, Any>("error" to (e.message ?: "media query failed"))
        }
    }

    private fun countMedia(context: Context, uri: Uri): Int {
        return try {
            context.contentResolver.query(
                uri, arrayOf(MediaStore.MediaColumns._ID), null, null, null
            )?.use { it.count } ?: 0
        } catch (_: Exception) {
            0
        }
    }

    /** Convenience for logging/telemetry. */
    fun describeBundle(bundle: Bundle?): String = bundle?.keySet()?.joinToString(",") { k ->
        "$k=${bundle.get(k)}"
    } ?: "null"
}
