import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'aims_hands_free_platform.dart';
import 'aims_locale.dart';
import 'aims_voice_command.dart';

enum AimsVoiceMode {
  off,
  wakeWord,
  command,
  speaking,
  error,
}

class AimsVoiceState {
  const AimsVoiceState({
    required this.enabled,
    required this.mode,
    required this.message,
    this.lastHeard = '',
  });

  final bool enabled;
  final AimsVoiceMode mode;
  final String message;
  final String lastHeard;
}

typedef AimsVoiceCommandHandler = Future<String> Function(AimsVoiceCommand command);

class AimsVoiceService {
  AimsVoiceService({
    required this.onCommand,
    required this.driverNameProvider,
  }) {
    _locale.addListener(_onLanguageChanged);
  }

  final AimsVoiceCommandHandler onCommand;
  final String Function() driverNameProvider;
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AimsVoiceCommandParser _parser = const AimsVoiceCommandParser();
  final AimsLocaleController _locale = AimsLocaleController.instance;
  final StreamController<AimsVoiceState> _states =
      StreamController<AimsVoiceState>.broadcast();

  StreamSubscription<void>? _assistantInvocationSub;
  Timer? _restartTimer;

  bool _initialized = false;
  bool _enabled = false;
  bool _commandMode = false;
  bool _speaking = false;
  bool _handlingResult = false;
  bool _maleVoiceMatched = false;
  String _localeId = 'hu_HU';
  String _lastHeard = '';

  Stream<AimsVoiceState> get states => _states.stream;
  bool get enabled => _enabled;

  Future<bool> initialize() async {
    if (_initialized) return true;

    final available = await _speech.initialize(
      onStatus: _onStatus,
      onError: _onError,
      debugLogging: false,
      finalTimeout: const Duration(seconds: 5),
    );
    if (!available) {
      _emit(
        AimsVoiceState(
          enabled: false,
          mode: AimsVoiceMode.error,
          message: _locale.t('speech_unavailable'),
        ),
      );
      return false;
    }

    await _applyLanguage();

    _assistantInvocationSub ??=
        AimsHandsFreePlatform.assistantInvoked.listen((_) {
      unawaited(triggerAssistant());
    });

    _initialized = true;
    return true;
  }

  Future<bool> enableHandsFree() async {
    final ok = await initialize();
    if (!ok) return false;

    _enabled = true;
    await AimsHandsFreePlatform.start();
    _commandMode = false;
    await _startWakeListening();
    return true;
  }

  Future<void> disableHandsFree() async {
    _enabled = false;
    _commandMode = false;
    _restartTimer?.cancel();
    await _speech.cancel();
    await _tts.stop();
    await AimsHandsFreePlatform.stop();
    _emit(
      AimsVoiceState(
        enabled: false,
        mode: AimsVoiceMode.off,
        message: _locale.t('hands_free_off'),
      ),
    );
  }

  Future<void> triggerAssistant() async {
    final ok = await initialize();
    if (!ok) return;
    if (!_enabled) {
      _enabled = true;
      await AimsHandsFreePlatform.start();
    }
    await _enterCommandMode();
  }

  Future<void> requestAndroidAssistantRole() async {
    await AimsHandsFreePlatform.requestAssistantRole();
  }

  Future<void> _startWakeListening() async {
    if (!_enabled || _speaking || _handlingResult) return;
    _commandMode = false;
    await _startListening(
      mode: AimsVoiceMode.wakeWord,
      message: _locale.t('wake_listening'),
      wakeOnly: true,
    );
  }

  Future<void> _startCommandListening() async {
    if (!_enabled || _speaking || _handlingResult) return;
    _commandMode = true;
    await _startListening(
      mode: AimsVoiceMode.command,
      message: _assistantGreeting(),
      wakeOnly: false,
    );
  }

