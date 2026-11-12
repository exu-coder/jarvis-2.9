package com.jarvis.dev

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast

/**
 * Device administrator receiver used by the assistant for device-level actions
 * that only an admin can perform — most importantly [DevicePolicyManager.lockNow]
 * ("lock the phone, JARVIS") and login monitoring for the Sentry protocol.
 *
 * Activation is user-driven: the Dart side opens `ACTION_ADD_DEVICE_ADMIN`.
 */
class JarvisDeviceAdminReceiver : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        Toast.makeText(context, "𝐉.𝐀.𝐑.𝐕.𝐈.𝐒 device control enabled", Toast.LENGTH_SHORT).show()
    }

    override fun onDisabled(context: Context, intent: Intent) {
        Toast.makeText(context, "𝐉.𝐀.𝐑.𝐕.𝐈.𝐒 device control disabled", Toast.LENGTH_SHORT).show()
    }
}
