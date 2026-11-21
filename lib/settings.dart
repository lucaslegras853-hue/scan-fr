import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class Favorite {
  final String title;
  final String url;
  const Favorite(this.title, this.url);

  Map<String, String> toJson() => {'title': title, 'url': url};
  static Favorite fromJson(Map<String, dynamic> j) =>
      Favorite(j['title'] as String? ?? '', j['url'] as String? ?? '');
}

/// Réglages simples gardés sur le téléphone.
class Settings {
  static const _kFavs = 'favs';
  static const _kDeepl = 'deepl_key';
  static const _kLast = 'last_url';

  static Future<List<Favorite>> favorites() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kFavs);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Favorite.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveFavorites(List<Favorite> favs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kFavs, jsonEncode(favs.map((f) => f.toJson()).toList()));
  }

  static Future<String> deeplKey() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kDeepl) ?? '';
  }

  static Future<void> setDeeplKey(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDeepl, key.trim());
  }

  static Future<String> lastUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLast) ?? '';
  }

  static Future<void> setLastUrl(String url) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLast, url);
  }
}
