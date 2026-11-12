import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'device_control_service.dart';
import 'inbox_service.dart';
import 'screen_automation_service.dart';

enum AppPermissionType {
  microphone,
  camera,
  location,
  backgroundLocation,
  sms,
  phone,
  contacts,
  calendar,
  mediaStorage,
  allFiles,
  bluetooth,
  nearbyWifi,
  bodySensors,
  activity,
  notifications,
  accessibility,
  overlay,
  notificationListener,
  usageStats,
  writeSettings,
  installPackages,
  exactAlarm,
  dndPolicy,
  deviceAdmin,
  batteryOptimization,
}

class AppPermissionInfo {
  final AppPermissionType type;
  final String title;
  final String description;
  final IconData icon;
  final bool isGranted;
  final bool isSystemSettingsOnly;

  const AppPermissionInfo({
    required this.type,
    required this.title,
    required this.description,
    required this.icon,
    required this.isGranted,
    this.isSystemSettingsOnly = false,
  });
}

/// Centralized permissions manager that audits and requests every Android
/// permission the JARVIS core declares in the manifest — runtime dialogs,
/// special-access screens and service-bound permissions alike.
///
/// All state comes from the native `com.jarvis.dev/device` channel
/// ([DeviceControlService]) so Dart and the OS agree on a single source of
/// truth; permission_handler is only used to fire the standard dialogs.
class PermissionManagerService extends ChangeNotifier {
  PermissionManagerService._();
  static final PermissionManagerService instance = PermissionManagerService._();

  final DeviceControlService _device = DeviceControlService.instance;

  List<AppPermissionInfo> _permissions = [];
  bool _isLoading = false;

  List<AppPermissionInfo> get permissions => List.unmodifiable(_permissions);
  bool get isLoading => _isLoading;

  int get grantedCount => _permissions.where((p) => p.isGranted).length;
  int get totalCount => _permissions.length;

  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();

    Map<String, dynamic> report;
    try {
      report = await _device.permissionReport();
    } catch (_) {
      report = const {};
    }

    bool state(String key, {bool fallback = false}) =>
        (report[key] as bool?) ?? fallback;

    // Runtime dialogs handled by permission_handler (native report mirrors it).
    final micStatus = state('microphone', fallback: await Permission.microphone.isGranted);
    final smsStatus = state('sms', fallback: await Permission.sms.isGranted);
    final contactsStatus = state('contacts', fallback: await Permission.contacts.isGranted);
    final notifStatus = state('notifications', fallback: await Permission.notification.isGranted);
    final batteryStatus = state('batteryOptimization',
        fallback: await Permission.ignoreBatteryOptimizations.isGranted);

    final accessibilityStatus = state('accessibility',
        fallback: await ScreenAutomationService.instance.isServiceEnabled());
    final overlayStatus = state('overlay');
    final notifListenerStatus = state('notificationListener',
        fallback: await InboxService.instance.isNotificationListenerEnabled());

