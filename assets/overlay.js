// Scan FR : repère les planches du manga, demande leur traduction à l'appli
// et pose le texte français par-dessus les bulles. La couche laisse passer le
// toucher, donc on peut scroller normalement.
(function () {
  if (window.__sft) return;
  window.__sft = { enabled: true };

  var MIN = 300;      // taille mini (px) pour qu'une image soit une planche
  var AHEAD = 3;      // on traduit jusqu'à 3 écrans en avance
  var layers = new Map();

  var css =
    '.sft-layer{position:absolute!important;pointer-events:none!important;z-index:2147483000;overflow:hidden;margin:0!important;padding:0!important;border:0!important}' +
    '.sft-b{position:absolute;pointer-events:auto;box-sizing:border-box;display:flex;align-items:center;justify-content:center;' +
    'text-align:center;background:#fff;color:#111;border-radius:8px;padding:1px 2px;overflow:hidden;' +
    'font-family:"Comic Neue","Comic Sans MS","Segoe Print",sans-serif;font-weight:700;line-height:1.08;' +
    'overflow-wrap:break-word;hyphens:auto;-webkit-hyphens:auto;box-shadow:0 0 0 1px rgba(0,0,0,.08)}' +
    '.sft-b.sft-en{background:#fff4c2}' +
    'html.sft-off .sft-layer{display:none!important}' +
    // Emplacements de pub classiques
    'ins.adsbygoogle,[id^="div-gpt-ad"],[id^="google_ads"],iframe[src*="ads."],iframe[src*="/ads/"],' +
    'iframe[id^="aswift"],[class*="adsbox"],[id*="popunder"],[class*="popunder"]{display:none!important}';

  var st = document.createElement('style');
  st.textContent = css;
  (document.head || document.documentElement).appendChild(st);

  function attr(img, n) { return img.getAttribute(n) || ''; }

  function realUrl(img) {
    var lazy = attr(img, 'data-src') || attr(img, 'data-lazy-src') ||
      attr(img, 'data-original') || attr(img, 'data-url');
    var cur = img.currentSrc || img.src || '';
    if (img.complete && img.naturalWidth >= MIN) return cur;
    return lazy || cur;
  }

  function abs(u) { try { return new URL(u, location.href).href; } catch (e) { return ''; } }

  function looksLikePage(img) {
    if (img.complete && img.naturalWidth) {
      if (img.naturalWidth >= MIN && img.naturalHeight >= MIN) return true;
    }
    // Image pas encore chargée (chargement paresseux) mais déjà grande dans la page
    return img.offsetWidth >= 250 && !!(attr(img, 'data-src') || attr(img, 'data-lazy-src') ||
      attr(img, 'data-original') || attr(img, 'data-url'));
  }

  function ready() {
    return window.flutter_inappwebview && window.flutter_inappwebview.callHandler;
  }

  function fetchB64(u) {
    return fetch(u, { credentials: 'include' })
      .then(function (r) { return r.ok ? r.blob() : null; })
      .then(function (b) {
        if (!b) return null;
        return new Promise(function (res) {
          var fr = new FileReader();
          fr.onload = function () { res(String(fr.result).split(',')[1] || null); };
          fr.onerror = function () { res(null); };
          fr.readAsDataURL(b);
        });
      })
      .catch(function () { return null; });
  }

  function clearImg(img) {
    var l = layers.get(img);
    if (l) l.remove();
    layers.delete(img);
    delete img.dataset.sft;
  }

  function process(img, u) {
    img.dataset.sft = u;
    var h = window.flutter_inappwebview;
    h.callHandler('sftImage', { url: u, referer: location.href, ua: navigator.userAgent })
      .then(function (res) {
        if (res && res.needBytes) {
          return fetchB64(u).then(function (b64) {
            return b64 ? h.callHandler('sftBytes', { url: u, data: b64 }) : null;
          });
        }
        return res;
      })
      .then(function (res) {
        if (img.dataset.sft !== u) return;      // l'image a changé entre temps
        if (res && res.bubbles && res.bubbles.length) render(img, res);
      })
      .catch(function () {});
  }

  function fit(box) {
    var fs = Math.max(7, Math.min(24, box.clientHeight * 0.42));
    box.style.fontSize = fs + 'px';
    var guard = 60;
    while (guard-- > 0 && fs > 6 &&
      (box.scrollHeight > box.clientHeight + 1 || box.scrollWidth > box.clientWidth + 1)) {
      fs -= 0.5;
      box.style.fontSize = fs + 'px';
    }
  }

  function render(img, res) {
    var old = layers.get(img);
    if (old) old.remove();
    var layer = document.createElement('div');
    layer.className = 'sft-layer';
    res.bubbles.forEach(function (b) {
      var d = document.createElement('div');
      d.className = 'sft-b';
      d.style.left = (b.x / res.w * 100) + '%';
      d.style.top = (b.y / res.h * 100) + '%';
      d.style.width = (b.w / res.w * 100) + '%';
      d.style.height = (b.h / res.h * 100) + '%';
      d.textContent = b.fr;
      // Toucher une bulle : voir l'anglais, retoucher : revenir au français
      d.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        var en = d.classList.toggle('sft-en');
        d.textContent = en ? b.en : b.fr;
        fit(d);
      });
      layer.appendChild(d);
    });
    var anchor = img.parentElement && img.parentElement.tagName === 'PICTURE' ? img.parentElement : img;
    anchor.insertAdjacentElement('afterend', layer);
    layers.set(img, layer);
    place(img, layer, true);
  }

  // La couche est posée à côté de l'image avec la même position et la même
  // taille : elle suit donc la page quand on scrolle, sans rien recalculer.
  function place(img, layer, force) {
    if (!img.isConnected) { layer.remove(); layers.delete(img); return; }
    var L = img.offsetLeft, T = img.offsetTop, W = img.offsetWidth, H = img.offsetHeight;
    var key = L + ',' + T + ',' + W + ',' + H;
    if (!force && layer.dataset.k === key) return;
    layer.dataset.k = key;
    layer.style.left = L + 'px';
    layer.style.top = T + 'px';
    layer.style.width = W + 'px';
    layer.style.height = H + 'px';
    layer.querySelectorAll('.sft-b').forEach(fit);
  }

  function scan() {
    layers.forEach(function (layer, img) { place(img, layer, false); });
    if (!window.__sft.enabled || !ready()) return;
    var vh = window.innerHeight || 800;
    var imgs = document.images;
    for (var i = 0; i < imgs.length; i++) {
      var img = imgs[i];
      var r = img.getBoundingClientRect();
      if (r.bottom < -vh || r.top > vh * AHEAD || r.width === 0) continue;
      var u = abs(realUrl(img));
      if (!u) continue;
      if (img.dataset.sft) {
        if (img.dataset.sft === u) continue;
        // Même balise, nouvelle image (lecteurs page par page)
        if (!(img.complete && img.naturalWidth >= MIN)) continue;
        clearImg(img);
      }
      if (!looksLikePage(img)) continue;
      process(img, u);
    }
  }

  window.__sft.setEnabled = function (on) {
    window.__sft.enabled = !!on;
    document.documentElement.classList.toggle('sft-off', !on);
    if (on) scan();
  };

  setInterval(scan, 700);
  window.addEventListener('scroll', function () {
    clearTimeout(window.__sftT);
    window.__sftT = setTimeout(scan, 150);
  }, { passive: true });
  window.addEventListener('flutterInAppWebViewPlatformReady', scan);
  scan();
})();
