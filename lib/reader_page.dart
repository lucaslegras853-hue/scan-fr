import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'adblock.dart';
import 'pipeline.dart';
import 'settings.dart';

class ReaderPage extends StatefulWidget {
  final String url;
  final Pipeline pipeline;
  const ReaderPage({super.key, required this.url, required this.pipeline});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  static const _searchSites = {'duckduckgo.com', 'google.com', 'google.fr', 'bing.com'};

  InAppWebViewController? _c;
  String? _js;
  late String _url;
  late String _allowedBase;
  String _title = '';
  bool _translate = true;
  double _progress = 0;
  bool _isFav = false;

  @override
  void initState() {
    super.initState();
    _url = widget.url;
    _allowedBase = baseDomain(Uri.parse(_url).host);
    rootBundle.loadString('assets/overlay.js').then((js) {
      if (mounted) setState(() => _js = js);
    });
    _prepareTranslator();
    _refreshFav();
    widget.pipeline.onResult = (url, result) {
      _c?.evaluateJavascript(
          source: 'window.__sft && window.__sft.deliver && '
              'window.__sft.deliver(${jsonEncode(url)}, ${jsonEncode(result)});');
    };
  }

  @override
  void dispose() {
    widget.pipeline.onResult = null;
    super.dispose();
  }

  Future<void> _prepareTranslator() async {
    final tr = widget.pipeline.translator;
    tr.deeplKey = await Settings.deeplKey();
    if (tr.deeplKey.isNotEmpty) return;
    if (await tr.isOfflineModelReady()) {
      tr.prepareOffline();
      return;
    }
    _toast('Téléchargement du traducteur (une seule fois, environ 30 Mo)…');
    try {
      await tr.prepareOffline();
      _toast('Traducteur prêt !');
    } catch (_) {
      _toast('Impossible de télécharger le traducteur. Vérifie ta connexion.');
    }
  }

