import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class VerificationPhotoResult {
  final Uint8List bytes;
  final String fileName;

  const VerificationPhotoResult({required this.bytes, required this.fileName});
}

class VerificationPhotoService {
  static const _maxWidth = 1600.0;
  static const _quality = 85;

  /// 카메라/갤러리에서 사진을 받아 우측하단에 KST 시각 워터마크를 새긴다.
  static Future<VerificationPhotoResult?> capture({
    required ImageSource source,
  }) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: _quality,
      maxWidth: _maxWidth,
    );
    if (picked == null) return null;

    final raw = await picked.readAsBytes();

    DateTime? captureTime;
    if (source == ImageSource.gallery) {
      captureTime = await _readExifDateTime(raw);
    }
    captureTime ??= DateTime.now();
    final kstLabel = _formatKst(captureTime);

    final processed = _drawTimestamp(raw, kstLabel) ?? raw;
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${picked.name.split('/').last}';
    return VerificationPhotoResult(
      bytes: processed,
      fileName: fileName.endsWith('.jpg') || fileName.endsWith('.jpeg')
          ? fileName
          : '$fileName.jpg',
    );
  }

  static Future<DateTime?> _readExifDateTime(Uint8List bytes) async {
    try {
      final tags = await readExifFromBytes(bytes);
      if (tags.isEmpty) return null;
      final raw = tags['EXIF DateTimeOriginal']?.printable ??
          tags['Image DateTime']?.printable;
      if (raw == null || raw.trim().isEmpty) return null;
      // 예: "2024:12:31 14:30:45"
      final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2})\s+(\d{2}):(\d{2}):(\d{2})')
          .firstMatch(raw.trim());
      if (m == null) return null;
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
        int.parse(m.group(6)!),
      );
    } catch (_) {
      return null;
    }
  }

  static String _formatKst(DateTime time) {
    // EXIF/카메라 모두 기기 로컬 시간이 들어옴. 한국 사용자는 거의 KST(UTC+9)이므로
    // UTC 변환 후 +9 시간을 더해 명시적인 KST 라벨로 통일한다.
    final kst = time.toUtc().add(const Duration(hours: 9));
    return '${DateFormat('yyyy.MM.dd HH:mm').format(kst)} KST';
  }

  static Uint8List? _drawTimestamp(Uint8List bytes, String label) {
    try {
      return _drawTimestampInternal(bytes, label);
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _drawTimestampInternal(Uint8List bytes, String label) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final image = img.bakeOrientation(decoded);

    final font = image.width >= 1400
        ? img.arial48
        : image.width >= 700
            ? img.arial24
            : img.arial14;
    final pad = font == img.arial48 ? 12 : 8;
    final margin = font == img.arial48 ? 28 : 16;

    // 실제 폰트 메트릭으로 정확한 박스 크기 계산
    var textWidth = 0;
    for (final char in label.split('')) {
      textWidth += font.characterXAdvance(char);
    }
    final lineHeight = font.lineHeight > 0
        ? font.lineHeight
        : font == img.arial48
            ? 48
            : font == img.arial24
                ? 24
                : 14;

    final boxRight = image.width - margin;
    final boxBottom = image.height - margin;
    final boxX = boxRight - textWidth - pad * 2;
    final boxY = boxBottom - lineHeight - pad * 2;

    img.fillRect(
      image,
      x1: boxX,
      y1: boxY,
      x2: boxRight,
      y2: boxBottom,
      color: img.ColorRgba8(0, 0, 0, 170),
    );
    img.drawString(
      image,
      label,
      font: font,
      x: boxX + pad,
      y: boxY + pad,
      color: img.ColorRgb8(255, 255, 255),
    );

    return Uint8List.fromList(img.encodeJpg(image, quality: 88));
  }
}
