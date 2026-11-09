/* RealFaceAI — website behaviour. No dependencies. */
(function () {
  "use strict";

  var doc = document.documentElement;
  doc.classList.remove("no-js");
  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------- nav: scrolled state + mobile sheet ---------- */
  var nav = document.querySelector(".nav");
  if (nav) {
    var onScroll = function () { nav.classList.toggle("is-scrolled", window.scrollY > 8); };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    var menuBtn = nav.querySelector(".nav__menu");
    if (menuBtn) {
      menuBtn.addEventListener("click", function () {
        var open = nav.classList.toggle("is-open");
        menuBtn.setAttribute("aria-expanded", open ? "true" : "false");
      });
      nav.querySelectorAll(".nav__sheet a").forEach(function (a) {
        a.addEventListener("click", function () { nav.classList.remove("is-open"); menuBtn.setAttribute("aria-expanded", "false"); });
      });
    }
  }

  /* ---------- in-page anchors: smooth scroll ---------- */
  document.querySelectorAll('a[href^="#"]').forEach(function (a) {
    a.addEventListener("click", function (e) {
      var id = a.getAttribute("href");
      if (id.length < 2) return;
      var el = document.querySelector(id);
      if (!el) return;
      e.preventDefault();
      window.scrollTo({ top: el.getBoundingClientRect().top + window.scrollY - 76, behavior: reduceMotion ? "auto" : "smooth" });
      history.replaceState(null, "", id);
    });
  });

  /* ---------- scroll reveal ---------- */
  (function () {
    var targets = document.querySelectorAll("[data-reveal]");
    if (!("IntersectionObserver" in window) || reduceMotion) {
      targets.forEach(function (t) { t.classList.add("in"); });
      return;
    }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -6% 0px" });
    targets.forEach(function (t) { io.observe(t); });
  })();

  /* ---------- toasts (Django messages) ---------- */
  document.querySelectorAll(".toast button").forEach(function (b) {
    b.addEventListener("click", function () { b.closest(".toast").remove(); });
  });
  setTimeout(function () {
    document.querySelectorAll(".toast[data-autohide]").forEach(function (t) { t.remove(); });
  }, 9000);

  /* ---------- pixel face: the brand mark as a live, generative field ---------- */
  function PixelFace(canvas) {
    var ctx = canvas.getContext("2d");
    var W = 0, H = 0, dpr = 1, running = false, t0 = performance.now();
    var hudTime = document.querySelector("[data-timecode]");
    var hudLat = document.querySelector("[data-latency]");
    var lastLat = 0;

    function hash(a, b) {
      var h = Math.sin(a * 127.1 + b * 311.7) * 43758.5453;
      return h - Math.floor(h);
    }

    function resize() {
      var r = canvas.getBoundingClientRect();
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      W = r.width; H = r.height;
      canvas.width = Math.round(W * dpr);
      canvas.height = Math.round(H * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    function rr(x, y, w, h, r) {
      ctx.beginPath();
      ctx.moveTo(x + r, y);
      ctx.arcTo(x + w, y, x + w, y + h, r);
      ctx.arcTo(x + w, y + h, x, y + h, r);
      ctx.arcTo(x, y + h, x, y, r);
      ctx.arcTo(x, y, x + w, y, r);
      ctx.closePath();
    }

    function frame(now) {
      var t = (now - t0) / 1000;
      ctx.clearRect(0, 0, W, H);

      var cell = Math.max(10, Math.round(W / 30));
      var pitch = cell * 1.24;
      var cx = W * 0.47, cy = H * 0.5;
      var rx = W * 0.25, ry = H * 0.33;
      var seam = cx + rx * 0.10 + rx * 0.22 * Math.sin(t * 0.42);

      // 1. ambient dot field
      ctx.fillStyle = "rgba(255,255,255,0.07)";
      var step = pitch;
      for (var gx = step / 2; gx < W; gx += step) {
        for (var gy = step / 2; gy < H; gy += step) {
          ctx.fillRect(gx - 0.75, gy - 0.75, 1.5, 1.5);
        }
      }

      // 2. solid half (the "real" face): ellipse clipped left of the seam
      ctx.save();
      ctx.beginPath();
      ctx.ellipse(cx, cy, rx, ry, 0, 0, Math.PI * 2);
      ctx.clip();
      var g = ctx.createLinearGradient(0, cy - ry, 0, cy + ry);
      g.addColorStop(0, "#FFFFFF");
      g.addColorStop(1, "#C9CAFF");
      ctx.fillStyle = g;
      ctx.fillRect(cx - rx - 2, cy - ry - 2, seam - (cx - rx) + 2, ry * 2 + 4);
      ctx.restore();

      // 3. landmark contour on the solid half
      ctx.fillStyle = "#3A3DFF";
      for (var i = 0; i < 28; i++) {
        var a = Math.PI * 0.5 + (i / 27) * Math.PI;
        var px = cx + Math.cos(a) * rx * 0.86, py = cy + Math.sin(a) * ry * 0.9;
        if (px < seam - 6) { ctx.beginPath(); ctx.arc(px, py, 1.6, 0, Math.PI * 2); ctx.fill(); }
      }
      // brow / eye / mouth guides (only where solid)
      var guides = [[-0.55, -0.18], [-0.38, -0.2], [-0.2, -0.18], [-0.48, -0.06], [-0.3, -0.06], [-0.32, 0.38], [-0.16, 0.42], [0, 0.43]];
      guides.forEach(function (p) {
        var gx2 = cx + p[0] * rx, gy2 = cy + p[1] * ry;
        if (gx2 < seam - 6) { ctx.beginPath(); ctx.arc(gx2, gy2, 1.6, 0, Math.PI * 2); ctx.fill(); }
      });

      // 4. dissolving pixel columns (the "swap"): each column smaller and sparser
      var reach = rx * 1.5;
      var x0 = seam + cell * 0.3;
      var cols = Math.max(1, Math.ceil((cx + reach - x0) / pitch));
      for (var k = 0; k < cols; k++) {
        var d = k / cols;                                  // 0 near the seam, -> 1 at the edge
        var size = cell * (1 - 0.66 * d);
        var x = x0 + k * pitch + (cell - size) / 2;
        var rows = Math.floor(ry / pitch);
        for (var j = -rows; j <= rows; j++) {
          var y = cy + j * pitch;
          var ex = (x + size / 2 - cx) / reach, ey = (y - cy) / ry;
          if (ex * ex + ey * ey > 1) continue;
          var n = hash(k, j);
          if (d > 0.3 && n < (d - 0.3) * 1.25) continue;  // thin out the tail
          var s = size * (0.9 + 0.1 * Math.sin(t * 1.6 + n * 11));
          ctx.globalAlpha = 1 - 0.62 * d;
          ctx.fillStyle = (d > 0.5 && n > 0.88) ? "#7B7EFF" : "#FFFFFF";
          rr(x + (size - s) / 2, y - s / 2, s, s, Math.max(1.5, s * 0.22));
          ctx.fill();
        }
      }
      ctx.globalAlpha = 1;

      // 5. seam scan line
      var lg = ctx.createLinearGradient(0, cy - ry * 1.35, 0, cy + ry * 1.35);
      lg.addColorStop(0, "rgba(123,126,255,0)");
      lg.addColorStop(0.5, "rgba(123,126,255,0.9)");
      lg.addColorStop(1, "rgba(123,126,255,0)");
      ctx.fillStyle = lg;
      ctx.fillRect(seam, cy - ry * 1.35, 1, ry * 2.7);

      // HUD
      if (hudTime) {
        var fr = Math.floor(t * 30);
        var ff = fr % 30, ss = Math.floor(fr / 30) % 60, mm = Math.floor(fr / 1800) % 60;
        hudTime.textContent = "00:" + pad(mm) + ":" + pad(ss) + ":" + pad(ff);
      }
      if (hudLat && now - lastLat > 420) {
        lastLat = now;
        hudLat.textContent = String(34 + Math.round(hash(Math.floor(now / 420), 3) * 11));
      }
    }

    function pad(n) { return n < 10 ? "0" + n : "" + n; }

    function loop(now) {
      if (!running) return;
      frame(now);
      requestAnimationFrame(loop);
    }

    resize();
    window.addEventListener("resize", function () { resize(); if (!running) frame(t0 + 2600); });

    if (reduceMotion) { frame(t0 + 2600); return; }

    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (es) {
        es.forEach(function (e) {
          if (e.isIntersecting && !running) { running = true; requestAnimationFrame(loop); }
          else if (!e.isIntersecting) { running = false; }
        });
      }).observe(canvas);
    } else {
      running = true; requestAnimationFrame(loop);
    }
  }
  document.querySelectorAll("canvas[data-pixel-face]").forEach(function (c) { PixelFace(c); });

  /* ---------- product showcase tabs ---------- */
  (function () {
    var root = document.querySelector("[data-showcase]");
    if (!root) return;
    var tabs = root.querySelectorAll("[role=tab]");
    var imgs = root.querySelectorAll(".window__view img");
    var notes = root.querySelectorAll(".showcase__notes > div");
    var title = root.querySelector("[data-window-title]");
    var i = 0, timer = null;
    function show(n) {
      i = n;
      tabs.forEach(function (t, k) { t.setAttribute("aria-selected", k === n ? "true" : "false"); t.tabIndex = k === n ? 0 : -1; });
      imgs.forEach(function (im, k) { im.classList.toggle("is-on", k === n); });
      notes.forEach(function (d, k) { d.classList.toggle("is-on", k === n); });
      if (title) title.textContent = "realfaceai — " + tabs[n].dataset.name;
    }
    function auto() {
      if (reduceMotion) return;
      clearInterval(timer);
      timer = setInterval(function () { show((i + 1) % tabs.length); }, 5200);
    }
    tabs.forEach(function (t, k) {
      t.addEventListener("click", function () { show(k); auto(); });
      t.addEventListener("keydown", function (e) {
        if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
          var n = (k + (e.key === "ArrowRight" ? 1 : tabs.length - 1)) % tabs.length;
          show(n); tabs[n].focus(); auto();
        }
      });
    });
    show(0); auto();
  })();

  /* ---------- credit calculator ---------- */
  (function () {
    var packsEl = document.getElementById("credit-packs-data");
    var slider = document.getElementById("sessionsSlider");
    if (!packsEl || !slider) return;
    var PACKS = [];
    try { PACKS = JSON.parse(packsEl.textContent); } catch (e) { PACKS = []; }
    if (!PACKS.length) return;

    var sessionsVal = document.getElementById("sessionsVal");
    var creditsNeeded = document.getElementById("creditsNeeded");
    var costPerMonth = document.getElementById("costPerMonth");
    var recName = document.getElementById("recName");
    var recDetail = document.getElementById("recDetail");
    var recBtn = document.getElementById("recBtn");
    var durationBtns = document.querySelectorAll(".dur-btn");
    var selectedSecs = 30;
    var max = parseInt(slider.max, 10) || 1000, min = parseInt(slider.min, 10) || 1;

    function fmt(n) { return Number(n).toLocaleString("en-US"); }

    function update() {
      var sessions = parseInt(slider.value, 10);
      sessionsVal.textContent = fmt(sessions);
      var needed = sessions * selectedSecs; // 1 credit ≈ 1 second of streaming
      creditsNeeded.textContent = fmt(needed);
      var pct = ((sessions - min) / (max - min)) * 100;
      slider.style.background = "linear-gradient(to right, #3A3DFF " + pct + "%, #E7E8EF " + pct + "%)";

      var best = PACKS[PACKS.length - 1];
      for (var i = 0; i < PACKS.length; i++) { if (PACKS[i].credits >= needed) { best = PACKS[i]; break; } }
      var packsNeeded = Math.max(1, Math.ceil(needed / best.credits));
      var total = packsNeeded * best.price;
      costPerMonth.innerHTML = "$" + fmt(total) + ' <span class="cost-arrow">→</span> ' + fmt(packsNeeded * best.credits) + " credits" + (packsNeeded > 1 ? " · " + packsNeeded + "× " + best.label : "");
      recName.textContent = best.label;
      recDetail.textContent = fmt(best.credits) + " credits · $" + fmt(best.price) + " · covers ~" + best.sessions + " sessions";
      recBtn.textContent = "Get " + best.label;
      recBtn.setAttribute("data-pack-id", best.id);
    }
    slider.addEventListener("input", update);
    durationBtns.forEach(function (btn) {
      btn.addEventListener("click", function () {
        durationBtns.forEach(function (b) { b.classList.remove("active"); b.setAttribute("aria-pressed", "false"); });
        btn.classList.add("active"); btn.setAttribute("aria-pressed", "true");
        selectedSecs = parseInt(btn.dataset.secs, 10);
        update();
      });
    });
    update();
  })();

  /* ---------- download page: detect OS, install tabs ---------- */
  (function () {
    var cards = document.querySelectorAll("[data-os]");
    if (cards.length) {
      var ua = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || navigator.userAgent || "";
      var os = /mac|iphone|ipad/i.test(ua) ? "mac" : /win/i.test(ua) ? "windows" : "";
      cards.forEach(function (c) { if (c.dataset.os === os) c.classList.add("is-mine"); });
      var grid = document.querySelector(".dl-cards");
      if (os === "windows" && grid) grid.insertBefore(grid.querySelector('[data-os="windows"]'), grid.firstElementChild);
    }
  })();
  document.querySelectorAll("[data-install-tab]").forEach(function (b) {
    b.addEventListener("click", function () {
      var k = b.dataset.installTab;
      document.querySelectorAll("[data-install-tab]").forEach(function (x) { x.classList.toggle("active", x === b); x.setAttribute("aria-selected", x === b ? "true" : "false"); });
      document.querySelectorAll("[data-install-panel]").forEach(function (p) { p.classList.toggle("active", p.dataset.installPanel === k); });
    });
  });
  (function () {
    var cards = document.querySelectorAll("[data-os]");
    if (!cards.length) return;
    var ua = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || navigator.userAgent || "";
    var os = /mac|iphone|ipad/i.test(ua) ? "mac" : /win/i.test(ua) ? "windows" : "";
    var tab = document.querySelector('[data-install-tab="' + os + '"]');
    if (tab) tab.click();
  })();

  /* ---------- legal: table-of-contents scrollspy ---------- */
  (function () {
    var links = document.querySelectorAll(".legal__toc nav a");
    if (!links.length || !("IntersectionObserver" in window)) return;
    var map = {};
    links.forEach(function (a) { map[a.getAttribute("href").slice(1)] = a; });
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        if (e.isIntersecting) {
          links.forEach(function (a) { a.classList.remove("is-on"); });
          var a = map[e.target.id]; if (a) a.classList.add("is-on");
        }
      });
    }, { rootMargin: "-20% 0px -70% 0px" });
    document.querySelectorAll(".legal__body section[id]").forEach(function (s) { io.observe(s); });
  })();
})();