  Future<void> _startListening({
    required AimsVoiceMode mode,
    required String message,
    required bool wakeOnly,
  }) async {
    if (_speech.isListening) return;

    _emit(
      AimsVoiceState(
        enabled: _enabled,
        mode: mode,
        message: message,
        lastHeard: wakeOnly ? '' : _lastHeard,
      ),
    );

    final options = SpeechListenOptions(
      listenMode: wakeOnly ? ListenMode.search : ListenMode.dictation,
      onDevice: wakeOnly,
      cancelOnError: false,
      partialResults: true,
      autoPunctuation: false,
      enableHapticFeedback: false,
      pauseFor: wakeOnly
          ? const Duration(seconds: 2)
          : const Duration(seconds: 4),
      listenFor: wakeOnly
          ? const Duration(seconds: 10)
          : const Duration(seconds: 12),
      localeId: _localeId,
      contextualPhrases: switch (_locale.languageCode) {
        'en' => const [
            'AIMS',
            'pickup',
            'delivery',
            'job',
            'navigation',
            'contact',
            'CMR',
          ],
        'de' => const [
            'AIMS',
            'Abholung',
            'Zustellung',
            'Auftrag',
            'Navigation',
            'Ansprechpartner',
            'CMR',
          ],
        _ => const [
            'AIMS',
            'AIMS Flow',
            'éjms',
            'éjmsz',
            'aimsz',
            'eims',
            'ems',
            'felrakó',
            'lerakó',
            'fuvar',
            'navigáció',
            'kapcsolattartó',
            'CMR',
          ],
      },
    );

    try {
      await _speech.listen(
        onResult: _onResult,
        listenOptions: options,
      );
    } catch (_) {
      if (!wakeOnly) rethrow;

      // Some Android speech engines do not support on-device recognition.
      // Fall back to a short search session instead of the old 2-minute
      // continuous dictation loop.
      await _speech.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.search,
          onDevice: false,
          cancelOnError: false,
          partialResults: true,
          autoPunctuation: false,
          enableHapticFeedback: false,
          pauseFor: const Duration(seconds: 2),
          listenFor: const Duration(seconds: 8),
          localeId: _localeId,
          contextualPhrases: const [
            'AIMS',
            'AIMS Flow',
            'éjms',
            'éjmsz',
            'aimsz',
            'eims',
            'ems',
          ],
        ),
      );
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    final heard = result.recognizedWords.trim();
    if (heard.isEmpty) return;
    _lastHeard = heard;

    if (_commandMode) {
      _emit(
        AimsVoiceState(
          enabled: _enabled,
          mode: AimsVoiceMode.command,
          message: _assistantGreeting(),
          lastHeard: heard,
        ),
      );
      if (result.finalResult && !_handlingResult) {
        unawaited(_executeCommandText(heard));
      }
      return;
    }

    final normalized = AimsVoiceCommandParser.normalize(heard);
    final wake = _wakeMatch(normalized);
    if (wake == null || _handlingResult) return;

