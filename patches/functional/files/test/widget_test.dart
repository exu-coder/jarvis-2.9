// `ThemeMode` is used by the SettingsService theme test below; without this
// import the analyzer reports `undefined_identifier` at the two call sites.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:private_agent/models/skill.dart';
import 'package:private_agent/models/task_step.dart';
import 'package:private_agent/services/jarvis_tools_service.dart';
import 'package:private_agent/services/settings_service.dart';
import 'package:private_agent/services/voice_service.dart';
import 'package:private_agent/services/workflow_service.dart';

void main() {
  group('TaskStep parsing', () {
    test('parses a plain JSON object', () {
      final step = TaskStep.tryParse(
        '{"action":"click_text","params":{"text":"Search"},'
        '"reasoning":"tap search","is_complete":false}',
      );
      expect(step, isNotNull);
      expect(step!.action, TaskStep.actionClickText);
      expect(step.stringParam('text'), 'Search');
      expect(step.isComplete, isFalse);
    });

    test('parses JSON wrapped in markdown fences with prose around it', () {
      final step = TaskStep.tryParse(
        'Here is my decision:\n```json\n{"action":"scroll",'
        '"params":{"direction":"down"},"is_complete":false}\n```\nDone.',
      );
      expect(step, isNotNull);
      expect(step!.action, TaskStep.actionScroll);
      expect(step.stringParam('direction'), 'down');
    });

    test('parses done action with is_complete', () {
      final step = TaskStep.tryParse('{"action":"done","is_complete":true}');
      expect(step, isNotNull);
      expect(step!.isComplete, isTrue);
    });

    test('rejects non-JSON and unknown actions', () {
      expect(TaskStep.tryParse('I cannot help with that'), isNull);
      expect(TaskStep.tryParse('{"action":"explode"}'), isNull);
    });
  });

  group('Skill matching', () {
    test('normalize collapses whitespace and case', () {
      expect(Skill.normalize('  Open   YouTube '), 'open youtube');
    });

    test('similarity rewards shared tokens', () {
      expect(Skill.similarity('open youtube', 'open youtube'), 1.0);
      expect(
        Skill.similarity(
          'open youtube and play lofi',
          'open youtube and play jazz',
        ),
        greaterThan(0.5),
      );
      expect(Skill.similarity('open youtube', 'call mom'), 0.0);
    });
  });

  group('SettingsService', () {
    test('persists AI settings', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService.instance;
      await settings.init();

      await settings.setProvider('openrouter');
      expect(settings.provider, 'openrouter');
      expect(settings.baseUrl, 'https://openrouter.ai/api/v1');

      await settings.setMaxSteps(25);
      expect(settings.maxSteps, 25);

      await settings.setThemeMode(ThemeMode.dark);
      expect(settings.themeMode, ThemeMode.dark);
    });

    test('persists the interaction mode, defaulting to agent', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService.instance;
      await settings.init();

      expect(settings.appMode, AppMode.agent);

      await settings.setAppMode(AppMode.chat);
      expect(settings.appMode, AppMode.chat);

      await settings.setAppMode(AppMode.jarvis);
      expect(settings.appMode, AppMode.jarvis);

      await settings.setAppMode(AppMode.agent);
      expect(settings.appMode, AppMode.agent);
    });

    test('backward compatibility migrates saved genie to agent', () async {
      SharedPreferences.setMockInitialValues({'ui_app_mode': 'genie'});
      final settings = SettingsService.instance;
      await settings.init();

      expect(settings.appMode, AppMode.agent);
    });
  });

  // These two used to be `testWidgets` that pumped the real app. That cannot
  // work in this codebase: `PrivateAgentApp` renders the onboarding wizard and
  // the home screen as WebViews (`assets/hud/*.html`), so there is no Flutter
  // text to find, and `pumpAndSettle` never returns because the HUD animation
  // loops forever — both tests hung until the 10-minute test timeout rather
  // than failing. The behaviour they were guarding lives in SettingsService,
  // so it is asserted directly instead.

  test('a fresh install is not marked as onboarded', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService.instance;
    await settings.init();

    // `PrivateAgentApp` shows OnboardingScreen while this is false, then the
    // HUD. Defaulting to `true` would drop first-run users straight into the
    // HUD with no provider/API key configured.
    expect(settings.onboardingComplete, isFalse);

    await settings.setOnboardingComplete(true);
    expect(settings.onboardingComplete, isTrue);
  });

  test('a custom model survives unrelated settings changes', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService.instance;
    await settings.init();

    // Selecting a provider preset fills in that provider's default model.
    await settings.setProvider('ollama');
    expect(settings.model, 'llama3.2');

    await settings.setModel('qwen2.5:7b');
    expect(settings.model, 'qwen2.5:7b');

    // Unrelated settings must not reset the model to the preset default. This
    // is the regression: every settings change rebuilds the screen, and a
    // controller re-initialised from the preset used to overwrite the field.
    await settings.setAppMode(AppMode.jarvis);
    await settings.setUseSystemPrompt(true);
    await settings.setTemperature(1.1);
    expect(settings.model, 'qwen2.5:7b');

    // Re-selecting the same provider *is* an explicit reset, and only then.
    await settings.setProvider('ollama');
    expect(settings.model, 'llama3.2');
  });

  group('JARVIS & Hermes Workflow tests', () {
    test('WorkflowService matches study, sleep, and cinema protocols', () async {
      SharedPreferences.setMockInitialValues({});
      final workflows = WorkflowService.instance;
      await workflows.init();

      final studyMatch = workflows.findMatch('Jarvis I have to study for exams');
      expect(studyMatch, isNotNull);
      expect(studyMatch!.id, 'study');
      expect(studyMatch.brightness, 0.45);
      expect(studyMatch.volume, 0.0);

      final nightMatch = workflows.findMatch('going to sleep now goodnight');
      expect(nightMatch, isNotNull);
      expect(nightMatch!.id, 'night');
      expect(nightMatch.brightness, 0.05);

      final cinemaMatch = workflows.findMatch('let us watch a movie in cinema mode');
      expect(cinemaMatch, isNotNull);
      expect(cinemaMatch!.id, 'cinema');
      expect(cinemaMatch.volume, 0.70);
    });

    test('SettingsService persists JARVIS configuration', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsService.instance;
      await settings.init();

      // H10: defaults are privacy-safe (opt-in). The previous expectations
      // asserted `true` here while the implementation defaults both flags to
      // `false`, so the test could never pass and CI never ran it.
      expect(settings.jarvisAlwaysOn, isFalse);
      expect(settings.jarvisVoice, 'paul');
      expect(settings.jarvisNeuralVoice, 'en-GB-RyanNeural');
      expect(settings.useNeuralVoice, isFalse);
      expect(settings.jarvisWorkflowsEnabled, isTrue);

      await settings.setJarvisAlwaysOn(true);
      await settings.setJarvisVoice('friday');
      await settings.setJarvisNeuralVoice('en-US-GuyNeural');
      await settings.setUseNeuralVoice(true);
      await settings.setJarvisWorkflowsEnabled(false);

      expect(settings.jarvisAlwaysOn, isTrue);
      expect(settings.jarvisVoice, 'friday');
      expect(settings.jarvisNeuralVoice, 'en-US-GuyNeural');
      expect(settings.useNeuralVoice, isTrue);
      expect(settings.jarvisWorkflowsEnabled, isFalse);
    });

    test('JarvisToolsService formats temporal diagnostics', () {
      final dt = JarvisToolsService.instance.getCurrentDateTime();
      expect(dt, isNotEmpty);
      expect(dt.contains(DateTime.now().year.toString()), isTrue);
    });

    test('VoiceService sanitizes J.A.R.V.I.S. into natural spoken Jarvis', () {
      final voice = VoiceService.instance;
      expect(voice.sanitizeForSpeech('I am J.A.R.V.I.S., sir.'), 'I am Jarvis, sir.');
      expect(voice.sanitizeForSpeech('Hello J.A.R.V.I.S'), 'Hello Jarvis');
      expect(voice.sanitizeForSpeech('Welcome to JARVIS mode'), 'Welcome to Jarvis mode');
    });
  });
}
