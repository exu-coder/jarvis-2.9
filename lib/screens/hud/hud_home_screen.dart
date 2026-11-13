import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../settings/permissions_screen.dart';
import '../settings/settings_screen.dart';
import '../../services/ai_service.dart';

/// 𝐉.𝐀.𝐑.𝐕.𝐈.𝐒 HUD home — the `assets/hud/uI.html` arc-reactor interface
/// rendered in a WebView, wired to the real AI core through a JS bridge.
///
/// Bridge contract (from the HTML side):
///   • `JARVIS_NATIVE.ask(text)`          → user sends a message
///   • `JARVIS_NATIVE.postMessage('jv:…')` → HUD control commands
///   • `window.onJarvisReply(text)`       → host delivers the AI answer
///   • `window.onJarvisError(message)`    → host delivers an error
class HudHomeScreen extends StatefulWidget {
  const HudHomeScreen({super.key});

  @override
  State<HudHomeScreen> createState() => _HudHomeScreenState();
}

class _HudHomeScreenState extends State<HudHomeScreen> {
  static const _commandPrefix = 'jv:';

  WebViewController? _controller;
  bool _ready = false;
  // Serialised bridge: uI.html shows one typing indicator at a time, so
  // answers must be delivered in the order the questions were asked.
  final List<_PendingAsk> _queue = [];
  bool _draining = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF01060C))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _ready = true);
          },
        ),
      )
      ..addJavaScriptChannel(
        'JARVIS_NATIVE',
        onMessageReceived: (msg) {
          final text = msg.message;
          if (text.startsWith(_commandPrefix)) {
            _handleCommand(text.substring(_commandPrefix.length));
          } else {
            _enqueueAsk(text);
          }
        },
      )
      ..loadFlutterAsset('assets/hud/uI.html');
    _controller = controller;
  }

  /// HUD chrome actions raised from `uI.html` (permissions, settings).
  void _handleCommand(String command) {
    if (!mounted) return;
    switch (command) {
      case 'permissions':
        Navigator.of(context).push(
          _hudRoute(const PermissionsScreen()),
        );
      case 'settings':
        Navigator.of(context).push(
          _hudRoute(const SettingsScreen()),
        );
    }
  }

  PageRouteBuilder<T> _hudRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// Handles one `JARVIS_NATIVE.ask(text)` call from the HUD.
  Future<void> _enqueueAsk(String text) async {
    if (text.trim().isEmpty) return;
    _queue.add(_PendingAsk(text));
    await _drain();
  }

  Future<void> _drain() async {
    if (_draining || _controller == null || !_ready) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeAt(0);
        String reply;
        try {
          reply = await AiService.instance.chat(message: job.text);
        } catch (e) {
          reply = 'My apologies, sir — I could not reach the uplink ($e).';
        }
        if (!mounted) return;
        await _controller!.runJavaScript(
          'window.onJarvisReply(${jsonEncode(reply)});',
        );
      }
    } finally {
      _draining = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF01060C),
      body: Stack(
        children: [
          if (_controller != null)
            WebViewWidget(controller: _controller!)
          else
            const SizedBox.expand(),
        ],
      ),
    );
  }
}

class _PendingAsk {
  _PendingAsk(this.text);
  final String text;
}
