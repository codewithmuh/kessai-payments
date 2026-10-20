// Kessai landing page. One payment followed end to end as the visitor scrolls.
// No dependencies; the page reads fine with JavaScript off (every section is plain HTML).
//
// Pieces, in order: helpers, mobile nav, sound, hero ledger, the journey (pinned scene driven by scroll position),
// scroll progress + stations, reveals, syntax colouring and copy, the R3 race, the architecture trace, the
// lost-payment diff, the drills, counters.

(() => {
  "use strict";

  document.documentElement.classList.replace("no-js", "js");

  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const stacked = window.matchMedia("(max-width: 900px)");
  const SVG = "http://www.w3.org/2000/svg";

  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const lerp = (a, b, t) => a + (b - a) * clamp(t, 0, 1);
  const easeOut = (t) => 1 - Math.pow(1 - t, 3);
  const yen = (n) => `${n < 0 ? "−" : ""}¥${Math.abs(Math.round(n)).toLocaleString("en-US")}`;
  const svgEl = (name, attrs = {}, parent = null) => {
    const el = document.createElementNS(SVG, name);
    for (const k in attrs) el.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(el);
    return el;
  };
  // Deterministic pseudo-random, so the hero ledger reads the same on every visit.
  const mulberry = (seed) => () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const onScreen = (el, margin = 0) => {
    const r = el.getBoundingClientRect();
    return r.bottom > -margin && r.top < window.innerHeight + margin;
  };
  // Runs play() while `el` is on screen and the tab is visible, pause() otherwise.
  const whileVisible = (el, play, pause, threshold = 0) => {
    let visible = false;
    const sync = () => (visible && !document.hidden ? play() : pause());
    new IntersectionObserver(
      (entries) => {
        visible = entries[0].isIntersecting;
        sync();
      },
      { threshold },
    ).observe(el);
    document.addEventListener("visibilitychange", sync);
  };

  // ------------------------------------------------------------------ Mobile nav
  const toggle = document.querySelector(".nav-toggle");
  const links = document.getElementById("nav-links");
  if (toggle && links) {
    const setOpen = (open) => {
      links.classList.toggle("open", open);
      toggle.setAttribute("aria-expanded", String(open));
    };
    toggle.addEventListener("click", () => setOpen(!links.classList.contains("open")));
    links.addEventListener("click", (e) => {
      if (e.target.closest("a")) setOpen(false);
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") setOpen(false);
    });
  }

  // ------------------------------------------------------------------ Sound
  // On by default, mutable, and silent until the visitor's first click, tap or key press (browsers block audio
  // before one). Every sound is synthesised with the Web Audio API: no files, notes from one pentatonic scale.
  const sound = (() => {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    let ctx = null;
    let out = null;
    let on = false;
    const lastAt = {};

    const start = () => {
      if (!AudioCtx || !on) return Promise.resolve(false);
      if (!ctx) {
        ctx = new AudioCtx();
        // notes -> out -> compressor -> speakers, plus a quiet echo (out -> delay -> filter -> wet) for some room
        const comp = ctx.createDynamicsCompressor();
        comp.threshold.value = -18;
        comp.knee.value = 12;
        comp.ratio.value = 4;
        comp.attack.value = 0.005;
        comp.release.value = 0.2;
        comp.connect(ctx.destination);
        out = ctx.createGain();
        out.gain.value = 0.75;
        out.connect(comp);
        const delay = ctx.createDelay(1);
        delay.delayTime.value = 0.24;
        const tone = ctx.createBiquadFilter();
        tone.type = "lowpass";
        tone.frequency.value = 2200;
        const feedback = ctx.createGain();
        feedback.gain.value = 0.26;
        const wet = ctx.createGain();
        wet.gain.value = 0.2;
        out.connect(delay);
        delay.connect(tone);
        tone.connect(feedback);
        feedback.connect(delay);
        tone.connect(wet);
        wet.connect(comp);
      }
      if (ctx.state === "running") return Promise.resolve(true);
      return ctx.resume().then(
        () => ctx.state === "running",
        () => false,
      );
    };

    const note = (freq, at, dur, gain = 0.07, type = "sine", glideTo = 0) => {
      const t = ctx.currentTime + at;
      const osc = ctx.createOscillator();
      const env = ctx.createGain();
      osc.type = type;
      osc.frequency.setValueAtTime(freq, t);
      if (glideTo) osc.frequency.exponentialRampToValueAtTime(glideTo, t + dur);
      env.gain.setValueAtTime(0.0001, t);
      env.gain.exponentialRampToValueAtTime(gain, t + 0.012);
      env.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      osc.connect(env);
      env.connect(out);
      osc.start(t);
      osc.stop(t + dur + 0.05);
    };

    const SOUNDS = {
      welcome: () => [392, 523.25, 659.25, 783.99].forEach((f, i) => note(f, i * 0.08, 0.6, 0.05, "triangle")),
      ping: () => note(1480, 0, 0.16, 0.02, "sine", 1180),
      tick: () => note(1760, 0, 0.07, 0.012),
      send: () => note(523.25, 0, 0.24, 0.035, "sine", 783.99), // a request leaves: a short rising glide
      // The 済 stamp: a soft thud with a click on top, then the two bright notes of money settling.
      stamp: () => {
        note(196, 0, 0.24, 0.09, "sine", 98);
        note(1567.98, 0.004, 0.04, 0.02, "triangle");
      },
      settled: () => [1046.5, 1567.98].forEach((f, i) => note(f, 0.1 + i * 0.08, 0.55, 0.04, "triangle")),
      ack: () => [783.99, 1046.5].forEach((f, i) => note(f, i * 0.09, 0.4, 0.04, "triangle")),
      replay: () => [880, 880].forEach((f, i) => note(f, i * 0.17, 0.22, 0.035)), // same answer, twice
      queue: () => note(130.81, 0, 0.6, 0.07, "triangle"), // the queue: a bass note under everything
      decline: () => note(246.94, 0, 0.4, 0.04, "triangle", 196),
      webhook: () => [783.99, 1046.5].forEach((f, i) => note(f, i * 0.07, 0.35, 0.035, "triangle")),
      commit: () => [1567.98, 1318.5].forEach((f, i) => note(f, i * 0.07, 0.05, 0.03, "triangle")),
      arrive: () => [1046.5, 1318.5].forEach((f, i) => note(f, i * 0.08, 0.45, 0.035, "triangle")),
      blip: () => note(1174.66, 0, 0.12, 0.025, "triangle", 1046.5),
      osaka: () => note(523.25, 0, 0.5, 0.03, "sine", 783.99), // a long glide west
      vault: () => {
        note(146.83, 0, 0.36, 0.06, "triangle");
        note(2093, 0.03, 0.03, 0.015, "triangle");
      },
      alert: () => [196, 174.61].forEach((f, i) => note(f, i * 0.14, 0.42, 0.035, "triangle")),
      handled: () => [392, 523.25].forEach((f, i) => note(f, i * 0.1, 0.5, 0.03, "triangle")),
      sweep: () => note(392, 0, 0.32, 0.035, "sine", 880),
      resolve: () => [523.25, 659.25, 783.99].forEach((f, i) => note(f, i * 0.03, 0.9, 0.026, "triangle")),
      count: () => [523.25, 659.25, 783.99, 1046.5].forEach((f, i) => note(f, i * 0.09, 0.18, 0.025)),
      cell: () => note(2093, 0, 0.03, 0.007, "triangle"),
      overdraft: () => [233.08, 207.65, 233.08].forEach((f, i) => note(f, i * 0.16, 0.3, 0.04, "triangle")),
    };
    // A rising pentatonic step per hop: transaction steps, and a packet crossing the architecture diagram.
    const SCALE = [523.25, 587.33, 659.25, 783.99, 880, 1046.5, 1174.66, 1318.5, 1567.98];
    const hop = (step, bright) => {
      const f = SCALE[Math.min(step, SCALE.length - 1)];
      if (bright) note(f * 1.5, 0, 0.16, 0.022, "triangle");
      else note(f, 0, 0.3, 0.03, "sine");
    };

    return {
      supported: Boolean(AudioCtx),
      get on() {
        return on;
      },
      enable() {
        on = true;
        return start();
      },
      disable() {
        on = false;
        if (ctx) ctx.suspend();
      },
      arm() {
        on = true;
      },
      start,
      // minGap: never repeat the same sound within that many ms (scrolling fast must not become a drum roll).
      play(name, minGap = 0) {
        if (!(on && ctx && ctx.state === "running")) return;
        const now = performance.now();
        if (minGap && now - (lastAt[name] || -Infinity) < minGap) return;
        lastAt[name] = now;
        SOUNDS[name]();
      },
      hop(step, bright = false) {
        if (!(on && ctx && ctx.state === "running")) return;
        const now = performance.now();
        if (now - (lastAt.hop || -Infinity) < 90) return;
        lastAt.hop = now;
        hop(step, bright);
      },
    };
  })();

  const soundBtn = document.querySelector(".sound-toggle");
  if (soundBtn && sound.supported && !reducedMotion) {
    const label = soundBtn.querySelector(".sound-label");
    const show = (on) => {
      soundBtn.setAttribute("aria-pressed", String(on));
      label.textContent = on ? "Sound on" : "Sound off";
      soundBtn.title = on ? "Mute the page" : "Play the page with sound";
    };
    const save = (value) => {
      try {
        localStorage.setItem("kessai-sound", value);
      } catch {
        // private mode or blocked storage: the choice just isn't remembered
      }
    };
    let saved = null;
    try {
      saved = localStorage.getItem("kessai-sound");
    } catch {
      saved = null;
    }
    // Scrolling with a wheel or trackpad is not a gesture browsers accept for audio, so a visitor who only
    // scrolls hears nothing. Until the first real gesture, the toggle pulses and a note explains.
    const nudge = document.getElementById("sound-nudge");
    let nudgeTimer = 0;
    let woken = false;
    const hideNudge = () => {
      if (nudge) nudge.hidden = true;
      soundBtn.classList.remove("pulse");
      clearTimeout(nudgeTimer);
    };
    const showNudge = (ms) => {
      if (woken || !sound.on || !nudge) return;
      nudge.hidden = false;
      soundBtn.classList.add("pulse");
      clearTimeout(nudgeTimer);
      nudgeTimer = setTimeout(hideNudge, ms);
    };

    const GESTURES = ["pointerdown", "pointerup", "touchend", "keydown"];
    const stopListening = () => GESTURES.forEach((g) => document.removeEventListener(g, wake, true));
    const awake = () => {
      woken = true;
      stopListening();
      hideNudge();
      sound.play("welcome");
    };
    function wake(e) {
      if (woken || !sound.on || soundBtn.contains(e.target)) return;
      sound.start().then((running) => {
        if (running && !woken) awake();
      });
    }
    if (saved !== "off") {
      sound.arm();
      GESTURES.forEach((g) => document.addEventListener(g, wake, true));
      setTimeout(() => showNudge(14000), 1200);
      // A second reminder when the story starts, if nothing has been clicked yet.
      const journeySection = document.getElementById("journey");
      if (journeySection && "IntersectionObserver" in window) {
        const once = new IntersectionObserver(
          (entries) => {
            if (!entries[0].isIntersecting) return;
            once.disconnect();
            showNudge(9000);
          },
          { threshold: 0.15 },
        );
        once.observe(journeySection);
      }
    }
    show(sound.on);
    soundBtn.addEventListener("click", () => {
      if (sound.on && !woken) {
        // Armed but not yet allowed to play: this click is the permission, not a mute.
        sound.start().then((running) => {
          if (running) awake();
        });
        return;
      }
      if (sound.on) {
        sound.disable();
        show(false);
        save("off");
        hideNudge();
      } else {
        show(true);
        save("on");
        sound.enable().then((running) => {
          if (running) awake();
        });
      }
    });
    soundBtn.hidden = false;
  }

  // ------------------------------------------------------------------ Hero ledger
  // A ledger page fills in behind the headline: every movement is two balanced lines, each gets a 済 stamp,
  // the total stays ¥0, and when the page is full it turns. The scoreboard and feed follow along.
  const ledger = document.getElementById("hero-ledger");
  const hero = document.querySelector(".hero");
  if (ledger) {
    const W = 1200;
    const H = 640;
    const ROW = 34;
    const TOP = 96;
    const X_A = 806;
    const X_Y = 1062;
    const X_S = 1102;
    for (let y = TOP; y <= H; y += ROW) svgEl("line", { class: "lg-rule", x1: 0, x2: W, y1: y, y2: y }, ledger);
    svgEl("line", { class: "lg-margin", x1: 776, x2: 776, y1: 0, y2: H }, ledger);
    svgEl("line", { class: "lg-margin", x1: 782, x2: 782, y1: 0, y2: H }, ledger);
    const head = (x, text, anchor = "start") => {
      const t = svgEl("text", { class: "lg-head", x, y: TOP - 14, "text-anchor": anchor }, ledger);
      t.textContent = text;
    };
    head(X_A, "ACCOUNT");
    head(X_Y, "YEN", "end");

    const page = svgEl("g", {}, ledger);
    page.style.transition = "opacity 0.6s ease";
    const stamps = svgEl("g", {}, page);
    const nRows = Math.floor((H - TOP - ROW) / ROW) - 1;
    const rowY = (r) => TOP + ROW * (r + 1) - 11;
    const rows = Array.from({ length: nRows }, (_, r) => {
      const g = svgEl("g", { class: "lg-row" }, page);
      const a = svgEl("text", { class: "lg-text", x: X_A, y: rowY(r) }, g);
      const v = svgEl("text", { class: "lg-text", x: X_Y, y: rowY(r), "text-anchor": "end" }, g);
      return { g, a, v };
    });
    const sumLabel = svgEl("text", { class: "lg-sum", x: X_A, y: rowY(nRows) }, ledger);
    sumLabel.textContent = "Σ every entry";
    const sumValue = svgEl("text", { class: "lg-sum", x: X_Y, y: rowY(nRows), "text-anchor": "end" }, ledger);
    sumValue.textContent = "¥0";

    const rnd = mulberry(11);
    const pick = (arr) => arr[Math.floor(rnd() * arr.length)];
    const CUSTOMERS = ["Sato", "Tanaka", "Suzuki", "Ito", "Watanabe", "Yamamoto", "Kato", "Kobayashi"];
    const MERCHANTS = ["Komorebi", "Ramen Ichi", "Hanaya", "Books Kiri", "Sento Nana", "Kissa Nagi"];
    const ID = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    const shortId = () => ID[Math.floor(rnd() * 32)] + ID[Math.floor(rnd() * 32)];
    let clock = 12 * 3600 + 4 * 60 + 5;
    const hhmmss = (s) => [Math.floor(s / 3600), Math.floor((s / 60) % 60), Math.floor(s % 60)].map((n) => String(n).padStart(2, "0")).join(":");

    const nextTx = () => {
      const r = rnd();
      const c = pick(CUSTOMERS);
      const m = pick(MERCHANTS);
      clock += 1 + Math.floor(rnd() * 4);
      if (r < 0.2) return { ev: "topup.succeeded", pre: "top", from: "bank clearing", to: `wallet · ${c}`, amount: pick([3000, 5000, 10000]) };
      if (r < 0.3) return { ev: "refund.succeeded", pre: "re", from: `wallet · ${m}`, to: `wallet · ${c}`, amount: pick([480, 680, 980]) };
      return { ev: "payment.succeeded", pre: "pay", from: `wallet · ${c}`, to: `wallet · ${m}`, amount: pick([480, 680, 760, 980, 1200, 1500, 2400, 3600]) };
    };

    const feed = document.getElementById("hero-feed");
    const acked = document.getElementById("score-acked");
    const found = document.getElementById("score-found");
    let count = 1284;
    let slot = 0;

    const write = (tx, animate) => {
      const id = `${tx.pre}_…${shortId()}`;
      const a = rows[slot * 2];
      const b = rows[slot * 2 + 1];
      rows.forEach((row) => row.g.classList.remove("fresh"));
      a.a.textContent = tx.from;
      a.v.textContent = `−${tx.amount.toLocaleString("en-US")}`;
      a.v.setAttribute("class", "lg-text lg-neg");
      b.a.textContent = tx.to;
      b.v.textContent = `+${tx.amount.toLocaleString("en-US")}`;
      b.v.setAttribute("class", "lg-text lg-pos");
      if (animate) {
        a.g.classList.add("fresh");
        b.g.classList.add("fresh");
      }
      const at = svgEl("g", { transform: `translate(${X_S} ${(rowY(slot * 2) + rowY(slot * 2 + 1)) / 2 - 6})` }, stamps);
      const s = svgEl("g", { class: "lg-stamp" }, at);
      svgEl("circle", { r: 16 }, s);
      const k = svgEl("text", { y: 8, lang: "ja" }, s);
      k.textContent = "済";
      slot++;
      count++;
      if (acked) acked.textContent = count.toLocaleString("en-US");
      if (found) found.textContent = count.toLocaleString("en-US");
      if (feed) {
        const line = document.createElement("div");
        line.innerHTML = `<span class="t">${hhmmss(clock)}</span> <span class="k">${tx.ev}</span> <span class="v">${id}</span> ¥${tx.amount.toLocaleString("en-US")}`;
        feed.prepend(line);
        while (feed.children.length > 2) feed.lastElementChild.remove();
      }
      if (animate) sound.play("ping", 2000);
    };

    const turnPage = (then) => {
      page.style.opacity = "0";
      setTimeout(() => {
        rows.forEach((row) => {
          row.a.textContent = "";
          row.v.textContent = "";
          row.g.classList.remove("fresh");
        });
        stamps.replaceChildren();
        slot = 0;
        page.style.opacity = "1";
        then();
      }, 650);
    };

    for (let i = 0; i < 3; i++) write(nextTx(), false);

    if (!reducedMotion) {
      let timer = 0;
      let running = false;
      const step = () => {
        if (!running) return;
        const go = () => {
          write(nextTx(), true);
          timer = setTimeout(step, 2300 + rnd() * 1300);
        };
        if (slot * 2 >= nRows) turnPage(go);
        else go();
      };
      whileVisible(
        hero,
        () => {
          if (running) return;
          running = true;
          timer = setTimeout(step, 1400);
        },
        () => {
          running = false;
          clearTimeout(timer);
        },
      );
    }
  }

  // ------------------------------------------------------------------ Journey: one payment, driven by scroll
  const scene = document.getElementById("scene");
  const journey = (() => {
    if (!scene) return null;

    const steps = Array.from(document.querySelectorAll("#steps-col .jstep"));
    const flow = {};
    document.querySelectorAll("#flow li").forEach((li) => (flow[li.dataset.n] = li));
    const wireViews = {};
    document.querySelectorAll(".wire-view").forEach((v) => (wireViews[v.dataset.view] = v));
    const dbViews = {};
    document.querySelectorAll(".db-view").forEach((v) => (dbViews[v.dataset.view] = { el: v, items: Array.from(v.children) }));
    const wireWho = document.getElementById("wire-who");
    const wireSub = document.getElementById("wire-sub");
    const dbWho = document.getElementById("db-who");
    const clockEl = document.getElementById("scene-clock");
    const balCus = document.getElementById("bal-cus");
    const balMer = document.getElementById("bal-mer");
    const walletCus = document.getElementById("w-cus");
    const newEntries = Array.from(document.querySelectorAll(".je-new"));

    const N = steps.length; // six steps, each a sixth of the scroll
    const STAGES = ["request", "sent", "tx", "committed", "durable", "ack", "replay", "relay", "try1", "try2", "recon", "recon_ok"];
    const STAGE_SOUND = { sent: "send", committed: "stamp", ack: "ack", replay: "replay", relay: "queue", try1: "decline", try2: "webhook", recon: "tick", recon_ok: "resolve" };
    const ms = (h, m, s, milli) => ({ h, m, s, milli });
    const fmtClock = ({ h, m, s, milli }) =>
      `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}.${String(Math.round(milli)).padStart(3, "0")}`;
    const at = (base, addMs) => {
      const total = base.s * 1000 + base.milli + addMs;
      return ms(base.h, base.m, Math.floor(total / 1000), total % 1000);
    };
    const T0 = ms(12, 4, 5, 20);

    // Everything on screen is a pure function of p in [0, 1].
    function sceneAt(p) {
      const s = clamp(p, 0, 0.999999) * N;
      const k = Math.floor(s);
      const q = s - k;
      const o = {
        step: k, stage: "request", flow: { client: "hot" },
        wire: "request", wireWho: "On the wire", wireSub: "HTTPS · sketch of v1",
        db: "tx", dbWho: "One transaction", done: 0, now: -1, failAt: -1,
        entries: "", committed: false, cus: 5000, mer: 0, locked: false, acked: false, try1: false, try2: false,
        clock: fmtClock(T0),
      };
      if (k >= 2) {
        o.committed = true;
        o.cus = 3800;
        o.mer = 1200;
        o.entries = "posted";
      }
      if (k === 0) {
        if (q >= 0.5) {
          o.stage = "sent";
          o.flow = { client: "on", api: "hot" };
        }
        o.clock = fmtClock(at(T0, q * 10));
      } else if (k === 1) {
        const n = Math.min(8, Math.floor((q / 0.86) * 8));
        o.stage = n >= 8 ? "committed" : "tx";
        o.done = n;
        o.now = n < 8 ? n : -1;
        o.locked = n >= 2 && n < 8;
        o.entries = n >= 8 ? "posted" : n >= 4 ? "pending" : "";
        o.committed = n >= 8;
        if (o.committed) {
          const t = easeOut(clamp((q - 0.86) / 0.1, 0, 1));
          o.cus = Math.round(lerp(5000, 3800, t));
          o.mer = Math.round(lerp(0, 1200, t));
        }
        o.flow = { client: "on", api: "on", db: "hot" };
        o.clock = fmtClock(at(T0, 11 + Math.min(q, 0.9) * 97));
      } else if (k === 2) {
        const n = Math.min(4, Math.floor((q / 0.8) * 4));
        o.db = "durable";
        o.dbWho = "After COMMIT";
        o.done = n;
        o.now = n < 4 ? n : -1;
        o.acked = n >= 3;
        o.stage = o.acked ? "ack" : "durable";
        o.wire = "ack";
        o.wireSub = "201 · acks.log";
        o.flow = n >= 2 ? { db: "on", api: "on", client: "hot" } : { db: "hot", api: "on" };
        o.clock = fmtClock(at(T0, 98 + q * 8));
      } else if (k === 3) {
        const n = Math.min(5, Math.floor((q / 0.85) * 5));
        o.stage = "replay";
        o.db = "replay";
        o.dbWho = "Idempotency check";
        o.done = n;
        o.now = n < 5 ? n : -1;
        o.wire = "retry";
        o.wireSub = "same key, same body";
        o.flow = { client: "on", api: "hot", db: "on" };
        o.clock = fmtClock(at(ms(12, 4, 8, 130), q * 6));
      } else if (k === 4) {
        const n = Math.min(6, Math.floor((q / 0.88) * 6));
        o.db = "outbox";
        o.dbWho = "Outbox and deliveries";
        o.done = n;
        o.now = n < 6 ? n : -1;
        o.failAt = n > 3 ? 3 : -1;
        o.try1 = n >= 3;
        o.try2 = n >= 4;
        o.stage = n >= 4 ? "try2" : n >= 3 ? "try1" : "relay";
        o.wire = "webhook";
        o.wireWho = "The merchant receives";
        o.wireSub = "signed webhook";
        if (n < 1) o.flow = { db: "hot" };
        else if (n < 3) o.flow = { db: "on", queue: "hot" };
        else if (n === 3) o.flow = { db: "on", queue: "on", merchant: "bad" };
        else o.flow = { db: "on", queue: "on", merchant: "hot" };
        o.clock = n >= 4 ? "12:04:39.214" : n >= 3 ? "12:04:09.210" : fmtClock(at(ms(12, 4, 9, 0), q * 200));
      } else {
        const n = Math.min(4, Math.floor((q / 0.8) * 4));
        o.db = "recon";
        o.dbWho = "Nightly check";
        o.done = n;
        o.now = n < 4 ? n : -1;
        o.stage = n >= 3 ? "recon_ok" : "recon";
        o.wire = "recon";
        o.wireWho = "The operator sees";
        o.wireSub = "CronJob · daily";
        o.flow = n < 1 ? { bank: "hot" } : { bank: "on", db: n >= 3 ? "on" : "hot" };
        o.clock = "03:00:00 · next night";
      }
      return o;
    }

    const shown = {};
    let lastStage = 0;
    let lastHopKey = "";

    function render(p) {
      const o = sceneAt(p);

      if (o.stage !== shown.stage) {
        scene.dataset.stage = o.stage;
        const idx = STAGES.indexOf(o.stage);
        if (idx > lastStage && STAGE_SOUND[o.stage]) {
          sound.play(STAGE_SOUND[o.stage], 300);
          if (o.stage === "committed") setTimeout(() => sound.play("settled", 300), 60);
        }
        lastStage = idx;
        shown.stage = o.stage;
      }
      if (o.step !== shown.step) {
        steps.forEach((li, i) => li.classList.toggle("is-active", i === o.step));
        scene.dataset.step = String(o.step);
        shown.step = o.step;
      }

      const flowKey = JSON.stringify(o.flow);
      if (flowKey !== shown.flow) {
        for (const n in flow) {
          const state = o.flow[n] || "";
          flow[n].classList.toggle("on", state === "on");
          flow[n].classList.toggle("hot", state === "hot");
          flow[n].classList.toggle("bad", state === "bad");
        }
        shown.flow = flowKey;
      }

      scene.classList.toggle("committed", o.committed);
      scene.classList.toggle("acked", o.acked);
      scene.classList.toggle("try1", o.try1);
      scene.classList.toggle("try2", o.try2);
      walletCus.classList.toggle("locked", o.locked);
      if (o.cus !== shown.cus) {
        balCus.textContent = yen(o.cus);
        shown.cus = o.cus;
      }
      if (o.mer !== shown.mer) {
        balMer.textContent = yen(o.mer);
        shown.mer = o.mer;
      }
      if (o.entries !== shown.entries) {
        newEntries.forEach((li) => {
          li.classList.toggle("pending", o.entries === "pending");
          li.classList.toggle("posted", o.entries === "posted");
        });
        shown.entries = o.entries;
      }

      if (o.wire !== shown.wire) {
        for (const k in wireViews) wireViews[k].classList.toggle("active", k === o.wire);
        shown.wire = o.wire;
      }
      if (o.wireWho !== shown.wireWho) {
        wireWho.textContent = o.wireWho;
        shown.wireWho = o.wireWho;
      }
      if (o.wireSub !== shown.wireSub) {
        wireSub.textContent = o.wireSub;
        shown.wireSub = o.wireSub;
      }

      const dbKey = `${o.db}:${o.done}:${o.now}:${o.failAt}`;
      if (dbKey !== shown.db) {
        for (const k in dbViews) dbViews[k].el.classList.toggle("active", k === o.db);
        dbViews[o.db].items.forEach((li, i) => {
          li.classList.toggle("done", i < o.done && i !== o.failAt);
          li.classList.toggle("now", i === o.now);
          li.classList.toggle("failed", i === o.failAt);
        });
        if (o.dbWho !== shown.dbWho) {
          dbWho.textContent = o.dbWho;
          shown.dbWho = o.dbWho;
        }
        // Each step inside the transaction is a rising note; the other lists tick.
        const hopKey = `${o.db}:${o.done}`;
        if (hopKey !== lastHopKey && shown.db !== undefined) {
          const forward = lastHopKey.startsWith(`${o.db}:`) ? o.done > Number(lastHopKey.split(":")[1]) : true;
          if (forward && o.db === "tx" && o.done > 0 && o.done < 8) sound.hop(o.done);
          else if (forward && o.done > 0 && o.db !== "tx") sound.play("tick", 120);
        }
        lastHopKey = hopKey;
        shown.db = dbKey;
      }

      if (o.clock !== shown.clock) {
        clockEl.textContent = o.clock;
        shown.clock = o.clock;
      }
    }

    // Progress through the steps column: 0 when the first step's top reaches the focus line, 1 when the last
    // step's bottom does. On narrow screens the scene is pinned above the text, so the focus line sits in the
    // space below it.
    function progress() {
      const first = steps[0].getBoundingClientRect();
      const last = steps[steps.length - 1].getBoundingClientRect();
      let focus = window.innerHeight * 0.5;
      if (stacked.matches) {
        const sr = scene.getBoundingClientRect();
        focus = sr.bottom + (window.innerHeight - sr.bottom) * 0.45;
      }
      return clamp((focus - first.top) / (last.bottom - first.top), 0, 1);
    }

    const section = document.getElementById("journey");
    let lastP = -1;
    return {
      update() {
        if (!onScreen(section, 200)) return;
        const p = progress();
        if (p === lastP) return;
        lastP = p;
        render(p);
      },
      init() {
        render(progress());
      },
    };
  })();

  // ------------------------------------------------------------------ Scroll: progress bar, stations, journey
  const progressFill = document.getElementById("progress-fill");
  const stationLinks = Array.from(document.querySelectorAll(".stations a"));
  const stationTargets = stationLinks.map((a) => document.querySelector(a.getAttribute("href")));
  const stationsNav = document.querySelector(".stations");
  const stationsList = document.querySelector(".stations ol");
  const scrollCue = document.querySelector(".scroll-cue");
  let lastActive = -1;

  function onScroll() {
    const doc = document.documentElement;
    const max = doc.scrollHeight - window.innerHeight;
    const p = max > 0 ? window.scrollY / max : 0;
    if (progressFill) progressFill.style.transform = `scaleX(${p.toFixed(4)})`;
    if (scrollCue) scrollCue.style.opacity = window.scrollY > 120 ? "0" : "1";
    if (stationsNav) stationsNav.classList.toggle("shown", window.scrollY > window.innerHeight * 0.6);

    if (stationLinks.length) {
      let active = 0;
      stationTargets.forEach((t, i) => {
        if (t && t.getBoundingClientRect().top <= window.innerHeight * 0.45) active = i;
      });
      if (window.scrollY + window.innerHeight >= doc.scrollHeight - 4) active = stationLinks.length - 1;
      if (active !== lastActive) {
        stationLinks.forEach((a, i) => {
          a.classList.toggle("active", i === active);
          a.classList.toggle("passed", i < active);
        });
        stationsList.style.setProperty("--fill", (active / (stationLinks.length - 1)).toFixed(3));
        if (lastActive !== -1 && active > lastActive) sound.play("tick", 600);
        lastActive = active;
      }
    }
    if (journey) journey.update();
  }

  let scrollRaf = 0;
  const requestScroll = () => {
    if (scrollRaf) return;
    scrollRaf = requestAnimationFrame(() => {
      scrollRaf = 0;
      onScroll();
    });
  };
  window.addEventListener("scroll", requestScroll, { passive: true });
  window.addEventListener("resize", requestScroll);
  if (journey) journey.init();
  onScroll();

  // ------------------------------------------------------------------ Reveals
  document.querySelectorAll(".reveal-group").forEach((group) => {
    Array.from(group.querySelectorAll(":scope > .reveal")).forEach((el, i) => el.style.setProperty("--i", String(Math.min(i, 7))));
  });
  const reveals = Array.from(document.querySelectorAll(".reveal"));
  if ("IntersectionObserver" in window && !reducedMotion) {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) {
            e.target.classList.add("in");
            io.unobserve(e.target);
          }
        });
      },
      { threshold: 0.1, rootMargin: "0px 0px -6% 0px" },
    );
    reveals.forEach((el) => io.observe(el));
  } else {
    reveals.forEach((el) => el.classList.add("in"));
  }

  // ------------------------------------------------------------------ Syntax colouring and copy
  const RULES = {
    bash: /(#[^\n]*)|("(?:[^"\\\n]|\\.)*")|(\b(?:curl|make)\b)/g,
  };
  const escapeHtml = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  document.querySelectorAll("code[data-lang]").forEach((el) => {
    const rule = RULES[el.dataset.lang];
    if (!rule) return;
    const text = el.textContent;
    let html = "";
    let last = 0;
    rule.lastIndex = 0;
    let m;
    while ((m = rule.exec(text))) {
      // A # inside a word (a URL fragment, say) is not a comment.
      if (m[1] && m.index > 0 && !/\s/.test(text[m.index - 1])) {
        rule.lastIndex = m.index + 1;
        continue;
      }
      const cls = m[1] ? "tok-c" : m[2] ? "tok-s" : "tok-k";
      html += escapeHtml(text.slice(last, m.index)) + `<span class="${cls}">${escapeHtml(m[0])}</span>`;
      last = m.index + m[0].length;
    }
    el.innerHTML = html + escapeHtml(text.slice(last));
  });

  document.querySelectorAll(".copy").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const code = btn.parentElement.querySelector("code");
      try {
        await navigator.clipboard.writeText(code.textContent);
        btn.textContent = "Copied";
      } catch {
        const range = document.createRange();
        range.selectNodeContents(code);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
        btn.textContent = "Selected";
      }
      setTimeout(() => (btn.textContent = "Copy"), 1600);
    });
  });

  // ------------------------------------------------------------------ R3 race: 200 payments, money for 50
  // With the lock, payments run one after another. Without it, a burst of them reads the same balance before any
  // of them writes, so a whole burst can pass the "enough money?" check at once.
  const raceGrid = document.getElementById("race-grid");
  if (raceGrid) {
    const TOTAL = 200;
    const PRICE = 100;
    const START = 5000;
    const cells = Array.from({ length: TOTAL }, () => {
      const c = document.createElement("span");
      c.className = "cell";
      raceGrid.appendChild(c);
      return c;
    });
    const balEl = document.getElementById("race-bal");
    const okEl = document.getElementById("race-ok");
    const noEl = document.getElementById("race-no");
    const verdict = document.getElementById("race-verdict");
    const runBtn = document.getElementById("race-run");
    const lockBtns = Array.from(document.querySelectorAll("#race [data-lock]"));
    let lock = true;
    let timer = 0;
    let running = false;

    const showStats = (balance, ok, no) => {
      balEl.textContent = yen(balance);
      balEl.classList.toggle("negative", balance < 0);
      okEl.textContent = String(ok);
      noEl.textContent = String(no);
    };
    const reset = () => {
      clearTimeout(timer);
      running = false;
      runBtn.disabled = false;
      cells.forEach((c) => (c.className = "cell"));
      showStats(START, 0, 0);
      verdict.className = "race-verdict";
      verdict.textContent = lock
        ? 'With a row lock, each payment waits for the one before it to commit. Press "Fire 200 payments".'
        : 'Without a lock, payments that arrive together all read the same balance. Press "Fire 200 payments".';
    };

    lockBtns.forEach((b) =>
      b.addEventListener("click", () => {
        lock = b.dataset.lock === "on";
        lockBtns.forEach((x) => x.setAttribute("aria-pressed", String(x === b)));
        reset();
        sound.play("tick", 100);
      }),
    );

    runBtn.addEventListener("click", () => {
      reset();
      running = true;
      runBtn.disabled = true;
      let balance = START;
      let ok = 0;
      let no = 0;
      let i = 0;
      const mark = (idx, cls) => (cells[idx].className = `cell ${cls}`);
      const finish = () => {
        running = false;
        runBtn.disabled = false;
        const over = Math.max(0, ok - START / PRICE);
        if (over === 0) {
          verdict.className = "race-verdict good";
          verdict.textContent = `${ok} succeeded, ${no} declined, balance ${yen(balance)}. Every payment waited its turn, so R3 holds.`;
          sound.play("resolve");
        } else {
          verdict.className = "race-verdict bad";
          verdict.textContent = `${ok} succeeded, balance ${yen(balance)}. ${over} payment${over === 1 ? "" : "s"} spent money that was never there. R3 is broken, and this test would fail.`;
          sound.play("overdraft");
        }
      };
      const tick = () => {
        if (lock) {
          for (let j = 0; j < 2 && i < TOTAL; j++, i++) {
            if (balance >= PRICE) {
              balance -= PRICE;
              ok++;
              mark(i, "c-ok");
            } else {
              no++;
              mark(i, "c-no");
            }
          }
        } else {
          const burst = 3 + Math.floor(Math.random() * 7);
          const seen = balance; // every payment in the burst read this before any of them wrote
          let wins = 0;
          for (let j = 0; j < burst && i < TOTAL; j++, i++) {
            if (seen >= PRICE) {
              wins++;
              ok++;
              mark(i, ok > START / PRICE ? "c-over" : "c-ok");
            } else {
              no++;
              mark(i, "c-no");
            }
          }
          balance -= wins * PRICE;
        }
        showStats(balance, ok, no);
        sound.play("cell", 45);
        if (i < TOTAL) {
          if (reducedMotion) tick();
          else timer = setTimeout(tick, lock ? 24 : 40);
        } else finish();
      };
      tick();
    });
    reset();
  }

  // ------------------------------------------------------------------ Architecture trace
  // A packet travels the real edges of the diagram. The caption explains each hop as the packet makes it.
  const arch = document.getElementById("arch");
  if (arch) {
    const packetsG = document.getElementById("packets");
    const traceText = document.getElementById("trace-text");
    const traceStep = document.getElementById("trace-step");
    const caption = document.querySelector(".trace-caption");
    const SPEED = 150; // units per second
    const DWELL = 0.5; // pause at each node, in seconds
    const COLOR = { pay: "var(--brand)", event: "var(--shu)", recon: "var(--kin)", dr: "var(--fuji)" };

    const TRACES = {
      pay: {
        start: "n-client",
        lanes: [
          { edges: ["e-client-alb", "e-alb-api", "e-api-writer", "e-writer-reader"] },
          { after: 3, edges: ["e-api-client"] },
          { after: 3, delay: 1.3, edges: ["e-db-global"] },
        ],
        captions: [
          [0, 0, "The payment client, outside AWS, sends POST /v1/payments with an Idempotency-Key. Route 53 points it at Tokyo."],
          [0, 1, "The ALB spreads requests over at least three api pods in three AZs. A pod that is shutting down fails readiness first."],
          [0, 2, "The api writes the payment, both ledger entries, the key and the outbox event in one transaction on the Aurora writer."],
          [0, 3, "The reader waits in another AZ. If the writer's AZ fails, Aurora promotes the reader, with a target of 60 seconds."],
          [1, 0, "Only once the commit is durable does the 201 go back. The client appends it to acks.log, outside AWS: the score sheet."],
          [2, 0, "On DR days, Aurora Global Database also copies every commit to Osaka, usually less than a second behind."],
        ],
      },
      event: {
        start: "n-aurora",
        lanes: [
          { edges: ["e-db-relay", "e-relay-sqs", "e-sqs-sender", "e-sender-merchant"] },
          { after: 4, edges: ["e-sender-db"] },
        ],
        captions: [
          [0, 0, "The outbox row was committed with the payment, so the event exists the moment the payment does. outbox-relay picks it up."],
          [0, 1, "The relay puts it on an SQS FIFO queue. If the relay dies mid-send, the row is still in Aurora to send again."],
          [0, 2, "webhook-sender takes it off the queue and signs it. Failed tries go back on the queue; too many, and it waits in the dead-letter queue for replay."],
          [0, 3, "The merchant gets payment.succeeded at least once. merchant-sim deduplicates by event id, and counts."],
          [1, 0, "The delivery table in Aurora marks it delivered. If Tokyo is lost, Osaka re-sends every event not marked yet."],
        ],
      },
      recon: {
        start: "n-bank",
        lanes: [{ edges: ["e-bank-recon"] }, { after: 1, edges: ["e-db-recon"] }],
        captions: [
          [0, 0, "Every night the mock bank drops a settlement file in S3: every top-up the bank actually saw."],
          [1, 0, "reconcile reads the ledger from Aurora. All entries must sum to ¥0 and every top-up must match the bank; any difference raises an alert."],
        ],
      },
      dr: {
        start: "n-aurora",
        lanes: [{ edges: ["e-db-vault"] }, { after: 1, edges: ["e-db-global"] }],
        extra: { "e-db-global": ["n-pilot"] },
        captions: [
          [0, 0, "AWS Backup snapshots Aurora every hour and copies each recovery point to a Vault-Locked vault in a separate account in Osaka."],
          [1, 0, "On DR days, Aurora Global Database keeps a secondary in Osaka, with a pilot-light EKS cluster synced by Argo CD beside it."],
        ],
      },
    };
    const END_NODE = {
      "e-client-alb": "n-alb", "e-alb-api": "n-api", "e-api-writer": "n-writer", "e-writer-reader": "n-reader",
      "e-api-client": "n-client", "e-db-relay": "n-relay", "e-relay-sqs": "n-sqs", "e-sqs-sender": "n-sender",
      "e-sender-merchant": "n-merchant", "e-sender-db": "n-writer", "e-bank-recon": "n-recon", "e-db-recon": "n-recon",
      "e-db-global": "n-global", "e-db-vault": "n-vault",
    };
    // What a packet sounds like when it reaches each node. Nodes not listed get the next step of the melody.
    const ACCENT = {
      "n-writer": "commit", "n-reader": "blip", "n-client": "ack", "n-sqs": "queue", "n-merchant": "arrive",
      "n-global": "osaka", "n-vault": "vault", "n-bank": "blip",
    };

    let current = "pay";
    let plan = null;
    let packets = [];
    let t0 = null;
    let raf = 0;
    let running = false;
    let shownCaption = -1;
    let reached = new Set();

    function build(name) {
      const trace = TRACES[name];
      const lanes = trace.lanes.map((lane) => {
        const segs = [];
        let t = 0;
        lane.edges.forEach((id) => {
          const path = document.getElementById(id);
          const len = path.getTotalLength();
          segs.push({ id, path, len, start: t, end: t + len / SPEED });
          t += len / SPEED + DWELL;
        });
        return { segs, offset: 0, after: lane.after || 0, delay: lane.delay || 0 };
      });
      lanes.forEach((lane, li) => {
        if (li === 0) return;
        lane.offset = (lane.after ? lanes[0].segs[lane.after - 1].end + DWELL : 0) + lane.delay;
      });
      const segsAbs = [];
      lanes.forEach((lane, li) =>
        lane.segs.forEach((s, si) => segsAbs.push({ ...s, lane: li, index: si, start: s.start + lane.offset, end: s.end + lane.offset })),
      );
      const captions = trace.captions
        .map(([li, si, text]) => ({ at: lanes[li].offset + lanes[li].segs[si].start, text }))
        .sort((a, b) => a.at - b.at);
      const total = Math.max(...segsAbs.map((s) => s.end)) + 2;
      return { lanes, segsAbs, captions, total, start: trace.start, extra: trace.extra || {} };
    }

    function dim(name) {
      arch.querySelectorAll(".node, .edges path, .edge-labels text").forEach((el) => {
        const t = (el.getAttribute("data-t") || "").split(" ");
        el.classList.toggle("dim", !t.includes(name));
      });
    }

    function lightEnd(seg) {
      const ids = [END_NODE[seg.id], ...(plan.extra[seg.id] || [])];
      ids.forEach((id) => {
        const node = document.getElementById(id);
        if (node) node.classList.add("lit");
      });
    }

    function reset() {
      arch.querySelectorAll(".lit").forEach((el) => el.classList.remove("lit"));
      arch.querySelectorAll(".edges path").forEach((p) => p.setAttribute("marker-end", "url(#arrow)"));
      packets.forEach((p) => p.remove());
      packets = plan.lanes.map(() => svgEl("circle", { class: "packet", r: 6.5, opacity: 0 }, packetsG));
      document.getElementById(plan.start).classList.add("lit");
      shownCaption = -1;
      reached = new Set();
      t0 = null;
    }

    function setCaption(i) {
      const c = plan.captions[i];
      if (!c) return;
      traceText.classList.add("swap");
      setTimeout(() => {
        traceText.textContent = c.text;
        traceText.classList.remove("swap");
      }, 180);
      traceStep.textContent = `${i + 1} / ${plan.captions.length}`;
    }

    let lastT = 0;
    function frame(now) {
      if (t0 === null) t0 = now;
      const t = ((now - t0) / 1000) % plan.total;
      if (t < lastT) {
        // a new cycle
        const keep = t0;
        reset();
        t0 = keep;
        sound.play("resolve", 2000);
      }
      lastT = t;
      plan.segsAbs.forEach((s) => {
        const packet = packets[s.lane];
        if (t >= s.start && t <= s.end) {
          const pt = s.path.getPointAtLength(((t - s.start) / (s.end - s.start)) * s.len);
          packet.setAttribute("cx", pt.x.toFixed(1));
          packet.setAttribute("cy", pt.y.toFixed(1));
          packet.setAttribute("opacity", "1");
          if (!s.path.classList.contains("lit")) {
            s.path.classList.add("lit");
            s.path.setAttribute("marker-end", `url(#arrow-${current})`);
          }
        }
        const key = `${s.lane}:${s.index}`;
        if (t > s.end && !reached.has(key)) {
          reached.add(key);
          lightEnd(s);
          const accent = ACCENT[END_NODE[s.id]];
          if (accent) sound.play(accent, 150);
          else sound.hop(s.index + (s.lane ? plan.lanes[s.lane].after : 0), current === "event");
        }
      });
      // hide packets whose lane is between segments or finished
      plan.lanes.forEach((lane, li) => {
        const active = lane.segs.some((s) => t >= s.start + lane.offset && t <= s.end + lane.offset);
        if (!active) packets[li].setAttribute("opacity", "0");
      });
      let ci = -1;
      plan.captions.forEach((c, i) => {
        if (t >= c.at) ci = i;
      });
      if (ci !== shownCaption && ci >= 0) {
        shownCaption = ci;
        setCaption(ci);
      }
      raf = requestAnimationFrame(frame);
    }

    function select(name) {
      current = name;
      arch.dataset.trace = name;
      arch.style.setProperty("--trace", COLOR[name]);
      caption.style.setProperty("--trace", COLOR[name]);
      document.querySelectorAll(".trace-btn").forEach((b) => b.setAttribute("aria-selected", String(b.dataset.trace === name)));
      plan = build(name);
      dim(name);
      reset();
      lastT = 0;
      setCaption(0);
      shownCaption = 0;
      if (reducedMotion) {
        // Static: light the whole trace and show the first caption.
        plan.segsAbs.forEach((s) => {
          s.path.classList.add("lit");
          s.path.setAttribute("marker-end", `url(#arrow-${name})`);
          lightEnd(s);
        });
      }
    }

    document.querySelectorAll(".trace-btn").forEach((b) =>
      b.addEventListener("click", () => {
        if (b.dataset.trace === current) return;
        select(b.dataset.trace);
        sound.play("sweep", 300);
      }),
    );
    select("pay");

    if (!reducedMotion) {
      whileVisible(
        arch,
        () => {
          if (running) return;
          running = true;
          t0 = null;
          lastT = 0;
          reset();
          raf = requestAnimationFrame(frame);
        },
        () => {
          running = false;
          cancelAnimationFrame(raf);
        },
        0.2,
      );
    }
  }

  // ------------------------------------------------------------------ The lost-payment check, as an example
  const diff = document.getElementById("diff");
  if (diff) {
    const btns = Array.from(diff.querySelectorAll("[data-mode]")).filter((el) => el.tagName === "BUTTON");
    btns.forEach((b) =>
      b.addEventListener("click", () => {
        if (diff.dataset.mode === b.dataset.mode) return;
        diff.dataset.mode = b.dataset.mode;
        btns.forEach((x) => x.setAttribute("aria-pressed", String(x === b)));
        sound.play(b.dataset.mode === "fail" ? "alert" : "resolve", 300);
      }),
    );
  }

  // ------------------------------------------------------------------ Drills
  const DRILLS = {
    1: {
      title: "Kill pods mid-traffic", phase: 1, status: "template",
      models: "The everyday failure: pods crash and nodes get replaced",
      inject: "FIS aws:eks:pod-delete on api, outbox-relay and webhook-sender pods",
      pass: "0 lost; no duplicate effects at the merchant",
      answer: "Clients get a few errors and retry with the same key. Disruption budgets keep enough api pods up, and a relay or sender that dies mid-send leaves its row or message to be picked up again.",
      state: { api: "degraded", workers: "degraded" },
    },
    2: {
      title: "Merchant down for 30 minutes", phase: 0, status: "local",
      models: "A merchant's endpoint that stops answering",
      inject: "merchant-sim returns 503 for 30 minutes",
      pass: "Retries, DLQ and replay: every event takes effect once",
      answer: "Deliveries fail and go back on the queue. Events that run out of tries wait in the dead-letter queue, replay sends them when the merchant is back, and merchant-sim's event-id check means each takes effect once.",
      state: { merchant: "down", sqs: "degraded", workers: "degraded" },
    },
    3: {
      title: "Deploy, drain and upgrade under load", phase: 1, status: "planned",
      models: "The changes a team makes every week",
      inject: "Rollout restart, Karpenter consolidation, an EKS version upgrade",
      pass: "0 non-2xx responses",
      answer: "Readiness fails before a pod stops, in-flight requests drain within 20 seconds, and disruption budgets stop a drain from taking too many pods at once. The target is no failed request at all.",
      state: { api: "degraded" },
    },
    4: {
      title: "Lose a Tokyo AZ", phase: 1, status: "template",
      models: "The 2019 apne1-az4 cooling failure",
      inject: "FIS AZ Power Interruption (shortened) and zonal autoshift, plus a gray-failure variant",
      pass: "0 lost; errors < 1 % for < 2 min; no new nodes needed",
      answer: "The load balancer and zonal autoshift move traffic out of the AZ, Aurora promotes the reader if the writer was there, and pods already running in the other two AZs carry the load.",
      state: { api: "degraded", aurora: "degraded", workers: "degraded" },
    },
    5: {
      title: "Database failover", phase: 1, status: "template",
      models: "A writer that disappears while clients retry",
      inject: "FIS aws:rds:failover-db-cluster, with clients retrying the same keys",
      pass: "0 lost; one payment per key; writer back ≤ 60 s",
      answer: "For a short window requests get 503 database_unavailable with Retry-After, and pods stay ready through the grace period. That half already works today. Retries with the same key find the saved response, so each key stays one payment.",
      state: { aurora: "down", api: "degraded" },
    },
    6: {
      title: "Someone runs DELETE on the ledger", phase: 2, status: "planned",
      models: "A bad query, a bad script, a bad day",
      inject: "Aurora point-in-time restore, then reconciliation",
      pass: "RPO ≤ 5 min, RTO ≤ 60 min, ledger sums to 0",
      answer: "Aurora restores to a moment just before the DELETE, and reconciliation proves the restored ledger is whole and still sums to ¥0.",
      state: { aurora: "down" },
    },
    7: {
      title: "Whole cluster lost", phase: 2, status: "planned",
      models: "A cluster deleted, or broken beyond repair",
      inject: "Rebuild with Argo CD and AWS Backup for EKS (compared with Velero)",
      pass: "Back in ≤ 30 min",
      answer: "Argo CD rebuilds every workload from git into a new cluster, and AWS Backup for EKS restores what git doesn't hold. The payments themselves never lived in the cluster.",
      state: { api: "down", workers: "down" },
    },
    8: {
      title: "Ransomware tries to delete the backups", phase: 2, status: "planned",
      models: "The Askul ransomware attack, 2025",
      inject: "An admin role in the production account tries to delete recovery points",
      pass: "0 recovery points deleted; restore time measured",
      answer: "Backups live in another account's vault with Vault Lock, so even an administrator in the production account cannot delete a recovery point. The drill tries anyway, then times a restore.",
      state: { backups: "degraded" },
    },
    9: {
      title: "Planned move to Osaka", phase: 3, status: "planned",
      models: "A planned region switch",
      inject: "Aurora Global switchover, Argo CD and Route 53",
      pass: "RPO 0; ≤ 30 min end to end",
      answer: "A planned Global Database switchover loses nothing. Argo CD brings the Osaka pilot light up, and Route 53 moves the traffic.",
      state: { region: "degraded" },
    },
    10: {
      title: "Tokyo region lost", phase: 3, status: "planned",
      models: "A whole region that stops answering",
      inject: "FIS cross-region connectivity, then an unplanned global failover",
      pass: "Lost payments counted, then all recovered from the snapshot; ≤ 30 min",
      answer: "A person decides to fail over, and the decision is logged. Osaka is promoted. Payments acknowledged in the last moments may be missing, so they are counted, then recovered from the failover snapshot, and the Osaka relay re-sends every undelivered event.",
      state: { region: "down", api: "down", aurora: "down" },
    },
    11: {
      title: "One bad release breaks both regions", phase: 3, status: "planned",
      models: "The Zengin system outage, 2023",
      inject: "Promote a broken config",
      pass: "Osaka never receives it; rollback to the last good version",
      answer: "A release must never reach both regions at once. The drill promotes a broken config, checks that Osaka never gets it, and rolls Tokyo back to the last good version.",
      state: { api: "down", region: "degraded" },
    },
    12: {
      title: "Month-end peak with a batch job", phase: 1, status: "planned",
      models: "The Mizuho outages, 2021",
      inject: "k6 at 3–5× normal load while reconciliation runs",
      pass: "The payment SLO holds; the batch job slows down instead",
      answer: "Payments keep priority. The payment SLO must hold while load triples and reconciliation runs, and the batch job is the one that waits.",
      state: { api: "degraded", aurora: "degraded" },
    },
  };
  const STATUS = {
    template: ["pill pill-wip", "FIS template written"],
    local: ["pill pill-next", "Runs locally next"],
    planned: ["pill pill-plan", "Planned"],
  };
  const drillBtns = Array.from(document.querySelectorAll(".drill-list button"));
  if (drillBtns.length) {
    const panel = document.querySelector(".drill-panel");
    const chain = Array.from(document.querySelectorAll(".drill-panel .gd-chain li"));
    const el = (id) => document.getElementById(id);
    const list = document.querySelector(".drill-list");
    const show = (n, withSound) => {
      const d = DRILLS[n];
      drillBtns.forEach((b) => b.setAttribute("aria-selected", String(b.dataset.drill === String(n))));
      // On narrow screens the list is one swipeable row: bring the chosen drill into it, without moving the page.
      if (stacked.matches) {
        const delta = drillBtns[n - 1].getBoundingClientRect().left - list.getBoundingClientRect().left - 16;
        list.scrollTo({ left: list.scrollLeft + delta, behavior: withSound && !reducedMotion ? "smooth" : "auto" });
      }
      chain.forEach((li) => li.setAttribute("data-state", d.state[li.dataset.c] || "ok"));
      panel.classList.add("swap");
      setTimeout(() => {
        el("d-title").textContent = `Drill ${n} · ${d.title}`;
        el("d-phase").textContent = `Phase ${d.phase}`;
        el("d-status").className = STATUS[d.status][0];
        el("d-status").textContent = STATUS[d.status][1];
        el("d-models").textContent = d.models;
        el("d-inject").textContent = d.inject;
        el("d-pass").textContent = d.pass;
        el("d-answer").textContent = d.answer;
        el("d-result").textContent = d.status === "template" ? "Not run yet · the experiment is written and checked" : "Not run yet";
        panel.classList.remove("swap");
      }, 160);
      if (withSound) {
        sound.play("alert", 300);
        setTimeout(() => sound.play("handled", 300), 700);
      }
    };
    drillBtns.forEach((b) => b.addEventListener("click", () => show(Number(b.dataset.drill), true)));
    show(4, false);
  }

  // ------------------------------------------------------------------ Counters
  // The HTML holds the final values (so the page reads right without JavaScript); they count up from zero.
  const counters = Array.from(document.querySelectorAll("[data-count]"));
  const counterFmt = (el, n) => {
    const decimals = Number(el.dataset.decimals || 0);
    return (el.dataset.prefix || "") + n.toLocaleString("en-US", { minimumFractionDigits: decimals, maximumFractionDigits: decimals }) + (el.dataset.suffix || "");
  };
  if (!reducedMotion && "IntersectionObserver" in window) counters.forEach((el) => (el.textContent = counterFmt(el, 0)));
  const runCounter = (el) => {
    const target = Number(el.dataset.count);
    const decimals = Number(el.dataset.decimals || 0);
    const fmt = (n) => counterFmt(el, n);
    if (reducedMotion) {
      el.textContent = fmt(target);
      return;
    }
    const start = performance.now();
    const dur = 1400;
    const step = (now) => {
      const t = clamp((now - start) / dur, 0, 1);
      el.textContent = fmt(decimals ? target * easeOut(t) : Math.round(target * easeOut(t)));
      if (t < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  };
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (!e.isIntersecting) return;
          runCounter(e.target);
          sound.play("count", 4000);
          io.unobserve(e.target);
        });
      },
      { threshold: 0.4 },
    );
    counters.forEach((el) => io.observe(el));
  } else {
    counters.forEach(runCounter);
  }
})();
