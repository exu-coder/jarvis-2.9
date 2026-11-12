import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../home/home_screen.dart';
import '../../services/ai_service.dart';

/// 𝐉.𝐀.𝐑.𝐕.𝐈.𝐒 HUD home — the `assets/hud/uI.html` arc-reactor interface
/// rendered in a WebView, wired to the real AI core through a JS bridge.
///
/// Bridge contract (from the HTML side):
///   • `JARVIS_NATIVE.ask(text)`          → user sends a message
///   • `window.onJarvisReply(text)`       → host delivers the AI answer
///   • `window.onJarvisError(message)`    → host delivers an error
class HudHomeScreen extends StatefulWidget {
  const HudHomeScreen({super.key});

  @override
  State<HudHomeScreen> createState() => _HudHomeScreenState();
}

class _HudHomeScreenState extends State<HudHomeScreen> {
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
        onMessageReceived: (msg) => _enqueueAsk(msg.message),
      )
      ..loadFlutterAsset('assets/hud/uI.html');
    _controller = controller;
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
          // Legacy Material dashboard, one tap away (bottom-right keeps the
          // HUD's top clock + status clear; floating controls are bottom-center).
          Positioned(
            bottom: 0,
            right: 0,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(
                  Icons.apps_rounded,
                  color: Color(0x6642E8FF),
                  size: 22,
                ),
                tooltip: 'Dashboard',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingAsk {
  _PendingAsk(this.text);
  final String text;
}
