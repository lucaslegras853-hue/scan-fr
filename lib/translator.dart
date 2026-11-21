import 'dart:convert';

import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:http/http.dart' as http;

/// Traduit de l'anglais vers le français.
/// - Avec une clé DeepL (gratuite) : meilleure qualité, besoin d'internet.
/// - Sinon : traduction Google intégrée au téléphone, hors ligne.
class Translator {
  String deeplKey = '';
  OnDeviceTranslator? _onDevice;
  Future<void>? _modelReady;
  final Map<String, String> _cache = {};

  Future<bool> isOfflineModelReady() async {
    final mgr = OnDeviceTranslatorModelManager();
    return await mgr.isModelDownloaded(TranslateLanguage.french.bcpCode) &&
        await mgr.isModelDownloaded(TranslateLanguage.english.bcpCode);
  }

  /// Télécharge le modèle hors ligne (environ 30 Mo, une seule fois).
  Future<void> prepareOffline() => _modelReady ??= _prepare();

  Future<void> _prepare() async {
    final mgr = OnDeviceTranslatorModelManager();
    for (final lang in [TranslateLanguage.english, TranslateLanguage.french]) {
      if (!await mgr.isModelDownloaded(lang.bcpCode)) {
        await mgr.downloadModel(lang.bcpCode, isWifiRequired: false);
      }
    }
    _onDevice = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: TranslateLanguage.french,
    );
  }

  Future<List<String>> translateAll(List<String> texts) async {
    final out = List<String?>.filled(texts.length, null);
    final todo = <int>[];
    for (var i = 0; i < texts.length; i++) {
      final hit = _cache[texts[i]];
      if (hit != null) {
        out[i] = hit;
      } else {
        todo.add(i);
      }
    }

    if (todo.isNotEmpty && deeplKey.isNotEmpty) {
      try {
        final res = await _deepl(todo.map((i) => texts[i]).toList());
        for (var k = 0; k < todo.length; k++) {
          out[todo[k]] = res[k];
        }
        todo.clear();
      } catch (_) {
        // DeepL indisponible (pas de réseau, quota atteint...) : on passe au hors ligne.
      }
    }

    if (todo.isNotEmpty) {
      await prepareOffline();
      for (final i in todo) {
        try {
          out[i] = await _onDevice!.translateText(texts[i]);
        } catch (_) {
          out[i] = texts[i];
        }
      }
    }

    for (var i = 0; i < texts.length; i++) {
      _cache[texts[i]] = out[i]!;
    }
    return out.cast<String>();
  }

  Future<List<String>> _deepl(List<String> texts) async {
    final host = deeplKey.endsWith(':fx') ? 'api-free.deepl.com' : 'api.deepl.com';
    final resp = await http
        .post(
          Uri.https(host, '/v2/translate'),
          headers: {
            'Authorization': 'DeepL-Auth-Key $deeplKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'text': texts,
            'source_lang': 'EN',
            'target_lang': 'FR',
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('DeepL ${resp.statusCode}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final list = (data['translations'] as List)
        .map((t) => (t as Map<String, dynamic>)['text'] as String)
        .toList();
    if (list.length != texts.length) throw Exception('DeepL: réponse incomplète');
    return list;
  }
}
