import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'aims_locale.dart';

/// Output-only voice layer for AIMS Flow.
///
/// This service never opens the microphone, never performs speech recognition,
/// never listens for a wake word, and never executes spoken commands.
/// It only reads operational information aloud to the driver.
class AimsVoiceAnnouncerService {
  AimsVoiceAnnouncerService() {
    _locale.addListener(_onLanguageChanged);
  }

  final FlutterTts _tts = FlutterTts();
  final AimsLocaleController _locale = AimsLocaleController.instance;

  bool _initialized = false;
  bool _speaking = false;
  String _lastAnnouncement = '';
  DateTime? _lastAnnouncementAt;

  Future<bool> initialize() async {
    if (_initialized) return true;
    try {
      await _applyLanguage();
      _initialized = true;
      return true;
    } catch (_) {
      _initialized = false;
      return false;
    }
  }

  /// Reads an operational message aloud.
  ///
  /// Duplicate events are suppressed briefly because the same push/runtime
  /// event can arrive through more than one recovery path.
  Future<void> announce(String text) async {
    final value = text.trim();
    if (value.isEmpty) return;

    final now = DateTime.now();
    if (_lastAnnouncement == value &&
        _lastAnnouncementAt != null &&
        now.difference(_lastAnnouncementAt!) < const Duration(seconds: 12)) {
      return;
    }
    _lastAnnouncement = value;
    _lastAnnouncementAt = now;

    final ok = await initialize();
    if (!ok) return;
    await _speak(value);
  }

  Future<void> _speak(String text) async {
    if (_speaking) {
      await _tts.stop();
    }
    _speaking = true;
    try {
      final result = await _tts.speak(text);
      if (result != 1) {
        return;
      }
    } finally {
      _speaking = false;
    }
  }

  Future<void> _applyLanguage() async {
    // Prefer Google's Android TTS engine when available because it usually
    // exposes the best network/neural voices on current Android devices.
    try {
      final engines = await _tts.getEngines;
      if (engines is List &&
          engines.map((e) => e.toString()).contains('com.google.android.tts')) {
        await _tts.setEngine('com.google.android.tts');
      }
    } catch (_) {}

    await _tts.setLanguage(_locale.ttsLocale);
    await _selectPreferredVoice();
    await _tts.setSpeechRate(0.50);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<void> _selectPreferredVoice() async {
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
        if (locale == wantedLocale) score += 500;
        if (haystack.contains('neural') ||
            haystack.contains('natural') ||
            haystack.contains('wavenet')) {
          score += 1400;
        }
        if (haystack.contains('network')) score += 900;
        if ((voice['network_required'] ?? '').toString() == 'true') {
          score += 700;
        }
        if (_looksMaleVoice(haystack)) score += 250;

        final quality =
            int.tryParse((voice['quality'] ?? '').toString()) ?? 0;
        score += quality;

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
    } catch (_) {
      return;
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
    await _tts.stop();
    await _applyLanguage();
  }

  Future<void> dispose() async {
    await _tts.stop();
    _locale.removeListener(_onLanguageChanged);
  }
}
