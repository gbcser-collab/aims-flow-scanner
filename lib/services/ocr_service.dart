import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  OcrService() : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  Future<String> recognize(String imagePath) async {
    final image = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(image);
    return result.text;
  }

  /// OCR is intentionally run on both the perspective-corrected document and
  /// the untouched high-resolution camera photo. A bad corner estimate or an
  /// aggressive crop must never be allowed to destroy otherwise readable
  /// printed CMR text.
  Future<String> recognizeBest({
    required String processedImagePath,
    String? originalImagePath,
  }) async {
    final candidates = <String>[];

    Future<void> add(String? path) async {
      if (path == null || path.trim().isEmpty) return;
      try {
        final value = await recognize(path);
        if (value.trim().isNotEmpty) candidates.add(value);
      } catch (_) {
        // One OCR pass may fail on a device/image while the other still works.
      }
    }

    await add(processedImagePath);
    if (originalImagePath != null &&
        originalImagePath.trim().isNotEmpty &&
        originalImagePath != processedImagePath) {
      await add(originalImagePath);
    }

    if (candidates.isEmpty) return '';
    candidates.sort((a, b) => _score(b).compareTo(_score(a)));
    return candidates.first;
  }

  int _score(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return 0;

    final compact = text.replaceAll(RegExp(r'\s+'), '');
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .length;
    final alnum = RegExp(r'[A-Za-zÀ-ž0-9]').allMatches(text).length;

    var score = compact.length + lines * 14 + alnum ~/ 3;
    final lower = text.toLowerCase();

    const cmrHints = <String>[
      'cmr',
      'sender',
      'consignee',
      'place of delivery',
      'place of taking over',
      'gross weight',
      'feladó',
      'címzett',
      'lerakó',
      'felrakó',
      'absender',
      'empfänger',
      'nadawca',
      'odbiorca',
      'expéditeur',
      'destinataire',
    ];
    for (final hint in cmrHints) {
      if (lower.contains(hint)) score += 140;
    }

    final numberedFields = RegExp(
      r'(^|\n)\s*(?:1|2|3|4|7|9|11|16|21|22|23|24)\s*[.)\-:]?',
      multiLine: true,
    ).allMatches(text).length;
    score += numberedFields * 80;

    return score;
  }

  Future<void> dispose() => _recognizer.close();
}
