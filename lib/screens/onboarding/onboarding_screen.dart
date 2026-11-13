import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/screen_automation_service.dart';
import '../../services/settings_service.dart';

/// First-boot wizard, rendered from `assets/hud/onboarding.html` so the very
/// first screen already matches the HUD (palette, serif type, scanlines).
///
/// Bridge contract (`JARVIS_BOOT`, JSON both ways):
///   ready | refresh | provider{id} | apiKey{value} | permission{kind}
///   accessibility | appInfo | complete
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  final _settings = SettingsService.instance;
  final _automation = ScreenAutomationService.instance;

  WebViewController? _controller;
  bool _pageReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initController();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pushA11yState();
    }
  }

  void _initController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF01060C))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _pageReady = true;
            _pushState();
          },
        ),
      )
      ..addJavaScriptChannel(
        'JARVIS_BOOT',
        onMessageReceived: (msg) => _onHostMessage(msg.message),
      )
      ..loadFlutterAsset('assets/hud/onboarding.html');
    _controller = controller;
  }

  Future<void> _run(String script) async {
    if (!_pageReady || _controller == null) return;
    await _controller!.runJavaScript(script);
  }

  Future<void> _pushState() async {
    final accessibility = await _automation.isServiceEnabled();
    final payload = jsonEncode({
      'providers': [
        for (final e in SettingsService.providers.entries)
          if (e.key != 'custom') {'id': e.key, 'label': e.value.label},
      ],
      'provider': _settings.provider,
      'model': _settings.model,
      'apiKey': _settings.apiKey,
      'accessibility': accessibility,
    });
    await _run('window.bootState($payload);');
  }

  Future<void> _pushA11yState() async {
    final accessibility = await _automation.isServiceEnabled();
    await _run('window.bootA11y($accessibility);');
  }

  Future<void> _toast(String text) async {
    await _run('window.bootToast(${jsonEncode(text)});');
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
        await _pushState();
      case 'refresh':
        await _pushA11yState();
      case 'provider':
        final id = cmd['id'] as String?;
        if (id == null) return;
        await _settings.setProvider(id);
        await _pushState();
      case 'apiKey':
        await _settings.setApiKey((cmd['value'] as String?) ?? '');
      case 'accessibility':
        await _automation.openAccessibilitySettings();
      case 'appInfo':
        await _automation.openAppInfoSettings();
      case 'permission':
        final kind = cmd['kind'] as String?;
        await _requestPermission(kind);
      case 'complete':
        await _settings.setOnboardingComplete(true);
        if (mounted) widget.onFinished();
    }
  }

  Future<void> _requestPermission(String? kind) async {
    try {
      switch (kind) {
        case 'microphone': {
          final status = await Permission.microphone.request();
          await _toast(
              status.isGranted ? 'MICROPHONE ONLINE' : 'MICROPHONE DENIED');
        }
        case 'notifications': {
          final status = await Permission.notification.request();
          await _toast(status.isGranted
              ? 'NOTIFICATIONS ONLINE'
              : 'NOTIFICATIONS DENIED');
        }
        case 'contacts': {
          final status = await Permission.contacts.request();
          await _toast(status.isGranted ? 'CONTACTS ONLINE' : 'CONTACTS DENIED');
        }
        case 'overlay': {
          final granted = await FlutterOverlayWindow.requestPermission();
          await _toast(
              granted == true ? 'FLOATING BUBBLE ONLINE' : 'BUBBLE NOT GRANTED');
        }
      }
    } catch (_) {
      await _toast('CLEARANCE REQUEST FAILED');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF01060C),
      body: _controller == null
          ? const ColoredBox(color: Color(0xFF01060C))
          : WebViewWidget(controller: _controller!),
    );
  }
}
