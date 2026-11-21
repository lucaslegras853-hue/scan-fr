import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import 'ocr.dart';
import 'translator.dart';

/// Image -> lecture du texte -> traduction. Garde les résultats en mémoire
/// pour qu'une page déjà vue s'affiche tout de suite.
class Pipeline {
  final MangaOcr _ocr = MangaOcr();
  final Translator translator = Translator();

  final Map<String, Map<String, dynamic>> _cache = {};
  final Map<String, Future<Map<String, dynamic>>> _inflight = {};

  /// Nombre de pages en cours de traduction (affiché dans la barre du haut).
  final ValueNotifier<int> busy = ValueNotifier(0);

  static const _maxParallel = 2;
  int _running = 0;
  final List<Completer<void>> _waiting = [];

  Future<T> _slot<T>(Future<T> Function() job) async {
    while (_running >= _maxParallel) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    _running++;
    try {
      return await job();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  /// Appelé par la page quand elle trouve une planche.
  Future<Map<String, dynamic>> fromUrl(String url, String referer, String ua) {
    final hit = _cache[url];
    if (hit != null) return Future.value(hit);
    return _inflight[url] ??= _track(() async {
      final bytes = await _download(url, referer, ua);
      // Le site refuse qu'on télécharge l'image en dehors de la page :
      // on demande à la page de nous l'envoyer elle-même.
      if (bytes == null) return {'needBytes': true};
      return _slot(() => _analyze(url, bytes));
    }).whenComplete(() => _inflight.remove(url));
  }

  /// Image envoyée directement par la page (en base64).
  Future<Map<String, dynamic>> fromBytes(String url, String b64) {
    final hit = _cache[url];
    if (hit != null) return Future.value(hit);
    return _track(() => _slot(() => _analyze(url, base64Decode(b64))));
  }

  Future<Map<String, dynamic>> _track(Future<Map<String, dynamic>> Function() f) async {
    busy.value++;
    try {
      return await f();
    } catch (e) {
      return {'error': e.toString()};
    } finally {
      busy.value--;
    }
  }

  Future<Uint8List?> _download(String url, String referer, String ua) async {
    if (url.startsWith('data:')) {
      try {
        return UriData.parse(url).contentAsBytes();
      } catch (_) {
        return null;
      }
    }
    if (!url.startsWith('http')) return null; // blob: et autres -> la page s'en charge
    try {
      final cookies = await CookieManager.instance().getCookies(url: WebUri(url));
      final headers = <String, String>{
        'Referer': referer,
        'User-Agent': ua,
        'Accept': 'image/avif,image/webp,image/png,image/jpeg,image/*,*/*;q=0.8',
      };
      if (cookies.isNotEmpty) {
        headers['Cookie'] = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      }
      final resp = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 20));
      final type = resp.headers['content-type'] ?? '';
      if (resp.statusCode == 200 &&
          resp.bodyBytes.length > 1000 &&
          !type.contains('text/html')) {
        return resp.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> _analyze(String url, Uint8List bytes) async {
    final page = await _ocr.scan(bytes);
    if (page.bubbles.isNotEmpty) {
      final fr = await translator.translateAll(page.bubbles.map((b) => b.en).toList());
      for (var i = 0; i < fr.length; i++) {
        page.bubbles[i].fr = fr[i];
      }
    }
    final result = {
      'w': page.width,
      'h': page.height,
      'bubbles': page.bubbles.map((b) => b.toJson()).toList(),
    };
    _cache[url] = result;
    return result;
  }
}
