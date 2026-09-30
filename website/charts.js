/* MonitorX landing page: chart engine + demo data.
   No dependencies. Everything animates only while on screen, and nothing loops under prefers-reduced-motion.
   All data below is generated for the demo; the page says so next to the charts. */
(function () {
  'use strict';

  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var clamp = function (v, a, b) { return Math.max(a, Math.min(b, v)); };
  var lerp = function (a, b, t) { return a + (b - a) * t; };

  /* ---------- theme tokens (read once, refreshed on theme change) ---------- */
  var C = {};
  function readColors() {
    var cs = getComputedStyle(document.documentElement);
    ['bg', 'ink', 'ink-2', 'ink-3', 'line', 'line-2', 's1', 's2', 's3', 's4', 'warn', 'serious', 'crit'].forEach(function (n) {
      C[n] = cs.getPropertyValue('--' + n).trim();
    });
  }
  readColors();
  var themeListeners = [];
  function themeChanged() { readColors(); themeListeners.forEach(function (f) { f(); }); }
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', themeChanged);

  $('#theme').addEventListener('click', function () {
    var root = document.documentElement;
    var cur = root.dataset.theme || (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    var next = cur === 'dark' ? 'light' : 'dark';
    root.dataset.theme = next;
    try { localStorage.setItem('mx-theme', next); } catch (e) {}
    themeChanged();
  });

  /* ---------- formatters ---------- */
  function fmtRate(b) {
    if (b >= 1048576) return (b / 1048576).toFixed(b >= 10485760 ? 0 : 1) + ' MB/s';
    if (b >= 1024) return Math.round(b / 1024) + ' KB/s';
    return Math.round(b) + ' B/s';
  }
  function fmtPct(v) { return Math.round(v * 100) + '%'; }

  /* ---------- data generators ---------- */
  function walker(o) {
    var min = o.min, max = o.max, speed = o.speed || 0.22, jump = o.jump == null ? 0.05 : o.jump;
    var v = o.start == null ? (min + max) / 2 : o.start, t = v;
    return function () {
      if (Math.random() < jump) t = min + Math.random() * (max - min);
      v += (t - v) * speed + (Math.random() - 0.5) * (max - min) * 0.05;
      v = clamp(v, min, max);
      return v;
    };
  }
  function logWalker(min, max, o) {
    var w = walker(Object.assign({ min: Math.log(min), max: Math.log(max) }, o));
    return function () { return Math.exp(w()); };
  }

  /* ---------- visibility ---------- */
  var live = [];                     // things with frame(now) and .visible
  var rafId = 0;
  function loop(now) {
    rafId = 0;
    var any = false;
    for (var i = 0; i < live.length; i++) {
      if (live[i].visible && !document.hidden) { live[i].frame(now); any = true; }
    }
    if (any) rafId = requestAnimationFrame(loop);
  }
  function wake() { if (!rafId && !reduced) rafId = requestAnimationFrame(loop); }
  document.addEventListener('visibilitychange', wake);

  function watch(el, onChange, threshold) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { onChange(e.isIntersecting); });
    }, { threshold: threshold || 0.12 });
    io.observe(el);
  }

  /* ---------- floating tooltip helper (DOM, values lead / labels follow) ---------- */
  function rowHTML(color, label, value) {
    var r = document.createElement('div'); r.className = 'r';
    if (color) { var k = document.createElement('i'); k.style.background = color; r.appendChild(k); }
    var l = document.createElement('span'); l.textContent = label; r.appendChild(l);
    var s = document.createElement('strong'); s.textContent = value; r.appendChild(s);
    return r;
  }
  function fillTip(tip, title, rows) {
    tip.textContent = '';
    var b = document.createElement('b'); b.textContent = title; tip.appendChild(b);
    rows.forEach(function (r) { tip.appendChild(rowHTML(r[0], r[1], r[2])); });
  }
  function placeTip(tip, host, x, y) {
    tip.hidden = false;
    var w = tip.offsetWidth, hostW = host.clientWidth;
    var left = x + 16 + w > hostW ? x - 16 - w : x + 16;
    tip.style.left = Math.max(0, left) + 'px';
    tip.style.top = clamp(y - 10, 0, host.clientHeight - tip.offsetHeight) + 'px';
  }

  /* ---------- canvas plumbing ---------- */
  function fitCanvas(canvas, onResize) {
    function size() {
      var dpr = window.devicePixelRatio || 1;
      var w = canvas.clientWidth, h = canvas.clientHeight;
      canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
      canvas.getContext('2d').setTransform(dpr, 0, 0, dpr, 0, 0);
      onResize && onResize();
    }
    new ResizeObserver(size).observe(canvas);
    size();
  }
  var FONT = '12px system-ui, -apple-system, "PingFang SC", sans-serif';
  var FONT_B = '700 13px "Bricolage Grotesque", system-ui, -apple-system, "PingFang SC", sans-serif';

  function niceCeil(v) {
    if (v <= 0) return 1;
    var p = Math.pow(10, Math.floor(Math.log10(v))), n = v / p;
    return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * p;
  }
  var RATE_STEPS = [65536, 131072, 262144, 524288, 1048576, 2097152, 4194304, 8388608, 16777216, 33554432, 67108864];
  function stepCeil(steps, v) {
    for (var i = 0; i < steps.length; i++) if (steps[i] >= v) return steps[i];
    return steps[steps.length - 1];
  }
  function rr(ctx, x, y, w, h, tl, tr) { // rounded top corners only
    ctx.beginPath();
    ctx.moveTo(x, y + h); ctx.lineTo(x, y + tl);
    ctx.quadraticCurveTo(x, y, x + tl, y);
    ctx.lineTo(x + w - tr, y);
    ctx.quadraticCurveTo(x + w, y, x + w, y + tr);
    ctx.lineTo(x + w, y + h); ctx.closePath();
  }

  /* ================= LiveChart: sliding line/area or stacked columns ================= */
  function LiveChart(o) {
    var self = this;
    this.o = o; this.canvas = o.canvas; this.tip = o.tip; this.host = o.canvas.parentNode;
    this.ctx = o.canvas.getContext('2d');
    this.cap = o.capacity || 60; this.n = this.cap + 2;
    this.data = o.series.map(function () { return []; });
    this.interval = o.interval || 700;
    this.ceil = o.fixedMax || 1; this.tgt = this.ceil;
    this.visible = false; this.hover = null;
    for (var i = 0; i < this.n; i++) this.push();
    if (!o.fixedMax) this.ceil = this.targetCeil();
    this.last = performance.now();
    fitCanvas(this.canvas, function () { self.draw(0.999); });

    this.canvas.addEventListener('pointermove', function (e) {
      var r = self.canvas.getBoundingClientRect();
      self.hover = { x: e.clientX - r.left, y: e.clientY - r.top };
      if (reduced) self.draw(0.999);
    });
    this.canvas.addEventListener('pointerleave', function () { self.hover = null; self.tip.hidden = true; if (reduced) self.draw(0.999); });
    themeListeners.push(function () { self.draw(0.999); });
    live.push(this);
    watch(this.canvas, function (v) { self.visible = v; if (v) { self.last = performance.now(); wake(); } });
  }
  LiveChart.prototype.push = function () {
    var vals = this.o.gen(), self = this;
    vals.forEach(function (v, i) { self.data[i].push(v); if (self.data[i].length > self.n) self.data[i].shift(); });
  };
  LiveChart.prototype.totals = function (j) {
    var s = 0; for (var i = 0; i < this.data.length; i++) s += this.data[i][j] || 0; return s;
  };
  LiveChart.prototype.targetCeil = function () {
    var m = 0, stacked = this.o.mode === 'bars';
    for (var j = 0; j < this.n; j++) {
      if (stacked) m = Math.max(m, this.totals(j));
      else for (var i = 0; i < this.data.length; i++) m = Math.max(m, this.data[i][j] || 0);
    }
    var want = Math.max(m * 1.15, this.o.minCeil || 1);
    return this.o.steps ? stepCeil(this.o.steps, want) : niceCeil(want);
  };
  LiveChart.prototype.frame = function (now) {
    if (now - this.last >= this.interval) {
      this.last = now - Math.min(now - this.last - this.interval, this.interval);
      this.push();
    }
    this.draw(clamp((now - this.last) / this.interval, 0, 0.999));
  };
  LiveChart.prototype.draw = function (p) {
    var o = this.o, ctx = this.ctx, W = this.canvas.clientWidth, H = this.canvas.clientHeight;
    if (!W || !H) return;
    this.tgt = o.fixedMax || this.targetCeil();
    if (!o.fixedMax) this.ceil += (this.tgt - this.ceil) * (reduced ? 1 : 0.08);
    var ceil = this.ceil;

    var compact = W < 520;
    var padL = compact ? 52 : 58, padR = o.endLabels ? (compact ? 78 : (o.padR || 132)) : 10, padT = 10, padB = 22;
    var x0 = padL, x1 = W - padR, y0 = padT, y1 = H - padB;
    var pw = x1 - x0, ph = y1 - y0, step = pw / (this.cap - 1);
    var self = this;
    function X(j) { return x1 + step * (1 - p) - step * (self.n - 1 - j); }
    function Y(v) { return y1 - clamp(v / ceil, 0, 1) * ph; }

    ctx.clearRect(0, 0, W, H);
    ctx.font = FONT; ctx.textBaseline = 'middle';

    // grid: hairline, solid, recessive. Ticks carry the values that aren't labelled.
    for (var k = 0; k <= 2; k++) {
      var tickVal = this.tgt * k / 2;              // clean values, drawn where the data actually sits
      var gy = Math.round(Y(tickVal)) + 0.5;
      ctx.strokeStyle = k === 0 ? C['line-2'] : C.line; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(x0, gy); ctx.lineTo(x1, gy); ctx.stroke();
      ctx.fillStyle = C['ink-3']; ctx.textAlign = 'right';
      ctx.fillText(o.fmtY(tickVal), x0 - 8, gy);
    }
    ctx.fillStyle = C['ink-3']; ctx.textAlign = 'left'; ctx.fillText(o.xStart || '', x0, H - 8);
    ctx.textAlign = 'right'; ctx.fillText('现在', x1, H - 8);

    ctx.save();
    ctx.beginPath(); ctx.rect(x0, 0, pw + 1, H); ctx.clip();

    if (o.mode === 'bars') this.drawBars(ctx, X, Y, step, y1);
    else this.drawLines(ctx, X, Y, y1);

    // hover crosshair snaps to the nearest sample
    var hj = -1;
    if (this.hover && this.hover.x >= x0 && this.hover.x <= x1) {
      hj = Math.round(this.n - 1 - (x1 + step * (1 - p) - this.hover.x) / step);
      hj = clamp(hj, 1, this.n - 2);
      var hx = Math.round(X(hj)) + 0.5;
      if (o.mode !== 'bars') {
        ctx.strokeStyle = C['ink-3']; ctx.lineWidth = 1;
        ctx.beginPath(); ctx.moveTo(hx, y0); ctx.lineTo(hx, y1); ctx.stroke();
        for (var i = 0; i < this.data.length; i++) this.dot(ctx, hx, Y(this.data[i][hj]), C[o.series[i].color]);
      } else {
        ctx.fillStyle = 'rgba(128,140,170,.14)';
        ctx.fillRect(hx - step / 2, y0, step, ph);
      }
    }
    ctx.restore();

    // direct end labels (text wears text tokens; the dot carries the series color)
    if (o.endLabels) {
      var last = this.n - 1, ys = [];
      for (var s = 0; s < this.data.length; s++) {
        var v = lerp(this.data[s][last - 1], this.data[s][last], p);
        this.dot(ctx, x1, Y(v), C[o.series[s].color]);
        ys.push({ y: Y(v), v: v, s: s });
      }
      ys.sort(function (a, b) { return a.y - b.y; });
      for (var t = 1; t < ys.length; t++) if (ys[t].y - ys[t - 1].y < 17) ys[t].y = ys[t - 1].y + 17;
      ctx.textAlign = 'left';
      ys.forEach(function (e) {
        var name = compact ? '' : o.series[e.s].label, nw = 0;
        if (name) { ctx.fillStyle = C['ink-3']; ctx.font = FONT; ctx.fillText(name, x1 + 12, e.y); nw = ctx.measureText(name).width + 6; }
        ctx.fillStyle = C.ink; ctx.font = FONT_B; ctx.fillText(o.fmtVal(e.v), x1 + 12 + nw, e.y);
      });
    }

    // tooltip: one readout listing every series at that sample
    if (hj >= 0) {
      var rows = o.series.map(function (sr, i) { return [C[sr.color], sr.label, o.fmtVal(self.data[i][hj])]; });
      fillTip(this.tip, o.tipTitle(this.n - 1 - hj, this.interval), rows);
      placeTip(this.tip, this.host, this.hover.x, this.hover.y);
    } else if (!this.tip.hidden) this.tip.hidden = true;
  };
  LiveChart.prototype.dot = function (ctx, x, y, color) {
    ctx.beginPath(); ctx.arc(x, y, 6, 0, 6.2832); ctx.fillStyle = C.bg; ctx.fill();   // 2px surface ring
    ctx.beginPath(); ctx.arc(x, y, 4, 0, 6.2832); ctx.fillStyle = color; ctx.fill();
  };
  LiveChart.prototype.drawLines = function (ctx, X, Y, y1) {
    var self = this;
    this.data.forEach(function (d, i) {
      var color = C[self.o.series[i].color];
      ctx.beginPath();
      for (var j = 0; j < d.length; j++) { var x = X(j), y = Y(d[j]); j ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
      var line = new Path2D();
      ctx.lineJoin = 'round'; ctx.lineCap = 'round';
      // area wash (~10%)
      ctx.lineTo(X(d.length - 1), y1); ctx.lineTo(X(0), y1); ctx.closePath();
      ctx.globalAlpha = 0.10; ctx.fillStyle = color; ctx.fill(); ctx.globalAlpha = 1;
      ctx.beginPath();
      for (var k = 0; k < d.length; k++) { var xx = X(k), yy = Y(d[k]); k ? ctx.lineTo(xx, yy) : ctx.moveTo(xx, yy); }
      ctx.strokeStyle = color; ctx.lineWidth = 2; ctx.stroke();
    });
  };
  LiveChart.prototype.drawBars = function (ctx, X, Y, step, y1) {
    var bw = Math.min(12, step * 0.64), self = this;
    for (var j = 0; j < this.n; j++) {
      var cx = X(j), base = y1, tops = [];
      for (var i = 0; i < this.data.length; i++) {
        var h = (this.data[i][j] / this.ceil) * (y1 - Y(this.ceil));
        tops.push(h);
      }
      var lastIdx = -1; for (var q = tops.length - 1; q >= 0; q--) if (tops[q] > 0.5) { lastIdx = q; break; }
      for (var s = 0; s < this.data.length; s++) {
        var hh = tops[s]; if (hh <= 0.5) continue;
        var gap = s > 0 ? 2 : 0, top = base - hh;
        ctx.fillStyle = C[this.o.series[s].color];
        var r = s === lastIdx ? Math.min(4, bw / 2, hh) : 0;
        rr(ctx, cx - bw / 2, top, bw, hh - gap, r, r); ctx.fill();
        base = top;
      }
    }
  };

  /* ================= CoreChart: per-core columns ================= */
  function CoreChart(canvas, tip) {
    var self = this;
    this.canvas = canvas; this.tip = tip; this.host = canvas.parentNode; this.ctx = canvas.getContext('2d');
    this.cores = 12;
    this.gens = []; this.cur = []; this.tgt = [];
    for (var i = 0; i < this.cores; i++) {
      var busy = i % 4 === 0 ? 0.45 : 0.14;
      this.gens.push(walker({ min: 0.02, max: Math.min(1, busy + 0.5), jump: 0.1, speed: 0.4, start: busy }));
      this.cur.push(busy); this.tgt.push(busy);
    }
    this.visible = false; this.hover = null; this.lastStep = 0;
    fitCanvas(canvas, function () { self.draw(); });
    canvas.addEventListener('pointermove', function (e) { var r = canvas.getBoundingClientRect(); self.hover = { x: e.clientX - r.left, y: e.clientY - r.top }; if (reduced) self.draw(); });
    canvas.addEventListener('pointerleave', function () { self.hover = null; tip.hidden = true; if (reduced) self.draw(); });
    themeListeners.push(function () { self.draw(); });
    live.push(this);
    watch(canvas, function (v) { self.visible = v; if (v) wake(); });
    this.draw();
  }
  CoreChart.prototype.frame = function (now) {
    if (now - this.lastStep > 900) { this.lastStep = now; for (var i = 0; i < this.cores; i++) this.tgt[i] = this.gens[i](); }
    for (var k = 0; k < this.cores; k++) this.cur[k] += (this.tgt[k] - this.cur[k]) * 0.12;
    this.draw();
  };
  CoreChart.prototype.draw = function () {
    var ctx = this.ctx, W = this.canvas.clientWidth, H = this.canvas.clientHeight;
    if (!W || !H) return;
    ctx.clearRect(0, 0, W, H);
    ctx.font = FONT; ctx.textBaseline = 'middle';
    var padL = W < 520 ? 52 : 58, padB = 20, top = 6, base = H - padB, ph = base - top;
    var slot = (W - padL - 8) / this.cores, bw = Math.min(24, slot * 0.6);
    ctx.strokeStyle = C['line-2']; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(padL, base + 0.5); ctx.lineTo(W - 8, base + 0.5); ctx.stroke();
    ctx.fillStyle = C['ink-3']; ctx.textAlign = 'right'; ctx.fillText('100%', padL - 8, top + 4); ctx.fillText('0', padL - 8, base);
    var hv = -1;
    if (this.hover && this.hover.x > padL) hv = clamp(Math.floor((this.hover.x - padL) / slot), 0, this.cores - 1);
    for (var i = 0; i < this.cores; i++) {
      var v = this.cur[i], cx = padL + slot * (i + 0.5), h = Math.max(3, v * ph);
      var color = v > 0.92 ? C.crit : v > 0.8 ? C.serious : C.s1;
      ctx.fillStyle = color; ctx.globalAlpha = hv === i ? 1 : 0.92;
      rr(ctx, cx - bw / 2, base - h, bw, h, 4, 4); ctx.fill(); ctx.globalAlpha = 1;
      if (i === 0 || i === 5 || i === 11) { ctx.fillStyle = C['ink-3']; ctx.textAlign = 'center'; ctx.fillText(String(i + 1), cx, H - 7); }
    }
    if (hv >= 0) {
      fillTip(this.tip, '核心 ' + (hv + 1), [[C.s1, '占用', fmtPct(this.cur[hv])]]);
      placeTip(this.tip, this.host, this.hover.x, this.hover.y);
    } else if (!this.tip.hidden) this.tip.hidden = true;
  };

  /* ================= Hero: ranking race ================= */
  (function race() {
    var APPS = [
      { name: 'Google Chrome', n: 33, base: 46 }, { name: 'Xcode', n: 9, base: 41 },
      { name: 'WindowServer', n: 1, base: 34 }, { name: 'Docker Desktop', n: 6, base: 30 },
      { name: 'kernel_task', n: 1, base: 27 }, { name: 'node', n: 7, base: 24 },
      { name: 'Slack', n: 12, base: 21 }, { name: 'Spotify', n: 5, base: 17 }, { name: 'Finder', n: 1, base: 11 }
    ];
    var SHOW = 8, ROW = 44;
    var host = $('#race'), tbody = $('#race-table tbody'), tableEl = $('#race-table');
    host.style.height = SHOW * ROW + 'px';
    var items = APPS.map(function (a) {
      var el = document.createElement('div'); el.className = 'row';
      el.innerHTML = '<div class="name"></div><div class="lane"><div class="fill"></div></div><div class="val"></div>';
      var nm = el.querySelector('.name'); nm.textContent = a.name;
      if (a.n > 1) { var s = document.createElement('small'); s.textContent = '×' + a.n; nm.appendChild(s); }
      host.appendChild(el);
      var burst = 0;
      var w = walker({ min: a.base * 0.55, max: a.base * 1.6, jump: 0.2, speed: 0.4, start: a.base });
      return { a: a, el: el, fill: el.querySelector('.fill'), val: el.querySelector('.val'), v: a.base,
               next: function () {
                 if (burst > 0) { burst--; return a.base * 2.3 + Math.random() * a.base * 0.4; }
                 if (Math.random() < 0.09) { burst = 2; return a.base * 2.3; }
                 return w();
               } };
    });

    function sev(v) { var f = v / 100; return f < 0.35 ? C.s1 : f < 0.65 ? C.warn : f < 1 ? C.serious : C.crit; }
    function fmt(v) { return v >= 100 ? Math.round(v) + '%' : v.toFixed(1) + '%'; }

    function render() {
      var sorted = items.slice().sort(function (x, y) { return y.v - x.v; });
      var denom = Math.max(110, sorted[0].v * 1.06);
      sorted.forEach(function (it, rank) {
        var shown = rank < SHOW;
        it.el.style.transform = 'translateY(' + Math.min(rank, SHOW) * ROW + 'px)';
        it.el.style.opacity = shown ? 1 : 0;
        it.el.style.pointerEvents = 'none';
        it.el.setAttribute('aria-hidden', shown ? 'false' : 'true');
        it.fill.style.width = (it.v / denom * 100) + '%';
        it.fill.style.backgroundColor = sev(it.v);
        it.val.textContent = fmt(it.v);
        it.val.style.color = it.v >= 65 ? sev(it.v) : '';
      });
      if (!tableEl.hidden) {
        tbody.textContent = '';
        sorted.slice(0, SHOW).forEach(function (it) {
          var tr = document.createElement('tr');
          [it.a.name, it.a.n > 1 ? String(it.a.n) : '1', fmt(it.v)].forEach(function (t) { var td = document.createElement('td'); td.textContent = t; tr.appendChild(td); });
          tbody.appendChild(tr);
        });
      }
    }

    function tick() { items.forEach(function (it) { it.v = it.next(); }); render(); }
    tick(); tick();

    var timer = 0, seen = false;
    function run() { if (!timer && !reduced) timer = setInterval(function () { if (!document.hidden) tick(); }, 1500); }
    function stop() { clearInterval(timer); timer = 0; }
    watch($('.race'), function (v) { seen = v; v ? run() : stop(); }, 0.2);
    themeListeners.push(render);

    // chart / table switch
    var btns = document.querySelectorAll('.seg button');
    btns.forEach(function (b) {
      b.addEventListener('click', function () {
        var table = b.dataset.view === 'table';
        btns.forEach(function (x) { x.setAttribute('aria-pressed', String(x === b)); });
        host.hidden = table; tableEl.hidden = !table;
        render();
      });
    });
  })();

  /* ================= CPU + cores ================= */
  (function cpu() {
    var g = walker({ min: 0.09, max: 0.62, jump: 0.07, speed: 0.3, start: 0.22 });
    var chart = new LiveChart({
      canvas: $('#cpu-chart'), tip: $('#cpu-tip'), mode: 'line', capacity: 60, interval: 700,
      series: [{ label: 'CPU', color: 's1' }], fixedMax: 1, endLabels: true, xStart: '42 秒前',
      gen: function () { return [g()]; }, fmtY: fmtPct, fmtVal: fmtPct,
      tipTitle: function (age, iv) { return age === 0 ? '现在' : (age * iv / 1000).toFixed(0) + ' 秒前'; }
    });
    var out = $('#cpu-now');
    function readout() { var d = chart.data[0]; out.textContent = fmtPct(d[d.length - 1]); var s = document.createElement('small'); s.textContent = '总占用'; out.appendChild(s); }
    setInterval(function () { if (chart.visible) readout(); }, 700); readout();
    new CoreChart($('#core-chart'), $('#core-tip'));
  })();

  /* ================= Memory ================= */
  (function memory() {
    var total = 16;
    var parts = [
      { key: 'app', label: 'App', gb: 5.9, color: 's1' },
      { key: 'wired', label: '联动', gb: 3.4, color: 's2' },
      { key: 'comp', label: '压缩', gb: 1.6, color: 's3' },
      { key: 'cache', label: '缓存', gb: 3.9, color: 's4' },
      { key: 'free', label: '空闲', gb: 1.2, color: null }
    ];
    var stack = $('#mem-stack'), legend = $('#mem-legend'), out = $('#mem-now');
    var tip = document.createElement('div'); tip.className = 'tip'; tip.hidden = true;
    stack.style.position = 'relative'; stack.appendChild(tip);
    var segs = parts.map(function (p) {
      var el = document.createElement('div'); el.className = 'seg-m';
      el.style.background = p.color ? 'var(--' + p.color + ')' : 'var(--line-2)';
      el.addEventListener('pointermove', function (e) {
        var r = stack.getBoundingClientRect();
        fillTip(tip, p.label, [[p.color ? C[p.color] : C['line-2'], (p.gb / total * 100).toFixed(0) + '%', p.gb.toFixed(1) + ' GB']]);
        placeTip(tip, stack, e.clientX - r.left, 0);
      });
      el.addEventListener('pointerleave', function () { tip.hidden = true; });
      stack.insertBefore(el, tip);
      var li = document.createElement('li');
      li.innerHTML = '<i></i><span></span><b></b>';
      li.querySelector('i').style.background = p.color ? 'var(--' + p.color + ')' : 'var(--line-2)';
      li.querySelector('span').textContent = p.label;
      legend.appendChild(li);
      return { el: el, val: li.querySelector('b'), p: p };
    });
    function apply() {
      segs.forEach(function (s) { s.el.style.flexBasis = 'calc(' + (s.p.gb / total * 100) + '% - 2px)'; s.val.textContent = s.p.gb.toFixed(1) + ' GB'; });
      var used = parts[0].gb + parts[1].gb + parts[2].gb;
      out.textContent = used.toFixed(1) + ' GB';
      var s = document.createElement('small'); s.textContent = '已使用'; out.appendChild(s);
      var m = $('#pressure i'); m.style.left = 'calc(' + (used / total * 26) + '% - 2px)';
    }
    var wApp = walker({ min: 5.3, max: 6.6, speed: 0.3, jump: 0.2, start: 5.9 });
    var wComp = walker({ min: 1.2, max: 2.1, speed: 0.3, jump: 0.2, start: 1.6 });
    var timer = 0;
    watch(stack, function (v) {
      if (v) {
        apply();
        if (!reduced && !timer) timer = setInterval(function () {
          parts[0].gb = wApp(); parts[2].gb = wComp();
          parts[4].gb = Math.max(0.3, total - parts[0].gb - parts[1].gb - parts[2].gb - parts[3].gb);
          apply();
        }, 2200);
      } else { clearInterval(timer); timer = 0; }
    }, 0.4);
    apply();
    if (!reduced) segs.forEach(function (s) { s.el.style.flexBasis = '0px'; });   // grows in when scrolled to
    themeListeners.push(function () {});
  })();

  /* ================= Network ================= */
  (function network() {
    var down = logWalker(2e4, 6e6, { speed: 0.35, jump: 0.12 });
    var up = logWalker(4e3, 7e5, { speed: 0.35, jump: 0.12 });
    var chart = new LiveChart({
      canvas: $('#net-chart'), tip: $('#net-tip'), mode: 'line', capacity: 60, interval: 800,
      series: [{ label: '下载', color: 's1' }, { label: '上传', color: 's2' }], minCeil: 131072, steps: RATE_STEPS, endLabels: true, xStart: '48 秒前',
      gen: function () { return [down(), up()]; }, fmtY: function (v) { return v ? fmtRate(v).replace('/s', '') : '0'; }, fmtVal: fmtRate,
      tipTitle: function (age, iv) { return age === 0 ? '现在' : (age * iv / 1000).toFixed(0) + ' 秒前'; }
    });
    var lg = $('#net-legend');
    [['下载', 's1'], ['上传', 's2']].forEach(function (x) {
      var li = document.createElement('li'); li.innerHTML = '<i></i><span></span>';
      li.querySelector('i').style.background = 'var(--' + x[1] + ')'; li.querySelector('span').textContent = x[0]; lg.appendChild(li);
    });
    var out = $('#net-now');
    function readout() { var d = chart.data[0]; out.textContent = fmtRate(d[d.length - 1]); var s = document.createElement('small'); s.textContent = '下载'; out.appendChild(s); }
    setInterval(function () { if (chart.visible) readout(); }, 800); readout();
  })();

  /* ================= Disk ================= */
  (function disk() {
    var meter = $('#disk-meter'), fill = $('#disk-meter i'), out = $('#disk-now');
    var pct = 0.87;
    function paint() {
      fill.style.width = pct * 100 + '%';
      fill.style.backgroundColor = pct > 0.9 ? C.crit : pct > 0.8 ? C.warn : C.s1;
      out.textContent = Math.round(pct * 100) + '%';
      var s = document.createElement('small'); s.textContent = '已用 405 GB，剩余 61 GB'; out.appendChild(s);
    }
    if (!reduced) fill.style.width = '0%';
    watch(meter, function (v) { if (v) paint(); }, 0.6);
    if (reduced) paint();
    themeListeners.push(function () { if (fill.style.width !== '0%') paint(); });

    var r = logWalker(2e5, 4.2e7, { speed: 0.4, jump: 0.14 }), w = logWalker(1e5, 1.2e7, { speed: 0.4, jump: 0.14 });
    new LiveChart({
      canvas: $('#io-chart'), tip: $('#io-tip'), mode: 'bars', capacity: 36, interval: 900,
      series: [{ label: '读取', color: 's1' }, { label: '写入', color: 's2' }], minCeil: 2097152, steps: RATE_STEPS,
      gen: function () { return [r(), w()]; }, fmtY: function (v) { return v ? fmtRate(v).replace('/s', '') : '0'; }, fmtVal: fmtRate,
      tipTitle: function (age, iv) { return age === 0 ? '现在' : (age * iv / 1000).toFixed(0) + ' 秒前'; }
    });
    var lg = $('#io-legend');
    [['读取', 's1'], ['写入', 's2']].forEach(function (x) {
      var li = document.createElement('li'); li.innerHTML = '<i></i><span></span>';
      li.querySelector('i').style.background = 'var(--' + x[1] + ')'; li.querySelector('span').textContent = x[0]; lg.appendChild(li);
    });
  })();

  /* ================= Sensors heatmap ================= */
  (function sensors() {
    var GROUPS = [
      { title: '处理器', base: 66, spread: 5, names: ['CPU 二极管', 'CPU 二极管（虚拟）', 'CPU 邻近', 'CPU PECI', 'CPU 最高核心', 'CPU 系统代理', 'CPU 核心 1', 'CPU 核心 2', 'CPU 核心 3', 'CPU 核心 4', 'CPU 核心 5', 'CPU 核心 6'] },
      { title: '显卡', base: 50, spread: 8, names: ['GPU 核显', 'GPU 邻近', 'GPU 邻近 2', 'GPU（独显）', 'GPU（独显）核心', 'GPU（独显）显存', 'GPU 电压调节 F', 'GPU 电压调节 P'] },
      { title: '电池', base: 34, spread: 1.5, names: ['电池 1', '电池 2', '电池 3'] },
      { title: '存储', base: 35, spread: 2, names: ['SSD 控制器', 'SSD A', 'SSD B', 'SSD C', 'SSD D', 'SSD 2 A', 'SSD 2 B', 'SSD X', '硬盘邻近'] },
      { title: '内存', base: 53, spread: 4, names: ['内存邻近', '内存插槽 1', '内存插槽 2'] },
      { title: '主板与环境', base: 42, spread: 12, names: ['主板邻近', '平台控制器', '北桥邻近', 'Airport 邻近', '环境温度', '左侧进风', '右侧进风', '掌托左', '掌托右', '热管 1', '热管 2', '雷雳左'] }
    ];
    var host = $('#heat'), out = $('#sen-now');
    var tip = document.createElement('div'); tip.className = 'tip'; tip.hidden = true;
    host.style.position = 'relative'; host.appendChild(tip);
    var cells = [];
    GROUPS.forEach(function (g) {
      var row = document.createElement('div'); row.className = 'grp';
      var t = document.createElement('span'); t.textContent = g.title; row.appendChild(t);
      var wrap = document.createElement('div'); wrap.className = 'cells'; row.appendChild(wrap);
      g.names.forEach(function (name, i) {
        var el = document.createElement('div'); el.className = 'cell';
        var v = g.base + (Math.random() - 0.5) * 2 * g.spread;
        var w = walker({ min: v - 1.6, max: v + 1.6, speed: 0.4, jump: 0.2, start: v });
        var c = { el: el, name: name, v: v, w: w, idx: cells.length };
        el.addEventListener('pointermove', function (e) {
          var r = host.getBoundingClientRect();
          fillTip(tip, g.title, [[null, name, c.v.toFixed(0) + '°C']]);
          placeTip(tip, host, e.clientX - r.left, e.clientY - r.top);
        });
        el.addEventListener('pointerleave', function () { tip.hidden = true; });
        wrap.appendChild(el); cells.push(c);
      });
      host.insertBefore(row, tip);
    });
    function paint(c) {
      var t = clamp((c.v - 30) / 50, 0, 1) * 4, i = Math.min(3, Math.floor(t)), p = Math.round((t - i) * 100);
      c.el.style.backgroundColor = 'color-mix(in oklab, var(--heat-' + (i + 1) + ') ' + p + '%, var(--heat-' + i + '))';
    }
    function readout() {
      var hot = cells.reduce(function (a, b) { return b.v > a.v ? b : a; });
      out.textContent = '最高 ' + hot.v.toFixed(0) + '°C';
      var s = document.createElement('small'); s.textContent = hot.name; out.appendChild(s);
    }
    cells.forEach(paint); readout();

    var timer = 0, shown = false;
    watch(host, function (v) {
      if (v && !shown) {
        shown = true;
        cells.forEach(function (c) { c.el.style.transitionDelay = (c.idx * 14) + 'ms'; c.el.classList.add('on'); });
        setTimeout(function () { cells.forEach(function (c) { c.el.style.transitionDelay = ''; }); }, cells.length * 14 + 700);
      }
      if (v && !reduced && !timer) timer = setInterval(function () { cells.forEach(function (c) { c.v = c.w(); paint(c); }); readout(); }, 1600);
      if (!v) { clearInterval(timer); timer = 0; }
    }, 0.3);
    if (reduced) cells.forEach(function (c) { c.el.classList.add('on'); });

    // fans
    var fans = [{ name: '左侧风扇', min: 1836, max: 5297, rpm: 3700 }, { name: '右侧风扇', min: 1700, max: 4905, rpm: 3500 }];
    var fh = $('#fans');
    var fel = fans.map(function (f) {
      var d = document.createElement('div'); d.className = 'fan';
      d.innerHTML = '<div class="top"><span></span><b></b></div><div class="lane"><i></i></div><div class="range"><span></span><span></span></div>';
      d.querySelector('.top span').textContent = f.name;
      var rs = d.querySelectorAll('.range span'); rs[0].textContent = f.min + ' RPM'; rs[1].textContent = f.max + ' RPM';
      fh.appendChild(d);
      return { f: f, b: d.querySelector('b'), i: d.querySelector('.lane i'), w: walker({ min: f.min * 1.4, max: f.max * 0.8, speed: 0.15, jump: 0.05, start: f.rpm }) };
    });
    function fanPaint() {
      fel.forEach(function (x) { x.b.textContent = Math.round(x.f.rpm) + ' RPM'; x.i.style.width = clamp((x.f.rpm - x.f.min) / (x.f.max - x.f.min), 0, 1) * 100 + '%'; });
    }
    if (!reduced) fel.forEach(function (x) { x.i.style.width = '0%'; });
    var ft = 0;
    watch(fh, function (v) {
      if (v) { fanPaint(); if (!reduced && !ft) ft = setInterval(function () { fel.forEach(function (x) { x.f.rpm = x.w(); }); fanPaint(); }, 2000); }
      else { clearInterval(ft); ft = 0; }
    }, 0.5);
    if (reduced) fanPaint();
  })();

  /* ================= Copy command ================= */
  (function copy() {
    var b = $('#copy'), c = $('#cmd');
    if (!b) return;
    b.addEventListener('click', function () {
      var done = function () { b.textContent = '已复制'; setTimeout(function () { b.textContent = '复制'; }, 1400); };
      if (navigator.clipboard) navigator.clipboard.writeText(c.textContent).then(done);
    });
  })();
})();
