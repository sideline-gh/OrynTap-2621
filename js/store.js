// =====================================================================
// OrynTap data layer.
// Two implementations with the SAME interface:
//   SupabaseStore – real PostgreSQL database (Supabase), used when
//                   js/config.js contains a URL and anon key.
//   DemoStore     – keeps everything in localStorage so the site works
//                   on GitHub Pages before the database is connected.
// =====================================================================
(function () {
  "use strict";

  const HOUR = 3600e3, MIN = 60e3;
  const T = (k, v) => (window.I18N ? window.I18N.t(k, v) : k);

  // Admin accounts. In Supabase mode the database decides (handle_new_user
  // trigger, database/05_update_2026-10-14.sql); this list is used only by
  // the browser demo mode.
  const ADMIN_EMAILS = ["260925@astanait.edu.kz", "261234@astanait.edu.kz", "261584@astanait.edu.kz"];

  // ---------- shared helpers ----------
  function domainOf(email) {
    return String(email || "").trim().toLowerCase().split("@")[1] || "";
  }
  function universityForEmail(unis, email) {
    const d = domainOf(email);
    if (!d) return null;
    return unis.find(u => u.domains.some(x => d === x || d.endsWith("." + x))) || null;
  }
  function validatePassword(p) {
    if (!p || p.length < 8) return T("err_pw_len");
    if (!/[A-Za-z]/.test(p) || !/[0-9]/.test(p)) return T("err_pw_mix");
    return null;
  }
  function cleanName(s) {
    return String(s || "").replace(/[<>]/g, "").trim().slice(0, 50);
  }

  // =================================================================
  // Supabase (PostgreSQL)
  // =================================================================
  class SupabaseStore {
    constructor(url, key) {
      this.mode = "supabase";
      this.sb = window.supabase.createClient(url, key, {
        auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
      });
      this.unis = [];
    }
    async init() {
      // An error from an e-mail confirmation link comes back in the URL.
      const params = new URLSearchParams(location.hash.replace(/^#/, "") + "&" + location.search.replace(/^\?/, ""));
      const err = params.get("error_description");
      if (err) {
        history.replaceState(null, "", location.pathname + "#/profile");
        this.pendingError = /database error/i.test(err) ? T("err_only_uni") : decodeURIComponent(err.replace(/\+/g, " "));
      }
      await this.getUniversities();
    }
    async getUniversities() {
      const { data, error } = await this.sb
        .from("universities").select("id, code, name, address, map_image_url, map_embed_url, email_domains(domain)").order("id");
      if (error) throw error;
      this.unis = data.map(u => ({ ...u, short: u.code, domains: (u.email_domains || []).map(d => d.domain) }));
      return this.unis;
    }
    async getSpaces(universityId) {
      const { data, error } = await this.sb
        .from("space_availability").select("*").eq("university_id", universityId).order("id");
      if (error) throw error;
      return data;
    }
    async getSpacesByIds(ids) {
      if (!ids.length) return [];
      const { data, error } = await this.sb.from("space_availability").select("*").in("id", ids).order("id");
      if (error) throw error;
      return data;
    }
    async getSession() {
      const { data } = await this.sb.auth.getSession();
      const user = data.session && data.session.user;
      if (!user) return null;
      const { data: profile, error } = await this.sb.from("profiles").select("*").eq("id", user.id).maybeSingle();
      if (error) throw error;
      if (!profile) { await this.sb.auth.signOut(); return null; }
      return { user: { id: user.id, email: user.email }, profile };
    }
    async signIn(email, password) {
      const { error } = await this.sb.auth.signInWithPassword({ email: email.trim(), password });
      if (error) throw new Error(error.message === "Invalid login credentials" ? T("err_wrong_login") : error.message);
      return this.getSession();
    }
    async signUp({ email, password, first_name, last_name }) {
      if (!universityForEmail(this.unis, email)) throw new Error(T("err_uni_email"));
      const pErr = validatePassword(password); if (pErr) throw new Error(pErr);
      const { data, error } = await this.sb.auth.signUp({
        email: email.trim(), password,
        options: {
          data: { first_name: cleanName(first_name), last_name: cleanName(last_name), consent: "true" },
          emailRedirectTo: location.origin + location.pathname,
        },
      });
      if (error) throw new Error(/database error/i.test(error.message) ? T("err_only_uni") : error.message);
      if (!data.session) return { needsConfirmation: true };
      return this.getSession();
    }
    async signOut() { await this.sb.auth.signOut(); }
    async updateProfile(id, patch) {
      const { data, error } = await this.sb.from("profiles")
        .update({ first_name: cleanName(patch.first_name), last_name: cleanName(patch.last_name) })
        .eq("id", id).select().single();
      if (error) throw error;
      return data;
    }
    async getActiveCheckIn() {
      const { data, error } = await this.sb.from("check_ins")
        .select("id, space_id, uses_outlet, started_at, expires_at")
        .is("left_at", null).gt("expires_at", new Date().toISOString())
        .order("started_at", { ascending: false }).limit(1);
      if (error) throw error;
      return data[0] || null;
    }
    async checkIn(userId, spaceId, hours, usesOutlet) {
      const { data, error } = await this.sb.from("check_ins").insert({
        user_id: userId, space_id: spaceId, uses_outlet: !!usesOutlet,
        expires_at: new Date(Date.now() + hours * HOUR).toISOString(),
      }).select("id, space_id, uses_outlet, started_at, expires_at").single();
      // Row-Level Security refuses check-ins at another university
      if (error) throw (/row-level security/i.test(error.message || "") ? new Error(T("err_own_uni")) : error);
      return data;
    }
    async leave(checkInId) {
      const { error } = await this.sb.from("check_ins").update({ left_at: new Date().toISOString() }).eq("id", checkInId);
      if (error) throw error;
    }
    async getFavourites() {
      const { data, error } = await this.sb.from("favourites").select("space_id");
      if (error) throw error;
      return data.map(r => r.space_id);
    }
    async setFavourite(userId, spaceId, on) {
      const q = on
        ? this.sb.from("favourites").insert({ user_id: userId, space_id: spaceId })
        : this.sb.from("favourites").delete().eq("user_id", userId).eq("space_id", spaceId);
      const { error } = await q;
      if (error && error.code !== "23505") throw error;
    }
    async updateSpace(id, patch, hours) {
      const { error } = await this.sb.from("study_spaces").update(patch).eq("id", id);
      if (error) throw error;
      const del = await this.sb.from("opening_hours").delete().eq("space_id", id);
      if (del.error) throw del.error;
      if (hours.length) {
        const ins = await this.sb.from("opening_hours").insert(hours.map(h => ({ space_id: id, ...h })));
        if (ins.error) throw ins.error;
      }
    }
    async usageByHour() {
      const { data, error } = await this.sb.rpc("admin_usage_by_hour");
      if (error) throw error;
      return data;
    }
    subscribe(onChange) {
      // R4 / R9: every check-in or leave bumps space_activity -> all browsers refresh
      this.sb.channel("oryntap-live")
        .on("postgres_changes", { event: "*", schema: "public", table: "space_activity" }, onChange)
        .on("postgres_changes", { event: "*", schema: "public", table: "study_spaces" }, onChange)
        .subscribe();
      this.sb.auth.onAuthStateChange((evt) => { if (evt === "SIGNED_IN" || evt === "SIGNED_OUT") onChange(); });
    }
  }

  // =================================================================
  // Demo mode (localStorage) — simulates other students so the cards
  // look alive, and hashes passwords with PBKDF2 even here.
  // =================================================================
  const KEY = "oryntap.demo.v2", SKEY = "oryntap.demo.session";

  async function hashPassword(password, salt) {
    if (window.crypto && crypto.subtle) {
      const enc = new TextEncoder();
      const key = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
      const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", salt: enc.encode(salt), iterations: 100000, hash: "SHA-256" }, key, 256);
      return "pbkdf2$" + Array.from(new Uint8Array(bits)).map(b => b.toString(16).padStart(2, "0")).join("");
    }
    let h = 2166136261; for (const c of salt + password) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); }
    return "fnv$" + (h >>> 0).toString(16);
  }
  const uid = () => (crypto.randomUUID ? crypto.randomUUID() : "u" + Math.random().toString(36).slice(2) + Date.now().toString(36));

  // How full a space usually is at a given hour (0..1)
  function occupancy(kind, hourOfDay) {
    const peak = { library: 0.86, coworking: 0.72, atrium: 0.7, rooms: 0.65, lounge: 0.5, cafe: 0.6 }[kind] || 0.6;
    const curve = Math.exp(-Math.pow((hourOfDay - 14.5) / 4.2, 2));
    return Math.max(0.03, peak * curve);
  }

  class DemoStore {
    constructor(seed) {
      this.mode = "demo";
      this.seed = seed;
      this.unis = seed.universities;
    }
    load() {
      try { return JSON.parse(localStorage.getItem(KEY)) || null; } catch (e) { return null; }
    }
    save(db) {
      try { localStorage.setItem(KEY, JSON.stringify(db)); } catch (e) { /* storage full / blocked */ }
      this.db = db;
    }
    async init() {
      let db = this.load();
      if (!db || db.version !== 2) {
        db = { version: 2, users: [], checkins: [], favourites: [], spaces: {}, activity: {}, sim: {} };
      }
      this.save(db);
    }
    async getUniversities() { return this.unis; }
    spaceRow(base) {
      const o = this.db.spaces[base.id] || {};
      return { ...base, ...o };
    }
    simulate() {
      // Keep a realistic number of "other students" checked in.
      const db = this.db, now = Date.now();
      const local = new Date(now + 5 * HOUR); // Astana, UTC+5
      const hourOfDay = local.getUTCHours() + local.getUTCMinutes() / 60;
      let changed = false;
      for (const base of this.seed.spaces) {
        const s = this.spaceRow(base);
        let list = (db.sim[s.id] || []).filter(x => x.e > now);
        if (list.length !== (db.sim[s.id] || []).length) {
          changed = true;
          db.activity[s.id] = Math.max(db.activity[s.id] || 0, ...(db.sim[s.id] || []).filter(x => x.e <= now).map(x => x.e));
        }
        const open = App.statusOf(s).state !== "closed";
        const target = open ? Math.round(s.seat_capacity * occupancy(s.kind, hourOfDay)) : 0;
        const first = !db.sim[s.id];
        while (list.length < target) {
          const ago = first ? Math.random() * 110 * MIN : Math.random() * 4 * MIN;
          const st = now - ago;
          list.push({ s: st, e: st + (60 + Math.random() * 120) * MIN, o: Math.random() < Math.min(0.55, 0.8 * s.outlet_capacity / s.seat_capacity) });
          db.activity[s.id] = Math.max(db.activity[s.id] || 0, st);
          changed = true;
          if (!first && list.length < target - 3) break; // arrive gradually
        }
        if (!open && list.length) { list = []; changed = true; }
        db.sim[s.id] = list;
      }
      if (changed) this.save(db);
    }
    withCounts(base) {
      const s = this.spaceRow(base), now = Date.now();
      const sim = (this.db.sim[s.id] || []).filter(x => x.e > now);
      const real = this.db.checkins.filter(c => c.space_id === s.id && !c.left_at && Date.parse(c.expires_at) > now);
      const seats = sim.length + real.length;
      const outlets = sim.filter(x => x.o).length + real.filter(c => c.uses_outlet).length;
      return {
        ...s,
        free_seats: Math.max(0, s.seat_capacity - seats),
        free_outlets: Math.max(0, s.outlet_capacity - outlets),
        updated_at: new Date(this.db.activity[s.id] || now - 30 * MIN).toISOString(),
      };
    }
    async getSpaces(universityId) {
      this.db = this.load() || this.db;
      this.simulate();
      return this.seed.spaces.filter(s => s.university_id === universityId).map(s => this.withCounts(s));
    }
    async getSpacesByIds(ids) {
      this.db = this.load() || this.db;
      this.simulate();
      return this.seed.spaces.filter(s => ids.includes(s.id)).map(s => this.withCounts(s));
    }
    currentUser() {
      let id = null; try { id = localStorage.getItem(SKEY); } catch (e) {}
      return this.db.users.find(u => u.id === id) || null;
    }
    async getSession() {
      this.db = this.load() || this.db;
      const u = this.currentUser();
      if (!u) return null;
      const { salt, hash, ...profile } = u;
      return { user: { id: u.id, email: u.email }, profile };
    }
    async signIn(email, password) {
      const u = this.db.users.find(x => x.email === email.trim().toLowerCase());
      if (!u || (await hashPassword(password, u.salt)) !== u.hash) throw new Error(T("err_wrong_login"));
      try { localStorage.setItem(SKEY, u.id); } catch (e) {}
      return this.getSession();
    }
    async signUp({ email, password, first_name, last_name }) {
      email = email.trim().toLowerCase();
      const uni = universityForEmail(this.unis, email);
      if (!uni) throw new Error(T("err_uni_email"));
      const pErr = validatePassword(password); if (pErr) throw new Error(pErr);
      if (this.db.users.some(x => x.email === email)) throw new Error(T("err_exists"));
      if (!cleanName(first_name)) throw new Error(T("err_name"));
      const salt = uid();
      const u = { id: uid(), email, salt, hash: await hashPassword(password, salt), first_name: cleanName(first_name),
        last_name: cleanName(last_name), university_id: uni.id, role: ADMIN_EMAILS.includes(email) ? "admin" : "student", consent_at: new Date().toISOString(), created_at: new Date().toISOString() };
      this.db.users.push(u); this.save(this.db);
      try { localStorage.setItem(SKEY, u.id); } catch (e) {}
      return this.getSession();
    }
    async signOut() { try { localStorage.removeItem(SKEY); } catch (e) {} }
    async updateProfile(id, patch) {
      const u = this.db.users.find(x => x.id === id);
      if (!cleanName(patch.first_name)) throw new Error(T("name_empty"));
      u.first_name = cleanName(patch.first_name); u.last_name = cleanName(patch.last_name);
      this.save(this.db);
      const { salt, hash, ...profile } = u; return profile;
    }
    async getActiveCheckIn() {
      const u = this.currentUser(); if (!u) return null;
      const now = Date.now();
      return this.db.checkins.find(c => c.user_id === u.id && !c.left_at && Date.parse(c.expires_at) > now) || null;
    }
    async checkIn(userId, spaceId, hours, usesOutlet) {
      const now = Date.now();
      const user = this.db.users.find(u => u.id === userId), space = this.seed.spaces.find(s => s.id === spaceId);
      if (!user || !space || user.university_id !== space.university_id) throw new Error(T("err_own_uni"));
      for (const c of this.db.checkins) if (c.user_id === userId && !c.left_at) c.left_at = new Date(Math.min(now, Date.parse(c.expires_at))).toISOString();
      const c = { id: now, user_id: userId, space_id: spaceId, uses_outlet: !!usesOutlet,
        started_at: new Date(now).toISOString(), expires_at: new Date(now + Math.min(3, Math.max(0.25, hours)) * HOUR).toISOString(), left_at: null };
      this.db.checkins.push(c); this.db.activity[spaceId] = now; this.save(this.db);
      return c;
    }
    async leave(checkInId) {
      const c = this.db.checkins.find(x => x.id === checkInId);
      if (c && !c.left_at) { c.left_at = new Date().toISOString(); this.db.activity[c.space_id] = Date.now(); this.save(this.db); }
    }
    async getFavourites() {
      const u = this.currentUser(); if (!u) return [];
      return this.db.favourites.filter(f => f.user_id === u.id).map(f => f.space_id);
    }
    async setFavourite(userId, spaceId, on) {
      this.db.favourites = this.db.favourites.filter(f => !(f.user_id === userId && f.space_id === spaceId));
      if (on) this.db.favourites.push({ user_id: userId, space_id: spaceId, created_at: new Date().toISOString() });
      this.save(this.db);
    }
    async updateSpace(id, patch, hours) {
      const u = this.currentUser();
      const base = this.seed.spaces.find(s => s.id === id);
      if (!u || u.role !== "admin" || u.university_id !== base.university_id) throw new Error(T("err_admin_only"));
      this.db.spaces[id] = { ...(this.db.spaces[id] || {}), ...patch, hours };
      this.db.activity[id] = Date.now();
      this.save(this.db);
    }
    async usageByHour() {
      const u = this.currentUser(); if (!u || u.role !== "admin") return [];
      // Demo: synthesise a believable profile from the occupancy curve
      const out = [];
      for (const s of this.seed.spaces.filter(x => x.university_id === u.university_id)) {
        for (let h = 8; h <= 22; h++) out.push({ space_id: s.id, space_name: s.name, hour_of_day: h,
          check_ins: Math.round(s.seat_capacity * occupancy(s.kind, h) * 0.6) });
      }
      return out;
    }
    subscribe(onChange) {
      // Other tabs of the same browser act as "other devices" in demo mode.
      window.addEventListener("storage", (e) => { if (e.key === KEY || e.key === SKEY) onChange(); });
    }
  }

  // ---------- factory ----------
  function loadScript(src) {
    return new Promise((res, rej) => {
      const s = document.createElement("script");
      s.src = src; s.onload = res; s.onerror = () => rej(new Error("Could not load " + src));
      document.head.appendChild(s);
    });
  }

  window.OrynStore = {
    universityForEmail, domainOf,
    async create() {
      const cfg = window.ORYNTAP_CONFIG || {};
      // Accept "https://xyz.supabase.co/rest/v1/" too: the client adds /rest/v1 itself
      const url = String(cfg.SUPABASE_URL || "").trim().replace(/\/(rest|auth)\/v1\/?$/, "").replace(/\/+$/, "");
      const key = String(cfg.SUPABASE_ANON_KEY || "").trim();
      if (url && key) {
        try {
          const cdns = [
            "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js",
            "https://unpkg.com/@supabase/supabase-js@2.45.4/dist/umd/supabase.js",
          ];
          for (const src of cdns) { try { await loadScript(src); break; } catch (e) { console.warn(e.message); } }
          if (!window.supabase) throw new Error("Supabase library could not be loaded");
          const st = new SupabaseStore(url, key);
          await st.init();
          return st;
        } catch (e) {
          console.error("[OrynTap] Supabase unavailable, falling back to demo mode:", e);
          const st = new DemoStore(window.ORYNTAP_DEMO);
          st.fallbackReason = String((e && e.message) || e);
          await st.init();
          return st;
        }
      }
      const st = new DemoStore(window.ORYNTAP_DEMO);
      await st.init();
      return st;
    },
  };
})();