  void _toast(String msg, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  Future<void> _refreshFav() async {
    final favs = await Settings.favorites();
    if (mounted) setState(() => _isFav = favs.any((f) => f.url == _url));
  }

  Future<void> _toggleFav() async {
    final favs = await Settings.favorites();
    if (favs.any((f) => f.url == _url)) {
      favs.removeWhere((f) => f.url == _url);
      _toast('Retiré des favoris');
    } else {
      favs.insert(0, Favorite(_title, _url));
      _toast('Ajouté aux favoris');
    }
    await Settings.saveFavorites(favs);
    _refreshFav();
  }

  Future<void> _setTranslate(bool on) async {
    setState(() => _translate = on);
    await _c?.evaluateJavascript(
        source: 'window.__sft && window.__sft.setEnabled && window.__sft.setEnabled($on);');
  }

  dynamic _firstArg(dynamic data) {
    if (data is List) return data.isEmpty ? null : data.first;
    try {
      final List a = (data as dynamic).args as List;
      return a.isEmpty ? null : a.first;
    } catch (_) {
      return null;
    }
  }

  void _load(String url) {
    _allowedBase = baseDomain(Uri.parse(url).host);
    _c?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _editUrl() async {
    final ctrl = TextEditingController(text: _url);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aller à'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Ouvrir')),
        ],
      ),
    );
    if (res == null || res.trim().isEmpty) return;
    var u = res.trim();
    if (!u.startsWith('http')) {
      u = u.contains('.') && !u.contains(' ')
          ? 'https://$u'
          : 'https://duckduckgo.com/?q=${Uri.encodeQueryComponent(u)}';
    }
    _load(u);
  }

  /// Anti-pub : on reste sur le site de scans. Les redirections automatiques
  /// vers d'autres sites (souvent des pubs) sont bloquées en silence.
  Future<NavigationActionPolicy> _onNavigate(
      InAppWebViewController c, NavigationAction action) async {
    final uri = action.request.url;
    if (uri == null) return NavigationActionPolicy.ALLOW;
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return NavigationActionPolicy.CANCEL; // intent://, market://… = pubs
    }
    if (!action.isForMainFrame) return NavigationActionPolicy.ALLOW;
    final base = baseDomain(uri.host);
    if (base == _allowedBase) return NavigationActionPolicy.ALLOW;

    final gesture = action.hasGesture == true;
    if (gesture && _searchSites.contains(_allowedBase)) {
      _allowedBase = base; // clic sur un résultat de recherche
      return NavigationActionPolicy.ALLOW;
    }
    if (gesture) {
      _toast(
        'Lien vers un autre site bloqué (${uri.host})',
        action: SnackBarAction(label: 'Ouvrir quand même', onPressed: () => _load(uri.toString())),
      );
    }
    return NavigationActionPolicy.CANCEL;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (_c != null && await _c!.canGoBack()) {
          _c!.goBack();
        } else {
          nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: InkWell(
            onTap: _editUrl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title.isEmpty ? 'Chargement…' : _title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16)),
                Text(Uri.tryParse(_url)?.host ?? '',
                    maxLines: 1,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          actions: [
            ValueListenableBuilder<int>(
              valueListenable: widget.pipeline.busy,
              builder: (_, n, __) => n == 0
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(children: [
                        const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 6),
                        Text('$n', style: const TextStyle(fontSize: 13)),
                      ]),
                    ),
            ),
            IconButton(
              tooltip: _translate ? 'Couper la traduction' : 'Activer la traduction',
              isSelected: _translate,
              icon: const Icon(Icons.translate),
              selectedIcon: Icon(Icons.translate, color: scheme.primary),
              onPressed: () => _setTranslate(!_translate),
            ),
            IconButton(
              tooltip: 'Favori',
              icon: Icon(_isFav ? Icons.star_rounded : Icons.star_border_rounded),
              onPressed: _toggleFav,
            ),
          ],
          bottom: _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: _progress, minHeight: 2),
                )
              : null,
        ),
        body: _js == null
            ? const Center(child: CircularProgressIndicator())
            : InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                initialUserScripts: UnmodifiableListView([
                  UserScript(source: _js!, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END),
                ]),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  useShouldOverrideUrlLoading: true,
                  supportMultipleWindows: true,
                  javaScriptCanOpenWindowsAutomatically: false,
                  mediaPlaybackRequiresUserGesture: true,
                  thirdPartyCookiesEnabled: true,
                  contentBlockers: buildAdBlockers(),
                ),
                onWebViewCreated: (c) {
                  _c = c;
                  c.addJavaScriptHandler(
                    handlerName: 'sftImage',
                    callback: (data) async {
                      final m = Map<String, dynamic>.from(_firstArg(data) as Map);
                      return widget.pipeline.fromUrl(
                        m['url'] as String,
                        (m['referer'] as String?) ?? '',
                        (m['ua'] as String?) ?? '',
                      );
                    },
                  );
                  c.addJavaScriptHandler(
                    handlerName: 'sftBytes',
                    callback: (data) async {
                      final m = Map<String, dynamic>.from(_firstArg(data) as Map);
                      return widget.pipeline.fromBytes(m['url'] as String, m['data'] as String);
                    },
                  );
                },
                shouldOverrideUrlLoading: _onNavigate,
                // Pop-ups et nouveaux onglets : bloqués. Un vrai lien du même site
                // qui voulait s'ouvrir dans un nouvel onglet s'ouvre ici à la place.
                onCreateWindow: (c, action) async {
                  final u = action.request.url;
                  if (u != null &&
                      action.hasGesture == true &&
                      baseDomain(u.host) == _allowedBase) {
                    c.loadUrl(urlRequest: URLRequest(url: u));
                  }
                  return false;
                },
                onProgressChanged: (c, p) => setState(() => _progress = p / 100),
                onTitleChanged: (c, t) => setState(() => _title = t ?? ''),
                onUpdateVisitedHistory: (c, url, _) {
                  if (url == null) return;
                  setState(() => _url = url.toString());
                  _refreshFav();
                },
                onLoadStop: (c, url) async {
                  if (url != null) {
                    _url = url.toString();
                    Settings.setLastUrl(_url);
                  }
                  await c.evaluateJavascript(
                      source: 'window.__sft && window.__sft.setEnabled && '
                          'window.__sft.setEnabled($_translate);');
                },
              ),
      ),
    );
  }
}
