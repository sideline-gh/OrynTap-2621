// =====================================================================
// OrynTap — user interface
// Hash routes: #/home  #/map  #/favourites  #/profile  #/checkin/<spaceId>
// =====================================================================
(function () {
  "use strict";

  const $ = (sel, root = document) => root.querySelector(sel);
  const esc = (s) => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const MIN = 60e3, HOUR = 3600e3;
  const t = (k, v) => window.I18N.t(k, v);
  const LS = {
    get(k, d) { try { const v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} },
    del(k) { try { localStorage.removeItem(k); } catch (e) {} },
  };

  // ---------------- icons ----------------
  const I = {
    homeLine: '<svg class="i-line" viewBox="0 0 40 40" aria-hidden="true"><path d="M7 17.5 20 7l13 10.5V33a1.5 1.5 0 0 1-1.5 1.5H8.5A1.5 1.5 0 0 1 7 33z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/><path d="M16.5 34.5V25a1 1 0 0 1 1-1h5a1 1 0 0 1 1 1v9.5" fill="none" stroke="currentColor" stroke-width="1.8"/></svg>',
    homeFill: '<svg class="i-fill" viewBox="0 0 40 40" aria-hidden="true"><path d="M7 17.5 20 7l13 10.5V33a1.5 1.5 0 0 1-1.5 1.5H24V25.5a1.5 1.5 0 0 0-1.5-1.5h-5a1.5 1.5 0 0 0-1.5 1.5v9H8.5A1.5 1.5 0 0 1 7 33z" fill="currentColor"/></svg>',
    mapLine: '<svg class="i-line" viewBox="0 0 40 40" aria-hidden="true"><path d="M20 5a10 10 0 0 0-10 10c0 7.5 10 17 10 17s10-9.5 10-17A10 10 0 0 0 20 5z" fill="none" stroke="currentColor" stroke-width="1.8"/><circle cx="20" cy="15" r="4" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M12.5 29.5C8.7 30.3 6.5 31.6 6.5 33c0 2.2 6 4 13.5 4s13.5-1.8 13.5-4c0-1.4-2.2-2.7-6-3.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
    mapFill: '<svg class="i-fill" viewBox="0 0 40 40" aria-hidden="true"><path fill="currentColor" fill-rule="evenodd" d="M20 4a11 11 0 0 0-11 11c0 8 11 18 11 18s11-10 11-18A11 11 0 0 0 20 4zm0 6.5a4.5 4.5 0 1 1 0 9 4.5 4.5 0 0 1 0-9z"/><path d="M12.5 29.5C8.7 30.3 6.5 31.6 6.5 33c0 2.2 6 4 13.5 4s13.5-1.8 13.5-4c0-1.4-2.2-2.7-6-3.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
    heartLine: '<svg class="i-line" viewBox="0 0 40 40" aria-hidden="true"><path d="M20 33S5 24.5 5 14.5A7.5 7.5 0 0 1 20 11a7.5 7.5 0 0 1 15 3.5C35 24.5 20 33 20 33z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg>',
    heartFill: '<svg class="i-fill" viewBox="0 0 40 40" aria-hidden="true"><path d="M20 33S5 24.5 5 14.5A7.5 7.5 0 0 1 20 11a7.5 7.5 0 0 1 15 3.5C35 24.5 20 33 20 33z" fill="currentColor"/></svg>',
    userLine: '<svg class="i-line" viewBox="0 0 40 40" aria-hidden="true"><circle cx="20" cy="12" r="6.5" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M7.5 35v-3.5c0-5 4-9 9-9h7c5 0 9 4 9 9V35z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/></svg>',
    userFill: '<svg class="i-fill" viewBox="0 0 40 40" aria-hidden="true"><circle cx="20" cy="12" r="7" fill="currentColor"/><path d="M7 35v-3.5c0-5.2 4.3-9.5 9.5-9.5h7c5.2 0 9.5 4.3 9.5 9.5V35z" fill="currentColor"/></svg>',
    sun: '<svg viewBox="0 0 32 32" aria-hidden="true"><circle cx="16" cy="16" r="6" fill="currentColor"/><g stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-dasharray="2 3"><path d="M16 2v4M16 26v4M2 16h4M26 16h4M6 6l2.8 2.8M23.2 23.2 26 26M6 26l2.8-2.8M23.2 8.8 26 6"/></g></svg>',
    moon: '<svg viewBox="0 0 32 32" aria-hidden="true"><path d="M20.5 4.5A12 12 0 1 0 27.5 22 10 10 0 0 1 20.5 4.5z" fill="currentColor"/></svg>',
    sensor: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 13.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3zM8.5 8.5a5 5 0 0 0 0 7M15.5 8.5a5 5 0 0 1 0 7M5.6 5.6a9 9 0 0 0 0 12.8M18.4 5.6a9 9 0 0 1 0 12.8" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>',
    play: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 4.5v15l13-7.5z"/></svg>',
    x: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>',
    bell: '<svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"/></svg>',
    bellOff: '<svg class="ico" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0M4 4l16 16" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round" stroke-linecap="round"/></svg>',
    pin: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 2a7 7 0 0 0-7 7c0 5.3 7 13 7 13s7-7.7 7-13a7 7 0 0 0-7-7zm0 9.5A2.5 2.5 0 1 1 12 6.5a2.5 2.5 0 0 1 0 5z"/></svg>',
  };
  const heartIcon = (on) => on ? I.heartFill.replace('class="i-fill"', "") : I.heartLine.replace('class="i-line"', "");

  // ---------------- time & status ----------------
  const TZ_OFFSET = 5 * HOUR; // Astana, UTC+5 (all of Kazakhstan since March 2024)
  const DAYS = () => t("days");
  function astana(now = Date.now()) {
    const d = new Date(now + TZ_OFFSET);
    return { wd: ((d.getUTCDay() + 6) % 7) + 1, min: d.getUTCHours() * 60 + d.getUTCMinutes() };
  }
  const toMin = (t) => { const [h, m] = String(t).split(":").map(Number); return h * 60 + m; };
  const hhmm = (t) => (t === "24:00" ? "00:00" : String(t).slice(0, 5));

  // Returns {state: open|soon|closed, label, detail}
  function statusOf(space, now = Date.now()) {
    const hours = space.hours || [];
    const { wd, min } = astana(now);
    const byDay = {}; hours.forEach(h => { byDay[h.weekday] = h; });
    const is247 = hours.length === 7 && hours.every(h => hhmm(h.opens) === "00:00" && h.closes.startsWith("24"));
    if (is247) return { state: "open", label: t("st_open"), detail: t("st_247") };
    const today = byDay[wd];
    if (today) {
      const o = toMin(today.opens), c = toMin(today.closes);
      if (min >= o && min < c) {
        const left = c - min;
        return { state: left <= 60 ? "soon" : "open", label: t(left <= 60 ? "st_soon" : "st_open"), detail: t("closes_at", { t: hhmm(today.closes) }) };
      }
      if (min < o) return { state: "closed", label: t("st_closed"), detail: t("opens_at", { t: hhmm(today.opens) }) };
    }
    for (let i = 1; i <= 7; i++) {
      const d = ((wd - 1 + i) % 7) + 1;
      if (byDay[d]) return { state: "closed", label: t("st_closed"), detail: i === 1 ? t("opens_tomorrow", { t: hhmm(byDay[d].opens) }) : t("opens_day", { d: DAYS()[d], t: hhmm(byDay[d].opens) }) };
    }
    return { state: "closed", label: t("st_closed"), detail: t("temp_closed") };
  }
  // Closing time today (ms) if the place is open now; null if it is closed now or open around the
  // clock. A check-in never lasts past it (same rule as closing_time() in the database).
  function closingTime(space, now = Date.now()) {
    const hours = space.hours || [];
    if (hours.length === 7 && hours.every(h => hhmm(h.opens) === "00:00" && h.closes.startsWith("24"))) return null;
    const { wd, min } = astana(now);
    const h = hours.find(x => x.weekday === wd); if (!h) return null;
    const o = toMin(h.opens), c = toMin(h.closes);
    if (min < o || min >= c || c >= 24 * 60) return null;
    return now - (now % MIN) + (c - min) * MIN;
  }
  const clock = (ms) => { const d = new Date(ms + TZ_OFFSET); return `${String(d.getUTCHours()).padStart(2, "0")}:${String(d.getUTCMinutes()).padStart(2, "0")}`; };
  function agoText(iso) {
    const m = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / MIN));
    if (m < 1) return t("just_now");
    if (m < 60) return t("ago_min", { n: m });
    if (m < 60 * 24) return t("ago_h", { n: Math.round(m / 60) });
    return t("ago_d", { n: Math.round(m / 1440) });
  }
  const ago = (iso) => t("updated", { ago: agoText(iso) });
  const fmtLeft = (ms) => {
    const s = Math.max(0, Math.round(ms / 1000)), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), ss = s % 60;
    return h ? t("fmt_hm", { h, m: String(m).padStart(2, "0") }) : `${m}:${String(ss).padStart(2, "0")}`;
  };

  window.App = { statusOf, closingTime };

  // ---------------- state ----------------
  const state = {
    store: null, unis: [], uniId: LS.get("oryntap.uni", null),
    spaces: [], favSpaces: [], session: null, active: null, favs: new Set(),
    filters: new Set(LS.get("oryntap.filters", [])),
    route: "home", editing: false, authMode: LS.get("oryntap.verify", null) ? "verify" : "login", loading: true,
    drafts: {},   // (verify step: see showVerify)
    verify: LS.get("oryntap.verify", null),   // {email} while an account waits for e-mail confirmation   // what the user typed in the sign-up / login / profile forms (see keepForms)
    offlineSince: null, pomodoro: null, sensor: {}, sound: LS.get("oryntap.sound", false),
    sortBest: LS.get("oryntap.sortBest", false),   // "Best right now" order on Home
    watch: LS.get("oryntap.watch", {}),            // {spaceId: until (ms)}: tell me when a seat is free
    busy: {}, busyOpen: new Set(),                 // "usually busy" data per university
    recovery: sessionStorage.getItem("oryntap.recovery") === "1",   // came from a password reset link
  };
  const isAdmin = () => state.session && state.session.profile.role === "admin";
  const uni = () => state.unis.find(u => u.id === state.uniId);

  // ---------------- toasts ----------------
  function toast(msg, err) {
    const t = document.createElement("div");
    t.className = "toast" + (err ? " err" : ""); t.textContent = msg;
    $("#toasts").appendChild(t);
    setTimeout(() => t.remove(), err ? 6000 : 3500);
  }
  const fail = (e) => { console.error(e); toast(e && e.message ? e.message : t("went_wrong"), true); };

  // ---------------- theme ----------------
  function paintTheme() {
    const dark = document.documentElement.getAttribute("data-theme") === "dark";
    $("#themeKnob").innerHTML = dark ? I.moon : I.sun;
    $("#themeBtn").setAttribute("aria-label", t(dark ? "theme_light" : "theme_dark"));
    document.querySelector('meta[name="theme-color"]').setAttribute("content", dark ? "#2a2d31" : "#ffffff");
  }
  $("#themeBtn").addEventListener("click", () => {
    const next = document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", next);
    try { localStorage.setItem("oryntap.theme", next); } catch (e) {}
    paintTheme();
  });

  // ---------------- language ----------------
  function paintStatic() {
    const sel = $("#langSel");
    sel.innerHTML = window.I18N.LANGS.map(l => `<option value="${l}" ${l === window.I18N.lang ? "selected" : ""}>${window.I18N.label(l)}</option>`).join("");
    sel.setAttribute("aria-label", t("lang_label"));
    $("#skipLink").textContent = t("skip");
    paintTheme();
  }
  $("#langSel").addEventListener("change", (e) => {
    window.I18N.setLang(e.target.value);
    paintStatic(); paintUniPicker(); render();
  });

  // ---------------- university picker ----------------
  function paintUniPicker() {
    const u = uni();
    $("#uniLabel").innerHTML = u ? `<span class="full">${esc(u.name)}</span><span class="short-only">${esc(u.short)}</span>` : esc(t("choose_uni"));
    $("#uniMenu").innerHTML = state.unis.map(x =>
      `<li><button role="option" aria-checked="${x.id === state.uniId}" data-uni="${x.id}"><span class="code">${esc(x.short)}</span><span>${esc(x.name)}</span></button></li>`).join("");
  }
  function toggleMenu(open) {
    const m = $("#uniMenu"); const show = open == null ? m.hidden : open;
    m.hidden = !show; $("#uniBtn").setAttribute("aria-expanded", String(show));
  }
  $("#uniBtn").addEventListener("click", (e) => { e.stopPropagation(); toggleMenu(); });
  document.addEventListener("click", (e) => { if (!e.target.closest(".uni-picker")) toggleMenu(false); });
  $("#uniMenu").addEventListener("click", (e) => {
    const b = e.target.closest("[data-uni]"); if (!b) return;
    selectUni(Number(b.dataset.uni)); toggleMenu(false);
  });
  async function selectUni(id) {
    state.uniId = id; LS.set("oryntap.uni", id);
    paintUniPicker(); state.loading = true; render();
    await refresh();
  }

  // ---------------- navigation ----------------
  function navItems() {
    const items = [
      { r: "home", label: t("nav_home"), short: t("nav_home"), line: I.homeLine, fill: I.homeFill },
      { r: "map", label: t("nav_map"), short: t("nav_map_short"), line: I.mapLine, fill: I.mapFill },
      { r: "favourites", label: t("nav_fav"), short: t("nav_fav"), line: I.heartLine, fill: I.heartFill },
      { r: "profile", label: t("nav_profile"), short: t("nav_profile"), line: I.userLine, fill: I.userFill },
    ];
    return isAdmin() ? items.filter(i => i.r !== "favourites") : items;
  }
  function paintNav() {
    const items = navItems();
    const html = items.map(i => `<li><a href="#/${i.r}" ${state.route === i.r ? 'aria-current="page"' : ""}>${i.line}${i.fill}<span>${i.label}</span></a></li>`).join("");
    $("#nav").innerHTML = html;
    $("#tabbar").innerHTML = items.map(i => `<a href="#/${i.r}" ${state.route === i.r ? 'aria-current="page"' : ""}>${i.line}${i.fill}<span>${i.short}</span></a>`).join("");
    $("#tabbar").style.setProperty("--tabs", items.length);
  }

  // ---------------- data ----------------
  const cacheKey = () => "oryntap.cache." + state.uniId;
  // quiet = a background refresh (timer, Realtime, back online), not something the user just did
  async function refresh(opts = {}) {
    const st = state.store;
    const hadSession = !!state.session;
    try {
      state.session = await st.getSession();
      if (state.uniId == null || !state.unis.some(u => u.id === state.uniId)) {
        state.uniId = state.session ? state.session.profile.university_id : state.unis[0].id;
        LS.set("oryntap.uni", state.uniId);
      }
      const [spaces, active, favs, sensor] = await Promise.all([
        st.getSpaces(state.uniId),
        state.session ? st.getActiveCheckIn() : null,
        state.session && !isAdmin() ? st.getFavourites() : [],
        st.getSensorNow ? st.getSensorNow().catch(() => ({})) : {},
        loadBusy(state.uniId),
      ]);
      state.spaces = spaces; state.active = active; state.favs = new Set(favs); state.sensor = sensor || {};
      // Name of the place where the student is checked in, even if it is not in the current list
      if (active && !spaces.some(s => s.id === active.space_id) && (!state.activeSpace || state.activeSpace.id !== active.space_id)) {
        state.activeSpace = (await st.getSpacesByIds([active.space_id]).catch(() => []))[0] || null;
      }
      state.favSpaces = state.route === "favourites" && favs.length ? await st.getSpacesByIds(favs) : state.favSpaces.filter(s => favs.includes(s.id));
      state.offlineSince = null;
      checkWatch();
      LS.set(cacheKey(), { at: Date.now(), spaces });
    } catch (e) {
      console.warn("[OrynTap] refresh failed", e);
      const cache = LS.get(cacheKey(), null);
      if (cache) { state.spaces = cache.spaces; state.offlineSince = cache.at; }
      else if (!state.spaces.length) toast(t("cant_load"), true);
    }
    state.loading = false;
    if (state.session && state.verify) setVerify(null);
    paintUniPicker();
    // A form on screen (sign-up, login, profile) shows no live data, so a background refresh only
    // updates the header and the menu. Re-rendering would rebuild the inputs and, on phones, close
    // the keyboard. If the login state changed in the background, the page must change: render.
    if (opts.quiet && $("#view form[data-keep]") && hadSession === !!state.session) { paintNav(); return; }
    render();
  }

  // ---------------- views ----------------
  function render() {
    paintNav();
    const v = $("#view");
    const views = { home: viewHome, map: viewMap, favourites: viewFavourites, profile: viewProfile };
    const focus = focusedField();
    v.innerHTML = (views[state.route] || viewHome)();
    keepForms(v, focus);
    afterRender();
  }

  // ---------------- form state ----------------
  // render() rebuilds the page from templates, so the inputs of a form are new, empty elements
  // after every render. That used to delete what a student had typed into the sign-up form
  // whenever the page refreshed in the background. Now every form marked data-keep="<key>"
  // stores its values in state.drafts[<key>] while the user types (listener below), and
  // keepForms() puts them back, together with the cursor, after each render.
  // Drafts live only in memory (never in localStorage) and are cleared when the form is
  // completed (registered, logged in, profile saved) or cancelled on purpose.
  function focusedField() {
    const a = document.activeElement;
    if (!a || !a.form || !a.form.dataset.keep || !a.name) return null;
    let start = null, end = null;
    try { start = a.selectionStart; end = a.selectionEnd; } catch (e) { /* checkbox: no cursor */ }
    return { key: a.form.dataset.keep, name: a.name, start, end };
  }
  function keepForms(root, focus) {
    root.querySelectorAll("form[data-keep]").forEach(f => {
      const d = state.drafts[f.dataset.keep]; if (!d) return;
      for (const [name, val] of Object.entries(d)) {
        const el = f.elements.namedItem(name); if (!el || !el.tagName) continue;
        if (el.type === "checkbox") el.checked = !!val; else el.value = val;
      }
    });
    if (!focus) return;
    const f = root.querySelector(`form[data-keep="${focus.key}"]`);
    const el = f && f.elements.namedItem(focus.name);
    if (!el || !el.focus) return;
    el.focus({ preventScroll: true });
    if (focus.start != null) { try { el.setSelectionRange(focus.start, focus.end); } catch (e) {} }
  }
  function rememberField(e) {
    const el = e.target, f = el && el.form;
    if (!f || !f.dataset.keep || !el.name) return;
    (state.drafts[f.dataset.keep] = state.drafts[f.dataset.keep] || {})[el.name] = el.type === "checkbox" ? el.checked : el.value;
  }
  $("#view").addEventListener("input", rememberField);
  $("#view").addEventListener("change", rememberField);

  function modeBanner() {
    let html = "";
    if (state.offlineSince) html += `<div class="banner warn" role="status"><strong>${esc(t("offline"))}</strong>: ${esc(t("offline_text", { ago: agoText(new Date(state.offlineSince).toISOString()) }))}</div>`;
    if (state.store.fallbackReason) html += `<div class="banner warn">${esc(t("fallback"))} <span class="muted">(${esc(state.store.fallbackReason)})</span></div>`;
    return html;
  }

  function sessionBanner() {
    const a = state.active; if (!a) return "";
    const s = state.spaces.find(x => x.id === a.space_id) || state.favSpaces.find(x => x.id === a.space_id) || (state.activeSpace && state.activeSpace.id === a.space_id ? state.activeSpace : null);
    const name = s ? s.name : t("your_space");
    const p = state.pomodoro;
    const exp = Date.parse(a.expires_at), now = Date.now();
    const close = s ? closingTime(s, now) : null;
    const atClose = close && Math.abs(exp - close) < MIN;
    // Extend 1 h: at most 3 h ahead and never past closing time (the database checks the same)
    const next = Math.min(exp + HOUR, now + 3 * HOUR, close || Infinity);
    const canExtend = next >= exp + MIN;
    const ending = exp - now <= 10 * MIN;
    return `<section class="session${ending ? " ending" : ""}" aria-label="${esc(t("aria_session"))}">
      <div>
        <h2>${esc(t("studying_at", { n: name }))}</h2>
        <p>${t("ends_in", { t: `<span class="timer" data-until="${esc(a.expires_at)}">${fmtLeft(exp - now)}</span>` })}${atClose ? esc(t("at_closing", { t: clock(close) })) : ""}${a.uses_outlet ? esc(t("with_outlet")) : ""}${p ? ` · ${esc(t(p.phase === "focus" ? "focus" : "brk"))} <span class="timer" data-pomo>${fmtLeft(p.until - Date.now())}</span>` : ""}</p>
        ${ending ? `<p class="ending-note" role="status">${esc(t(canExtend ? "ending_note" : "ending_note_noext"))}</p>` : ""}
      </div>
      <div class="actions">
        <button class="btn small" data-act="extend" ${canExtend ? "" : `disabled title="${esc(t(atClose || (close && next >= close) ? "ext_closing" : "ext_max"))}"`}>${esc(t("btn_extend"))}</button>
        <button class="btn small" data-act="pomodoro">${esc(t(p ? "pomo_stop" : "pomo_start"))}</button>
        ${p ? `<button class="btn small" data-act="sound" aria-pressed="${state.sound}">${state.sound ? I.bell : I.bellOff}${esc(t(state.sound ? "sound_on" : "sound_off"))}</button>` : ""}
        <button class="btn small primary" data-act="leave">${esc(t("btn_leave"))}</button>
      </div>
    </section>`;
  }

  // ---------------- how-to video (time-based media) ----------------
  // A 14-second silent screen recording of the real check-in flow.
  // No autoplay, no sound track; captions in EN/RU/KK and a text version below it.
  // MP4 (H.264) only: in our test VP9/WebM was not smaller for this screen recording
  // (282 KB vs 290 KB at the same quality), and H.264 plays in every browser.
  const HOWTO = { poster: "assets/media/howto-poster.webp", thumb: "assets/media/howto-thumb.webp",
                  mp4: "assets/media/howto-checkin.mp4", dur: "0:14" };
  function howtoTeaser() {
    if (LS.get("oryntap.howto.hidden", false) || isAdmin()) return "";
    return `<section class="howto" aria-labelledby="howtoH">
      <button class="howto-thumb" data-act="howto" aria-label="${esc(t("howto_watch"))}">
        <img src="${HOWTO.thumb}" alt="" width="336" height="189" decoding="async">
        <span class="play" aria-hidden="true">${I.play}</span>
        <span class="dur" aria-hidden="true">${HOWTO.dur}</span>
      </button>
      <div><h2 id="howtoH">${esc(t("howto_title"))}</h2><p>${esc(t("howto_sub", { d: HOWTO.dur }))}</p></div>
      <button class="x" data-act="howto-hide" aria-label="${esc(t("howto_hide"))}" title="${esc(t("howto_hide"))}">${I.x}</button>
    </section>`;
  }
  function openHowTo() {
    const lang = window.I18N.lang;
    const tracks = window.I18N.LANGS.map(l => `<track kind="captions" src="assets/media/howto-checkin.${l}.vtt" srclang="${l}" label="${esc(window.I18N.label(l))}"${l === lang ? " default" : ""}>`).join("");
    openModal(`<h2>${esc(t("howto_modal"))}</h2>
      <p class="lead">${esc(t("howto_lead"))}</p>
      <div class="video-box">
        <video controls playsinline preload="metadata" poster="${HOWTO.poster}" width="1280" height="720">
          <source src="${HOWTO.mp4}" type="video/mp4">
          ${tracks}
          <p>${esc(t("video_fallback"))}</p>
        </video>
      </div>
      <details class="transcript"><summary>${esc(t("transcript"))}</summary>
        <ol>${t("howto_steps").map(x => `<li>${esc(x)}</li>`).join("")}</ol></details>
      <div class="form-actions"><button class="btn secondary" data-dismiss>${esc(t("close"))}</button></div>`,
    (m) => { m.classList.add("video-modal"); });
  }

  // ---------------- notification sound (opt-in) ----------------
  // Off by default and never played without a click first. Every chime has a
  // visual equivalent: the toast (also read by screen readers), a flashing
  // session banner and, if allowed, a system notification.
  let chime = null;
  function playChime() {
    if (!state.sound) return;
    try { if (!chime) chime = new Audio("assets/media/chime.mp3"); chime.currentTime = 0; chime.play().catch(() => {}); } catch (e) {}
  }
  function toggleSound() {
    state.sound = !state.sound; LS.set("oryntap.sound", state.sound);
    render();
    if (state.sound) { playChime(); toast(t("sound_preview")); }   // a preview, started by the user's own click
  }

  const approx = (s) => (s.counts_exact ? "" : "~");
  function stat(free, cap, label, a) {
    const pct = cap > 0 ? Math.round((free / cap) * 100) : 0;
    const lvl = cap === 0 ? "none" : pct >= 30 ? "ok" : pct >= 10 ? "mid" : "low";
    return `<div class="stat ${lvl}">
        <div class="num">${a}${free}<small> / ${cap}</small></div>
        <div class="lbl">${esc(label)}</div>
        <div class="meter" aria-hidden="true"><i style="width:${Math.min(100, pct)}%"></i></div>
      </div>`;
  }
  function factList(s, extra = "") {
    const a = approx(s);
    const tags = [];
    if (s.is_quiet) tags.push(t("tag_quiet"));
    if (s.group_work) tags.push(t("tag_group"));
    if (s.food_allowed) tags.push(t("tag_food"));
    return `<div class="stats">${stat(s.free_seats, s.seat_capacity, t("free_seats"), a)}${stat(s.free_outlets, s.outlet_capacity, t("free_outlets"), a)}</div>
      ${tags.length || extra ? `<div class="facts-row">${tags.length ? `<ul class="tags">${tags.map(x => `<li>${esc(x)}</li>`).join("")}</ul>` : ""}${extra}</div>` : ""}`;
  }
  // A logged-in student may check in only at their own university (also enforced by RLS)
  const otherUni = (s) => state.session && !isAdmin() && s.university_id !== state.session.profile.university_id;
  const uniShort = (id) => (state.unis.find(u => u.id === id) || {}).short || "";

  // Media (Assignment 4):
  //  * photos are WebP files sized for the card; width/height reserve the space (no layout shift)
  //  * the first card is the largest element on screen, so it loads at once; the rest load lazily
  //  * alt text comes from the database (image_alt); illustrations have none -> alt="" (decorative,
  //    the heading below already names the place)
  // Stage 2, Part D3: count from the (simulated) door sensor, if this space has one.
  // Fewer than 3 people is shown as "few" (privacy rule from database/07_stage2.sql).
  function sensorLine(s) {
    const r = state.sensor && state.sensor[s.id]; if (!r) return "";
    const txt = r.few ? t("sensor_few") : t("sensor_now", { n: r.people_inside });
    return `<p class="sensor">${I.sensor}<span>${esc(txt)} · ${esc(agoText(r.measured_at))}</span></p>`;
  }

  // Part D (IoT): occupancy panel on Home. Data = view space_sensor_now in Supabase, written by
  // the Python door-counter simulator (iot/sensor_sim.py). No real sensor is connected yet.
  // Refreshed every 10 s (see timers). Free seats = seats - people inside (computed in the view).
  const secAgo = (iso) => {
    const sec = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 1000));
    return sec < 60 ? t("occ_sec_ago", { n: sec }) : agoText(iso);
  };
  function occupancyPanel() {
    const rows = state.spaces.filter(s => state.sensor && state.sensor[s.id]).map(s => [s, state.sensor[s.id]]);
    if (!rows.length) return `<div id="occ" hidden></div>`;
    const blocks = rows.map(([s, r]) => {
      const cap = r.seat_capacity ?? s.seat_capacity;
      const free = r.few ? null : (r.free_seats ?? Math.max(cap - r.people_inside, 0));
      const time = new Date(r.measured_at).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
      return `<div class="occ-space">
        <h3>${esc(r.space_name || s.name)}</h3>
        <div class="stats occ-stats">
          <div class="stat"><div class="num">${r.few ? esc(t("occ_few")) : r.people_inside}</div><div class="lbl">${esc(t("occ_inside"))}</div></div>
          <div class="stat"><div class="num">${free == null ? "≥ " + (cap - 2) : free}<small> / ${cap}</small></div><div class="lbl">${esc(t("occ_free"))}</div></div>
          <div class="stat"><div class="num">${esc(time)}</div><div class="lbl">${esc(t("occ_updated"))} · <span data-since="${esc(r.measured_at)}">${esc(secAgo(r.measured_at))}</span></div></div>
        </div>
      </div>`;
    }).join("");
    return `<section class="occ" id="occ" aria-label="${esc(t("occ_title"))}">
      <div class="occ-head">${I.sensor}<h2>${esc(t("occ_title"))}</h2><span class="occ-tag">${esc(t("occ_sim"))}</span></div>
      ${blocks}
      <p class="occ-note">${esc(t("occ_note"))}</p>
    </section>`;
  }
  async function refreshOccupancy() {
    const st = state.store;
    if (!st.getSensorNow || state.route !== "home" || document.hidden) return;
    state.sensor = await st.getSensorNow().catch(() => state.sensor) || {};
    const el = $("#occ"); if (!el) return;
    el.outerHTML = occupancyPanel();
  }

  // "Usually busy": how many past check-ins (last 8 weeks) covered each hour of the day. Loaded
  // once per university and kept for 30 min. Shown only for places with at least 15 check-ins.
  async function loadBusy(uniId) {
    const st = state.store, c = state.busy[uniId];
    if (!st.getBusyHours || (c && Date.now() - c.at < 30 * MIN)) return;
    const rows = await st.getBusyHours(uniId).catch(() => null);
    if (!rows) return;
    const by = {};
    rows.forEach(r => { (by[r.space_id] = by[r.space_id] || { n: Number(r.check_ins), h: {} }).h[r.hour_of_day] = Number(r.presence); });
    state.busy[uniId] = { at: Date.now(), by };
  }
  const BUSY_HOURS = Array.from({ length: 15 }, (_, i) => i + 8);   // 08:00–22:00, like the admin chart
  function busyInfo(s) {
    const b = (state.busy[s.university_id] || {}).by; const d = b && b[s.id]; if (!d) return null;
    const max = Math.max(0, ...BUSY_HOURS.map(h => d.h[h] || 0)); if (!max) return null;
    const peak = BUSY_HOURS.reduce((a, h) => ((d.h[h] || 0) > (d.h[a] || 0) ? h : a), BUSY_HOURS[0]);
    let from = peak, to = peak + 1;                       // busiest stretch: hours within 85 % of the peak
    while (from > 8 && (d.h[from - 1] || 0) >= 0.85 * max) from--;
    while (to < 23 && (d.h[to] || 0) >= 0.85 * max) to++;
    const hour = Math.floor(astana().min / 60);
    return { d, max, from, to, n: d.n, now: hour >= from && hour < to, soon: hour === from - 1 };
  }
  function busyLine(s, st) {
    const b = busyInfo(s); if (!b) return "";
    const range = `${String(b.from).padStart(2, "0")}:00–${String(b.to).padStart(2, "0")}:00`;
    const open = st.state !== "closed";
    const txt = open && b.now ? t("busy_now", { r: range }) : open && b.soon ? t("busy_soon", { t: `${String(b.from).padStart(2, "0")}:00` }) : t("busy_usual", { r: range });
    const hot = open && (b.now || b.soon);
    return `<details class="busy" data-id="${s.id}"${state.busyOpen.has(s.id) ? " open" : ""}>
        <summary><span class="${hot ? "hot" : ""}">${esc(txt)}</span></summary>
        <div class="bars" aria-hidden="true">${BUSY_HOURS.map(h => `<span class="${h >= b.from && h < b.to ? "pk" : ""}" style="height:${Math.round(((b.d.h[h] || 0) / b.max) * 100)}%"></span>`).join("")}</div>
        <div class="bar-labels" aria-hidden="true">${BUSY_HOURS.map(h => `<span>${h % 2 ? "" : h}</span>`).join("")}</div>
        <p class="busy-src">${esc(t("busy_src", { n: b.n }))}</p>
      </details>`;
  }
  document.addEventListener("toggle", (e) => {
    const d = e.target; if (!d.classList || !d.classList.contains("busy")) return;
    const id = Number(d.dataset.id); d.open ? state.busyOpen.add(id) : state.busyOpen.delete(id);
  }, true);

  // "Tell me when a seat is free" (only while OrynTap is open: there is no push server)
  function watching(id) { const u = state.watch[id]; return !!u && u > Date.now(); }
  function toggleWatch(space) {
    if (watching(space.id)) { delete state.watch[space.id]; LS.set("oryntap.watch", state.watch); toast(t("watch_off", { n: space.name })); render(); return; }
    if ("Notification" in window && Notification.permission === "default") { try { Notification.requestPermission(); } catch (e) {} }
    state.watch[space.id] = Math.min(Date.now() + 3 * HOUR, closingTime(space) || Infinity);
    LS.set("oryntap.watch", state.watch); toast(t("watch_on", { n: space.name })); render();
  }
  function checkWatch() {
    let changed = false;
    for (const [id, until] of Object.entries(state.watch)) {
      const s = state.spaces.find(x => x.id === Number(id)) || state.favSpaces.find(x => x.id === Number(id));
      if (until <= Date.now()) { delete state.watch[id]; changed = true; continue; }
      if (s && s.free_seats > 0 && statusOf(s).state !== "closed") {
        delete state.watch[id]; changed = true;
        notify(t("watch_free", { n: s.name, f: approx(s) + s.free_seats }));
      }
    }
    if (changed) LS.set("oryntap.watch", state.watch);
  }

  // Team photos exist as <name>-480.webp and <name>-960.webp (tools/optimise_images.py). The browser
  // takes the 960 px file only for high-resolution screens; the card size and crop do not change.
  function photoSrcset(url) {
    const m = /^(.*)-480\.webp$/.exec(url || ""); if (!m) return "";
    return ` srcset="${esc(m[1])}-480.webp 480w, ${esc(m[1])}-960.webp 960w" sizes="(max-width: 720px) calc(100vw - 48px), 300px"`;
  }
  function card(s, opts = {}) {
    const st = statusOf(s);
    const here = state.active && state.active.space_id === s.id;
    const fav = state.favs.has(s.id);
    const where = [s.building, s.floor].filter(Boolean).join(" · ");
    const corner = isAdmin()
      ? (state.session.profile.university_id === s.university_id ? `<button class="edit-btn" data-act="edit" data-id="${s.id}">${esc(t("btn_edit"))}</button>` : "")
      : `<button class="heart-btn" data-act="fav" data-id="${s.id}" aria-pressed="${fav}" aria-label="${esc(t(!state.session ? "fav_login" : fav ? "fav_remove" : "fav_add", { n: s.name }))}"${state.session ? "" : ` title="${esc(t("fav_login", { n: s.name }))}"`}>${heartIcon(fav)}</button>`;
    let actions = "";
    if (isAdmin()) {
      if (state.session.profile.university_id === s.university_id) actions = `<button class="btn small" data-act="qr" data-id="${s.id}">${esc(t("btn_qr"))}</button>`;
    } else if (here) {
      actions = `<button class="btn small primary" data-act="leave">${esc(t("btn_leave"))}</button>`;
    } else if (otherUni(s)) {
      actions = `<button class="btn small" disabled>${esc(t("only_uni", { u: uniShort(s.university_id) }))}</button>`;
    } else {
      actions = `<button class="btn small ${st.state === "closed" ? "" : "primary"}" data-act="checkin" data-id="${s.id}" ${st.state === "closed" ? "disabled" : ""}>${esc(t(st.state === "closed" ? "btn_closed" : state.session ? "btn_checkin" : "btn_checkin_login"))}</button>`;
      if (s.free_seats === 0 && st.state !== "closed") {
        const on = watching(s.id);
        actions += `<button class="btn small" data-act="watch" data-id="${s.id}" aria-pressed="${on}">${on ? I.bell : I.bellOff}${esc(t(on ? "watch_btn_on" : "watch_btn"))}</button>`;
      }
    }
    // "Wrong number?": a logged-in student tells the admins what they really see there
    if (state.session && !isAdmin() && !otherUni(s)) actions += `<button class="btn link rep-btn" data-act="report" data-id="${s.id}">${esc(t("rep_btn"))}</button>`;
    const uniTag = opts.showUni ? `<p class="uni-tag">${esc((state.unis.find(u => u.id === s.university_id) || {}).name || "")}</p>` : "";
    return `<article class="card" id="space-${s.id}">
      <figure class="photo-wrap">
        <img class="photo" src="${esc(s.image_url)}"${photoSrcset(s.image_url)} alt="${esc(s.image_alt || "")}" width="640" height="400" decoding="async" ${opts.first ? 'fetchpriority="high"' : 'loading="lazy"'}
             onerror="this.onerror=null;this.src='assets/img/fallback-${esc(s.kind)}.svg';var c=this.nextElementSibling;if(c)c.remove()">
        ${s.image_credit ? `<figcaption class="credit">${esc(t("photo", { c: s.image_credit }))}</figcaption>` : ""}
      </figure>
      <div class="body">
        ${corner}
        <h3>${esc(s.name)}</h3>
        ${uniTag}
        ${here ? `<span class="here-badge">● ${esc(t("here"))}</span>` : ""}
        <p class="status"><span class="st ${st.state}">${esc(st.label)}</span><span class="sep" aria-hidden="true"></span><span>${esc(st.detail)}</span><span class="upd">${esc(ago(s.updated_at))}</span></p>
        ${where ? `<p class="where">${I.pin}<span>${esc(where)}</span></p>` : ""}
        ${sensorLine(s)}
        ${factList(s, busyLine(s, st))}
        <div class="card-actions">${actions}</div>
      </div>
    </article>`;
  }

  const FILTERS = [
    { k: "outlets", label: "f_outlets", test: s => s.free_outlets > 0 },
    { k: "quiet", label: "f_quiet", test: s => s.is_quiet },
    { k: "group", label: "f_group", test: s => s.group_work },
    { k: "food", label: "f_food", test: s => s.food_allowed },
    { k: "open", label: "f_open", test: s => statusOf(s).state !== "closed" },
  ];
  // "Best right now": half free seats, a quarter free outlets, a quarter how long it stays open
  // (up to 4 h; 24/7 places count as 4 h). Closed places always go last.
  function bestScore(s) {
    const seats = s.seat_capacity ? s.free_seats / s.seat_capacity : 0;
    const outlets = s.outlet_capacity ? s.free_outlets / s.outlet_capacity : 0;
    const close = closingTime(s);
    const open = close == null ? 4 * HOUR : close - Date.now();
    return 0.5 * seats + 0.25 * outlets + 0.25 * Math.min(1, open / (4 * HOUR));
  }
  const title = (key, accentKey) => `<h1 class="page-title">${t(key, { a: `<span class="accent">${esc(t(accentKey))}</span>` })}</h1>`;

  function viewHome() {
    const chips = `<button class="chip sort-chip" data-act="sort-best" aria-pressed="${state.sortBest}">${esc(t("sort_best"))}</button><span class="chip-sep" aria-hidden="true"></span>`
      + FILTERS.map(f => `<button class="chip" data-filter="${f.k}" aria-pressed="${state.filters.has(f.k)}">${esc(t(f.label))}</button>`).join("");
    let body;
    if (state.loading) body = `<div class="skeleton"></div><div class="skeleton"></div>`;
    else {
      const active = FILTERS.filter(f => state.filters.has(f.k));
      const order = { open: 0, soon: 1, closed: 2 };
      const here = (s) => (state.active && state.active.space_id === s.id ? 1 : 0);
      const list = state.spaces.filter(s => active.every(f => f.test(s)))
        .sort(state.sortBest
          ? (a, b) => here(b) - here(a) || (statusOf(a).state === "closed") - (statusOf(b).state === "closed") || bestScore(b) - bestScore(a)
          : (a, b) => here(b) - here(a) || order[statusOf(a).state] - order[statusOf(b).state] || (b.free_seats / b.seat_capacity) - (a.free_seats / a.seat_capacity));
      body = list.length ? `<div class="cards">${list.map((s, i) => card(s, { first: i === 0 })).join("")}</div>`
        : `<div class="empty"><h2>${esc(t("no_match"))}</h2><p>${esc(t("no_match_p"))}</p><button class="btn" data-act="clear-filters">${esc(t("clear_filters"))}</button></div>`;
    }
    const live = state.offlineSince
      ? `<p class="live-line off"><span class="live-dot" aria-hidden="true"></span><strong>${esc(t("offline"))}</strong></p>`
      : `<p class="live-line"><span class="live-dot" aria-hidden="true"></span><strong>${esc(t("live"))}</strong><span>${esc(t("live_text"))}</span></p>`;
    return `${modeBanner()}${title("home_title", "home_accent")}
      ${live}
      ${howtoTeaser()}
      ${sessionBanner()}
      ${state.loading ? "" : occupancyPanel()}
      <div class="chips" role="group" aria-label="${esc(t("filters"))}">${chips}</div>
      ${state.sortBest ? `<p class="sort-note">${esc(t("sort_best_note"))}</p>` : ""}
      ${body}`;
  }

  function viewMap() {
    const u = uni();
    let inner;
    const embed = u && u.map_embed_url;
    const mode = embed && state.mapMode !== "live" ? "interactive" : "live";
    const tabs = embed ? `<div class="seg map-tabs" role="tablist" aria-label="${esc(t("aria_mapview"))}">
        <button type="button" role="tab" aria-selected="${mode === "interactive"}" aria-checked="${mode === "interactive"}" data-act="map-mode" data-mode="interactive">${esc(t("map_interactive"))}</button>
        <button type="button" role="tab" aria-selected="${mode === "live"}" aria-checked="${mode === "live"}" data-act="map-mode" data-mode="live">${esc(t("map_live"))}</button>
      </div>` : "";
    if (embed && mode === "interactive") {
      inner = `<div class="map-frame map-embed"><iframe src="${esc(embed)}" title="${esc(t("map_iframe", { u: u.name }))}" loading="lazy" allow="fullscreen"></iframe></div>
        <p class="map-credit">${t("map_credit", { a: `<a href="https://github.com/Yuujiso/aitumap" target="_blank" rel="noopener">Yuujiso</a>`, o: `<a href="${esc(embed)}" target="_blank" rel="noopener">${esc(t("map_open"))}</a>` })}</p>`;
    } else if (u && u.map_image_url) {
      const pins = state.spaces.filter(s => s.map_x != null).map(s =>
        `<button class="pin" style="left:${s.map_x}%;top:${s.map_y}%" data-act="goto" data-id="${s.id}" aria-label="${esc(t("map_pin", { n: s.name, s: s.free_seats }))}"><span class="pin-name">${esc(s.name)} · </span>${esc(t("map_free", { n: approx(s) + s.free_seats }))}</button>`).join("");
      inner = `<div class="map-frame"><div class="map-inner"><img src="${esc(u.map_image_url)}" alt="${esc(t("map_alt", { u: u.name }))}">${pins}</div>
        <p class="legend">${esc(t("map_legend"))}</p></div>`;
    } else {
      inner = `<div class="map-frame"><div class="map-placeholder">
        <h2>${esc(u ? u.name : "Campus")}</h2>
        <p>${esc(t("map_soon", { addr: u ? u.address : "" }))}</p>
        <a class="btn" href="https://2gis.kz/astana/search/${encodeURIComponent(u ? u.name : "")}" target="_blank" rel="noopener">${esc(t("map_2gis"))}</a>
      </div></div>`;
    }
    const list = `<ul class="where-list">${state.spaces.map(s => `<li><strong>${esc(s.name)}</strong><span class="muted">${esc([s.building, s.floor].filter(Boolean).join(" · ") || "—")}</span><br><span>${esc(statusOf(s).label)} · ${esc(t("n_free_seats", { n: approx(s) + s.free_seats }))}</span></li>`).join("")}</ul>`;
    return `${modeBanner()}${title("map_title", "map_accent")}${tabs}${inner}${list}`;
  }

  function viewFavourites() {
    let body;
    if (!state.session) body = `<div class="empty"><h2>${esc(t("fav_login_h"))}</h2><p>${esc(t("fav_login_p"))}</p><a class="btn primary" href="#/profile">${esc(t("login"))}</a></div>`;
    else if (!state.favs.size) body = `<div class="empty"><h2>${esc(t("fav_empty_h"))}</h2><p>${esc(t("fav_empty_p"))}</p><a class="btn" href="#/home">${esc(t("browse"))}</a></div>`;
    else body = `<div class="cards">${state.favSpaces.filter(s => state.favs.has(s.id)).map(s => card(s, { showUni: s.university_id !== state.uniId })).join("")}</div>`;
    return `${modeBanner()}${title("fav_title", "fav_accent")}${sessionBanner()}${body}`;
  }

  function viewProfile() {
    const s = state.session;
    if (!s) {
      const u = uni();
      const ph = !u ? "barcode@astanait.edu.kz" : u.short === "AITU" ? "barcode@astanait.edu.kz" : u.short === "NU" ? "name.surname@nu.edu.kz" : `your.name@${u.domains[0]}`;
      const demoHint = state.store.mode === "demo" ? `<p class="hint">${esc(t("demo_hint"))}</p>` : "";
      const next = sessionStorage.getItem("oryntap.afterLabel");
      const afterHint = next ? `<p class="hint">${esc(next)}</p>` : "";
      if (state.authMode === "verify") {
        const v = state.verify || {};
        return `<form class="box auth-box" id="verifyForm" data-keep="verify" novalidate>
          <h2>${esc(t("verify_title"))}</h2>
          <p class="form-error" id="formErr" role="alert">${esc(state.verifyMsg || "")}</p>
          <p>${v.email ? esc(t("verify_sent", { e: v.email })) : esc(t("verify_enter"))}</p>
          <label class="field"><span class="sr-only">${esc(t("uni_email"))}</span><input class="input" name="email" type="email" value="${esc(v.email || "")}" placeholder="${esc(ph)}" autocomplete="email" required></label>
          <p class="hint">${esc(t("verify_hint"))}</p>
          <button class="btn primary block" type="submit" id="resendBtn">${esc(t("verify_resend"))}</button>
          <p class="auth-alt"><button type="button" class="btn link" data-act="verify-login">${esc(t("verify_login"))}</button> · <button type="button" class="btn link" data-act="verify-change">${esc(t("verify_change"))}</button></p>
        </form>`;
      }
      if (state.authMode === "forgot") {
        return `<form class="box auth-box" id="forgotForm" data-keep="forgot" novalidate>
          <h2>${esc(t("forgot_title"))}</h2>
          <p class="form-error" id="formErr" role="alert">${esc(state.forgotErr || "")}</p>
          <p class="form-ok" id="formOk" role="status">${esc(state.forgotOk || "")}</p>
          <p>${esc(t("forgot_lead"))}</p>
          <label class="field"><span class="sr-only">${esc(t("uni_email"))}</span><input class="input" name="email" type="email" placeholder="${esc(ph)}" autocomplete="email" required></label>
          <button class="btn primary block" type="submit" id="forgotBtn">${esc(t("forgot_send"))}</button>
          <p class="auth-alt"><button type="button" class="btn link" data-act="auth-mode" data-mode="login">${esc(t("forgot_back"))}</button></p>
          ${demoHint}
        </form>`;
      }
      if (state.authMode === "signup") {
        return `<form class="box auth-box" id="signupForm" data-keep="signup" novalidate>
          <h2>${esc(t("signup"))}</h2>
          ${afterHint}
          <p class="form-error" id="formErr" role="alert"></p>
          <label class="field"><span class="sr-only">${esc(t("name"))}</span><input class="input" name="first_name" placeholder="${esc(t("name"))}" autocomplete="given-name" required maxlength="50"></label>
          <label class="field"><span class="sr-only">${esc(t("surname"))}</span><input class="input" name="last_name" placeholder="${esc(t("surname"))}" autocomplete="family-name" maxlength="50"></label>
          <label class="field"><span class="sr-only">${esc(t("uni_email"))}</span><input class="input" name="email" type="email" placeholder="${esc(ph)}" autocomplete="email" required></label>
          <label class="field"><span class="sr-only">${esc(t("password"))}</span><input class="input" name="password" type="password" placeholder="${esc(t("password_hint"))}" autocomplete="new-password" required minlength="8"></label>
          <label class="check consent"><input type="checkbox" name="consent" required> <span>${esc(t("consent"))}</span></label>
          <button class="btn primary block" type="submit">${esc(t("create_account"))}</button>
          <p class="auth-alt">${esc(t("have_account"))} <button type="button" class="btn link" data-act="auth-mode" data-mode="login">${esc(t("login"))}</button></p>
          ${demoHint}
        </form>`;
      }
      return `<form class="box auth-box" id="loginForm" data-keep="login" novalidate>
        <h2>${esc(t("login"))}</h2>
        ${afterHint}
        <p class="form-error" id="formErr" role="alert"></p>
        <label class="field"><span class="sr-only">${esc(t("uni_email"))}</span><input class="input" name="email" type="email" placeholder="${esc(ph)}" autocomplete="username" required></label>
        <label class="field"><span class="sr-only">${esc(t("password"))}</span><input class="input" name="password" type="password" placeholder="${esc(t("password"))}" autocomplete="current-password" required></label>
        <button class="btn primary block" type="submit">${esc(t("login"))}</button>
        <p class="auth-alt forgot-alt"><button type="button" class="btn link" data-act="auth-mode" data-mode="forgot">${esc(t("forgot_link"))}</button></p>
        <p class="auth-alt">${esc(t("new_here"))} <button type="button" class="btn link" data-act="auth-mode" data-mode="signup">${esc(t("create_an_account"))}</button></p>
        ${demoHint}
      </form>`;
    }
    const p = s.profile, u = state.unis.find(x => x.id === p.university_id);
    const roleName = t(p.role === "admin" ? "role_admin" : "role_student");
    if (state.recovery) {   // came from a password reset link: Supabase has logged the user in
      return `<form class="box auth-box" id="newPwForm" novalidate>
        <h2>${esc(t("newpw_title"))}</h2>
        <p class="form-error" id="formErr" role="alert"></p>
        <p>${esc(t("newpw_lead", { e: s.user.email }))}</p>
        <label class="field"><span class="sr-only">${esc(t("newpw"))}</span><input class="input" name="password" type="password" placeholder="${esc(t("password_hint"))}" autocomplete="new-password" required minlength="8"></label>
        <label class="field"><span class="sr-only">${esc(t("newpw2"))}</span><input class="input" name="password2" type="password" placeholder="${esc(t("newpw2"))}" autocomplete="new-password" required minlength="8"></label>
        <button class="btn primary block" type="submit">${esc(t("newpw_save"))}</button>
        <p class="auth-alt"><button type="button" class="btn link" data-act="newpw-later">${esc(t("newpw_later"))}</button></p>
      </form>`;
    }
    if (state.editing) {
      return `<form class="box profile-box" id="profileForm" data-keep="profile">
        <h2 style="margin-bottom:22px">${esc(p.first_name)} ${esc(p.last_name)}</h2>
        <p class="form-error" id="formErr" role="alert"></p>
        <div class="edit-grid">
          <label for="pf1">${esc(t("name"))}</label><input class="input" id="pf1" name="first_name" value="${esc(p.first_name)}" required maxlength="50">
          <label for="pf2">${esc(t("surname"))}</label><input class="input" id="pf2" name="last_name" value="${esc(p.last_name)}" maxlength="50">
          <label for="pf3">${esc(t("university"))}</label><input class="input" id="pf3" value="${esc(u ? u.name : "")}" disabled>
          <label for="pf4">${esc(t("role"))}</label><input class="input" id="pf4" value="${esc(roleName)}" disabled>
        </div>
        <div class="form-actions"><button class="btn secondary" type="button" data-act="cancel-edit">${esc(t("cancel"))}</button><button class="btn primary" type="submit">${esc(t("save_all"))}</button></div>
      </form>`;
    }
    return `<section class="box profile-box">
        <h2>${t("welcome_back_name", { n: `<span class="accent">${esc(p.first_name)} ${esc(p.last_name)}</span>` })}</h2>
        <div class="sub">${esc(t("user_details"))}</div>
        <div class="profile-head">
          <dl>
            <div><dt>${esc(t("name"))}</dt><dd>${esc(p.first_name)}</dd></div>
            <div><dt>${esc(t("surname"))}</dt><dd>${esc(p.last_name) || "—"}</dd></div>
            <div><dt>${esc(t("email"))}</dt><dd>${esc(s.user.email)}</dd></div>
            <div><dt>${esc(t("university"))}</dt><dd>${esc(u ? u.name : "")}</dd></div>
            <div><dt>${esc(t("role"))}</dt><dd>${esc(roleName)}</dd></div>
          </dl>
          <button class="btn link" data-act="edit-profile">${esc(t("edit_profile"))}</button>
        </div>
        <div class="profile-foot"><button class="btn" data-act="logout">${esc(t("logout"))}</button></div>
      </section>
      ${isAdmin() ? `<section class="box insights" id="insights"><h2>${esc(t("busiest"))}</h2><p class="muted">${esc(t("busiest_p"))}</p><div id="insightBody" class="skeleton" style="height:120px"></div>
        <h2 class="ins-h">${esc(t("ins_use"))}</h2><p class="muted">${esc(t("ins_use_p"))}</p><div id="insightUse" class="skeleton" style="height:90px"></div>
        <h2 class="ins-h">${esc(t("ins_stay"))}</h2><p class="muted">${esc(t("ins_stay_p"))}</p><div id="insightStay" class="skeleton" style="height:90px"></div>
        <h2 class="ins-h">${esc(t("ins_rep"))}</h2><p class="muted">${esc(t("ins_rep_p"))}</p><div id="insightRep" class="skeleton" style="height:60px"></div>
        <p class="muted ins-src">${esc(t("ins_src"))}</p></section>` : ""}`;
  }

  async function loadInsights() {
    const el = $("#insightBody"); if (!el) return;
    try {
      const rows = await state.store.usageByHour();
      const by = {};
      rows.forEach(r => { (by[r.space_id] = by[r.space_id] || { name: r.space_name, h: {} }).h[r.hour_of_day] = Number(r.check_ins); });
      const hours = Array.from({ length: 15 }, (_, i) => i + 8);
      el.className = "insight-grid"; el.removeAttribute("style");
      el.innerHTML = Object.values(by).map(sp => {
        const max = Math.max(1, ...Object.values(sp.h));
        const peak = Object.entries(sp.h).sort((a, b) => b[1] - a[1])[0];
        return `<div class="insight-row"><h3>${esc(sp.name)}</h3><p>${esc(t("peak", { h: peak ? peak[0] + ":00" : "—" }))}</p>
          <div class="bars" aria-hidden="true">${hours.map(h => `<span style="height:${Math.round(((sp.h[h] || 0) / max) * 100)}%" title="${h}:00 — ${sp.h[h] || 0}"></span>`).join("")}</div>
          <div class="bar-labels">${hours.map(h => `<span>${h % 2 ? "" : h}</span>`).join("")}</div></div>`;
      }).join("") || `<p class="muted">${esc(t("no_checkins"))}</p>`;
    } catch (e) { el.className = ""; el.removeAttribute("style"); el.innerHTML = `<p class="muted">${esc(t("insights_fail"))}</p>`; }
    loadMoreInsights();
  }
  // Stage 2, Part C5: results of analysis questions Q2 and Q3 inside the product
  async function loadMoreInsights() {
    const u = $("#insightUse"), s = $("#insightStay"); if (!u || !s) return;
    const done = (el) => { el.className = ""; el.removeAttribute("style"); };
    try {
      const rows = await state.store.spaceStats();
      const max = Math.max(1, ...rows.map(r => Number(r.per_100_seats)));
      done(u);
      u.innerHTML = rows.length ? `<ul class="use-list">${rows.map(r => `<li><span class="nm">${esc(r.space_name)}</span>
          <span class="bar" aria-hidden="true"><i style="width:${Math.round(Number(r.per_100_seats) / max * 100)}%"></i></span>
          <span class="val">${esc(t("ins_use_val", { n: Number(r.per_100_seats).toFixed(1), c: r.check_ins, o: r.pct_with_outlet == null ? "—" : r.pct_with_outlet }))}</span></li>`).join("")}</ul>`
        : `<p class="muted">${esc(t("no_checkins"))}</p>`;
    } catch (e) { done(u); u.innerHTML = `<p class="muted">${esc(t("insights_fail"))}</p>`; }
    try {
      const rows = await state.store.stayStats();
      done(s);
      s.innerHTML = rows.length ? `<table class="stay-table"><thead><tr><th scope="col">${esc(t("ins_planned"))}</th><th scope="col">${esc(t("ins_n"))}</th><th scope="col">${esc(t("ins_avg"))}</th><th scope="col">${esc(t("ins_early"))}</th><th scope="col">${esc(t("ins_auto"))}</th></tr></thead>
        <tbody>${rows.map(r => `<tr><td>${esc(t("hours_short", { h: r.planned_hours }))}</td><td>${r.check_ins}</td><td>${esc(t("ins_min", { m: r.avg_stay_min }))}</td><td>${r.pct_left_early}%</td><td>${r.pct_ended_by_itself}%</td></tr>`).join("")}</tbody></table>`
        : `<p class="muted">${esc(t("no_checkins"))}</p>`;
    } catch (e) { done(s); s.innerHTML = `<p class="muted">${esc(t("insights_fail"))}</p>`; }
    const r = $("#insightRep"); if (!r || !state.store.adminCountReports) return;
    try {
      const rows = await state.store.adminCountReports();
      done(r);
      r.innerHTML = rows.length ? `<table class="stay-table"><thead><tr><th scope="col">${esc(t("ins_rep_place"))}</th><th scope="col">${esc(t("rep_full"))}</th><th scope="col">${esc(t("rep_empty"))}</th><th scope="col">${esc(t("rep_closed"))}</th><th scope="col">${esc(t("ins_rep_last"))}</th></tr></thead>
        <tbody>${rows.map(x => `<tr><td>${esc(x.space_name)}</td><td>${x.full_n}</td><td>${x.empty_n}</td><td>${x.closed_n}</td><td>${esc(agoText(x.last_at))}</td></tr>`).join("")}</tbody></table>`
        : `<p class="muted">${esc(t("ins_rep_none"))}</p>`;
    } catch (e) { done(r); r.innerHTML = `<p class="muted">${esc(t("insights_fail"))}</p>`; }
  }

  function afterRender() {
    if (state.route === "profile" && isAdmin() && !state.editing) loadInsights();
    const lf = $("#loginForm"), sf = $("#signupForm"), pf = $("#profileForm");
    if (lf) lf.addEventListener("submit", onLogin);
    if (sf) sf.addEventListener("submit", onSignup);
    const vf = $("#verifyForm"); if (vf) vf.addEventListener("submit", onResend);
    const ff = $("#forgotForm"); if (ff) ff.addEventListener("submit", onForgot);
    const nf = $("#newPwForm"); if (nf) nf.addEventListener("submit", onNewPassword);
    if (pf) pf.addEventListener("submit", onSaveProfile);
    if (state.store.pendingError) { toast(state.store.pendingError, true); state.store.pendingError = null; }
    // Back from the confirmation e-mail: the link worked, or it had expired / was already used
    if (state.store.justConfirmed) {
      state.store.justConfirmed = false;
      if (state.session) { setVerify(null); state.drafts = {}; toast(t("verified_ok")); }
    }
    // Back from a password reset e-mail
    if (state.store.pendingReset) {
      const r = state.store.pendingReset; state.store.pendingReset = null;
      if (r === "ok" && state.session) { setRecovery(true); state.route = "profile"; history.replaceState(null, "", location.pathname + "#/profile"); render(); return; }
      if (r === "expired") { state.authMode = "forgot"; state.forgotOk = ""; state.forgotErr = t("err_reset_expired"); state.route = "profile"; history.replaceState(null, "", location.pathname + "#/profile"); render(); return; }
    }
    if (state.store.pendingVerify === "expired") {
      state.store.pendingVerify = null;
      if (!state.session) { showVerify((state.verify || {}).email || "", t("err_link_expired")); return; }
    }
  }

  // ---------------- actions ----------------
  // A logged-out student who taps "check in" or the heart is sent to the login page. What they
  // wanted to do is remembered here (this browser tab only) and done right after login/sign-up.
  const AFTER_KEYS = ["oryntap.after", "oryntap.afterFav", "oryntap.afterLabel"];
  function rememberIntent(kind, space) {
    AFTER_KEYS.forEach(k => sessionStorage.removeItem(k));
    if (kind === "fav") sessionStorage.setItem("oryntap.afterFav", String(space.id));
    else sessionStorage.setItem("oryntap.after", "#/checkin/" + space.id);
    sessionStorage.setItem("oryntap.afterLabel", t(kind === "fav" ? "after_fav" : "after_checkin", { n: space.name }));
  }
  async function continueAfterLogin() {
    const back = sessionStorage.getItem("oryntap.after"), fav = Number(sessionStorage.getItem("oryntap.afterFav"));
    AFTER_KEYS.forEach(k => sessionStorage.removeItem(k));
    if (fav && !isAdmin() && !state.favs.has(fav)) await toggleFav(fav);
    location.hash = back || "#/home";
  }
  function requireLogin(msg) {
    if (state.session) return true;
    toast(msg || t("need_login"));
    location.hash = "#/profile";
    return false;
  }
  async function onLogin(e) {
    e.preventDefault();
    const f = new FormData(e.target), btn = e.target.querySelector("[type=submit]");
    const email = String(f.get("email") || "").trim(), pw = String(f.get("password") || "");
    if (!email || !pw) { $("#formErr").textContent = t("enter_email_pw"); return; }
    btn.disabled = true;
    try {
      await state.store.signIn(email, pw);
      toast(t("welcome_back"));
      state.drafts = {}; setVerify(null);
      state.uniId = null; await refresh();
      await continueAfterLogin();
    } catch (err) {
      if (err.code === "email_not_confirmed") { showVerify(email, err.message); return; }
      $("#formErr").textContent = err.message;
    }
    finally { btn.disabled = false; }
  }
  async function onSignup(e) {
    e.preventDefault();
    const f = Object.fromEntries(new FormData(e.target)), btn = e.target.querySelector("[type=submit]");
    if (!f.consent) { $("#formErr").textContent = t("need_consent"); return; }
    btn.disabled = true;
    try {
      const res = await state.store.signUp(f);
      // Registered: the sign-up form has done its job. If the e-mail must be confirmed first,
      // the login form opens with the same e-mail already filled in.
      if (res && res.needsConfirmation) {
        // Not finished until the e-mail is confirmed: keep name and e-mail for "use a different e-mail"
        if (state.drafts.signup) delete state.drafts.signup.password;
        state.drafts.login = { email: f.email };
        toast(t("confirm_email")); showVerify(res.email || f.email);
        return;
      }
      toast(t("account_created"));
      state.drafts = {}; setVerify(null);
      state.uniId = null; await refresh(); await continueAfterLogin();
    } catch (err) { $("#formErr").textContent = err.message; }
    finally { btn.disabled = false; }
  }
  function setVerify(v) { state.verify = v; v ? LS.set("oryntap.verify", v) : LS.del("oryntap.verify"); }
  function showVerify(email, msg) {
    setVerify({ email: String(email || "").trim().toLowerCase() });
    delete state.drafts.verify;
    // Can run while the app is still starting (back from an expired link): switch to the
    // Profile page directly, so the verify step and its message are on screen.
    state.authMode = "verify"; state.route = "profile"; state.editing = false;
    if (location.hash !== "#/profile") history.replaceState(null, "", location.pathname + "#/profile");
    state.verifyMsg = msg || "";   // kept in state: re-renders (start-up, refresh) must not wipe it
    render();
  }
  async function onResend(e) {
    e.preventDefault();
    const btn = $("#resendBtn"), email = String(new FormData(e.target).get("email") || "").trim().toLowerCase();
    if (!email) { $("#formErr").textContent = t("enter_email_pw"); return; }
    if (!state.store.resendConfirmation) { $("#formErr").textContent = t("demo_no_mail"); return; }
    btn.disabled = true;
    try {
      await state.store.resendConfirmation(email);
      setVerify({ email }); state.verifyMsg = ""; $("#formErr").textContent = "";
      toast(t("verify_resent", { e: email }));
      // Supabase sends at most one e-mail per address every 60 s: count down on the button
      let left = 60; btn.textContent = t("verify_wait", { n: left });
      const timer = setInterval(() => {
        left -= 1; const b = $("#resendBtn");
        if (!b) return clearInterval(timer);
        if (left <= 0) { clearInterval(timer); b.disabled = false; b.textContent = t("verify_resend"); }
        else b.textContent = t("verify_wait", { n: left });
      }, 1000);
    } catch (err) { btn.disabled = false; $("#formErr").textContent = err.message; }
  }
  function setRecovery(on) { state.recovery = on; on ? sessionStorage.setItem("oryntap.recovery", "1") : sessionStorage.removeItem("oryntap.recovery"); }
  async function onForgot(e) {
    e.preventDefault();
    const btn = $("#forgotBtn"), email = String(new FormData(e.target).get("email") || "").trim().toLowerCase();
    state.forgotOk = ""; state.forgotErr = ""; $("#formOk").textContent = "";
    if (!email) { $("#formErr").textContent = t("enter_email"); return; }
    if (!state.store.requestPasswordReset) { $("#formErr").textContent = t("demo_no_mail"); return; }
    btn.disabled = true;
    try {
      await state.store.requestPasswordReset(email);
      state.forgotOk = t("forgot_sent", { e: email }); $("#formErr").textContent = ""; $("#formOk").textContent = state.forgotOk;
      // one e-mail per minute (Supabase rate limit): count down on the button
      let left = 60; btn.textContent = t("verify_wait", { n: left });
      const timer = setInterval(() => {
        left -= 1; const b = $("#forgotBtn");
        if (!b) return clearInterval(timer);
        if (left <= 0) { clearInterval(timer); b.disabled = false; b.textContent = t("forgot_send"); }
        else b.textContent = t("verify_wait", { n: left });
      }, 1000);
    } catch (err) { btn.disabled = false; state.forgotErr = err.message; $("#formErr").textContent = err.message; }
  }
  async function onNewPassword(e) {
    e.preventDefault();
    const f = new FormData(e.target), btn = e.target.querySelector("[type=submit]");
    const pw = String(f.get("password") || ""), pw2 = String(f.get("password2") || "");
    if (pw !== pw2) { $("#formErr").textContent = t("err_pw_match"); return; }
    btn.disabled = true;
    try {
      await state.store.updatePassword(pw);
      setRecovery(false); toast(t("newpw_done")); render();
    } catch (err) { btn.disabled = false; $("#formErr").textContent = err.message; }
  }
  async function onSaveProfile(e) {
    e.preventDefault();
    const f = Object.fromEntries(new FormData(e.target));
    if (!String(f.first_name || "").trim()) { $("#formErr").textContent = t("name_empty"); return; }
    try {
      state.session.profile = { ...state.session.profile, ...(await state.store.updateProfile(state.session.user.id, f)) };
      delete state.drafts.profile; state.editing = false; toast(t("profile_saved")); render();
    } catch (err) { $("#formErr").textContent = err.message; }
  }

  async function toggleFav(id) {
    if (!state.session) {
      const sp = state.spaces.find(x => x.id === id) || state.favSpaces.find(x => x.id === id);
      if (sp) rememberIntent("fav", sp);
      requireLogin(t("login_fav")); return;
    }
    const on = !state.favs.has(id);
    on ? state.favs.add(id) : state.favs.delete(id);
    render();
    try {
      await state.store.setFavourite(state.session.user.id, id, on);
      if (on && !state.favSpaces.some(s => s.id === id)) {
        const s = state.spaces.find(x => x.id === id); if (s) state.favSpaces.push(s);
      }
      toast(t(on ? "fav_added" : "fav_removed"));
    } catch (e) { on ? state.favs.delete(id) : state.favs.add(id); render(); fail(e); }
  }

  // ---------------- modals ----------------
  function openModal(html, onMount) {
    const root = $("#modalRoot");
    const last = document.activeElement;
    root.innerHTML = `<div class="modal-backdrop" data-close><div class="modal" role="dialog" aria-modal="true" aria-labelledby="modalTitle">${html}</div></div>`;
    const h = root.querySelector(".modal h2"); if (h) h.id = "modalTitle";
    const close = () => { root.innerHTML = ""; document.removeEventListener("keydown", onKey); if (last && last.focus) last.focus(); };
    const onKey = (e) => { if (e.key === "Escape") close(); };
    document.addEventListener("keydown", onKey);
    root.querySelector(".modal-backdrop").addEventListener("click", (e) => { if (e.target.hasAttribute("data-close") || e.target.closest("[data-dismiss]")) close(); });
    const first = root.querySelector("button, input, select, textarea"); if (first) first.focus();
    if (onMount) onMount(root.querySelector(".modal"), close);
  }

  function openCheckIn(space) {
    if (!state.session) { rememberIntent("checkin", space); requireLogin(t("login_checkin")); return; }
    if (isAdmin()) return;
    // Scanning the QR code of the place where you are already checked in = checking out
    if (state.active && state.active.space_id === space.id) { confirmLeave(space); return; }
    if (otherUni(space)) { toast(t("only_uni_toast", { u: uniShort(space.university_id) }), true); return; }
    const st = statusOf(space);
    if (st.state === "closed") { toast(t("closed_now_toast", { n: space.name, d: st.detail }), true); return; }
    const other = state.active && state.active.space_id !== space.id ? (state.spaces.find(s => s.id === state.active.space_id) || {}).name || t("another_place") : null;
    let hours = 2;
    openModal(`<h2>${esc(t("ci_title", { n: space.name }))}</h2>
      <p class="lead">${esc(t("ci_lead", { f: approx(space) + space.free_seats, c: space.seat_capacity, d: st.detail }))}</p>
      <p class="hint" style="margin:-8px 0 16px">${esc(t("ci_here"))}</p>
      <div id="ciLabel" class="label">${esc(t("ci_how_long"))}</div>
      <div class="seg" role="radiogroup" aria-labelledby="ciLabel">${[1, 2, 3].map(h => `<button type="button" role="radio" aria-checked="${h === hours}" data-h="${h}">${esc(t("hours_short", { h }))}</button>`).join("")}</div>
      <label class="check"><input type="checkbox" id="ciOutlet" ${space.free_outlets > 0 ? "checked" : "disabled"}> ${esc(t("ci_outlet"))}${space.free_outlets > 0 ? "" : esc(t("ci_none_free"))}</label>
      ${other ? `<p class="hint" style="margin:-8px 0 16px">${esc(t("ci_ends_other", { n: other }))}</p>` : ""}
      <p class="hint ci-end" id="ciEnd" style="margin:-8px 0 12px"></p>
      <p class="hint" style="margin:0 0 18px">${esc(t("ci_auto"))}</p>
      <div class="form-actions" style="margin-top:0"><button class="btn secondary" data-dismiss>${esc(t("cancel"))}</button><button class="btn primary" id="ciGo">${esc(t("ci_start"))}</button></div>`,
    (m, close) => {
      // A check-in ends at closing time at the latest (the database does the same)
      const showEnd = () => {
        const c = closingTime(space), end = Date.now() + hours * HOUR;
        $("#ciEnd", m).textContent = c && c < end ? t("ci_until_close", { t: clock(c) }) : t("ci_until", { t: clock(end) });
      };
      showEnd();
      m.querySelectorAll("[data-h]").forEach(b => b.addEventListener("click", () => {
        hours = Number(b.dataset.h); m.querySelectorAll("[data-h]").forEach(x => x.setAttribute("aria-checked", String(x === b)));
        showEnd();
      }));
      $("#ciGo", m).addEventListener("click", async (e) => {
        e.target.disabled = true;
        // for the reminder 10 minutes before the end (asked once, after a click)
        if ("Notification" in window && Notification.permission === "default") { try { Notification.requestPermission(); } catch (x) {} }
        try {
          state.active = await state.store.checkIn(state.session.user.id, space.id, hours, $("#ciOutlet", m).checked);
          const until = Date.parse(state.active.expires_at);
          close(); toast(until < Date.now() + hours * HOUR - 2 * MIN ? t("ci_done_close", { n: space.name, t: clock(until) }) : t("ci_done", { n: space.name, h: hours }));
          await refresh();
        } catch (err) { e.target.disabled = false; fail(err); }
      });
    });
  }

  function confirmLeave(space) {
    openModal(`<h2>${esc(t("studying_at", { n: space.name }))}</h2>
      <p class="lead">${esc(t("co_lead"))}</p>
      <div class="form-actions" style="margin-top:0"><button class="btn secondary" data-dismiss>${esc(t("co_stay"))}</button><button class="btn primary" id="coGo">${esc(t("co_leave"))}</button></div>`,
    (m, close) => {
      $("#coGo", m).addEventListener("click", async (e) => { e.target.disabled = true; close(); await leave(); });
    });
  }

  async function leave() {
    if (!state.active) return;
    try {
      await state.store.leave(state.active.id);
      state.active = null; state.pomodoro = null;
      toast(t("left"));
      await refresh();
    } catch (e) { fail(e); }
  }

  async function extend(btn) {
    if (!state.active) return;
    if (btn) btn.disabled = true;
    try {
      const until = await state.store.extendCheckIn(state.active.id);
      state.active = { ...state.active, expires_at: until };
      toast(t("ext_done", { t: clock(Date.parse(until)) }));
      await refresh();
    } catch (e) { if (btn) btn.disabled = false; fail(e); }
  }

  function openReport(space) {
    if (!state.session) return;
    let kind = null;
    const kinds = [["full", "rep_full_l"], ["empty", "rep_empty_l"], ["closed", "rep_closed_l"]];
    openModal(`<h2>${esc(t("rep_title", { n: space.name }))}</h2>
      <p class="lead">${esc(t("rep_lead", { f: approx(space) + space.free_seats, c: space.seat_capacity }))}</p>
      <div id="repLabel" class="label">${esc(t("rep_q"))}</div>
      <div class="seg seg-col" role="radiogroup" aria-labelledby="repLabel">${kinds.map(([k, l]) => `<button type="button" role="radio" aria-checked="false" data-k="${k}">${esc(t(l))}</button>`).join("")}</div>
      <p class="hint" style="margin:-4px 0 18px">${esc(t("rep_hint"))}</p>
      <p class="form-error" id="repErr" role="alert"></p>
      <div class="form-actions" style="margin-top:0"><button class="btn secondary" data-dismiss>${esc(t("cancel"))}</button><button class="btn primary" id="repGo">${esc(t("rep_send"))}</button></div>`,
    (m, close) => {
      m.querySelectorAll("[data-k]").forEach(b => b.addEventListener("click", () => {
        kind = b.dataset.k; m.querySelectorAll("[data-k]").forEach(x => x.setAttribute("aria-checked", String(x === b)));
        $("#repErr", m).textContent = "";
      }));
      $("#repGo", m).addEventListener("click", async (e) => {
        if (!kind) { $("#repErr", m).textContent = t("rep_pick"); return; }
        e.target.disabled = true;
        try { await state.store.reportCount(space.id, kind, space.free_seats); close(); toast(t("rep_done")); }
        catch (err) { e.target.disabled = false; $("#repErr", m).textContent = err.message; }
      });
    });
  }

  function openEdit(space) {
    const days = [1, 2, 3, 4, 5, 6, 7];
    const byDay = {}; (space.hours || []).forEach(h => { byDay[h.weekday] = h; });
    const D = DAYS();
    openModal(`<h2>${esc(t("ed_title", { n: space.name }))}</h2>
      <p class="lead">${esc(t("ed_lead"))}</p>
      <form id="editForm">
        <label class="field"><span>${esc(t("ed_name"))}</span><input class="input" name="name" value="${esc(space.name)}" required maxlength="80"></label>
        <label class="field"><span>${esc(t("ed_desc"))}</span><textarea class="input" name="description" maxlength="400">${esc(space.description || "")}</textarea></label>
        <div class="row">
          <label class="field"><span>${esc(t("ed_seats"))}</span><input class="input" name="seat_capacity" type="number" min="1" max="2000" value="${space.seat_capacity}" required></label>
          <label class="field"><span>${esc(t("ed_outlets"))}</span><input class="input" name="outlet_capacity" type="number" min="0" max="5000" value="${space.outlet_capacity}" required></label>
        </div>
        <div class="toggles">
          <label class="check"><input type="checkbox" name="is_quiet" ${space.is_quiet ? "checked" : ""}> ${esc(t("f_quiet"))}</label>
          <label class="check"><input type="checkbox" name="group_work" ${space.group_work ? "checked" : ""}> ${esc(t("f_group"))}</label>
          <label class="check"><input type="checkbox" name="food_allowed" ${space.food_allowed ? "checked" : ""}> ${esc(t("f_food"))}</label>
        </div>
        <div class="label">${esc(t("ed_hours"))}</div>
        <div class="hours-grid">${days.map(d => {
          const h = byDay[d];
          return `<span>${esc(D[d])}</span>
            <input class="input" type="time" name="o${d}" value="${h ? hhmm(h.opens) : "09:00"}" aria-label="${esc(t("ed_opens", { d: D[d] }))}" ${h ? "" : "disabled"}>
            <input class="input" type="time" name="c${d}" value="${h ? (h.closes.startsWith("24") ? "23:59" : hhmm(h.closes)) : "18:00"}" aria-label="${esc(t("ed_closes", { d: D[d] }))}" ${h ? "" : "disabled"}>
            <label><input type="checkbox" name="x${d}" ${h ? "" : "checked"}> ${esc(t("ed_off"))}</label>`;
        }).join("")}</div>
        <p class="form-error" id="editErr" role="alert"></p>
        <div class="form-actions" style="margin-top:0"><button class="btn secondary" type="button" data-dismiss>${esc(t("cancel"))}</button><button class="btn primary" type="submit">${esc(t("save_all"))}</button></div>
      </form>`,
    (m, close) => {
      days.forEach(d => m.querySelector(`[name=x${d}]`).addEventListener("change", (e) => {
        m.querySelector(`[name=o${d}]`).disabled = e.target.checked; m.querySelector(`[name=c${d}]`).disabled = e.target.checked;
      }));
      $("#editForm", m).addEventListener("submit", async (e) => {
        e.preventDefault();
        const f = e.target, err = $("#editErr", m);
        const seats = Number(f.seat_capacity.value), outlets = Number(f.outlet_capacity.value);
        if (!f.name.value.trim()) return (err.textContent = t("ed_name_req"));
        if (!(seats >= 1 && seats <= 2000) || !(outlets >= 0 && outlets <= 5000)) return (err.textContent = t("ed_numbers"));
        const hours = [];
        for (const d of days) {
          if (f[`x${d}`].checked) continue;
          let o = f[`o${d}`].value, c = f[`c${d}`].value;
          if (c === "23:59" && o === "00:00") c = "24:00";
          if (!o || !c || toMin(c) <= toMin(o)) return (err.textContent = t("ed_order", { d: D[d] }));
          hours.push({ weekday: d, opens: o, closes: c });
        }
        const patch = { name: f.name.value.trim().slice(0, 80), description: f.description.value.trim().slice(0, 400),
          seat_capacity: seats, outlet_capacity: outlets, is_quiet: f.is_quiet.checked, group_work: f.group_work.checked, food_allowed: f.food_allowed.checked };
        try { await state.store.updateSpace(space.id, patch, hours); close(); toast(t("saved")); await refresh(); }
        catch (ex) { err.textContent = ex.message || t("save_fail"); }
      });
    });
  }

  function loadScriptOnce(src) {
    return new Promise((res, rej) => {
      if (document.querySelector(`script[src="${src}"]`)) return res();
      const s = document.createElement("script"); s.src = src; s.onload = res; s.onerror = rej; document.head.appendChild(s);
    });
  }
  async function openQR(space) {
    const url = location.origin + location.pathname + "#/checkin/" + space.id;
    openModal(`<h2>${esc(t("qr_title", { n: space.name }))}</h2>
      <p class="lead">${esc(t("qr_lead"))}</p>
      <div class="qr" id="qrBox"></div><p class="qr-url">${esc(url)}</p>
      <p class="hint" style="margin:0 0 4px">${esc(t("poster_hint"))}</p>
      <div class="form-actions"><button class="btn secondary" data-dismiss>${esc(t("close"))}</button><button class="btn primary" id="posterBtn" disabled>${esc(t("poster_print"))}</button></div>`);
    try {
      await loadScriptOnce("https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js");
      new window.QRCode($("#qrBox"), { text: url, width: 220, height: 220 });
      const b = $("#posterBtn"); if (b) { b.disabled = false; b.addEventListener("click", () => printPoster(space, url)); }
    } catch (e) { $("#qrBox").textContent = t("qr_fail"); }
  }
  // A4 poster for the zone: big QR code and a short text in Kazakh, Russian and English
  // (a poster on the wall is read by everyone, whatever language the admin uses).
  function printPoster(space, url) {
    const holder = document.createElement("div");
    new window.QRCode(holder, { text: url, width: 640, height: 640, correctLevel: window.QRCode.CorrectLevel ? window.QRCode.CorrectLevel.M : undefined });
    const cv = holder.querySelector("canvas"), im = holder.querySelector("img");
    const src = cv ? cv.toDataURL("image/png") : im ? im.src : "";
    const where = [space.building, space.floor].filter(Boolean).join(" · ");
    const L = (k) => ["kk", "ru", "en"].map(l => `<p lang="${l}">${esc(window.I18N.tIn(l, k))}</p>`).join("");
    const old = $("#poster"); if (old) old.remove();
    const el = document.createElement("section"); el.id = "poster"; el.setAttribute("aria-hidden", "true");
    el.innerHTML = `<div class="p-logo">Oryn<span>Tap</span></div>
      <h1>${esc(space.name)}</h1>${where ? `<p class="p-where">${esc(where)}</p>` : ""}
      <div class="p-scan">${L("poster_scan")}</div>
      <img class="p-qr" src="${src}" alt="">
      <div class="p-steps">${L("poster_leave")}</div>
      <div class="p-rule">${L("poster_rule")}</div>
      <p class="p-url">${esc(url)}</p>`;
    document.body.appendChild(el); document.body.classList.add("print-poster");
    const done = () => { document.body.classList.remove("print-poster"); el.remove(); removeEventListener("afterprint", done); };
    addEventListener("afterprint", done);
    setTimeout(() => window.print(), 50);   // let the QR image decode first
  }

  function togglePomodoro() {
    if (state.pomodoro) { state.pomodoro = null; render(); return; }
    if ("Notification" in window && Notification.permission === "default") Notification.requestPermission();
    state.pomodoro = { phase: "focus", until: Date.now() + 25 * MIN };
    render();
  }
  function notify(text) {
    toast(text);
    playChime();
    const banner = $(".session"); if (banner) { banner.classList.remove("flash"); void banner.offsetWidth; banner.classList.add("flash"); }
    try { if (navigator.vibrate) navigator.vibrate(200); } catch (e) {}
    try { if ("Notification" in window && Notification.permission === "granted") new Notification("OrynTap", { body: text }); } catch (e) {}
  }

  // ---------------- global click handling ----------------
  document.addEventListener("click", (e) => {
    const chip = e.target.closest("[data-filter]");
    if (chip) {
      const k = chip.dataset.filter;
      state.filters.has(k) ? state.filters.delete(k) : state.filters.add(k);
      LS.set("oryntap.filters", [...state.filters]); render(); return;
    }
    const a = e.target.closest("[data-act]"); if (!a) return;
    const id = Number(a.dataset.id);
    const space = state.spaces.find(s => s.id === id) || state.favSpaces.find(s => s.id === id);
    switch (a.dataset.act) {
      case "fav": toggleFav(id); break;
      case "checkin": if (space) openCheckIn(space); break;
      case "leave": leave(); break;
      case "extend": extend(a); break;
      case "watch": if (space) toggleWatch(space); break;
      case "report": if (space) openReport(space); break;
      case "sort-best": state.sortBest = !state.sortBest; LS.set("oryntap.sortBest", state.sortBest); render(); break;
      case "newpw-later": setRecovery(false); render(); break;
      case "edit": if (space) openEdit(space); break;
      case "qr": if (space) openQR(space); break;
      case "pomodoro": togglePomodoro(); break;
      case "sound": toggleSound(); break;
      case "howto": openHowTo(); break;
      case "howto-hide": LS.set("oryntap.howto.hidden", true); render(); break;
      case "map-mode": state.mapMode = a.dataset.mode; render(); break;
      case "clear-filters": state.filters.clear(); LS.set("oryntap.filters", []); render(); break;
      case "auth-mode":
        if (a.dataset.mode === "forgot") { state.forgotOk = ""; state.forgotErr = ""; state.drafts.forgot = { email: (state.drafts.login || {}).email || "" }; }
        state.authMode = a.dataset.mode; render(); break;
      case "verify-login": state.verifyMsg = ""; state.drafts.login = { ...(state.drafts.login || {}), email: (state.verify || {}).email || "" }; state.authMode = "login"; render(); break;
      case "verify-change": state.verifyMsg = ""; setVerify(null); state.authMode = "signup"; render(); break;
      case "edit-profile": delete state.drafts.profile; state.editing = true; render(); break;
      case "cancel-edit": delete state.drafts.profile; state.editing = false; render(); break;
      case "logout":
        state.store.signOut().then(() => { state.drafts = {}; AFTER_KEYS.forEach(k => sessionStorage.removeItem(k)); state.session = null; state.active = null; state.favs = new Set(); state.pomodoro = null; setRecovery(false); toast(t("logged_out")); location.hash = "#/home"; refresh(); });
        break;
      case "goto": location.hash = "#/home"; setTimeout(() => { const el = document.getElementById("space-" + id); if (el) el.scrollIntoView({ behavior: "smooth", block: "center" }); }, 60); break;
    }
  });

  // ---------------- router ----------------
  async function route() {
    // The Supabase library removes the token from the address after an e-mail link, which fires
    // hashchange while the app is still starting; boot() calls route() itself when it is ready.
    if (!state.store || !state.unis.length) return;
    $("#modalRoot").innerHTML = "";
    const parts = location.hash.replace(/^#\/?/, "").split("/");
    let r = parts[0] || "home";
    if (r === "checkin") {
      const id = Number(parts[1]);
      history.replaceState(null, "", location.pathname + "#/home");
      r = "home";
      state.route = r;
      let s = state.spaces.find(x => x.id === id);
      if (!s) { const found = await state.store.getSpacesByIds([id]).catch(() => []); s = found[0]; if (s && s.university_id !== state.uniId) await selectUni(s.university_id); }
      render();
      if (s) openCheckIn(s);
      return;
    }
    if (!["home", "map", "favourites", "profile"].includes(r)) r = "home";
    if (r === "favourites" && isAdmin()) r = "home";
    const changed = state.route !== r;
    state.route = r;
    if (r !== "profile") state.editing = false;
    if (r !== "profile" && !state.session) AFTER_KEYS.forEach(k => sessionStorage.removeItem(k));   // gave up on logging in
    if (r === "favourites" && state.session && state.favs.size) {
      state.favSpaces = await state.store.getSpacesByIds([...state.favs]).catch(() => state.favSpaces);
    }
    render();
    if (changed) { scrollTo(0, 0); $("#view").focus({ preventScroll: true }); }
  }
  addEventListener("hashchange", route);

  // ---------------- timers ----------------
  setInterval(() => {
    document.querySelectorAll("[data-until]").forEach(el => {
      const left = Date.parse(el.dataset.until) - Date.now();
      el.textContent = fmtLeft(left);
      if (left <= 0 && state.active) { state.active = null; notify(t("checkin_ended")); refresh(); }
    });
    // Reminder 10 minutes before a check-in ends (once per end time, also after a reload)
    const a = state.active;
    if (a) {
      const left = Date.parse(a.expires_at) - Date.now(), key = a.id + "@" + a.expires_at;
      if (left > 0 && left <= 10 * MIN && LS.get("oryntap.reminded", null) !== key) {
        LS.set("oryntap.reminded", key);
        const sp = state.spaces.find(x => x.id === a.space_id) || state.favSpaces.find(x => x.id === a.space_id) || state.activeSpace;
        if (!$("#view form[data-keep]")) render();   // shows the note and the Extend button in the banner
        notify(t("remind_end", { n: sp ? sp.name : t("your_space"), m: Math.max(1, Math.ceil(left / MIN)) }));
      }
    }
    const p = state.pomodoro;
    if (p) {
      const left = p.until - Date.now();
      const el = $("[data-pomo]"); if (el) el.textContent = fmtLeft(left);
      if (left <= 0) {
        const msg = t(p.phase === "focus" ? "pomo_focus_done" : "pomo_break_done");
        state.pomodoro = p.phase === "focus" ? { phase: "break", until: Date.now() + 5 * MIN } : { phase: "focus", until: Date.now() + 25 * MIN };
        render(); notify(msg);
      }
    }
  }, 1000);
  setInterval(() => { document.querySelectorAll("[data-since]").forEach(el => { el.textContent = secAgo(el.dataset.since); }); }, 1000);
  setInterval(refreshOccupancy, 10e3);   // Part D: occupancy panel, every 10 s
  setInterval(() => { if (!$("#modalRoot").innerHTML && !state.editing) refresh({ quiet: true }); }, 30e3);
  addEventListener("online", () => refresh({ quiet: true }));
  addEventListener("offline", () => { state.offlineSince = Date.now(); render(); });

  // ---------------- boot ----------------
  (async function boot() {
    paintStatic();
    try {
      state.store = await window.OrynStore.create();
      state.unis = await state.store.getUniversities();
      state.store.subscribe(() => refresh({ quiet: true }));
      await refresh();
      await route();
      console.info(`[OrynTap] running in ${state.store.mode} mode`);
    } catch (e) {
      fail(e);
      $("#view").innerHTML = `<div class="empty"><h2>${esc(t("cant_start"))}</h2><p>${esc(e.message)}</p></div>`;
    }
  })();
})();