    _permissions = [
      // ---------- Core voice & automation ----------
      AppPermissionInfo(
        type: AppPermissionType.microphone,
        title: 'Microphone & Voice Input',
        description: 'Enables "Hey Jarvis" wake word detection and hands-free desk mode listening.',
        icon: Icons.mic_rounded,
        isGranted: micStatus,
      ),
      AppPermissionInfo(
        type: AppPermissionType.accessibility,
        title: 'Accessibility Service',
        description: 'Empowers PrivateAgent to tap, type, scroll, and execute autonomous tasks across apps.',
        icon: Icons.accessibility_new_rounded,
        isGranted: accessibilityStatus,
        isSystemSettingsOnly: true,
      ),
      AppPermissionInfo(
        type: AppPermissionType.overlay,
        title: 'Display Over Other Apps',
        description: 'Allows the floating holographic bubble and transcript panel over other applications.',
        icon: Icons.layers_outlined,
        isGranted: overlayStatus,
        isSystemSettingsOnly: true,
      ),
      AppPermissionInfo(
        type: AppPermissionType.batteryOptimization,
        title: 'Unrestricted Background Battery',
        description: 'Prevents Android OS from sleeping or terminating continuous listening in desk mode.',
        icon: Icons.battery_charging_full_rounded,
        isGranted: batteryStatus,
        isSystemSettingsOnly: true,
      ),

      // ---------- Communications & inboxes ----------
      AppPermissionInfo(
        type: AppPermissionType.sms,
        title: 'SMS Inbox & Messaging',
        description: 'Allows reading incoming SMS messages, verification codes, and drafting text replies.',
        icon: Icons.sms_outlined,
        isGranted: smsStatus,
      ),
      AppPermissionInfo(
        type: AppPermissionType.contacts,
        title: 'Contacts Access',
        description: 'Resolves names for voice commands like "Text John" or "Call Mom".',
        icon: Icons.contacts_outlined,
        isGranted: contactsStatus,
      ),
      AppPermissionInfo(
        type: AppPermissionType.notificationListener,
        title: 'Email & Notification Access',
        description: 'Enables live incoming email triage and notification summaries for Gmail & Outlook.',
        icon: Icons.mark_email_unread_outlined,
        isGranted: notifListenerStatus,
        isSystemSettingsOnly: true,
      ),
      AppPermissionInfo(
        type: AppPermissionType.notifications,
        title: 'System Notifications',
        description: 'Sends calendar alerts, daily morning briefings, and background status updates.',
        icon: Icons.notifications_active_outlined,
        isGranted: notifStatus,
      ),

      // ---------- Awareness & sensors ----------
      AppPermissionInfo(
        type: AppPermissionType.location,
        title: 'Location Services',
        description: 'Powers commute checks, location-aware reminders and "Where am I" queries.',
        icon: Icons.location_on_rounded,
        isGranted: state('location'),
      ),
      AppPermissionInfo(
        type: AppPermissionType.backgroundLocation,
        title: 'Background Location',
        description: 'Keeps proactive commute and geofence protocols alive while other apps run.',
        icon: Icons.my_location_rounded,
        isGranted: state('backgroundLocation'),
        isSystemSettingsOnly: true,
      ),
      AppPermissionInfo(
        type: AppPermissionType.camera,
        title: 'Camera & Jarvis Eye',
        description: 'Point-and-solve optical recognition through the Jarvis Eye scanner.',
        icon: Icons.photo_camera_rounded,
        isGranted: state('camera'),
      ),
      AppPermissionInfo(
        type: AppPermissionType.bodySensors,
        title: 'Body Sensors',
        description: 'Heart-rate and wellness telemetry for health-aware protocols.',
        icon: Icons.monitor_heart_outlined,
        isGranted: state('bodySensors'),
      ),
      AppPermissionInfo(
        type: AppPermissionType.activity,
        title: 'Activity Recognition',
        description: 'Detects walking, driving and workouts for adaptive automation.',
        icon: Icons.directions_walk_rounded,
        isGranted: state('activity'),
      ),

      // ---------- Device control ----------
      AppPermissionInfo(
        type: AppPermissionType.phone,
        title: 'Phone & Calls',
        description: 'Places calls, reads caller identity and manages the call log on request.',
        icon: Icons.phone_outlined,
        isGranted: state('phone') || state('callLog'),
      ),
      AppPermissionInfo(
        type: AppPermissionType.calendar,
        title: 'Calendar',
        description: 'Reads upcoming events so the daily briefing can include your schedule.',
        icon: Icons.calendar_month_outlined,
        isGranted: state('calendar'),
      ),
      AppPermissionInfo(
        type: AppPermissionType.mediaStorage,
        title: 'Photos, Videos & Audio',
        description: 'Indexes your media library for smart gallery and music actions.',
        icon: Icons.perm_media_outlined,
        isGranted: state('media'),
      ),
      AppPermissionInfo(
        type: AppPermissionType.allFiles,
        title: 'All Files Access',
        description: 'Full storage reach for the file manager and offline knowledge index.',
        icon: Icons.folder_outlined,
        isGranted: state('allFiles'),
        isSystemSettingsOnly: true,
      ),
      AppPermissionInfo(
        type: AppPermissionType.bluetooth,
        title: 'Bluetooth Control',
        description: 'Discovers and connects wearables, headphones and car kits.',
        icon: Icons.bluetooth_outlined,
        isGranted: state('bluetooth'),
      ),
      AppPermissionInfo(
        type: AppPermissionType.usageStats,
        title: 'Usage Statistics',
        description: 'Screen-time analytics and most-used-app ranking.',
        icon: Icons.donut_small_rounded,
        isGranted: state('usageStats'),
        isSystemSettingsOnly: true,
      ),

      // ---------- Special access ----------
      AppPermissionInfo(
        type: AppPermissionType.writeSettings,
        title: 'Modify System Settings',
        description: 'Adjusts brightness, volume, and other system controls on your command.',
        icon: Icons.tune_rounded,
        isGranted: state('writeSettings'),
        isSystemSettingsOnly: true,
      ),
      AppPermissionInfo(
        type: AppPermissionType.exactAlarm,
        title: 'Exact Alarms',
        description: 'Fires precise alarms and reminders at the second you specify.',
        icon: Icons.alarm_rounded,
        isGranted: state('exactAlarm'),
        isSystemSettingsOnly: true,
      ),
      AppPermissionInfo(
        type: AppPermissionType.installPackages,
        title: 'Install Apps',
        description: 'Installs and updates apps autonomously when you request it.',
        icon: Icons.system_update_alt_rounded,
        isGranted: state('installPackages'),
        isSystemSettingsOnly: true,
      ),
      AppPermissionInfo(
        type: AppPermissionType.dndPolicy,
        title: 'Do Not Disturb Policy',
        description: 'Engages focus mode and reads ringer state during meetings.',
        icon: Icons.do_not_disturb_on_rounded,
        isGranted: state('dndPolicy'),
        isSystemSettingsOnly: true,
      ),
      AppPermissionInfo(
        type: AppPermissionType.deviceAdmin,
        title: 'Device Administrator',
        description: 'Locks the screen and arms the Sentry anti-theft watchdog on your command.',
        icon: Icons.admin_panel_settings_rounded,
        isGranted: state('deviceAdmin'),
        isSystemSettingsOnly: true,
      ),
    ];

