import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/permission_manager_service.dart';

/// 𝐉.𝐀.𝐑.𝐕.𝐈.𝐒 authority matrix — the permissions console, rendered from
/// `assets/hud/permissions.html` so it matches the `uI.html` HUD exactly
/// (same palette, scanlines, serif type, chamfered panels).
///
/// Bridge contract (JS ↔ Dart, JSON over the `JARVIS_PERMS` channel):
///   ready | refresh | appInfo | close | grant{type} | all
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  final _service = PermissionManagerService.instance;

  WebViewController? _controller;
  bool _pageReady = false;

  /// Short HUD glyphs for each clearance, shown in the row's code plate.
  static const Map<AppPermissionType, String> _codes = {
    AppPermissionType.microphone: 'MIC',
    AppPermissionType.camera: 'CAM',
    AppPermissionType.location: 'LOC',
    AppPermissionType.backgroundLocation: 'BGL',
    AppPermissionType.sms: 'SMS',
    AppPermissionType.phone: 'TEL',
    AppPermissionType.contacts: 'CON',
    AppPermissionType.calendar: 'CAL',
    AppPermissionType.mediaStorage: 'MED',
    AppPermissionType.allFiles: 'FIL',
    AppPermissionType.bluetooth: 'BT',
    AppPermissionType.nearbyWifi: 'WIF',
    AppPermissionType.bodySensors: 'SEN',
    AppPermissionType.activity: 'ACT',
    AppPermissionType.notifications: 'NTF',
    AppPermissionType.accessibility: 'ACC',
    AppPermissionType.overlay: 'OVR',
    AppPermissionType.notificationListener: 'NLS',
    AppPermissionType.usageStats: 'USG',
    AppPermissionType.writeSettings: 'WRI',
    AppPermissionType.installPackages: 'PKG',
    AppPermissionType.exactAlarm: 'ALM',
    AppPermissionType.dndPolicy: 'DND',
    AppPermissionType.deviceAdmin: 'ADM',
    AppPermissionType.batteryOptimization: 'BAT',
  };

  /// Sector layout mirrors the grouping the HUD console renders.
  static const List<(String, List<AppPermissionType>)> _sectors = [
    (
      'Communications & Inboxes',
      [
        AppPermissionType.sms,
        AppPermissionType.notificationListener,
        AppPermissionType.contacts,
        AppPermissionType.notifications,
      ],
    ),
    (
      'Core Voice & Automation',
      [
        AppPermissionType.microphone,
        AppPermissionType.accessibility,
        AppPermissionType.overlay,
        AppPermissionType.batteryOptimization,
      ],
    ),
    (
      'Awareness & Sensors',
      [
        AppPermissionType.location,
        AppPermissionType.backgroundLocation,
        AppPermissionType.camera,
        AppPermissionType.bodySensors,
        AppPermissionType.activity,
      ],
    ),
    (
      'Device Control',
      [
        AppPermissionType.phone,
        AppPermissionType.calendar,
        AppPermissionType.mediaStorage,
        AppPermissionType.allFiles,
        AppPermissionType.bluetooth,
        AppPermissionType.usageStats,
      ],
    ),
    (
      'Special Access',
      [
        AppPermissionType.writeSettings,
        AppPermissionType.exactAlarm,
        AppPermissionType.installPackages,
        AppPermissionType.dndPolicy,
        AppPermissionType.deviceAdmin,
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service.addListener(_onServiceChanged);
    _initController();
    _service.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _service.refresh();
    }
  }

  void _onServiceChanged() {
    // Loading hops are noise for the HUD; only repaint settled snapshots.
    if (!_service.isLoading) _pushState();
  }

  void _initController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF11141A))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _pageReady = true;
            _pushState();
          },
        ),
      )
      ..addJavaScriptChannel(
        'JARVIS_PERMS',
        onMessageReceived: (msg) => _onHostMessage(msg.message),
      )
      ..loadFlutterAsset('assets/hud/permission.html');
    _controller = controller;
  }

  Future<void> _run(String script) async {
    if (!_pageReady || _controller == null) return;
    await _controller!.runJavaScript(script);
  }

  Map<String, dynamic> _snapshot() {
    final all = _service.permissions;
    return {
      'granted': _service.grantedCount,
      'total': _service.totalCount,
      'sections': [
        for (final (title, types) in _sectors)
          if (all.any((p) => types.contains(p.type)))
            {
              'title': title,
              'items': [
                for (final p in all.where((p) => types.contains(p.type)))
                  {
                    'type': p.type.name,
                    'code': _codes[p.type] ?? p.type.name.toUpperCase(),
                    'title': p.title,
                    'description': p.description,
                    'granted': p.isGranted,
                    'system': p.isSystemSettingsOnly,
                  },
              ],
            },
      ],
    };
  }

  Future<void> _pushState() async {
    if (!_pageReady || _controller == null) return;
    final payload = jsonEncode(_snapshot());
    await _run('window.matrixRender($payload);');
    await _run('window.matrixBusy(${_service.isLoading ? 'true' : 'false'});');
  }

  Future<void> _toast(String text) async {
    await _run('window.matrixToast(${jsonEncode(text)});');
  }

  Future<void> _onHostMessage(String raw) async {
    Map<String, dynamic> cmd;
    try {
      cmd = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (cmd['action']) {
      case 'ready':
        _pageReady = true;
        await _service.refresh();
        await _pushState();
      case 'refresh':
        await _service.refresh();
        await _pushState();
      case 'appInfo':
        await _service.openAppInfo();
      case 'close':
        if (mounted) Navigator.of(context).maybePop();
      case 'all':
        await _run('window.matrixBusy(true);');
        await _service.requestAllCorePermissions();
        await _pushState();
        await _toast(
          _service.grantedCount == _service.totalCount
              ? 'ALL CLEARANCES AUTHORIZED'
              : 'RUNTIME CLEARANCES UPDATED',
        );
      case 'grant':
        final name = cmd['type'] as String?;
        AppPermissionType? type;
        for (final t in AppPermissionType.values) {
          if (t.name == name) {
            type = t;
            break;
          }
        }
        if (type == null) return;
        await _run('window.matrixBusy(true);');
        await _service.requestPermission(type);
        await _pushState();
        await _toast('CLEARANCE RE-AUDITED');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF11141A),
      body: _controller == null
          ? const ColoredBox(color: Color(0xFF11141A))
          : WebViewWidget(controller: _controller!),
    );
  }
}
