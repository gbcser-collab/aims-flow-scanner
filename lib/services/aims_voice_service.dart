import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'aims_hands_free_platform.dart';
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
  });

  final AimsVoiceCommandHandler onCommand;
  final String Function() driverNameProvider;
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AimsVoiceCommandParser _parser = const AimsVoiceCommandParser();
  final StreamController<AimsVoiceState> _states =
      StreamController<AimsVoiceState>.broadcast();

  StreamSubscription<void>? _assistantInvocationSub;
  Timer? _restartTimer;

  bool _initialized = false;
  bool _enabled = false;
  bool _commandMode = false;
  bool _speaking = false;
  bool _handlingResult = false;
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
        const AimsVoiceState(
          enabled: false,
          mode: AimsVoiceMode.error,
          message: 'A beszédfelismerés nem érhető el ezen a telefonon.',
        ),
      );
      return false;
    }

    try {
      final locales = await _speech.locales();
      for (final locale in locales) {
        final id = locale.localeId.toLowerCase();
        if (id.startsWith('hu')) {
          _localeId = locale.localeId;
          break;
        }
      }
    } catch (_) {
      _localeId = 'hu_HU';
    }

    await _tts.setLanguage('hu-HU');
    await _tts.setSpeechRate(0.47);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);

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
      const AimsVoiceState(
        enabled: false,
        mode: AimsVoiceMode.off,
        message: 'AIMS Hands-Free kikapcsolva.',
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
      message: 'Figyelek. Mondd: AIMS.',
    );
  }

  Future<void> _startCommandListening() async {
    if (!_enabled || _speaking || _handlingResult) return;
    _commandMode = true;
    await _startListening(
      mode: AimsVoiceMode.command,
      message: _assistantGreeting(),
    );
  }

  Future<void> _startListening({
    required AimsVoiceMode mode,
    required String message,
  }) async {
    if (_speech.isListening) return;

    _emit(
      AimsVoiceState(
        enabled: _enabled,
        mode: mode,
        message: message,
        lastHeard: _lastHeard,
      ),
    );

    await _speech.listen(
      onResult: _onResult,
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        onDevice: false,
        cancelOnError: false,
        partialResults: true,
        autoPunctuation: false,
        enableHapticFeedback: false,
        pauseFor: const Duration(seconds: 8),
        listenFor: const Duration(minutes: 2),
        localeId: _localeId,
        contextualPhrases: const [
          'AIMS',
          'felrakó',
          'lerakó',
          'fuvar',
          'navigáció',
          'kapcsolattartó',
          'CMR',
        ],
      ),
    );
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
    const aliases = ['aims flow', 'aims', 'ejms', 'eims', 'ems'];
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
    if (name.isEmpty) return 'Tessék. Miben segíthetek?';
    return 'Tessék, $name. Miben segíthetek?';
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
      final command = _parser.parse(text);
      if (command.intent == AimsVoiceIntent.unknown) {
        await _speak('Ezt nem értettem. Mondd újra az AIMS után.');
      } else {
        final response = await onCommand(command);
        if (response.trim().isNotEmpty) {
          await _speak(response);
        }
      }
    } catch (_) {
      await _speak('A parancs végrehajtása nem sikerült.');
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
      _restartTimer = Timer(const Duration(milliseconds: 450), () {
        if (!_enabled || _speaking || _handlingResult) return;
        if (_commandMode) {
          unawaited(_startCommandListening());
        } else {
          unawaited(_startWakeListening());
        }
      });
    }
  }

  void _onError(SpeechRecognitionError error) {
    if (!_enabled) return;

    _emit(
      AimsVoiceState(
        enabled: true,
        mode: AimsVoiceMode.error,
        message: error.permanent
            ? 'A mikrofon vagy beszédfelismerés engedélye hiányzik.'
            : 'A hangfigyelés újraindul.',
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
    await _states.close();
  }
}
