import 'package:flutter/material.dart';

import '../../services/personality_service.dart';
import '../../services/settings_service.dart';
import '../../services/telegram_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_widgets.dart';
import 'jarvis_settings_screen.dart';
import 'permissions_screen.dart';

/// 𝐉.𝐀.𝐑.𝐕.𝐈.𝐒 core configuration console.
/// Same language as the HUD: cyan hairlines on black, serif type, cut corners.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService.instance;
  final _telegram = TelegramService.instance;

  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late final TextEditingController _tokenController;
  late final TextEditingController _chatsController;

  bool _obscureKey = true;
  bool _obscureToken = true;

  String _lastSyncedProvider = '';

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(text: _settings.baseUrl);
    _apiKeyController = TextEditingController(text: _settings.apiKey);
    _modelController = TextEditingController(text: _settings.model);
    _tokenController = TextEditingController(text: _settings.telegramToken);
    _chatsController =
        TextEditingController(text: _settings.telegramAllowedChats.join(', '));
    _lastSyncedProvider = _settings.provider;

    PersonalityService.instance.init().then((_) {
      if (mounted) setState(() {});
    });

    for (final c in [
      _baseUrlController,
      _apiKeyController,
      _modelController,
    ]) {
      c.addListener(_onAiFieldChanged);
    }
    for (final c in [
      _tokenController,
      _chatsController,
    ]) {
      c.addListener(_onTelegramFieldChanged);
    }
    _settings.addListener(_onSettingsChanged);
    _telegram.addListener(_onTelegramChanged);
    PersonalityService.instance.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _telegram.removeListener(_onTelegramChanged);
    PersonalityService.instance.removeListener(_onServiceChanged);
    for (final c in [
      _baseUrlController,
      _apiKeyController,
      _modelController,
    ]) {
      c.removeListener(_onAiFieldChanged);
    }
    for (final c in [
      _tokenController,
      _chatsController,
    ]) {
      c.removeListener(_onTelegramFieldChanged);
    }
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _tokenController.dispose();
    _chatsController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    if (_settings.provider != _lastSyncedProvider) {
      _lastSyncedProvider = _settings.provider;
      _baseUrlController.text = _settings.baseUrl;
      _modelController.text = _settings.model;
    }
    setState(() {});
  }

  void _onTelegramChanged() {
    if (mounted) setState(() {});
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _onAiFieldChanged() {
    if (mounted) setState(() {});
  }

  void _onTelegramFieldChanged() {
    if (mounted) setState(() {});
  }

  bool get _aiDirty =>
      _baseUrlController.text.trim() != _settings.baseUrl ||
      _apiKeyController.text.trim() != _settings.apiKey ||
      _modelController.text.trim() != _settings.model;

  bool get _telegramDirty =>
      _tokenController.text.trim() != _settings.telegramToken ||
      _chatsController.text.trim() != _settings.telegramAllowedChats.join(', ');

  Future<void> _saveTelegramSettings() async {
    await _settings.setTelegramToken(_tokenController.text.trim());
    await _settings.setTelegramAllowedChats(
      _chatsController.text
          .split(RegExp(r'[,\s]+'))
          .where((s) => s.isNotEmpty)
          .toList(),
    );
    if (_settings.telegramEnabled) {
      await _telegram.restart();
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 20),
              SizedBox(width: 10),
              Text('Telegram configuration saved & reloaded'),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      );
  }

  Future<void> _saveAiSettings() async {
    await _settings.setBaseUrl(_baseUrlController.text);
    await _settings.setApiKey(_apiKeyController.text);
    await _settings.setModel(_modelController.text);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 20),
              SizedBox(width: 10),
              Text('AI provider settings saved successfully'),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return LiquidGlassScaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                physics: const BouncingScrollPhysics(),
                children: [
                  _sectionHeader(
                    code: '01',
                    title: 'AI Intelligence Engine',
                    caption: 'Uplink · model · sampling',
                  ),
                  _aiProviderCard(),
                  const SizedBox(height: 20),
                  _sectionHeader(
                    code: '02',
                    title: 'J.A.R.V.I.S. Core',
                    caption: 'Ears · voice · persona',
                  ),
                  _jarvisCard(),
                  const SizedBox(height: 20),
                  _sectionHeader(
                    code: '03',
                    title: 'Permissions & Inboxes',
                    caption: 'Clearance matrix · telemetry',
                  ),
                  _permissionsCard(),
                  const SizedBox(height: 20),
                  _sectionHeader(
                    code: '04',
                    title: 'Automation Agent',
                    caption: 'Execution limits · memory',
                  ),
                  _agentCard(),
                  const SizedBox(height: 20),
                  _sectionHeader(
                    code: '05',
                    title: 'Telegram Remote Bridge',
                    caption: 'Off-site command relay',
                  ),
                  _telegramCard(),
                  const SizedBox(height: 20),
                  _sectionHeader(
                    code: '06',
                    title: 'Display Protocol',
                    caption: 'HUD luminance',
                  ),
                  _appearanceCard(),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'J.A.R.V.I.S. · BUILD 2.9 · LOCAL CONFIG',
                      style: TextStyle(
                        fontSize: 8,
                        letterSpacing: 2.4,
                        color: AppTheme.hudCyan.withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// HUD title bar: back chevron, dossier title, live status lamp.
  Widget _header(BuildContext context) {
    final cyan = AppTheme.hudCyan;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cyan.withValues(alpha: 0.18)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.chevron_left_rounded),
            color: cyan,
            tooltip: 'Back',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'J.A.R.V.I.S. · CORE CONFIGURATION',
                  style: TextStyle(
                    fontSize: 7.5,
                    letterSpacing: 2.6,
                    color: cyan.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'SETTINGS',
                  style: TextStyle(
                    fontSize: 17,
                    letterSpacing: 6,
                    color: const Color(0xFFDFF9FF),
                    shadows: [
                      Shadow(
                        color: cyan.withValues(alpha: 0.6),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: cyan.withValues(alpha: 0.35)),
              color: cyan.withValues(alpha: 0.06),
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.hudGreen,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.hudGreen.withValues(alpha: 0.9),
                        blurRadius: 7,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'SYS',
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1.8,
                    color: cyan.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required String code,
    required String title,
    String? caption,
  }) {
    final cyan = AppTheme.hudCyan;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: cyan.withValues(alpha: 0.45)),
              color: cyan.withValues(alpha: 0.08),
            ),
            child: Text(
              code,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.2,
                color: cyan,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.2,
                  color: cyan.withValues(alpha: 0.92),
                ),
              ),
              if (caption != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    caption.toUpperCase(),
                    style: TextStyle(
                      fontSize: 7.5,
                      letterSpacing: 1.8,
                      color: cyan.withValues(alpha: 0.35),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: cyan.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  /// HUD primary action bar.
  Widget _actionButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
    IconData icon = Icons.save_outlined,
  }) {
    final cyan = AppTheme.hudCyan;
    final active = enabled;
    return GestureDetector(
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: active
              ? cyan.withValues(alpha: 0.14)
              : cyan.withValues(alpha: 0.03),
          border: Border.all(
            color: cyan.withValues(alpha: active ? 0.75 : 0.16),
            width: active ? 1.2 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: cyan.withValues(alpha: 0.22),
                    blurRadius: 20,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? icon : Icons.check_rounded,
              size: 15,
              color: cyan.withValues(alpha: active ? 1 : 0.45),
            ),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 2.2,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: cyan.withValues(alpha: active ? 1 : 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiProviderCard() {
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Model Provider Preset',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in SettingsService.providers.entries)
                GlassPill(
                  label: entry.value.label,
                  isSelected: _settings.provider == entry.key,
                  onTap: () => _settings.setProvider(entry.key),
                ),
            ],
          ),
          const SizedBox(height: 18),
          GlassTextField(
            controller: _baseUrlController,
            labelText: 'Base URL',
            hintText: 'https://api.example.com/v1',
            prefixIcon: const Icon(Icons.link_rounded, size: 20),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          GlassTextField(
            controller: _apiKeyController,
            labelText: 'API key',
            obscureText: _obscureKey,
            prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureKey = !_obscureKey),
            ),
          ),
          const SizedBox(height: 12),
          GlassTextField(
            controller: _modelController,
            labelText: 'Model',
            hintText: 'deepseek-chat',
            prefixIcon: const Icon(Icons.psychology_outlined, size: 20),
          ),
          const SizedBox(height: 16),
          // Save button with liquid glass styling
          _actionButton(
            label: _aiDirty ? 'Commit uplink settings' : 'Uplink synchronised',
            enabled: _aiDirty,
            onTap: _saveAiSettings,
          ),
          if (_aiDirty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  'Unsaved changes — tap Save to persist your API key and model.',
                  style: TextStyle(fontSize: 11.5, color: Colors.amber),
                ),
              ),
            ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),
          GlassSwitchTile(
            title: 'Send system prompt',
            subtitle: 'Recommended — teaches model precise phone action schema',
            icon: Icons.code_rounded,
            value: _settings.useSystemPrompt,
            onChanged: (v) => _settings.setUseSystemPrompt(v),
          ),
          const SizedBox(height: 6),
          GlassSliderRow(
            label: 'Temperature (Creativity)',
            value: _settings.temperature,
            min: 0,
            max: 2,
            divisions: 20,
            displayValue: _settings.temperature.toStringAsFixed(1),
            onChanged: (v) => _settings.setTemperature(v),
          ),
          GlassSliderRow(
            label: 'Max Response Tokens',
            value: _settings.maxTokens.toDouble(),
            min: 256,
            max: 4096,
            divisions: 15,
            displayValue: _settings.maxTokens.toString(),
            onChanged: (v) => _settings.setMaxTokens(v.round()),
          ),
        ],
      ),
    );
  }

  Widget _jarvisCard() {
    final theme = Theme.of(context);
    final isAlwaysOn = _settings.jarvisAlwaysOn;
    final persona = PersonalityService.instance.archetype.name.toUpperCase();
    final voice = _settings.jarvisNeuralVoice.split('-').length > 2
        ? _settings.jarvisNeuralVoice.split('-')[2].replaceAll('Neural', '')
        : 'Ryan';

    return GlassCard(
      borderRadius: 22,
      padding: EdgeInsets.zero,
      borderColor: AppTheme.hudCyan.withValues(alpha: 0.35),
      child: InkWell(
        borderRadius: BorderRadius.zero,
        onTap: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(builder: (_) => const JarvisSettingsScreen()),
              )
              .then((_) => setState(() {}));
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          AppTheme.hudCyan.withValues(alpha: 0.35),
                          AppTheme.hudCyan.withValues(alpha: 0.08),
                        ],
                      ),
                      border: Border.all(
                        color: AppTheme.hudCyan.withValues(alpha: 0.7),
                        width: 1.2,
                      ),
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: AppTheme.hudCyan,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'J.A.R.V.I.S.',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.4,
                                fontFamily: AppTheme.serif,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: isAlwaysOn
                                    ? AppTheme.hudCyan.withValues(alpha: 0.18)
                                    : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.zero,
                                border: Border.all(
                                  color: isAlwaysOn
                                      ? AppTheme.hudCyan.withValues(alpha: 0.6)
                                      : theme.colorScheme.outline.withValues(alpha: 0.3),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                isAlwaysOn ? 'ALWAYS-ON ACTIVE' : 'STANDBY',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: isAlwaysOn
                                      ? AppTheme.hudCyan
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Always-on ears, studio neural voice, personality, workflows & memory',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: AppTheme.hudCyan,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  GlassPill(
                    icon: const Icon(Icons.mic_rounded, size: 13, color: AppTheme.hudCyan),
                    label: isAlwaysOn ? 'Hands-Free Receptors' : 'Tap to Talk',
                    color: AppTheme.hudCyan,
                  ),
                  GlassPill(
                    icon: const Icon(Icons.record_voice_over_rounded, size: 13, color: AppTheme.hudAmber),
                    label: '$voice Studio Voice',
                    color: AppTheme.hudAmber,
                  ),
                  GlassPill(
                    icon: const Icon(Icons.psychology_outlined, size: 13, color: AppTheme.hudGreen),
                    label: '$persona Tone',
                    color: AppTheme.hudGreen,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permissionsCard() {
    return GlassCard(
      borderRadius: 22,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.zero,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PermissionsScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.hudCyan.withValues(alpha: 0.15),
                      border: Border.all(
                        color: AppTheme.hudCyan.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_open_rounded,
                      color: AppTheme.hudCyan,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'App Permissions & Inboxes',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Microphone, SMS stream, Email inbox & Accessibility service',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  GlassPill(
                    icon: Icon(Icons.sms_outlined, size: 13, color: Colors.blueAccent),
                    label: 'SMS Inbox',
                    color: Colors.blueAccent,
                  ),
                  GlassPill(
                    icon: Icon(Icons.mark_email_unread_outlined, size: 13, color: Colors.amber),
                    label: 'Email Stream',
                    color: Colors.amber,
                  ),
                  GlassPill(
                    icon: Icon(Icons.mic_rounded, size: 13, color: AppTheme.hudCyan),
                    label: 'Mic Receptor',
                    color: AppTheme.hudCyan,
                  ),
                  GlassPill(
                    icon: Icon(Icons.accessibility_new_rounded, size: 13, color: AppTheme.hudCyan),
                    label: 'Screen Touch',
                    color: AppTheme.hudCyan,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _agentCard() {
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          GlassSliderRow(
            label: 'Maximum Task Steps',
            value: _settings.maxSteps.toDouble(),
            min: 3,
            max: 40,
            divisions: 37,
            displayValue: '${_settings.maxSteps} steps',
            onChanged: (v) => _settings.setMaxSteps(v.round()),
          ),
          GlassSliderRow(
            label: 'Step Delay Buffer',
            value: _settings.stepDelayMs.toDouble(),
            min: 200,
            max: 5000,
            divisions: 24,
            displayValue: '${(_settings.stepDelayMs / 1000).toStringAsFixed(1)}s',
            onChanged: (v) => _settings.setStepDelayMs(v.round()),
          ),
          const SizedBox(height: 4),
          GlassSwitchTile(
            title: 'Skill Memory (Macro Fast Replay)',
            subtitle: 'Replay known sequences without invoking AI model',
            icon: Icons.auto_awesome_rounded,
            value: _settings.skillsEnabled,
            onChanged: (v) => _settings.setSkillsEnabled(v),
          ),
          GlassSwitchTile(
            title: 'Spoken Voice Feedback',
            subtitle: 'Vocalize automation progress and task results aloud',
            icon: Icons.record_voice_over_rounded,
            value: _settings.voiceFeedback,
            onChanged: (v) => _settings.setVoiceFeedback(v),
          ),
        ],
      ),
    );
  }

  Widget _telegramCard() {
    final running = _telegram.isRunning;
    final owner = _settings.telegramOwnerChatId;

    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassSwitchTile(
            title: 'Enable Telegram Remote Bridge',
            subtitle: running ? 'Bot actively polling for commands' : 'Bot service stopped',
            icon: Icons.send_rounded,
            value: _settings.telegramEnabled,
            onChanged: (v) async {
              await _settings.setTelegramEnabled(v);
              if (v) {
                await _telegram.start();
              } else {
                _telegram.stop();
              }
            },
          ),
          const SizedBox(height: 12),
          GlassTextField(
            controller: _tokenController,
            labelText: 'Telegram Bot Token (from @BotFather)',
            obscureText: _obscureToken,
            prefixIcon: const Icon(Icons.key_outlined, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureToken ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureToken = !_obscureToken),
            ),
          ),
          const SizedBox(height: 12),
          GlassTextField(
            controller: _chatsController,
            labelText: 'Allowed Chat IDs',
            hintText: 'Comma-separated (leave empty for auto-pairing)',
            prefixIcon: const Icon(Icons.group_outlined, size: 20),
          ),
          const SizedBox(height: 14),
          _actionButton(
            label: _telegramDirty ? 'Commit bridge settings' : 'Bridge synchronised',
            enabled: _telegramDirty,
            onTap: _saveTelegramSettings,
            icon: Icons.send_outlined,
          ),
          const SizedBox(height: 14),
          if (owner.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_rounded, size: 18, color: Colors.greenAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Paired Owner Device',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.greenAccent,
                          ),
                        ),
                        Text(
                          'Chat ID: $owner',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      backgroundColor: AppTheme.danger.withValues(alpha: 0.10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                        side: BorderSide(
                          color: AppTheme.danger.withValues(alpha: 0.45),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.link_off_rounded, size: 15),
                    label: const Text('Unpair', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    onPressed: () async {
                      await _settings.setTelegramOwnerChatId('');
                      if (!mounted) return;
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Telegram owner pairing unlinked'),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        ),
                      );
                    },
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amberAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_outlined, size: 18, color: Colors.amberAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Status: Unpaired',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.amberAccent,
                          ),
                        ),
                        Text(
                          'Send /start or /pair to your bot in Telegram to auto-pair, or enter Chat IDs above.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _appearanceCard() {
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Theme Preference',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _themeOption(
                  mode: ThemeMode.system,
                  label: 'System',
                  icon: Icons.brightness_auto_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _themeOption(
                  mode: ThemeMode.light,
                  label: 'Light',
                  icon: Icons.light_mode_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _themeOption(
                  mode: ThemeMode.dark,
                  label: 'Dark',
                  icon: Icons.dark_mode_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _themeOption({
    required ThemeMode mode,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _settings.themeMode == mode;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => _settings.setThemeMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.hudCyan.withValues(alpha: 0.16)
              : AppTheme.hudCyan.withValues(alpha: 0.03),
          borderRadius: BorderRadius.zero,
          border: Border.all(
            color: isSelected
                ? AppTheme.hudCyan.withValues(alpha: 0.7)
                : AppTheme.hudCyan.withValues(alpha: 0.15),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
