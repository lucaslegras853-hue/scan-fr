import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Régies de pub et de pop-ups les plus courantes sur les sites de scans.
const List<String> adDomains = [
  'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
  'adservice.google.com', 'google-analytics.com', 'googletagmanager.com',
  'amazon-adsystem.com', 'adnxs.com', 'criteo.com', 'criteo.net', 'pubmatic.com',
  'rubiconproject.com', 'openx.net', 'taboola.com', 'outbrain.com', 'mgid.com',
  'popads.net', 'popcash.net', 'propellerads.com', 'propellerclick.com',
  'adsterra.com', 'adsterratools.com', 'highperformanceformat.com',
  'profitablegatecpm.com', 'effectivegatecpm.com', 'exoclick.com', 'exosrv.com',
  'juicyads.com', 'trafficjunky.net', 'trafficstars.com', 'onclickads.net',
  'onclickalgo.com', 'hilltopads.net', 'a-ads.com', 'adcash.com', 'monetag.com',
  'clickadu.com', 'galaksion.com', 'richpush.co', 'pushame.com', 'realsrv.com',
  'magsrv.com', 'tsyndicate.com', 'yandex.ru/ads', 'mc.yandex.ru', 'yieldmo.com',
  'adform.net', 'smartadserver.com', 'zedo.com', 'bidvertiser.com',
  'revcontent.com', 'disqusads.com', 'ad-maven.com', 'admaven.com',
  'dtscout.com', 'dtscdn.com', 'cloudfront.net/ads', 'acscdn.com', 'aclib.net',
  'ak.sail-horizon.com', 'whos.amung.us', 'histats.com', 'statcounter.com',
];

String _escape(String s) => s.replaceAllMapped(RegExp(r'[.\\/+*?^$()\[\]{}|-]'), (m) => '\\${m[0]}');

List<ContentBlocker> buildAdBlockers() {
  return adDomains
      .map((d) => ContentBlocker(
            trigger: ContentBlockerTrigger(
              urlFilter: '^https?://([^/]*\\.)?${_escape(d)}([/?:].*)?\$',
            ),
            action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
          ))
      .toList();
}

/// "chapitre.monsite.com" -> "monsite.com"
String baseDomain(String host) {
  final parts = host.toLowerCase().split('.');
  if (parts.length <= 2) return host.toLowerCase();
  return parts.sublist(parts.length - 2).join('.');
}
