import 'package:flutter/material.dart';

import 'pipeline.dart';
import 'reader_page.dart';
import 'settings.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Pipeline _pipeline = Pipeline();
  final TextEditingController _field = TextEditingController();
  List<Favorite> _favs = [];
  String _last = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final favs = await Settings.favorites();
    final last = await Settings.lastUrl();
    if (!mounted) return;
    setState(() {
      _favs = favs;
      _last = last;
    });
  }

  static String normalize(String input) {
    final s = input.trim();
    if (s.isEmpty) return '';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.contains('.') && !s.contains(' ')) return 'https://$s';
    return 'https://duckduckgo.com/?q=${Uri.encodeQueryComponent(s)}';
  }

  Future<void> _open(String url) async {
    final u = normalize(url);
    if (u.isEmpty) return;
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderPage(url: u, pipeline: _pipeline),
    ));
    _reload();
  }

  Future<void> _editDeepl() async {
    final ctrl = TextEditingController(text: await Settings.deeplKey());
    if (!mounted) return;
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Traduction DeepL (optionnel)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sans clé, l\'appli traduit hors ligne avec le traducteur de Google '
              '(correct, mais moyen sur l\'argot).\n\n'
              'Avec une clé DeepL gratuite (deepl.com → API → compte gratuit), '
              'les traductions sont bien meilleures. Il faut internet.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Clé DeepL',
                hintText: 'xxxxxxxx-xxxx-...:fx',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (res != null) {
      await Settings.setDeeplKey(res);
      _pipeline.translator.deeplKey = res.trim();
    }
  }

  Future<void> _removeFav(Favorite f) async {
    final favs = List<Favorite>.from(_favs)..removeWhere((x) => x.url == f.url);
    await Settings.saveFavorites(favs);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan FR', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Réglages de traduction',
            icon: const Icon(Icons.tune),
            onPressed: _editDeepl,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _field,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onSubmitted: _open,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Adresse du site de scans, ou recherche',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _open(_field.text),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          if (_last.isNotEmpty) ...[
            const SizedBox(height: 20),
            Card(
              color: scheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('Reprendre la lecture'),
                subtitle: Text(_last, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _open(_last),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Favoris', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_favs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Pas encore de favoris. Sur un site, touche l\'étoile en haut pour l\'ajouter ici.',
              ),
            ),
          ..._favs.map((f) => Card(
                child: ListTile(
                  leading: const Icon(Icons.star_rounded),
                  title: Text(f.title.isEmpty ? f.url : f.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(Uri.tryParse(f.url)?.host ?? f.url),
                  onTap: () => _open(f.url),
                  trailing: IconButton(
                    tooltip: 'Retirer',
                    icon: const Icon(Icons.close),
                    onPressed: () => _removeFav(f),
                  ),
                ),
              )),
          const SizedBox(height: 24),
          Text(
            'Pendant la lecture : le bouton de traduction en haut active ou coupe le français. '
            'Touche une bulle pour voir le texte anglais d\'origine.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
