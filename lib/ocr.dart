import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// Une zone de texte trouvée sur une planche (coordonnées en pixels de l'image).
class Bubble {
  final double x, y, w, h;
  final String en;
  String fr = '';
  Bubble(this.x, this.y, this.w, this.h, this.en);

  Map<String, dynamic> toJson() =>
      {'x': x, 'y': y, 'w': w, 'h': h, 'en': en, 'fr': fr};
}

class PageScan {
  final int width, height;
  final List<Bubble> bubbles;
  PageScan(this.width, this.height, this.bubbles);
}

/// Lit le texte des planches avec la reconnaissance de texte de Google (hors ligne).
/// Les images très hautes (webtoons) sont découpées en morceaux, sinon le texte
/// devient trop petit pour être lu.
class MangaOcr {
  final TextRecognizer _rec = TextRecognizer(script: TextRecognitionScript.latin);
  int _n = 0;

  Future<PageScan> scan(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final img = frame.image;
    final w = img.width, h = img.height;
    try {
      if (w < 300 || h < 300) return PageScan(w, h, []);

      final int tileH = (w * 1.6).round().clamp(600, 4000).toInt();
      final overlap = (tileH * 0.2).round();
      final step = tileH - overlap;
      final dir = await getTemporaryDirectory();
      final bubbles = <Bubble>[];

      for (var top = 0; top < h; top += step) {
        final bottom = (top + tileH) > h ? h : top + tileH;
        final first = top == 0;
        final last = bottom >= h;
        final png = await _crop(img, top, bottom - top);
        final f = File('${dir.path}/scanfr_${_n++}.png');
        await f.writeAsBytes(png, flush: true);
        try {
          final res = await _rec.processImage(InputImage.fromFilePath(f.path));
          // Dans la zone qui se chevauche, on ne garde chaque bulle qu'une fois.
          final keepFrom = first ? double.negativeInfinity : top + overlap / 2;
          final keepTo = last ? double.infinity : bottom - overlap / 2;
          for (final b in res.blocks) {
            final r = b.boundingBox;
            final cy = top + r.center.dy;
            if (cy < keepFrom || cy >= keepTo) continue;
            final text = cleanText(b.lines.map((l) => l.text).toList());
            if (text == null) continue;
            final lineH = b.lines.isEmpty ? r.height : r.height / b.lines.length;
            final double pad = (lineH * 0.35).clamp(3.0, 30.0).toDouble();
            final double x0 = (r.left - pad).clamp(0.0, w.toDouble()).toDouble();
            final double x1 = (r.right + pad).clamp(0.0, w.toDouble()).toDouble();
            final double y0 = (top + r.top - pad).clamp(0.0, h.toDouble()).toDouble();
            final double y1 = (top + r.bottom + pad).clamp(0.0, h.toDouble()).toDouble();
            bubbles.add(Bubble(x0, y0, x1 - x0, y1 - y0, text));
          }
        } finally {
          if (await f.exists()) await f.delete();
        }
        if (last) break;
      }
      return PageScan(w, h, bubbles);
    } finally {
      img.dispose();
    }
  }

  Future<Uint8List> _crop(ui.Image img, int top, int height) async {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    final wd = img.width.toDouble();
    canvas.drawImageRect(
      img,
      ui.Rect.fromLTWH(0, top.toDouble(), wd, height.toDouble()),
      ui.Rect.fromLTWH(0, 0, wd, height.toDouble()),
      ui.Paint(),
    );
    final pic = rec.endRecording();
    final out = await pic.toImage(img.width, height);
    pic.dispose();
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    return data!.buffer.asUint8List();
  }

  static final _watermark = RegExp(r'(www\.|https?://|\.com\b|\.net\b|\.org\b|discord\.gg)',
      caseSensitive: false);
  static final _letter = RegExp(r'[A-Za-z]');
  static final _upper = RegExp(r'[A-Z]');

  /// Recolle les lignes d'une bulle, enlève les déchets et remet en minuscules
  /// le texte écrit EN MAJUSCULES (la traduction marche bien mieux comme ça).
  static String? cleanText(List<String> lines) {
    var s = '';
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (s.endsWith('-') && line.isNotEmpty && _letter.hasMatch(line[0])) {
        s = s.substring(0, s.length - 1) + line;
      } else {
        s = s.isEmpty ? line : '$s $line';
      }
    }
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final letters = _letter.allMatches(s).length;
    if (letters < 2) return null;
    if (letters / s.replaceAll(' ', '').length < 0.5) return null;
    if (_watermark.hasMatch(s)) return null;

    final uppers = _upper.allMatches(s).length;
    if (uppers / letters > 0.7) {
      s = s.toLowerCase();
      s = s.replaceAllMapped(RegExp(r"(^|[.!?…]\s+|^[^a-z]*)([a-z])"),
          (m) => '${m[1]}${m[2]!.toUpperCase()}');
      s = s.replaceAllMapped(RegExp(r"\bi\b"), (_) => 'I');
    }
    return s;
  }
}
