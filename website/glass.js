/* Liquid Glass + the screenshot deck.
   - deck: centre-snapping carousel with a coverflow tilt, drag / keys / buttons, and a dock whose "lens" slides between tabs
   - refract(): in Chromium, swaps the glass backdrop-filter for an SVG displacement map so edges bend what is behind them.
     Other browsers keep the plain blur + rim highlight (still glass, just not refracting). */
(function () {
  'use strict';

  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var clamp = function (v, a, b) { return Math.max(a, Math.min(b, v)); };

  /* ================= refraction ================= */
  var ua = navigator.userAgent;
  var chromium = /Chrome\//.test(ua) && !/Firefox|FxiOS/.test(ua);
  var NS = 'http://www.w3.org/2000/svg', XL = 'http://www.w3.org/1999/xlink';
  var defs = $('#lg-defs'), uid = 0;

  // Displacement map for a rounded rectangle: neutral grey inside, and near the rim the R/G channels push the sampled
  // backdrop toward the interior, strongest at the very edge (a convex lens).
  function makeMap(w, h, radius, bezel) {
    var k = Math.min(1, 220 / Math.max(w, h));               // keep the canvas small; feImage stretches it back
    var cw = Math.max(8, Math.round(w * k)), ch = Math.max(8, Math.round(h * k));
    var r = Math.min(radius * k, cw / 2, ch / 2), bz = bezel * k;
    var cv = document.createElement('canvas'); cv.width = cw; cv.height = ch;
    var ctx = cv.getContext('2d'), img = ctx.createImageData(cw, ch), d = img.data;
    var hx = cw / 2, hy = ch / 2;
    for (var y = 0; y < ch; y++) {
      for (var x = 0; x < cw; x++) {
        var px = x + 0.5 - hx, py = y + 0.5 - hy;
        var qx = Math.abs(px) - (hx - r), qy = Math.abs(py) - (hy - r);
        var ox = Math.max(qx, 0), oy = Math.max(qy, 0);
        var dist = Math.sqrt(ox * ox + oy * oy) + Math.min(Math.max(qx, qy), 0) - r;   // < 0 inside
        var depth = -dist, i = (y * cw + x) * 4, R = 128, G = 128;
        if (depth >= 0 && depth < bz) {
          var t = 1 - depth / bz, s = t * t;
          var gx, gy;
          if (qx > 0 || qy > 0) { var len = Math.sqrt(ox * ox + oy * oy) || 1; gx = Math.sign(px) * ox / len; gy = Math.sign(py) * oy / len; }
          else if (qx > qy) { gx = Math.sign(px); gy = 0; } else { gx = 0; gy = Math.sign(py); }
          R = 128 - 127 * s * gx; G = 128 - 127 * s * gy;      // point inward
        }
        d[i] = R; d[i + 1] = G; d[i + 2] = 128; d[i + 3] = 255;
      }
    }
    ctx.putImageData(img, 0, 0);
    return cv.toDataURL();
  }

  function refract(els, o) {
    if (!chromium || !defs || !els.length) return;
    var id = 'lg' + (++uid);
    var f = document.createElementNS(NS, 'filter');
    f.setAttribute('id', id); f.setAttribute('filterUnits', 'userSpaceOnUse');
    f.setAttribute('color-interpolation-filters', 'sRGB');
    var im = document.createElementNS(NS, 'feImage');
    im.setAttribute('preserveAspectRatio', 'none'); im.setAttribute('result', 'map');
    var dm = document.createElementNS(NS, 'feDisplacementMap');
    dm.setAttribute('in', 'SourceGraphic'); dm.setAttribute('in2', 'map');
    dm.setAttribute('xChannelSelector', 'R'); dm.setAttribute('yChannelSelector', 'G');
    dm.setAttribute('scale', String(o.scale));
    f.appendChild(im); f.appendChild(dm); defs.appendChild(f);

    function update() {
      var r = els[0].getBoundingClientRect();
      var w = Math.round(r.width), h = Math.round(r.height);
      if (!w || !h) return;
      [f, im].forEach(function (n) { n.setAttribute('x', 0); n.setAttribute('y', 0); n.setAttribute('width', w); n.setAttribute('height', h); });
      var url = makeMap(w, h, o.radius, o.bezel);
      im.setAttribute('href', url); im.setAttributeNS(XL, 'xlink:href', url);
      els.forEach(function (el) { el.style.backdropFilter = 'url(#' + id + ') blur(' + (o.blur || 3) + 'px) saturate(1.8)'; });
    }
    new ResizeObserver(update).observe(els[0]);
    update();
  }

  /* ================= deck ================= */
  var deck = $('#deck');
  if (!deck) return;
  var panes = [].slice.call(deck.querySelectorAll('.pane'));
  var tabsEl = $('#dock-tabs'), lens = $('#lens'), desc = $('#deck-desc'), wall = $('#wallpaper');
  var prev = $('#prev'), next = $('#next');
  var active = -1, raf = 0, progress = 0;

  var tabs = panes.map(function (p, i) {
    var b = document.createElement('button');
    b.type = 'button'; b.className = 'tab'; b.setAttribute('role', 'tab');
    b.textContent = p.dataset.name;
    b.addEventListener('click', function () { go(i); });
    tabsEl.appendChild(b);
    return b;
  });

  function paneCenter(p) { return p.offsetLeft + p.offsetWidth / 2; }
  function go(i, instant) {
    i = clamp(i, 0, panes.length - 1);
    deck.scrollTo({ left: paneCenter(panes[i]) - deck.clientWidth / 2, behavior: instant || reduced ? 'auto' : 'smooth' });
  }

  function setActive(i) {
    if (i === active) return;
    active = i;
    panes.forEach(function (p, k) { p.setAttribute('aria-current', k === i ? 'true' : 'false'); });
    tabs.forEach(function (t, k) { t.setAttribute('aria-selected', k === i ? 'true' : 'false'); });
    desc.textContent = panes[i].dataset.name + '：' + panes[i].dataset.desc;
    prev.disabled = i === 0; next.disabled = i === panes.length - 1;
    moveLens();
    // keep the active tab visible inside a scrollable dock (narrow screens)
    var t = tabs[i], box = tabsEl;
    box.scrollTo({ left: t.offsetLeft - (box.clientWidth - t.offsetWidth) / 2, behavior: reduced ? 'auto' : 'smooth' });
  }
  function moveLens() {
    var t = tabs[active]; if (!t) return;
    lens.style.width = t.offsetWidth + 'px';
    lens.style.transform = 'translateX(' + t.offsetLeft + 'px)';
  }

  function layout() {
    raf = 0;
    var mid = deck.scrollLeft + deck.clientWidth / 2, best = 0, bd = Infinity;
    panes.forEach(function (p, i) {
      var d = (paneCenter(p) - mid) / (p.offsetWidth + 30);
      var ad = Math.min(Math.abs(d), 2);
      p.style.setProperty('--d', d.toFixed(3));
      p.style.setProperty('--ad', ad.toFixed(3));
      if (Math.abs(d) < bd) { bd = Math.abs(d); best = i; }
    });
    setActive(best);
    var span = deck.scrollWidth - deck.clientWidth;
    progress = span > 0 ? deck.scrollLeft / span : 0;
    if (wall && !reduced) wall.style.transform = 'translate3d(' + (-progress * 7).toFixed(2) + '%,' + (progress * 3).toFixed(2) + '%,0)';
  }
  function schedule() { if (!raf) raf = requestAnimationFrame(layout); }
  deck.addEventListener('scroll', schedule, { passive: true });
  window.addEventListener('resize', function () { schedule(); moveLens(); });

  prev.addEventListener('click', function () { go(active - 1); });
  next.addEventListener('click', function () { go(active + 1); });
  deck.addEventListener('keydown', function (e) {
    if (e.key === 'ArrowLeft') { e.preventDefault(); go(active - 1); }
    else if (e.key === 'ArrowRight') { e.preventDefault(); go(active + 1); }
    else if (e.key === 'Home') { e.preventDefault(); go(0); }
    else if (e.key === 'End') { e.preventDefault(); go(panes.length - 1); }
  });

  // drag with a mouse (touch and trackpads already scroll natively)
  var drag = null;
  deck.addEventListener('pointerdown', function (e) {
    if (e.pointerType !== 'mouse' || e.button !== 0) return;
    drag = { x: e.clientX, left: deck.scrollLeft, moved: false };
  });
  window.addEventListener('pointermove', function (e) {
    if (!drag) return;
    var dx = e.clientX - drag.x;
    if (!drag.moved && Math.abs(dx) < 4) return;
    drag.moved = true; deck.classList.add('dragging');
    deck.scrollLeft = drag.left - dx;
  });
  window.addEventListener('pointerup', function () {
    if (!drag) return;
    var moved = drag.moved; drag = null;
    if (moved) { deck.classList.remove('dragging'); go(active); }
  });

  // pointer-following specular highlight on the glass frames
  panes.forEach(function (p) {
    var fr = p.querySelector('.frame');
    fr.addEventListener('pointermove', function (e) {
      var r = fr.getBoundingClientRect();
      fr.style.setProperty('--mx', ((e.clientX - r.left) / r.width * 100).toFixed(1) + '%');
      fr.style.setProperty('--my', ((e.clientY - r.top) / r.height * 100).toFixed(1) + '%');
    });
  });

  // refraction (Chromium): the dock capsule and the frames
  function setupRefraction() {
    refract([$('#dock')], { scale: 34, radius: 999, bezel: 20, blur: 2 });
    refract(panes.map(function (p) { return p.querySelector('.frame'); }), { scale: 46, radius: 40, bezel: 30, blur: 2 });
  }

  // initial state (images have fixed width/height, so layout is stable before they load)
  layout();
  go(0, true);
  requestAnimationFrame(function () { layout(); moveLens(); setupRefraction(); });
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { moveLens(); });
})();
