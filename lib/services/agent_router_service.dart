import 'app_launcher_service.dart';
import 'device_control_service.dart';

/// Outcome of routing one natural-language request.
class AgentRouteResult {
  /// True when the request was executed as a device action, so the caller must
  /// show [spoken] instead of asking the LLM for a conversational reply.
  final bool handled;
  final String spoken;

  const AgentRouteResult({required this.handled, required this.spoken});
}

/// Decides whether an utterance is an *action* or a *conversation*, and runs
/// the action itself when it is one.
///
/// Why this exists: every path into the AI (HUD ask, Telegram, task executor)
/// used to send plain text straight to the conversational model. That model is
/// told it "cannot directly tap the screen in this mode", so "open YouTube"
/// produced a reply telling the user to switch to Agent mode — even though
/// launching an app needs no accessibility service, no screen dump and no
/// planner. Agent mode is the default, so the default path must be able to act.
///
/// Routing order:
///  1. App launch (`open`/`launch`/`start`/`run`/`switch to` + an installed
///     app) → `InstalledApps` launcher intent.
///  2. Anything [DeviceControlService.executeCommand] recognises (calls, SMS,
///     alarms, volume, brightness, torch, panels, location…) → native bridge.
///  3. Otherwise `null`, meaning "not an action — treat as conversation".
///
/// Deliberately conservative: a miss falls back to chat, which is always safe,
/// whereas a false positive would hijack an ordinary sentence.
class AgentRouterService {
  AgentRouterService._();
  static final AgentRouterService instance = AgentRouterService._();

  /// `open youtube`, `launch the camera`, `switch to whatsapp`, …
  static final RegExp _launchVerb = RegExp(
    r'^(?:open|launch|start|run|switch to|go to|bring up|fire up)\s+'
    r'(?:the\s+|my\s+|an?\s+)?(.+)$',
    caseSensitive: false,
  );

  /// Words that look like an app launch but belong to the device bridge
  /// (control panels) or to the agent loop (compound tasks). Checked *after*
  /// [appLaunchTarget] strips the verb, so these are bare targets.
  static const Set<String> _notApps = {
    'wifi',
    'wi-fi',
    'wlan',
    'bluetooth',
    'hotspot',
    'airplane mode',
    'flight mode',
    'flashlight',
    'torch',
    'notification',
    'notifications',
    'quick settings',
    'recent apps',
    'recents',
    'screen',
    'phone',
    'door',
    'window',
    'file',
    'folder',
    'link',
    'url',
    'website',
    'a website',
    'app',
    'an app',
  };

  /// Verbs that can legitimately start a native device command. Used as a
  /// guard *in front of* [DeviceControlService.executeCommand], which matches
  /// on substrings and would otherwise hijack sentences like "call of duty is
  /// a great game".
  static final RegExp _actionVerb = RegExp(
    r'^(?:call|dial|ring|text|sms|message|send|reply|set|turn|toggle|switch|'
    r'lock|unlock|open|close|start|stop|launch|raise|lower|increase|decrease|'
    r'mute|unmute|silence|take|track|activate|engage)\b',
    caseSensitive: false,
  );

  /// Extracts the app name from a launch phrase, or null when the utterance is
  /// not a plain single-app launch.
  ///
  /// Rejects compound commands (`open youtube and play …`) because those need
  /// the planner, and rejects targets that are longer than any real app label.
  String? appLaunchTarget(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final match = _launchVerb.firstMatch(trimmed);
    if (match == null) return null;

    var target = (match.group(1) ?? '').trim();
    // Trailing "app" is noise: "open the YouTube app".
    target = target.replaceFirst(RegExp(r'\s+app$', caseSensitive: false), '').trim();
    // Sentence punctuation from voice input.
    target = target.replaceFirst(RegExp(r'[.!?]+$'), '').trim();

    if (target.isEmpty) return null;
    if (target.length > 32) return null;
    final lower = target.toLowerCase();
    if (_notApps.contains(lower)) return null;
    // Compound goals ("open youtube and search lofi") need the agent loop.
    if (RegExp(r'\b(and|then|with|for|to)\b').hasMatch(lower)) return null;
    // A lone number or a phone number is a call, not an app.
    if (RegExp(r'^[\d\s()+\-]+$').hasMatch(target)) return null;
    return target;
  }

  /// Runs [text] as a device action when it is one.
  ///
  /// Returns null when the utterance is conversational, so the caller can fall
  /// back to the chat model.
  Future<AgentRouteResult?> route(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    // 1. App launch. Resolving the name first means "open wifi panel" (no such
    // app) falls through to the device bridge instead of claiming the app is
    // missing.
    final target = appLaunchTarget(trimmed);
    if (target != null) {
      final app = await AppLauncherService.instance.findApp(target);
      if (app != null) {
        final opened =
            await AppLauncherService.instance.launch(app.packageName);
        return AgentRouteResult(
          handled: true,
          spoken: opened == null
              ? 'I could not open ${app.name}, sir.'
              : '${app.name} is open, sir.',
        );
      }
    }

    // 2. Native device commands. `executeCommand` answers with an empty
    // `spoken` when nothing matched, which is the "not mine" signal. The verb
    // guard and the length cap keep ordinary sentences away from it — a false
    // positive here would answer a question with an action.
    if (trimmed.length > 80 || !_actionVerb.hasMatch(trimmed)) return null;
    final result = await DeviceControlService.instance.executeCommand(trimmed);
    if (result.spoken.isEmpty) return null;
    return AgentRouteResult(handled: true, spoken: result.spoken);
  }
}
