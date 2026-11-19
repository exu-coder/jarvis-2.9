import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/task_history_entry.dart';
import 'settings_service.dart';

/// Remote control through a Telegram bot.
///
/// Long-polls `getUpdates` in the background while enabled. Incoming text
/// messages from authorized chats are executed as agent tasks; status
/// updates and screenshots are sent back to the chat.
///
/// Authorization model (C3): a chat may only control the device after an
/// explicit on-device pairing. The user requests a 6-digit code in
/// Settings → Telegram Remote Bridge and sends `/pair <code>` to the bot; that
/// chat id is then appended to [SettingsService.telegramAllowedChats] and the
/// code is invalidated. Messages from any other chat are ignored — there is no
/// "first chat wins" ownership path.
class TelegramService extends ChangeNotifier {
  TelegramService._();
  static final TelegramService instance = TelegramService._();

  final http.Client _client = http.Client();

  bool _running = false;
  int _consecutiveErrors = 0;

  bool get isRunning => _running;

  /// Invoked for each incoming command text from an authorized chat.
  void Function(String chatId, String text)? onCommand;

  String get _token => SettingsService.instance.telegramToken;

  /// Telegram's Bot API authenticates **only** through the URL path
  /// (`https://api.telegram.org/bot<token>/<method>`) — there is no header or
  /// body credential for `getUpdates`/`sendMessage`. The token therefore has to
  /// be interpolated into the URI (C2). The mitigations are: build the URI at
  /// the call site instead of caching a reusable `bot<token>` base URL, never
  /// log it, and never include it in an exception message.
  Uri _endpoint(String method, [Map<String, String>? query]) {
    final uri = Uri.parse('https://api.telegram.org/bot$_token/$method');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  Future<void> start() async {
    if (_running) return;
    if (_token.isEmpty) return;
    _running = true;
    _consecutiveErrors = 0;
    notifyListeners();
    unawaited(_pollLoop());
  }

  void stop() {
    _running = false;
    notifyListeners();
  }

  Future<void> restart() async {
    stop();
    await Future.delayed(const Duration(milliseconds: 500));
    await start();
  }

  Future<void> _pollLoop() async {
    while (_running) {
      try {
        final offset = SettingsService.instance.telegramUpdateOffset;
        final uri = _endpoint('getUpdates', {
          'timeout': '25',
          'offset': '${offset == 0 ? -1 : offset}',
        });
        final res = await _client
            .get(uri)
            .timeout(const Duration(seconds: 35));
        if (res.statusCode != 200) {
          throw Exception('HTTP ${res.statusCode}');
        }
        _consecutiveErrors = 0;
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final updates = decoded['result'];
        if (updates is List) {
          for (final update in updates) {
            await _handleUpdate(update);
          }
        }
      } catch (_) {
        if (!_running) break;
        _consecutiveErrors++;
        final backoff = (_consecutiveErrors.clamp(1, 6)) * 5;
        await Future.delayed(Duration(seconds: backoff));
      }
    }
  }

  Future<void> _handleUpdate(dynamic update) async {
    if (update is! Map) return;
    final updateId = update['update_id'];
    if (updateId is int) {
      await SettingsService.instance.setTelegramUpdateOffset(updateId + 1);
    }

    final message = update['message'];
    if (message is! Map) return;
    final chat = message['chat'];
    final chatId = chat is Map ? '${chat['id']}' : null;
    final text = message['text'];
    if (chatId == null || text is! String) return;

    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // Pairing is the only thing an unpaired chat may do (C3).
    if (trimmed == '/pair' || trimmed.startsWith('/pair ')) {
      await _handlePairCommand(chatId, trimmed);
      return;
    }

    // Unknown chats are ignored silently: answering them would confirm that
    // the bot exists and is listening.
    if (!SettingsService.instance.telegramAllowedChats.contains(chatId)) {
      return;
    }
    onCommand?.call(chatId, trimmed);
  }

  /// Redeems a pairing code issued on the device.
  ///
  /// Nothing here grants access by itself: [SettingsService.consumeTelegramPairCode]
  /// only succeeds while a code generated on the phone is unexpired, and the
  /// code is burned on the first successful use.
  Future<void> _handlePairCommand(String chatId, String text) async {
    final settings = SettingsService.instance;
    final parts = text.split(RegExp(r'\s+'));

    if (parts.length != 2 || parts[1].length != 6) {
      await sendMessage(chatId,
          'Send /pair <code> with the 6-digit code from '
          'Settings → Telegram Remote Bridge.');
      return;
    }

    final ok = await settings.consumeTelegramPairCode(parts[1]);
    if (!ok) {
      // Neither echo the attempted code nor reveal whether a code exists.
      await sendMessage(chatId,
          'Pairing failed: the code is wrong or has expired. Request a new '
          'one on the device.');
      return;
    }

    final allowed = List<String>.from(settings.telegramAllowedChats);
    if (!allowed.contains(chatId)) {
      allowed.add(chatId);
      await settings.setTelegramAllowedChats(allowed);
    }
    await sendMessage(chatId,
        '👋 Paired with this chat. Send me any task, e.g.\n'
        '"Open YouTube and search for lofi music".\n\n'
        'Commands: /status /screenshot /cancel\n'
        'To revoke access, remove this chat in '
        'Settings → Telegram Remote Bridge.');
  }

  // ------------------------------------------------------------------
  // Sending
  // ------------------------------------------------------------------

  Future<bool> sendMessage(String chatId, String text) async {
    if (_token.isEmpty) return false;
    try {
      final res = await _client.post(
        _endpoint('sendMessage'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat_id': chatId,
          // Telegram hard limit is 4096 chars.
          'text': text.length > 4000 ? '${text.substring(0, 4000)}…' : text,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Sends a PNG screenshot (base64) as a photo message.
  Future<bool> sendScreenshot(String chatId, String base64Png,
      {String? caption}) async {
    return sendPhoto(chatId, base64Png, caption: caption ?? 'PrivateAgent screenshot');
  }

  /// Sends a photo (base64 string or byte array) to Telegram with custom caption.
  Future<bool> sendPhoto(String chatId, dynamic photoData, {String? caption}) async {
    if (_token.isEmpty) return false;
    try {
      final List<int> bytes = photoData is String
          ? base64Decode(photoData)
          : (photoData as List<int>);
      if (bytes.isEmpty) return false;
      final request = http.MultipartRequest('POST', _endpoint('sendPhoto'))
        ..fields['chat_id'] = chatId
        ..fields['caption'] = caption ?? '📸 J.A.R.V.I.S. Photo Telemetry'
        ..files.add(http.MultipartFile.fromBytes(
            'photo', bytes,
            filename: 'snapshot.jpg'));
      final streamed = await _client.send(request);
      return streamed.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Convenience formatter for task-finished push messages.
  String formatTaskResult(TaskHistoryEntry entry) {
    final icon = switch (entry.status) {
      TaskStatus.success => '✅',
      TaskStatus.cancelled => '⏹️',
      TaskStatus.failed => '❌',
    };
    final duration = entry.duration;
    final seconds = duration == null ? '' : ' in ${duration.inSeconds}s';
    return '$icon ${entry.goal}\n'
        'Status: ${entry.status.name} • ${entry.steps} step(s)$seconds';
  }
}