    _isLoading = false;
    notifyListeners();
  }

  /// Requests or navigates to the setting for a specific permission.
  Future<bool> requestPermission(AppPermissionType type) async {
    bool ok = false;
    switch (type) {
      case AppPermissionType.microphone:
        ok = await _requestRuntimeGroups(['microphone']);
      case AppPermissionType.camera:
        ok = await _requestRuntimeGroups(['camera']);
      case AppPermissionType.location:
        ok = await _requestRuntimeGroups(['location']);
      case AppPermissionType.backgroundLocation:
        await _device.openSettingsPage('location');
      case AppPermissionType.sms:
        ok = await _requestRuntimeGroups(['sms']);
      case AppPermissionType.phone:
        ok = await _requestRuntimeGroups(['phone', 'callLog']);
      case AppPermissionType.contacts:
        ok = await _requestRuntimeGroups(['contacts']);
      case AppPermissionType.calendar:
        ok = await _requestRuntimeGroups(['calendar']);
      case AppPermissionType.mediaStorage:
        ok = await _requestRuntimeGroups(['media']);
      case AppPermissionType.bluetooth:
        ok = await _requestRuntimeGroups(['bluetooth']);
      case AppPermissionType.nearbyWifi:
        ok = await _requestRuntimeGroups(['nearbyWifi']);
      case AppPermissionType.bodySensors:
        ok = await _requestRuntimeGroups(['bodySensors']);
      case AppPermissionType.activity:
        ok = await _requestRuntimeGroups(['activity']);
      case AppPermissionType.notifications:
        ok = await _requestRuntimeGroups(['notifications']);
      case AppPermissionType.accessibility:
        await ScreenAutomationService.instance.openAccessibilitySettings();
      case AppPermissionType.overlay:
        await _device.openSettingsPage('overlay');
      case AppPermissionType.notificationListener:
        await _device.openSettingsPage('notificationListener');
      case AppPermissionType.usageStats:
        await _device.openSettingsPage('usageStats');
      case AppPermissionType.writeSettings:
        await _device.openSettingsPage('writeSettings');
      case AppPermissionType.installPackages:
        await _device.openSettingsPage('installPackages');
      case AppPermissionType.exactAlarm:
        await _device.openSettingsPage('exactAlarm');
      case AppPermissionType.dndPolicy:
        await _device.openSettingsPage('dndPolicy');
      case AppPermissionType.deviceAdmin:
        await _device.openSettingsPage('deviceAdmin');
      case AppPermissionType.batteryOptimization:
        await _device.openSettingsPage('battery');
      case AppPermissionType.allFiles:
        await _device.openSettingsPage('allFiles');
    }
    await refresh();
    return ok;
  }

  Future<bool> _requestRuntimeGroups(List<String> groups) async {
    try {
      return await DeviceControlService.instance.requestPermissions(groups);
    } catch (_) {
      // Fallback to permission_handler if the native bridge is unavailable.
      final results = await [
        for (final g in groups)
          switch (g) {
            'microphone' => Permission.microphone,
            'camera' => Permission.camera,
            'location' => Permission.locationWhenInUse,
            'contacts' => Permission.contacts,
            'calendar' => Permission.calendar,
            'sms' => Permission.sms,
            'phone' => Permission.phone,
            'notifications' => Permission.notification,
            _ => Permission.notification,
          }
      ].request();
      return results.values.every((s) => s.isGranted);
    }
  }

  /// Requests all standard runtime dialog permissions in one batch.
  Future<void> requestAllCorePermissions() async {
    await _requestRuntimeGroups([
      'microphone',
      'camera',
      'location',
      'sms',
      'phone',
      'contacts',
      'calendar',
      'media',
      'bluetooth',
      'notifications',
      'activity',
      'bodySensors',
    ]);
    await refresh();
  }

  /// Opens the Android App Info page where all permissions can be managed.
  Future<void> openAppInfo() async {
    await _device.openSettingsPage('appInfo');
  }
}
