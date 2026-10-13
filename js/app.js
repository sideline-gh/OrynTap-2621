(function () {
  "use strict";

  const $ = (sel, root = document) => root.querySelector(sel);
  const esc = (s) => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const MIN = 60e3, HOUR = 3600e3;
  const LS = {
    get(k, d) { try { const v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} },
  };

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
    pin: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 2a7 7 0 0 0-7 7c0 5.3 7 13 7 13s7-7.7 7-13a7 7 0 0 0-7-7zm0 9.5A2.5 2.5 0 1 1 12 6.5a2.5 2.5 0 0 1 0 5z"/></svg>',
  };
  const heartIcon = (on) => on ? I.heartFill.replace('class="i-fill"', "") : I.heartLine.replace('class="i-line"', "");

  const TZ_OFFSET = 5 * HOUR; 
  const DAYS = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  function astana(now = Date.now()) {
    const d = new Date(now + TZ_OFFSET);
    return { wd: ((d.getUTCDay() + 6) % 7) + 1, min: d.getUTCHours() * 60 + d.getUTCMinutes() };
  }
  const toMin = (t) => { const [h, m] = String(t).split(":").map(Number); return h * 60 + m; };
  const hhmm = (t) => (t === "24:00" ? "00:00" : String(t).slice(0, 5));

  function statusOf(space, now = Date.now()) {
    const hours = space.hours || [];
    const { wd, min } = astana(now);
    const byDay = {}; hours.forEach(h => { byDay[h.weekday] = h; });
    const is247 = hours.length === 7 && hours.every(h => hhmm(h.opens) === "00:00" && h.closes.startsWith("24"));
    if (is247) return { state: "open", label: "Open", detail: "Open 24/7" };
    const today = byDay[wd];
    if (today) {
      const o = toMin(today.opens), c = toMin(today.closes);
      if (min >= o && min < c) {
        const left = c - min;
        return { state: left <= 60 ? "soon" : "open", label: left <= 60 ? "Closes soon" : "Open", detail: "Closes at " + hhmm(today.closes) };
      }
      if (min < o) return { state: "closed", label: "Closed", detail: "Opens at " + hhmm(today.opens) };
    }
    for (let i = 1; i <= 7; i++) {
      const d = ((wd - 1 + i) % 7) + 1;
      if (byDay[d]) return { state: "closed", label: "Closed", detail: "Opens " + (i === 1 ? "tomorrow" : DAYS[d]) + " " + hhmm(byDay[d].opens) };
    }
    return { state: "closed", label: "Closed", detail: "Temporarily closed" };
  }
  function ago(iso) {
    const m = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / MIN));
    if (m < 1) return "Updated just now";
    if (m < 60) return `Updated ${m} min ago`;
    if (m < 60 * 24) return `Updated ${Math.round(m / 60)} h ago`;
    return `Updated ${Math.round(m / 1440)} d ago`;
  }
  const fmtLeft = (ms) => {
    const s = Math.max(0, Math.round(ms / 1000)), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), ss = s % 60;
    return h ? `${h}h ${String(m).padStart(2, "0")}m` : `${m}:${String(ss).padStart(2, "0")}`;
  };

  window.App = { statusOf };

  const state = {
    store: null, unis: [], uniId: LS.get("oryntap.uni", null),
    spaces: [], favSpaces: [], session: null, active: null, favs: new Set(),
    filters: new Set(LS.get("oryntap.filters", [])),
    route: "home", editing: false, authMode: "login", loading: true,
    offlineSince: null, pomodoro: null,
  };
  const isAdmin = () => state.session && state.session.profile.role === "admin";
  const uni = () => state.unis.find(u => u.id === state.uniId);

  function toast(msg, err) {
    const t = document.createElement("div");
    t.className = "toast" + (err ? " err" : ""); t.textContent = msg;
    $("#toasts").appendChild(t);
    setTimeout(() => t.remove(), err ? 6000 : 3500);
  }
  const fail = (e) => { console.error(e); toast(e && e.message ? e.message : "Something went wrong", true); };

  function paintTheme() {
    const dark = document.documentElement.getAttribute("data-theme") === "dark";
    $("#themeKnob").innerHTML = dark ? I.moon : I.sun;
    $("#themeBtn").setAttribute("aria-label", dark ? "Switch to light theme" : "Switch to dark theme");
    document.querySelector('meta[name="theme-color"]').setAttribute("content", dark ? "#2a2d31" : "#ffffff");
  }
  $("#themeBtn").addEventListener("click", () => {
    const next = document.documentElement.getAttribute("data-theme") === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", next);
    try { localStorage.setItem("oryntap.theme", next); } catch (e) {}
    paintTheme();
  });

  function paintUniPicker() {
    const u = uni();
    $("#uniLabel").innerHTML = u ? `<span class="full">${esc(u.name)}</span><span class="short-only">${esc(u.short)}</span>` : "Choose university";
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

  function navItems() {
    const items = [
      { r: "home", label: "Home", line: I.homeLine, fill: I.homeFill },
      { r: "map", label: "Campus Map", line: I.mapLine, fill: I.mapFill },
      { r: "favourites", label: "Favourites", line: I.heartLine, fill: I.heartFill },
      { r: "profile", label: "Profile", line: I.userLine, fill: I.userFill },
    ];
    return isAdmin() ? items.filter(i => i.r !== "favourites") : items;
  }
  function paintNav() {
    const items = navItems();
    const html = items.map(i => `<li><a href="#/${i.r}" ${state.route === i.r ? 'aria-current="page"' : ""}>${i.line}${i.fill}<span>${i.label}</span></a></li>`).join("");
    $("#nav").innerHTML = html;
    $("#tabbar").innerHTML = items.map(i => `<a href="#/${i.r}" ${state.route === i.r ? 'aria-current="page"' : ""}>${i.line}${i.fill}<span>${i.label.replace("Campus ", "")}</span></a>`).join("");
    $("#tabbar").style.setProperty("--tabs", items.length);
  }

  const cacheKey = () => "oryntap.cache." + state.uniId;
  async function refresh() {
    const st = state.store;
    try {
      state.session = await st.getSession();
      if (state.uniId == null || !state.unis.some(u => u.id === state.uniId)) {
        state.uniId = state.session ? state.session.profile.university_id : state.unis[0].id;
        LS.set("oryntap.uni", state.uniId);
      }
      const [spaces, active, favs] = await Promise.all([
        st.getSpaces(state.uniId),
        state.session ? st.getActiveCheckIn() : null,
        state.session && !isAdmin() ? st.getFavourites() : [],
      ]);
      state.spaces = spaces; state.active = active; state.favs = new Set(favs);
      state.favSpaces = state.route === "favourites" && favs.length ? await st.getSpacesByIds(favs) : state.favSpaces.filter(s => favs.includes(s.id));
      state.offlineSince = null;
      LS.set(cacheKey(), { at: Date.now(), spaces });
    } catch (e) {
      console.warn("[OrynTap] refresh failed", e);
      const cache = LS.get(cacheKey(), null);
      if (cache) { state.spaces = cache.spaces; state.offlineSince = cache.at; }
      else if (!state.spaces.length) toast("Can't load study spaces. Check your connection.", true);
    }
    state.loading = false;
    paintUniPicker();
    render();
  }

  function render() {
    paintNav();
    const v = $("#view");
    const views = { home: viewHome, map: viewMap, favourites: viewFavourites, profile: viewProfile };
    v.innerHTML = (views[state.route] || viewHome)();
    afterRender();
  }

  function modeBanner() {
    let html = "";
    if (state.offlineSince) html += `<div class="banner warn" role="status"><strong>Offline</strong> — showing the last known data (${esc(ago(new Date(state.offlineSince).toISOString()).replace("Updated ", "updated "))}).</div>`;
    if (state.store.fallbackReason) html += `<div class="banner warn">${esc(state.store.fallbackReason)}</div>`;
    return html;
  }

  function sessionBanner() {
    const a = state.active; if (!a) return "";
    const s = state.spaces.find(x => x.id === a.space_id) || state.favSpaces.find(x => x.id === a.space_id);
    const name = s ? s.name : "your study space";
    const p = state.pomodoro;
    return `<section class="session" aria-label="Current study session">
      <div>
        <h2>You're studying at ${esc(name)}</h2>
        <p>Check-in ends in <span class="timer" data-until="${esc(a.expires_at)}">${fmtLeft(Date.parse(a.expires_at) - Date.now())}</span>${a.uses_outlet ? " · using a power outlet" : ""}${p ? ` · ${p.phase === "focus" ? "Focus" : "Break"} <span class="timer" data-pomo>${fmtLeft(p.until - Date.now())}</span>` : ""}</p>
      </div>
      <div class="actions">
        <button class="btn small" data-act="pomodoro">${p ? "Stop timer" : "Pomodoro 25:00"}</button>
        <button class="btn small primary" data-act="leave">Leave</button>
      </div>
    </section>`;
  }

  const approx = (s) => (s.counts_exact ? "" : "~");
  function factList(s) {
    const t = approx(s);
    const f = [
      `Free seats (${t}${s.free_seats}/${s.seat_capacity})`,
      `Free power outlets (${t}${s.free_outlets}/${s.outlet_capacity})`,
    ];
    if (s.is_quiet) f.push("Quiet Place (Yes)");
    if (s.group_work) f.push("For group work (Yes)");
    if (s.food_allowed) f.push("Food allowed (Yes)");
    if (!s.is_quiet && !s.group_work && !s.food_allowed) f.push("Quiet Place (No)");
    return `<ul class="facts">${f.map(x => `<li>${esc(x)}</li>`).join("")}</ul>`;
  }

  function card(s, opts = {}) {
    const st = statusOf(s);
    const here = state.active && state.active.space_id === s.id;
    const fav = state.favs.has(s.id);
    const where = [s.building, s.floor].filter(Boolean).join(" · ");
    const corner = isAdmin()
      ? (state.session.profile.university_id === s.university_id ? `<button class="edit-btn" data-act="edit" data-id="${s.id}">Edit</button>` : "")
      : `<button class="heart-btn" data-act="fav" data-id="${s.id}" aria-pressed="${fav}" aria-label="${fav ? "Remove from" : "Add to"} favourites: ${esc(s.name)}">${heartIcon(fav)}</button>`;
    let actions = "";
    if (isAdmin()) {
      if (state.session.profile.university_id === s.university_id) actions = `<button class="btn small" data-act="qr" data-id="${s.id}">QR code for check-in</button>`;
    } else if (here) {
      actions = `<button class="btn small primary" data-act="leave">Leave</button>`;
    } else {
      actions = `<button class="btn small ${st.state === "closed" ? "" : "primary"}" data-act="checkin" data-id="${s.id}" ${st.state === "closed" ? "disabled" : ""}>${st.state === "closed" ? "Closed now" : "I'm studying here"}</button>`;
    }
    const uniTag = opts.showUni ? `<p class="uni-tag">${esc((state.unis.find(u => u.id === s.university_id) || {}).name || "")}</p>` : "";
    return `<article class="card" id="space-${s.id}">
      <figure class="photo-wrap">
        <img class="photo" src="${esc(s.image_url)}" alt="${esc(s.name)} — ${esc(s.description || "study space")}" loading="lazy" referrerpolicy="no-referrer"
             onerror="this.onerror=null;this.src='assets/img/fallback-${esc(s.kind)}.svg';var c=this.nextElementSibling;if(c)c.remove()">
        ${s.image_credit ? `<figcaption class="credit">Photo: ${esc(s.image_credit)}</figcaption>` : ""}
      </figure>
      <div class="body">
        ${corner}
        <h3>${esc(s.name)}</h3>
        ${uniTag}
        ${here ? `<span class="here-badge">● You are here</span>` : ""}
        <p class="status"><span class="st ${st.state}">${esc(st.label)}</span><span class="sep" aria-hidden="true"></span><span>${esc(st.detail)}</span><span class="upd">(${esc(ago(s.updated_at))})</span></p>
        ${where ? `<p class="where">${I.pin}<span>${esc(where)}</span></p>` : ""}
        ${factList(s)}
        <div class="card-actions">${actions}</div>
      </div>
    </article>`;
  }

  const FILTERS = [
    { k: "outlets", label: "Free power outlets", test: s => s.free_outlets > 0 },
    { k: "quiet", label: "Quiet Place", test: s => s.is_quiet },
    { k: "group", label: "Group work", test: s => s.group_work },
    { k: "food", label: "Food allowed", test: s => s.food_allowed },
    { k: "open", label: "Open Now", test: s => statusOf(s).state !== "closed" },
  ];

  function viewHome() {
    const chips = FILTERS.map(f => `<button class="chip" data-filter="${f.k}" aria-pressed="${state.filters.has(f.k)}">${f.label}</button>`).join("");
    let body;
    if (state.loading) body = `<div class="skeleton"></div><div class="skeleton"></div>`;
    else {
      const active = FILTERS.filter(f => state.filters.has(f.k));
      const order = { open: 0, soon: 1, closed: 2 };
      const here = (s) => (state.active && state.active.space_id === s.id ? 1 : 0);
      const list = state.spaces.filter(s => active.every(f => f.test(s)))
        .sort((a, b) => here(b) - here(a) || order[statusOf(a).state] - order[statusOf(b).state] || (b.free_seats / b.seat_capacity) - (a.free_seats / a.seat_capacity));
      body = list.length ? `<div class="cards">${list.map(s => card(s)).join("")}</div>`
        : `<div class="empty"><h2>No places match these filters</h2><p>Try turning one of them off.</p><button class="btn" data-act="clear-filters">Clear filters</button></div>`;
    }
    return `${modeBanner()}<h1 class="page-title">Find your perfect <span class="accent">Oryn</span></h1>
      ${sessionBanner()}
      <div class="chips" role="group" aria-label="Filters">${chips}</div>
      ${body}`;
  }

  function viewMap() {
    const u = uni();
    let inner;
    const embed = u && u.map_embed_url;
    const mode = embed && state.mapMode !== "live" ? "interactive" : "live";
    const tabs = embed ? `<div class="seg map-tabs" role="tablist" aria-label="Map view">
        <button type="button" role="tab" aria-selected="${mode === "interactive"}" aria-checked="${mode === "interactive"}" data-act="map-mode" data-mode="interactive">Interactive map</button>
        <button type="button" role="tab" aria-selected="${mode === "live"}" aria-checked="${mode === "live"}" data-act="map-mode" data-mode="live">Live seats</button>
      </div>` : "";
    if (embed && mode === "interactive") {
      inner = `<div class="map-frame map-embed"><iframe src="${esc(embed)}" title="Interactive campus map of ${esc(u.name)}: floors, blocks and room search" loading="lazy" allow="fullscreen"></iframe></div>
        <p class="map-credit">Choose a floor and block or search for a room. Interactive map by <a href="https://github.com/Yuujiso/aitumap" target="_blank" rel="noopener">Yuujiso</a> (MIT licence) · <a href="${esc(embed)}" target="_blank" rel="noopener">Open full screen ↗</a></p>`;
    } else if (u && u.map_image_url) {
      const pins = state.spaces.filter(s => s.map_x != null).map(s =>
        `<button class="pin" style="left:${s.map_x}%;top:${s.map_y}%" data-act="goto" data-id="${s.id}" aria-label="${esc(s.name)}: about ${s.free_seats} free seats"><span class="pin-name">${esc(s.name)} · </span>${approx(s)}${s.free_seats} free</button>`).join("");
      inner = `<div class="map-frame"><div class="map-inner"><img src="${esc(u.map_image_url)}" alt="Floor plan of ${esc(u.name)}, block C1, first floor: Library, Assembly Hall, Coworking, Atrium and Dining Hall">${pins}</div>
        <p class="legend">Pins show live free seats. Tap a pin to open the place.</p></div>`;
    } else {
      inner = `<div class="map-frame"><div class="map-placeholder">
        <h2>${esc(u ? u.name : "Campus")}</h2>
        <p>${esc(u ? u.address : "")}, Astana. Indoor floor plan is coming soon — here is where each study space is.</p>
        <a class="btn" href="https://2gis.kz/astana/search/${encodeURIComponent(u ? u.name : "")}" target="_blank" rel="noopener">Open in 2GIS</a>
      </div></div>`;
    }
    const list = `<ul class="where-list">${state.spaces.map(s => `<li><strong>${esc(s.name)}</strong><span class="muted">${esc([s.building, s.floor].filter(Boolean).join(" · ") || "—")}</span><br><span>${esc(statusOf(s).label)} · ${approx(s)}${s.free_seats} free seats</span></li>`).join("")}</ul>`;
    return `${modeBanner()}<h1 class="page-title">Campus <span class="accent">Map</span></h1>${tabs}${inner}${list}`;
  }

  function viewFavourites() {
    let body;
    if (!state.session) body = `<div class="empty"><h2>Log in to save places</h2><p>Your favourites are stored in your account, so they stay after reloading and on every device.</p><a class="btn primary" href="#/profile">Log In</a></div>`;
    else if (!state.favs.size) body = `<div class="empty"><h2>No favourites yet</h2><p>Tap the heart on any place to keep it here.</p><a class="btn" href="#/home">Browse places</a></div>`;
    else body = `<div class="cards">${state.favSpaces.filter(s => state.favs.has(s.id)).map(s => card(s, { showUni: s.university_id !== state.uniId })).join("")}</div>`;
    return `${modeBanner()}<h1 class="page-title">Your Favourite <span class="accent">Places</span></h1>${sessionBanner()}${body}`;
  }

  function viewProfile() {
    const s = state.session;
    if (!s) {
      const u = uni();
      const ph = !u ? "barcode@astanait.edu.kz" : u.short === "AITU" ? "barcode@astanait.edu.kz" : u.short === "NU" ? "name.surname@nu.edu.kz" : `your.name@${u.domains[0]}`;
      const demoHint = state.store.mode === "demo"
        ? `<p class="hint"><strong>Demo mode</strong> — data is stored only in this browser. Create an account with any university e-mail, or log in as an administrator: <code>admin@${esc(u ? u.domains[0] : "astanait.edu.kz")}</code> / <code>Admin2026!</code></p>` : "";
      if (state.authMode === "signup") {
        return `<form class="box auth-box" id="signupForm" novalidate>
          <h2>Sign Up</h2>
          <p class="form-error" id="formErr" role="alert"></p>
          <label class="field"><span class="sr-only">Name</span><input class="input" name="first_name" placeholder="Name" autocomplete="given-name" required maxlength="50"></label>
          <label class="field"><span class="sr-only">Surname</span><input class="input" name="last_name" placeholder="Surname" autocomplete="family-name" maxlength="50"></label>
          <label class="field"><span class="sr-only">University e-mail</span><input class="input" name="email" type="email" placeholder="${esc(ph)}" autocomplete="email" required></label>
          <label class="field"><span class="sr-only">Password</span><input class="input" name="password" type="password" placeholder="Password (8+ characters, letters and numbers)" autocomplete="new-password" required minlength="8"></label>
          <button class="btn primary block" type="submit">Create account</button>
          <p class="auth-alt">Already have an account? <button type="button" class="btn link" data-act="auth-mode" data-mode="login">Log In</button></p>
          ${demoHint}
        </form>`;
      }
      return `<form class="box auth-box" id="loginForm" novalidate>
        <h2>Log In</h2>
        <p class="form-error" id="formErr" role="alert"></p>
        <label class="field"><span class="sr-only">University e-mail</span><input class="input" name="email" type="email" placeholder="${esc(ph)}" autocomplete="username" required></label>
        <label class="field"><span class="sr-only">Password</span><input class="input" name="password" type="password" placeholder="Password" autocomplete="current-password" required></label>
        <button class="btn primary block" type="submit">Log In</button>
        <div style="height:20px"></div>
        <button class="btn block google" type="button" data-act="google">Continue with Google</button>
        <p class="auth-alt">New here? <button type="button" class="btn link" data-act="auth-mode" data-mode="signup">Create an account</button></p>
        ${demoHint}
      </form>`;
    }
    const p = s.profile, u = state.unis.find(x => x.id === p.university_id);
    const roleName = p.role === "admin" ? "Administrator" : "Student";
    if (state.editing) {
      return `<form class="box profile-box" id="profileForm">
        <h2 style="margin-bottom:22px">${esc(p.first_name)} ${esc(p.last_name)}</h2>
        <p class="form-error" id="formErr" role="alert"></p>
        <div class="edit-grid">
          <label for="pf1">Name</label><input class="input" id="pf1" name="first_name" value="${esc(p.first_name)}" required maxlength="50">
          <label for="pf2">Surname</label><input class="input" id="pf2" name="last_name" value="${esc(p.last_name)}" maxlength="50">
          <label for="pf3">University</label><input class="input" id="pf3" value="${esc(u ? u.name : "")}" disabled>
          <label for="pf4">Role</label><input class="input" id="pf4" value="${roleName}" disabled>
        </div>
        <div class="form-actions"><button class="btn primary" type="submit">Save all changes</button><button class="btn secondary" type="button" data-act="cancel-edit">Cancel</button></div>
      </form>`;
    }
    return `<section class="box profile-box">
        <h2>Welcome back, <span class="accent">${esc(p.first_name)} ${esc(p.last_name)}!</span></h2>
        <div class="sub">User details</div>
        <div class="profile-head">
          <dl>
            <div><dt>Name</dt><dd>${esc(p.first_name)}</dd></div>
            <div><dt>Surname</dt><dd>${esc(p.last_name) || "—"}</dd></div>
            <div><dt>E-mail</dt><dd>${esc(s.user.email)}</dd></div>
            <div><dt>University</dt><dd>${esc(u ? u.name : "")}</dd></div>
            <div><dt>Role</dt><dd>${roleName}</dd></div>
          </dl>
          <button class="btn link" data-act="edit-profile">Edit profile</button>
        </div>
        <div style="margin-top:28px"><button class="btn" data-act="logout">Log out</button></div>
      </section>
      ${isAdmin() ? `<section class="box insights" id="insights"><h2>Busiest hours</h2><p class="muted">Check-ins per hour of the day over the last 30 days — shows where and when seats run short.</p><div id="insightBody" class="skeleton" style="height:120px"></div></section>` : ""}`;
  }

  async function loadInsights() {
    const el = $("#insightBody"); if (!el) return;
    try {
      const rows = await state.store.usageByHour();
      const by = {};
      rows.forEach(r => { (by[r.space_id] = by[r.space_id] || { name: r.space_name, h: {} }).h[r.hour_of_day] = Number(r.check_ins); });
      const hours = Array.from({ length: 15 }, (_, i) => i + 8);
      el.className = "";
      el.innerHTML = Object.values(by).map(sp => {
        const max = Math.max(1, ...Object.values(sp.h));
        const peak = Object.entries(sp.h).sort((a, b) => b[1] - a[1])[0];
        return `<div class="insight-row"><h3>${esc(sp.name)}</h3><p>Peak around ${peak ? peak[0] + ":00" : "—"}</p>
          <div class="bars" aria-hidden="true">${hours.map(h => `<span style="height:${Math.round(((sp.h[h] || 0) / max) * 100)}%" title="${h}:00 — ${sp.h[h] || 0}"></span>`).join("")}</div>
          <div class="bar-labels">${hours.map(h => `<span>${h % 2 ? "" : h}</span>`).join("")}</div></div>`;
      }).join("") || "<p class='muted'>No check-ins yet.</p>";
    } catch (e) { el.className = ""; el.innerHTML = `<p class="muted">Could not load insights.</p>`; }
  }

  function afterRender() {
    if (state.route === "profile" && isAdmin() && !state.editing) loadInsights();
    const lf = $("#loginForm"), sf = $("#signupForm"), pf = $("#profileForm");
    if (lf) lf.addEventListener("submit", onLogin);
    if (sf) sf.addEventListener("submit", onSignup);
    if (pf) pf.addEventListener("submit", onSaveProfile);
    if (state.store.pendingError) { toast(state.store.pendingError, true); state.store.pendingError = null; }
  }

  function requireLogin(msg) {
    if (state.session) return true;
    toast(msg || "Please log in first.");
    location.hash = "#/profile";
    return false;
  }
  async function onLogin(e) {
    e.preventDefault();
    const f = new FormData(e.target), btn = e.target.querySelector("[type=submit]");
    const email = String(f.get("email") || "").trim(), pw = String(f.get("password") || "");
    if (!email || !pw) { $("#formErr").textContent = "Enter your e-mail and password."; return; }
    btn.disabled = true;
    try {
      await state.store.signIn(email, pw);
      toast("Welcome back!");
      state.uniId = null; await refresh();
      const back = sessionStorage.getItem("oryntap.after"); sessionStorage.removeItem("oryntap.after");
      location.hash = back || "#/home";
    } catch (err) { $("#formErr").textContent = err.message; }
    finally { btn.disabled = false; }
  }
  async function onSignup(e) {
    e.preventDefault();
    const f = Object.fromEntries(new FormData(e.target)), btn = e.target.querySelector("[type=submit]");
    btn.disabled = true;
    try {
      const res = await state.store.signUp(f);
      if (res && res.needsConfirmation) { toast("Almost done! Check your university inbox to confirm the e-mail."); state.authMode = "login"; render(); return; }
      toast("Account created. Welcome to OrynTap!");
      state.uniId = null; await refresh(); location.hash = "#/home";
    } catch (err) { $("#formErr").textContent = err.message; }
    finally { btn.disabled = false; }
  }
  async function onSaveProfile(e) {
    e.preventDefault();
    const f = Object.fromEntries(new FormData(e.target));
    if (!String(f.first_name || "").trim()) { $("#formErr").textContent = "Name cannot be empty."; return; }
    try {
      state.session.profile = { ...state.session.profile, ...(await state.store.updateProfile(state.session.user.id, f)) };
      state.editing = false; toast("Profile saved."); render();
    } catch (err) { $("#formErr").textContent = err.message; }
  }

  async function toggleFav(id) {
    if (!requireLogin("Log in to save favourite places.")) return;
    const on = !state.favs.has(id);
    on ? state.favs.add(id) : state.favs.delete(id);
    render();
    try {
      await state.store.setFavourite(state.session.user.id, id, on);
      if (on && !state.favSpaces.some(s => s.id === id)) {
        const s = state.spaces.find(x => x.id === id); if (s) state.favSpaces.push(s);
      }
      toast(on ? "Added to favourites" : "Removed from favourites");
    } catch (e) { on ? state.favs.delete(id) : state.favs.add(id); render(); fail(e); }
  }

  function openModal(html, onMount) {
    const root = $("#modalRoot");
    const last = document.activeElement;
    root.innerHTML = `<div class="modal-backdrop" data-close><div class="modal" role="dialog" aria-modal="true">${html}</div></div>`;
    const close = () => { root.innerHTML = ""; document.removeEventListener("keydown", onKey); if (last && last.focus) last.focus(); };
    const onKey = (e) => { if (e.key === "Escape") close(); };
    document.addEventListener("keydown", onKey);
    root.querySelector(".modal-backdrop").addEventListener("click", (e) => { if (e.target.hasAttribute("data-close") || e.target.closest("[data-dismiss]")) close(); });
    const first = root.querySelector("button, input, select, textarea"); if (first) first.focus();
    if (onMount) onMount(root.querySelector(".modal"), close);
  }

  function openCheckIn(space) {
    if (!requireLogin("Log in with your university account to check in.")) { sessionStorage.setItem("oryntap.after", "#/checkin/" + space.id); return; }
    const st = statusOf(space);
    if (st.state === "closed") { toast(`${space.name} is closed now. ${st.detail}.`, true); return; }
    const other = state.active && state.active.space_id !== space.id ? (state.spaces.find(s => s.id === state.active.space_id) || {}).name || "another place" : null;
    let hours = 2;
    openModal(`<h2>Check in to ${esc(space.name)}</h2>
      <p class="lead">${approx(space)}${space.free_seats} of ${space.seat_capacity} seats free · ${esc(st.detail)}</p>
      <div id="ciLabel" style="font-weight:600">How long will you study?</div>
      <div class="seg" role="radiogroup" aria-labelledby="ciLabel">${[1, 2, 3].map(h => `<button type="button" role="radio" aria-checked="${h === hours}" data-h="${h}">${h} h</button>`).join("")}</div>
      <label class="check"><input type="checkbox" id="ciOutlet" ${space.free_outlets > 0 ? "checked" : "disabled"}> I'm using a power outlet${space.free_outlets > 0 ? "" : " (none free)"}</label>
      ${other ? `<p class="hint" style="margin:-8px 0 16px">This will end your check-in at ${esc(other)}.</p>` : ""}
      <p class="hint" style="margin:-8px 0 18px">Forgot to press Leave? Your check-in ends automatically when the time is up.</p>
      <div class="form-actions" style="margin-top:0"><button class="btn secondary" data-dismiss>Cancel</button><button class="btn primary" id="ciGo">Start studying</button></div>`,
    (m, close) => {
      m.querySelectorAll("[data-h]").forEach(b => b.addEventListener("click", () => {
        hours = Number(b.dataset.h); m.querySelectorAll("[data-h]").forEach(x => x.setAttribute("aria-checked", String(x === b)));
      }));
      $("#ciGo", m).addEventListener("click", async (e) => {
        e.target.disabled = true;
        try {
          state.active = await state.store.checkIn(state.session.user.id, space.id, hours, $("#ciOutlet", m).checked);
          close(); toast(`Checked in to ${space.name} for ${hours} h. Good luck!`);
          await refresh();
        } catch (err) { e.target.disabled = false; fail(err); }
      });
    });
  }

  async function leave() {
    if (!state.active) return;
    try {
      await state.store.leave(state.active.id);
      state.active = null; state.pomodoro = null;
      toast("You left. Thanks for freeing the seat!");
      await refresh();
    } catch (e) { fail(e); }
  }

  function openEdit(space) {
    const days = [1, 2, 3, 4, 5, 6, 7];
    const byDay = {}; (space.hours || []).forEach(h => { byDay[h.weekday] = h; });
    openModal(`<h2>Edit ${esc(space.name)}</h2>
      <p class="lead">Changes are visible to all students immediately and are written to the audit log.</p>
      <form id="editForm">
        <label class="field"><span>Name</span><input class="input" name="name" value="${esc(space.name)}" required maxlength="80"></label>
        <label class="field"><span>Description</span><textarea class="input" name="description" maxlength="400">${esc(space.description || "")}</textarea></label>
        <div class="row">
          <label class="field"><span>Seats</span><input class="input" name="seat_capacity" type="number" min="1" max="2000" value="${space.seat_capacity}" required></label>
          <label class="field"><span>Power outlets</span><input class="input" name="outlet_capacity" type="number" min="0" max="5000" value="${space.outlet_capacity}" required></label>
        </div>
        <div class="toggles">
          <label class="check"><input type="checkbox" name="is_quiet" ${space.is_quiet ? "checked" : ""}> Quiet place</label>
          <label class="check"><input type="checkbox" name="group_work" ${space.group_work ? "checked" : ""}> Group work</label>
          <label class="check"><input type="checkbox" name="food_allowed" ${space.food_allowed ? "checked" : ""}> Food allowed</label>
        </div>
        <div style="font-weight:600">Opening hours (Astana time)</div>
        <div class="hours-grid">${days.map(d => {
          const h = byDay[d];
          return `<span>${DAYS[d]}</span>
            <input class="input" type="time" name="o${d}" value="${h ? hhmm(h.opens) : "09:00"}" aria-label="${DAYS[d]} opens" ${h ? "" : "disabled"}>
            <input class="input" type="time" name="c${d}" value="${h ? (h.closes.startsWith("24") ? "23:59" : hhmm(h.closes)) : "18:00"}" aria-label="${DAYS[d]} closes" ${h ? "" : "disabled"}>
            <label><input type="checkbox" name="x${d}" ${h ? "" : "checked"}> Off</label>`;
        }).join("")}</div>
        <p class="form-error" id="editErr" role="alert"></p>
        <div class="form-actions" style="margin-top:0"><button class="btn secondary" type="button" data-dismiss>Cancel</button><button class="btn primary" type="submit">Save all changes</button></div>
      </form>`,
    (m, close) => {
      days.forEach(d => m.querySelector(`[name=x${d}]`).addEventListener("change", (e) => {
        m.querySelector(`[name=o${d}]`).disabled = e.target.checked; m.querySelector(`[name=c${d}]`).disabled = e.target.checked;
      }));
      $("#editForm", m).addEventListener("submit", async (e) => {
        e.preventDefault();
        const f = e.target, err = $("#editErr", m);
        const seats = Number(f.seat_capacity.value), outlets = Number(f.outlet_capacity.value);
        if (!f.name.value.trim()) return (err.textContent = "Name is required.");
        if (!(seats >= 1 && seats <= 2000) || !(outlets >= 0 && outlets <= 5000)) return (err.textContent = "Check the seat and outlet numbers.");
        const hours = [];
        for (const d of days) {
          if (f[`x${d}`].checked) continue;
          let o = f[`o${d}`].value, c = f[`c${d}`].value;
          if (c === "23:59" && o === "00:00") c = "24:00";
          if (!o || !c || toMin(c) <= toMin(o)) return (err.textContent = `${DAYS[d]}: closing time must be after opening time.`);
          hours.push({ weekday: d, opens: o, closes: c });
        }
        const patch = { name: f.name.value.trim().slice(0, 80), description: f.description.value.trim().slice(0, 400),
          seat_capacity: seats, outlet_capacity: outlets, is_quiet: f.is_quiet.checked, group_work: f.group_work.checked, food_allowed: f.food_allowed.checked };
        try { await state.store.updateSpace(space.id, patch, hours); close(); toast("Saved."); await refresh(); }
        catch (ex) { err.textContent = ex.message || "Could not save."; }
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
    openModal(`<h2>QR check-in · ${esc(space.name)}</h2>
      <p class="lead">Print this and place it in the zone. Scanning opens the check-in screen.</p>
      <div class="qr" id="qrBox"></div><p class="qr-url">${esc(url)}</p>
      <div class="form-actions"><button class="btn secondary" data-dismiss>Close</button><button class="btn primary" onclick="window.print()">Print</button></div>`);
    try {
      await loadScriptOnce("https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js");
      new window.QRCode($("#qrBox"), { text: url, width: 220, height: 220 });
    } catch (e) { $("#qrBox").textContent = "QR library could not load (offline?)."; }
  }

  function togglePomodoro() {
    if (state.pomodoro) { state.pomodoro = null; render(); return; }
    if ("Notification" in window && Notification.permission === "default") Notification.requestPermission();
    state.pomodoro = { phase: "focus", until: Date.now() + 25 * MIN };
    render();
  }
  function notify(text) {
    toast(text);
    try { if ("Notification" in window && Notification.permission === "granted") new Notification("OrynTap", { body: text }); } catch (e) {}
  }

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
      case "edit": if (space) openEdit(space); break;
      case "qr": if (space) openQR(space); break;
      case "pomodoro": togglePomodoro(); break;
      case "map-mode": state.mapMode = a.dataset.mode; render(); break;
      case "clear-filters": state.filters.clear(); LS.set("oryntap.filters", []); render(); break;
      case "auth-mode": state.authMode = a.dataset.mode; render(); break;
      case "google": state.store.signInWithGoogle().catch(fail); break;
      case "edit-profile": state.editing = true; render(); break;
      case "cancel-edit": state.editing = false; render(); break;
      case "logout":
        state.store.signOut().then(() => { state.session = null; state.active = null; state.favs = new Set(); state.pomodoro = null; toast("Logged out."); location.hash = "#/home"; refresh(); });
        break;
      case "goto": location.hash = "#/home"; setTimeout(() => { const el = document.getElementById("space-" + id); if (el) el.scrollIntoView({ behavior: "smooth", block: "center" }); }, 60); break;
    }
  });

  async function route() {
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
    if (r === "favourites" && state.session && state.favs.size) {
      state.favSpaces = await state.store.getSpacesByIds([...state.favs]).catch(() => state.favSpaces);
    }
    render();
    if (changed) { scrollTo(0, 0); $("#view").focus({ preventScroll: true }); }
  }
  addEventListener("hashchange", route);

  setInterval(() => {
    document.querySelectorAll("[data-until]").forEach(el => {
      const left = Date.parse(el.dataset.until) - Date.now();
      el.textContent = fmtLeft(left);
      if (left <= 0 && state.active) { state.active = null; notify("Your check-in has ended. The seat is free again."); refresh(); }
    });
    const p = state.pomodoro;
    if (p) {
      const left = p.until - Date.now();
      const el = $("[data-pomo]"); if (el) el.textContent = fmtLeft(left);
      if (left <= 0) {
        if (p.phase === "focus") { state.pomodoro = { phase: "break", until: Date.now() + 5 * MIN }; notify("Focus session done — take a 5-minute break."); }
        else { state.pomodoro = { phase: "focus", until: Date.now() + 25 * MIN }; notify("Break is over — back to focus!"); }
        render();
      }
    }
  }, 1000);
  setInterval(() => { if (!$("#modalRoot").innerHTML && !state.editing) refresh(); }, 30e3);
  addEventListener("online", refresh);
  addEventListener("offline", () => { state.offlineSince = Date.now(); render(); });

  (async function boot() {
    paintTheme();
    try {
      state.store = await window.OrynStore.create();
      state.unis = await state.store.getUniversities();
      state.store.subscribe(() => refresh());
      await refresh();
      await route();
      console.info(`[OrynTap] running in ${state.store.mode} mode`);
    } catch (e) {
      fail(e);
      $("#view").innerHTML = `<div class="empty"><h2>OrynTap could not start</h2><p>${esc(e.message)}</p></div>`;
    }
  })();
})();