    final suffix = normalized.substring(wake.$2).trim();
    if (suffix.isNotEmpty) {
      unawaited(_executeCommandText(suffix));
    } else {
      unawaited(_enterCommandMode());
    }
  }

  (String, int)? _wakeMatch(String normalized) {
    const aliases = [
      'aims flow',
      'aims',
      'aimsz',
      'aimsz flow',
      'ejms',
      'ejmsz',
      'ejms flow',
      'eims',
      'eimsz',
      'ems',
      'emsz',
      'ems flow',
    ];
    for (final alias in aliases) {
      final index = normalized.indexOf(alias);
      if (index >= 0) {
        return (alias, index + alias.length);
      }
    }
    return null;
  }

  String _assistantGreeting() {
    final name = driverNameProvider().trim();
    if (name.isEmpty) return _locale.t('assistant_empty');
    return _locale.t('assistant_named', vars: {'name': name});
  }

  Future<void> _enterCommandMode() async {
    if (_handlingResult) return;
    _handlingResult = true;
    try {
      await _speech.stop();
      await _speak(_assistantGreeting());
      _commandMode = true;
    } finally {
      _handlingResult = false;
    }
    await _startCommandListening();
  }

  Future<void> _executeCommandText(String text) async {
    if (_handlingResult) return;
    _handlingResult = true;
    _commandMode = false;

    try {
      await _speech.stop();
      final command = _parser.parse(
        text,
        language: _locale.languageCode,
      );
      if (command.intent == AimsVoiceIntent.unknown) {
        await _speak(_locale.t('not_understood'));
      } else {
        final response = await onCommand(command);
        if (response.trim().isNotEmpty) {
          await _speak(response);
        }
      }
    } catch (_) {
      await _speak(_locale.t('command_failed'));
    } finally {
      _handlingResult = false;
    }

    if (_enabled) {
      await _startWakeListening();
    }
  }

  Future<void> _speak(String text) async {
    _speaking = true;
    _emit(
      AimsVoiceState(
        enabled: _enabled,
        mode: AimsVoiceMode.speaking,
        message: text,
        lastHeard: _lastHeard,
      ),
    );
    try {
      await _speech.stop();
      await _tts.stop();
      await _tts.speak(text);
    } finally {
      _speaking = false;
    }
  }

  void _onStatus(String status) {
    final s = status.toLowerCase();
    if (!_enabled || _speaking || _handlingResult) return;
    if (s.contains('done') || s.contains('notlistening')) {
      _restartTimer?.cancel();
      _restartTimer = Timer(
        _commandMode
            ? const Duration(milliseconds: 350)
            : const Duration(milliseconds: 1200),
        () {
        if (!_enabled || _speaking || _handlingResult) return;
        if (_commandMode) {
          unawaited(_startCommandListening());
        } else {
          unawaited(_startWakeListening());
        }
        },
      );
    }
  }

  void _onError(SpeechRecognitionError error) {
    if (!_enabled) return;

    _emit(
      AimsVoiceState(
        enabled: true,
        mode: AimsVoiceMode.error,
        message: error.permanent
            ? _locale.t('speech_permission_error')
            : _locale.t('speech_restarting'),
        lastHeard: _lastHeard,
      ),
    );

    if (!error.permanent) {
      _restartTimer?.cancel();
      _restartTimer = Timer(const Duration(seconds: 1), () {
        if (_enabled && !_speaking && !_handlingResult) {
          unawaited(_startWakeListening());
        }
      });
    }
  }

  Future<void> _applyLanguage() async {
    _localeId = _locale.speechLocale;

    // Prefer Google's Android TTS engine when available; it generally exposes
    // the better quality network/neural voices on modern Android phones.
    try {
      final engines = await _tts.getEngines;
      if (engines is List &&
          engines.map((e) => e.toString()).contains('com.google.android.tts')) {
        await _tts.setEngine('com.google.android.tts');
      }
    } catch (_) {}

    await _tts.setLanguage(_locale.ttsLocale);
    await _selectPreferredVoice();
    await _tts.setSpeechRate(0.46);
    await _tts.setVolume(1.0);
    await _tts.setPitch(_maleVoiceMatched ? 0.92 : 0.78);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<void> _selectPreferredVoice() async {
    _maleVoiceMatched = false;

    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return;

      final wantedLocale = _locale.ttsLocale.toLowerCase().replaceAll('_', '-');
      final wantedLanguage = wantedLocale.split('-').first;

      Map<String, dynamic>? best;
      var bestScore = -100000;

      for (final item in raw) {
        if (item is! Map) continue;
        final voice = Map<String, dynamic>.from(item);
        final name = (voice['name'] ?? '').toString();
        final locale =
            (voice['locale'] ?? '').toString().toLowerCase().replaceAll('_', '-');
        if (name.isEmpty || locale.isEmpty) continue;
        if (!locale.startsWith(wantedLanguage)) continue;

        final haystack = [
          name,
          voice['gender'],
          voice['features'],
        ].where((v) => v != null).join(' ').toLowerCase();

        var score = 0;
        if (locale == wantedLocale) score += 200;
        if (_looksMaleVoice(haystack)) {
          score += 1000;
        }
        if (haystack.contains('neural') ||
            haystack.contains('natural') ||
            haystack.contains('wavenet')) {
          score += 180;
        }
        if ((voice['network_required'] ?? '').toString() == 'true') {
          score += 50;
        }

        final quality =
            int.tryParse((voice['quality'] ?? '').toString()) ?? 0;
        score += quality ~/ 10;

        if (score > bestScore) {
          bestScore = score;
          best = voice;
        }
      }

      if (best == null) return;

      final name = (best['name'] ?? '').toString();
      final locale = (best['locale'] ?? '').toString();
      if (name.isEmpty || locale.isEmpty) return;

      await _tts.setVoice({'name': name, 'locale': locale});

      final voiceText = [
        name,
        best['gender'],
        best['features'],
      ].where((v) => v != null).join(' ').toLowerCase();
      _maleVoiceMatched = _looksMaleVoice(voiceText);
    } catch (_) {
      _maleVoiceMatched = false;
    }
  }

  bool _looksMaleVoice(String text) {
    final value = text.toLowerCase();
    if (value.contains('female') ||
        value.contains('#female') ||
        value.contains('feminine')) {
      return false;
    }
    return value.contains('#male') ||
        value.contains('masculine') ||
        RegExp(r'(^|[^a-z])male([^a-z]|$)').hasMatch(value);
  }

  void _onLanguageChanged() {
    if (!_initialized) return;
    unawaited(_refreshLanguage());
  }

  Future<void> _refreshLanguage() async {
    _restartTimer?.cancel();
    await _speech.cancel();
    await _tts.stop();
    await _applyLanguage();
    if (_enabled && !_speaking && !_handlingResult) {
      await _startWakeListening();
    }
  }

  void _emit(AimsVoiceState value) {
    if (!_states.isClosed) {
      _states.add(value);
    }
  }

  Future<void> dispose() async {
    _enabled = false;
    _restartTimer?.cancel();
    await _assistantInvocationSub?.cancel();
    await _speech.cancel();
    await _tts.stop();
    await AimsHandsFreePlatform.stop();
    _locale.removeListener(_onLanguageChanged);
    await _states.close();
  }
}
