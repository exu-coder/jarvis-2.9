import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Interaction mode of the home screen.
///
/// - [agent]: agent mode — tasks are executed on the device via the
///   observe → think → act loop (accessibility service required).
/// - [chat]: plain chatbot mode — messages get a conversational LLM reply,
///   no screen reading and no device actions.
/// - [jarvis]: JARVIS mode — hands-free voice-first autonomous agent & assistant
///   with live holographic Iron Man HUD animation, intelligent action/chat routing,
///   and full device control.
enum AppMode { agent, chat, jarvis }

/// Visual HUD display style for JARVIS mode.
///
/// - [arcReactor]: Arc Reactor (3D spherical consciousness core with gyroscopic armillary rings).
/// - [jarvis]: Jarvis (3D Iron Man hologram suit avatar with reactive telemetry).
enum JarvisScreenStyle { arcReactor, jarvis }

/// Central, observable store for all user-configurable settings.
///
/// Backed by SharedPreferences for preferences and by Keystore-backed
/// [FlutterSecureStorage] for secrets (LLM API key, Telegram bot token).
/// Access via [SettingsService.instance] after calling [init] once at app start.
class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  SharedPreferences? _prefs;

  // ------------------------------------------------------------------
  // Secrets (C2)
  // ------------------------------------------------------------------

  /// Keystore-wrapped store for the two secrets. Values are cached in memory
  /// because every caller reads them through the synchronous getters below.
  ///
  /// v11 dropped `AndroidOptions.encryptedSharedPreferences` — the plugin now
  /// keeps its own encrypted file and wraps the AES key in the Android
  /// KeyStore, which is the stronger of the two schemes and is no longer
  /// dependent on the deprecated androidx.security crypto artifact.
  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  static const String _secureApiKeyKey = 'ai_api_key';
  static const String _secureTelegramTokenKey = 'telegram_token';

  String _secureApiKey = '';
  String _secureTelegramToken = '';

  bool get isReady => _prefs != null;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    // Ensure system prompt is enabled so models always receive the agent action grammar
    if (_prefs?.getBool('ai_use_system_prompt') != true) {
      await _prefs?.setBool('ai_use_system_prompt', true);
    }
    await _loadSecrets();
  }

  /// Loads both secrets from secure storage into memory and moves any
  /// plaintext leftovers out of SharedPreferences (one-time migration).
  Future<void> _loadSecrets() async {
    try {
      _secureApiKey = await _secure.read(key: _secureApiKeyKey) ?? '';
      _secureTelegramToken =
          await _secure.read(key: _secureTelegramTokenKey) ?? '';
    } catch (e) {
      debugPrint('[SettingsService] Secure storage unavailable: $e');
      _secureApiKey = '';
      _secureTelegramToken = '';
    }

    _secureApiKey = await _migratePlaintextSecret(
      prefsKey: _secureApiKeyKey,
      cached: _secureApiKey,
      secureKey: _secureApiKeyKey,
    );
    _secureTelegramToken = await _migratePlaintextSecret(
      prefsKey: _secureTelegramTokenKey,
      cached: _secureTelegramToken,
      secureKey: _secureTelegramTokenKey,
    );
  }

  /// Earlier builds stored these two values with `SharedPreferences.setString`,
  /// which also put them into Android auto-backup. Copy the plaintext value into
  /// secure storage (when secure storage has nothing yet) and delete the
  /// plaintext entry either way.
  Future<String> _migratePlaintextSecret({
    required String prefsKey,
    required String cached,
    required String secureKey,
  }) async {
    final legacy = _prefs?.getString(prefsKey)?.trim() ?? '';
    if (legacy.isEmpty) return cached;
    var value = cached;
    if (value.isEmpty) {
      value = legacy;
      await _writeSecret(secureKey, value);
      debugPrint('[SettingsService] Migrated "$prefsKey" to secure storage.');
    }
    await _prefs?.remove(prefsKey);
    return value;
  }

  Future<void> _writeSecret(String key, String value) async {
    try {
      if (value.isEmpty) {
        await _secure.delete(key: key);
      } else {
        await _secure.write(key: key, value: value);
      }
    } catch (e) {
      debugPrint('[SettingsService] Could not persist secret "$key": $e');
    }
  }

  // ------------------------------------------------------------------
  // AI provider
  // ------------------------------------------------------------------

  /// Well-known OpenAI-compatible providers.
  static const Map<String, ({String label, String baseUrl, String model})>
  providers = {
    'deepseek': (
      label: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
    ),
    'openai': (
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
    ),
    'gemini': (
      label: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      model: 'gemini-2.0-flash',
    ),
    'openrouter': (
      label: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'openai/gpt-4o-mini',
    ),
    'nvidia': (
      label: 'NVIDIA NIM',
      baseUrl: 'https://integrate.api.nvidia.com/v1',
      model: 'meta/llama-3.3-70b-instruct',
    ),
    'ollama': (
      label: 'Ollama (local)',
      baseUrl: 'http://127.0.0.1:11434/v1',
      model: 'llama3.2',
    ),
    'custom': (label: 'Custom (OpenAI-compatible)', baseUrl: '', model: ''),
  };

  String get provider => _prefs?.getString('ai_provider') ?? 'deepseek';
  Future<void> setProvider(String value) async {
    await _prefs?.setString('ai_provider', value);
    final preset = providers[value];
    if (preset != null && preset.baseUrl.isNotEmpty) {
      await _prefs?.setString('ai_base_url', preset.baseUrl);
      await _prefs?.setString('ai_model', preset.model);
    }
    notifyListeners();
  }

  String get baseUrl =>
      _prefs?.getString('ai_base_url') ??
      providers[provider]?.baseUrl ??
      providers['deepseek']!.baseUrl;
  Future<void> setBaseUrl(String value) async {
    await _prefs?.setString('ai_base_url', value.trim());
    notifyListeners();
  }

  /// LLM API key. Never written to SharedPreferences — it lives in
  /// Keystore-backed storage and is cached here for synchronous reads.
  String get apiKey => _secureApiKey;
  Future<void> setApiKey(String value) async {
    final trimmed = value.trim();
    _secureApiKey = trimmed;
    await _writeSecret(_secureApiKeyKey, trimmed);
    notifyListeners();
  }

  String get model =>
      _prefs?.getString('ai_model') ??
      providers[provider]?.model ??
      'deepseek-chat';
  Future<void> setModel(String value) async {
    await _prefs?.setString('ai_model', value.trim());
    notifyListeners();
  }

  /// Defaults to 2048 so reasoning models (which burn completion tokens on
  /// hidden thinking before answering) still have budget left for the reply.
  int get maxTokens => _prefs?.getInt('ai_max_tokens') ?? 2048;
  Future<void> setMaxTokens(int value) async {
    await _prefs?.setInt('ai_max_tokens', value.clamp(128, 16384));
    notifyListeners();
  }

  double get temperature => _prefs?.getDouble('ai_temperature') ?? 0.2;
  Future<void> setTemperature(double value) async {
    await _prefs?.setDouble('ai_temperature', value.clamp(0.0, 2.0));
    notifyListeners();
  }

  bool get useSystemPrompt => _prefs?.getBool('ai_use_system_prompt') ?? true;
  Future<void> setUseSystemPrompt(bool value) async {
    await _prefs?.setBool('ai_use_system_prompt', value);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Agent loop
  // ------------------------------------------------------------------

  int get maxSteps => _prefs?.getInt('agent_max_steps') ?? 15;
  Future<void> setMaxSteps(int value) async {
    await _prefs?.setInt('agent_max_steps', value.clamp(3, 40));
    notifyListeners();
  }

  /// Delay between loop iterations, lets the UI settle after each action.
  int get stepDelayMs => _prefs?.getInt('agent_step_delay_ms') ?? 1200;
  Future<void> setStepDelayMs(int value) async {
    await _prefs?.setInt('agent_step_delay_ms', value.clamp(200, 10000));
    notifyListeners();
  }

  bool get skillsEnabled => _prefs?.getBool('agent_skills_enabled') ?? true;
  Future<void> setSkillsEnabled(bool value) async {
    await _prefs?.setBool('agent_skills_enabled', value);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Telegram
  // ------------------------------------------------------------------

  bool get telegramEnabled => _prefs?.getBool('telegram_enabled') ?? false;
  Future<void> setTelegramEnabled(bool value) async {
    await _prefs?.setBool('telegram_enabled', value);
    notifyListeners();
  }

  /// Telegram bot token. Keystore-backed; read synchronously from the cache.
  String get telegramToken => _secureTelegramToken;
  Future<void> setTelegramToken(String value) async {
    final trimmed = value.trim();
    _secureTelegramToken = trimmed;
    await _writeSecret(_secureTelegramTokenKey, trimmed);
    notifyListeners();
  }

  /// Chat ids allowed to control the device.
  ///
  /// C3: pairing is explicit. The user requests a code on the phone, sends
  /// `/pair <code>` to the bot, and only then does the chat land in this list.
  /// There is no implicit "the first chat that writes becomes the owner" path
  /// any more.
  List<String> get telegramAllowedChats =>
      _prefs?.getStringList('telegram_allowed_chats') ?? const [];
  Future<void> setTelegramAllowedChats(List<String> value) async {
    await _prefs?.setStringList('telegram_allowed_chats', value);
    notifyListeners();
  }

  /// Primary paired chat — the push destination used by security alerts and
  /// Sentry snapshots. Derived from [telegramAllowedChats]; it is no longer an
  /// authorization source.
  String get telegramOwnerChatId =>
      telegramAllowedChats.isNotEmpty ? telegramAllowedChats.first : '';

  /// A6: full revoke of remote access.
  ///
  /// Clears every paired chat, any outstanding pairing code and the bot token
  /// itself, so the bridge stops working immediately and cannot be re-armed by
  /// a chat that was previously paired.
  ///
  /// The token must also be revoked in @BotFather: Telegram has no API to
  /// rotate a bot token, so a fresh one has to be issued there and pasted back
  /// in. Until then the bridge has no credentials at all, which is the safe
  /// state.
  Future<void> revokeTelegramAccess() async {
    await setTelegramAllowedChats(const []);
    await clearTelegramPairCode();
    await setTelegramToken('');
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Telegram pairing code (C3)
  // ------------------------------------------------------------------

  static const String _pairCodeKey = 'telegram_pair_code';
  static const String _pairExpiryKey = 'telegram_pair_expiry';
  static const String _pairFailKey = 'telegram_pair_failures';

  /// How long a freshly issued pairing code stays usable.
  static const Duration telegramPairCodeTtl = Duration(minutes: 10);

  /// Wrong guesses allowed before the displayed code is destroyed. Five keeps
  /// the odds of a blind guess at 5-in-a-million per code.
  static const int maxPairAttempts = 5;

  /// The code currently offered to the user (may be expired/empty).
  String get telegramPairCode => _prefs?.getString(_pairCodeKey) ?? '';
  int get telegramPairCodeExpiresAt => _prefs?.getInt(_pairExpiryKey) ?? 0;

  /// True while a displayed code can still be redeemed.
  bool get telegramPairCodeIsActive {
    final code = telegramPairCode;
    if (code.length != 6) return false;
    final expiry = telegramPairCodeExpiresAt;
    if (expiry <= 0) return false;
    return DateTime.now().millisecondsSinceEpoch < expiry;
  }

  /// Six digits from [Random.secure] (cryptographically secure on Android).
  static String generateTelegramPairCode([Random? random]) {
    final rnd = random ?? Random.secure();
    return rnd.nextInt(1000000).toString().padLeft(6, '0');
  }

  /// Pure validator, so the pairing rules stay unit-testable without
  /// SharedPreferences or a device. Compares digits in constant time and
  /// rejects an empty/expired code.
  static bool isTelegramPairCodeValid({
    required String stored,
    required int expiresAtMs,
    required String candidate,
    required int nowMs,
  }) {
    if (stored.length != 6 || candidate.length != 6) return false;
    if (expiresAtMs <= 0 || nowMs >= expiresAtMs) return false;
    var diff = 0;
    for (var i = 0; i < stored.length; i++) {
      diff |= stored.codeUnitAt(i) ^ candidate.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Issues a fresh code, stores it with its expiry and returns it so the
  /// settings screen can display it.
  Future<String> issueTelegramPairCode() async {
    final code = generateTelegramPairCode();
    final expiry =
        DateTime.now().add(telegramPairCodeTtl).millisecondsSinceEpoch;
    await _prefs?.setString(_pairCodeKey, code);
    await _prefs?.setInt(_pairExpiryKey, expiry);
    // A new code always starts with a clean attempt budget.
    await _prefs?.setInt(_pairFailKey, 0);
    notifyListeners();
    return code;
  }

  Future<void> clearTelegramPairCode() async {
    await _prefs?.remove(_pairCodeKey);
    await _prefs?.remove(_pairExpiryKey);
    await _prefs?.remove(_pairFailKey);
    notifyListeners();
  }

  /// Redeems [candidate] once: returns true only for the stored, unexpired
  /// code, and invalidates the code in that case.
  Future<bool> consumeTelegramPairCode(String candidate) async {
    final ok = isTelegramPairCodeValid(
      stored: telegramPairCode,
      expiresAtMs: telegramPairCodeExpiresAt,
      candidate: candidate.trim(),
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (ok) {
      await clearTelegramPairCode();
      return true;
    }
    // Failed attempts are counted and the code is destroyed after
    // [maxPairAttempts] misses. Without that cap a 6-digit code is a
    // 1-in-a-million lottery an unpaired chat can play for the whole TTL — and
    // the bot username is public.
    final failures = (_prefs?.getInt(_pairFailKey) ?? 0) + 1;
    if (failures >= maxPairAttempts) {
      await clearTelegramPairCode();
    } else {
      await _prefs?.setInt(_pairFailKey, failures);
    }
    return false;
  }

  int get telegramUpdateOffset => _prefs?.getInt('telegram_offset') ?? 0;
  Future<void> setTelegramUpdateOffset(int value) async {
    await _prefs?.setInt('telegram_offset', value);
  }

  // ------------------------------------------------------------------
  // ------------------------------------------------------------------
  // Interaction mode
  // ------------------------------------------------------------------

  /// Whether the home screen sends messages to the agent loop
  /// ([AppMode.agent]), treats them as plain conversation
  /// ([AppMode.chat]), or enters voice-first hands-free ([AppMode.jarvis]).
  AppMode get appMode {
    final raw = _prefs?.getString('ui_app_mode') ?? 'agent';
    if (raw == 'genie') return AppMode.agent;
    return AppMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => AppMode.agent,
    );
  }

  Future<void> setAppMode(AppMode mode) async {
    await _prefs?.setString('ui_app_mode', mode.name);
    notifyListeners();
  }

  // Appearance, voice & onboarding
  // ------------------------------------------------------------------

  /// Visual HUD display style for JARVIS mode.
  /// Options: [JarvisScreenStyle.arcReactor] ("Arc Reactor"), [JarvisScreenStyle.jarvis] ("Jarvis").
  JarvisScreenStyle get jarvisScreenStyle {
    final raw = _prefs?.getString('jarvis_screen_style') ?? 'arcReactor';
    return JarvisScreenStyle.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => JarvisScreenStyle.arcReactor,
    );
  }

  Future<void> setJarvisScreenStyle(JarvisScreenStyle value) async {
    await _prefs?.setString('jarvis_screen_style', value.name);
    notifyListeners();
  }

  /// Whether JARVIS listens continuously like Google Home without tapping.
  bool get jarvisAlwaysOn => _prefs?.getBool('jarvis_always_on') ?? false;
  Future<void> setJarvisAlwaysOn(bool value) async {
    await _prefs?.setBool('jarvis_always_on', value);
    notifyListeners();
  }

  /// Voice profile: 'paul' (British Jarvis), 'friday' (Irish), 'stark' (US), 'kip' (Deep), 'cortana' (Smooth).
  String get jarvisVoice => _prefs?.getString('jarvis_voice') ?? 'paul';
  Future<void> setJarvisVoice(String value) async {
    await _prefs?.setString('jarvis_voice', value);
    notifyListeners();
  }

  /// Studio Neural Voice (Edge-TTS) for ultra-realistic human speech.
  /// Defaults to en-GB-RyanNeural (Paul Bettany British JARVIS style).
  String get jarvisNeuralVoice =>
      _prefs?.getString('jarvis_neural_voice') ?? 'en-GB-RyanNeural';
  Future<void> setJarvisNeuralVoice(String value) async {
    await _prefs?.setString('jarvis_neural_voice', value);
    notifyListeners();
  }

  /// Whether to prioritize ultra-realistic neural human voices over offline TTS.
  bool get useNeuralVoice =>
      _prefs?.getBool('jarvis_use_neural_voice') ?? false;
  Future<void> setUseNeuralVoice(bool value) async {
    await _prefs?.setBool('jarvis_use_neural_voice', value);
    notifyListeners();
  }

  /// Set when the Edge-TTS endpoint has stopped working (Microsoft rotates the
  /// `Sec-MS-GEC` token format and the pinned browser version), so speech
  /// downgrades to the on-device engine instead of failing silently.
  ///
  /// Persisted so the downgrade survives a restart; cleared by
  /// `EdgeTtsService.resetDowngrade()`.
  bool get neuralVoiceDegraded =>
      _prefs?.getBool('jarvis_neural_voice_degraded') ?? false;
  Future<void> setNeuralVoiceDegraded(bool value) async {
    await _prefs?.setBool('jarvis_neural_voice_degraded', value);
    notifyListeners();
  }

  /// Self-evolving skills & workflows like Hermes Agent.
  bool get jarvisWorkflowsEnabled =>
      _prefs?.getBool('jarvis_workflows_enabled') ?? true;
  Future<void> setJarvisWorkflowsEnabled(bool value) async {
    await _prefs?.setBool('jarvis_workflows_enabled', value);
    notifyListeners();
  }

  /// Local-First Privacy Mode: forces on-device processing via local Ollama
  /// (127.0.0.1:11434) and offline voice synthesis, zero cloud data leakage.
  bool get localFirstPrivacyMode =>
      _prefs?.getBool('local_first_privacy_mode') ?? false;
  Future<void> setLocalFirstPrivacyMode(bool value) async {
    await _prefs?.setBool('local_first_privacy_mode', value);
    if (value) {
      await setProvider('ollama');
      await setUseNeuralVoice(false);
    }
    notifyListeners();
  }

  /// Permission system: prompts for explicit confirmation before high-risk operations
  /// (e.g. sending messages, placing calls, deleting data, purchases).
  bool get confirmRiskyActions =>
      _prefs?.getBool('confirm_risky_actions') ?? true;
  Future<void> setConfirmRiskyActions(bool value) async {
    await _prefs?.setBool('confirm_risky_actions', value);
    notifyListeners();
  }

  ThemeMode get themeMode {
    final raw = _prefs?.getString('ui_theme_mode') ?? 'system';
    return ThemeMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs?.setString('ui_theme_mode', mode.name);
    notifyListeners();
  }

  bool get onboardingComplete =>
      _prefs?.getBool('onboarding_complete') ?? false;
  Future<void> setOnboardingComplete(bool value) async {
    await _prefs?.setBool('onboarding_complete', value);
    notifyListeners();
  }

  /// Whether the assistant should speak results aloud via TTS.
  bool get voiceFeedback => _prefs?.getBool('voice_feedback') ?? false;
  Future<void> setVoiceFeedback(bool value) async {
    await _prefs?.setBool('voice_feedback', value);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Advanced Features: Smart Home, Commute, Jarvis Eye, Macro Recorder
  // ------------------------------------------------------------------

  /// Smart Home / Home Assistant URL (e.g. http://192.168.1.100:8123)
  String get homeAssistantUrl =>
      _prefs?.getString('smart_home_ha_url') ?? 'http://homeassistant.local:8123';
  Future<void> setHomeAssistantUrl(String value) async {
    await _prefs?.setString('smart_home_ha_url', value.trim());
    notifyListeners();
  }

  /// Home Assistant Long-Lived Access Token
  String get homeAssistantToken =>
      _prefs?.getString('smart_home_ha_token') ?? '';
  Future<void> setHomeAssistantToken(String value) async {
    await _prefs?.setString('smart_home_ha_token', value.trim());
    notifyListeners();
  }

  /// Whether Smart Home integration is enabled
  bool get smartHomeEnabled =>
      _prefs?.getBool('smart_home_enabled') ?? true;
  Future<void> setSmartHomeEnabled(bool value) async {
    await _prefs?.setBool('smart_home_enabled', value);
    notifyListeners();
  }

  /// Default Smart Home entity ID (e.g. light.living_room)
  String get smartHomeDefaultEntity =>
      _prefs?.getString('smart_home_default_entity') ?? 'light.living_room';
  Future<void> setSmartHomeDefaultEntity(String value) async {
    await _prefs?.setString('smart_home_default_entity', value.trim());
    notifyListeners();
  }

  /// Commute: Home address / origin
  String get commuteHomeAddress =>
      _prefs?.getString('commute_home_address') ?? 'Downtown';
  Future<void> setCommuteHomeAddress(String value) async {
    await _prefs?.setString('commute_home_address', value.trim());
    notifyListeners();
  }

  /// Commute: Work / standard destination address
  String get commuteWorkAddress =>
      _prefs?.getString('commute_work_address') ?? 'Tech Park';
  Future<void> setCommuteWorkAddress(String value) async {
    await _prefs?.setString('commute_work_address', value.trim());
    notifyListeners();
  }

  /// Commute travel mode: 'driving', 'transit', 'walking', 'cycling'
  String get commuteMode =>
      _prefs?.getString('commute_mode') ?? 'driving';
  Future<void> setCommuteMode(String value) async {
    await _prefs?.setString('commute_mode', value);
    notifyListeners();
  }

  /// Proactive Commute & Traffic warnings before meetings
  bool get proactiveCommuteEnabled =>
      _prefs?.getBool('proactive_commute_enabled') ?? true;
  Future<void> setProactiveCommuteEnabled(bool value) async {
    await _prefs?.setBool('proactive_commute_enabled', value);
    notifyListeners();
  }

  /// Jarvis Eye Multimodal Camera Perception
  bool get jarvisEyeEnabled =>
      _prefs?.getBool('jarvis_eye_enabled') ?? true;
  Future<void> setJarvisEyeEnabled(bool value) async {
    await _prefs?.setBool('jarvis_eye_enabled', value);
    notifyListeners();
  }

  /// Autonomous Macro Recorder
  bool get macroRecorderEnabled =>
      _prefs?.getBool('macro_recorder_enabled') ?? true;
  Future<void> setMacroRecorderEnabled(bool value) async {
    await _prefs?.setBool('macro_recorder_enabled', value);
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Autonomous Proactive Vocalization & Scheduled Nudges
  // ------------------------------------------------------------------

  /// Master switch: whether JARVIS can speak up proactively on its own
  bool get jarvisAutoSpeakEnabled =>
      _prefs?.getBool('jarvis_auto_speak_enabled') ?? true;
  Future<void> setJarvisAutoSpeakEnabled(bool value) async {
    await _prefs?.setBool('jarvis_auto_speak_enabled', value);
    notifyListeners();
  }

  /// Whether JARVIS automatically opens a hands-free confirmation window
  /// ("Yes" or "No") after asking a proactive question
  bool get proactiveVoiceConfirmationEnabled =>
      _prefs?.getBool('proactive_voice_confirmation_enabled') ?? true;
  Future<void> setProactiveVoiceConfirmationEnabled(bool value) async {
    await _prefs?.setBool('proactive_voice_confirmation_enabled', value);
    notifyListeners();
  }

  /// Proactive Bedtime / Night Mode prompt (around 9:30 PM - 11 PM)
  bool get proactiveNightModePrompt =>
      _prefs?.getBool('proactive_night_mode_prompt') ?? true;
  Future<void> setProactiveNightModePrompt(bool value) async {
    await _prefs?.setBool('proactive_night_mode_prompt', value);
    notifyListeners();
  }

  /// Proactive Morning Briefing prompt (around 7:30 AM - 9 AM)
  bool get proactiveMorningBriefingPrompt =>
      _prefs?.getBool('proactive_morning_briefing_prompt') ?? true;
  Future<void> setProactiveMorningBriefingPrompt(bool value) async {
    await _prefs?.setBool('proactive_morning_briefing_prompt', value);
    notifyListeners();
  }

  /// Proactive Study & Focus Protocol prompt (afternoon study session)
  bool get proactiveStudyPrompt =>
      _prefs?.getBool('proactive_study_prompt') ?? true;
  Future<void> setProactiveStudyPrompt(bool value) async {
    await _prefs?.setBool('proactive_study_prompt', value);
    notifyListeners();
  }

  /// Proactive Remaining Tasks Review (late afternoon agenda check)
  bool get proactiveTaskReminderPrompt =>
      _prefs?.getBool('proactive_task_reminder_prompt') ?? true;
  Future<void> setProactiveTaskReminderPrompt(bool value) async {
    await _prefs?.setBool('proactive_task_reminder_prompt', value);
    notifyListeners();
  }

  /// Proactive Upcoming Meeting Reminders (15-30m before calendar events)
  bool get proactiveMeetingReminders =>
      _prefs?.getBool('proactive_meeting_reminders') ?? true;
  Future<void> setProactiveMeetingReminders(bool value) async {
    await _prefs?.setBool('proactive_meeting_reminders', value);
    notifyListeners();
  }

  /// Proactive Low Battery Warning (< 20%)
  bool get proactiveBatteryAlert =>
      _prefs?.getBool('proactive_battery_alert') ?? true;
  Future<void> setProactiveBatteryAlert(bool value) async {
    await _prefs?.setBool('proactive_battery_alert', value);
    notifyListeners();
  }
}
