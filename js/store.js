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
      // Password reset links come back with ?reset=1 (see requestPasswordReset)
      const isReset = new URLSearchParams(location.search).get("reset") === "1";
      if (isReset) {
        history.replaceState(null, "", location.pathname + (err ? "#/profile" : location.hash));
        if (err) this.pendingReset = "expired";
        else if (params.get("type") === "recovery" && params.get("access_token")) this.pendingReset = "ok";
      } else if (err) {
        history.replaceState(null, "", location.pathname + "#/profile");
        // A confirmation link that has expired or was already used: offer a new one (app.js)
        if (params.get("error_code") === "otp_expired" || /invalid or has expired/i.test(err)) this.pendingVerify = "expired";
        else this.pendingError = /database error/i.test(err) ? T("err_only_uni") : decodeURIComponent(err.replace(/\+/g, " "));
      } else if (params.get("type") === "signup" && params.get("access_token")) {
        this.justConfirmed = true;   // came back from the link in the confirmation e-mail
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
      if (error) {
        // Supabase refuses to log in an account whose e-mail is not confirmed yet
        if (error.code === "email_not_confirmed" || /email not confirmed/i.test(error.message || "")) {
          const e = new Error(T("err_not_confirmed")); e.code = "email_not_confirmed"; throw e;
        }
        throw new Error(error.message === "Invalid login credentials" ? T("err_wrong_login") : error.message);
      }
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
      if (error) {
        if (error.code === "user_already_exists" || /already registered/i.test(error.message || "")) throw new Error(T("err_exists"));
        if (error.status === 429 || error.code === "over_email_send_rate_limit") throw new Error(T("err_resend_wait"));
        throw new Error(/database error/i.test(error.message) ? T("err_only_uni") : error.message);
      }
      // With "Confirm email" on, an e-mail that already has a confirmed account comes back as a user
      // with no identities and no e-mail is sent: say so instead of waiting for a link that never comes.
      if (data.user && Array.isArray(data.user.identities) && data.user.identities.length === 0) throw new Error(T("err_exists"));
      if (!data.session) return { needsConfirmation: true, email: email.trim().toLowerCase() };
      return this.getSession();
    }
    // A new confirmation e-mail (the old link stops working). Supabase allows one per address every 60 s.
    async resendConfirmation(email) {
      const { error } = await this.sb.auth.resend({
        type: "signup", email: email.trim(), options: { emailRedirectTo: location.origin + location.pathname },
      });
      if (error) throw new Error(error.status === 429 || /rate limit|security purposes|seconds/i.test(error.message || "") ? T("err_resend_wait") : error.message);
    }
    // Forgot password: Supabase e-mails a one-time link (same rate limit as above). For privacy the
    // answer is the same whether or not an account with this e-mail exists.
    async requestPasswordReset(email) {
      const { error } = await this.sb.auth.resetPasswordForEmail(email.trim(), {
        redirectTo: location.origin + location.pathname + "?reset=1",
      });
      if (error) throw new Error(error.status === 429 || /rate limit|security purposes|seconds/i.test(error.message || "") ? T("err_resend_wait") : error.message);
    }
    async updatePassword(password) {
      const pErr = validatePassword(password); if (pErr) throw new Error(pErr);
      const { error } = await this.sb.auth.updateUser({ password });
      if (error) throw new Error(/different from the old/i.test(error.message || "") ? T("err_pw_same") : error.message);
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
    // +1 hour, at most 3 h ahead and never past closing time (database/10_improvements.sql)
    async extendCheckIn(checkInId) {
      const { data, error } = await this.sb.rpc("extend_check_in", { p_id: checkInId });
      if (error) throw new Error(/cannot_extend/.test(error.message || "") ? T("ext_max") : /no_active/.test(error.message || "") ? T("checkin_ended") : error.message);
      return new Date(data).toISOString();
    }
    // "Usually busy": finished check-ins per hour of the day, last 8 weeks (aggregates only)
    async getBusyHours(universityId) {
      const { data, error } = await this.sb.rpc("space_busy_hours", { p_university: universityId });
      if (error) return [];   // before 10_improvements.sql is run: simply no hint
      return data;
    }
    async reportCount(spaceId, kind, shownFree) {
      const { error } = await this.sb.rpc("report_count", { p_space: spaceId, p_kind: kind, p_shown_free: shownFree });
      if (error) throw new Error(/too_soon/.test(error.message || "") ? T("rep_too_soon") : /own_university/.test(error.message || "") ? T("err_own_uni") : /not_verified/.test(error.message || "") ? T("err_not_confirmed") : error.message);
    }
    async adminCountReports() {
      const { data, error } = await this.sb.rpc("admin_count_reports");
      if (error) throw error;
      return data;
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
    // Stage 2, Part C5: the same numbers as analysis/queries.sql, for the admin's university
    async spaceStats() {
      const { data, error } = await this.sb.rpc("admin_space_stats");
      if (error) throw error;
      return data;
    }
    async stayStats() {
      const { data, error } = await this.sb.rpc("admin_stay_stats");
      if (error) throw error;
      return data;
    }
    // Stage 2, Part D3: latest door-sensor count per space (view space_sensor_now).
    // Before 07_stage2.sql is run the view does not exist: then there is simply no sensor data.
    async getSensorNow() {
      const { data, error } = await this.sb.from("space_sensor_now").select("*");
      if (error) return {};
      const out = {}; (data || []).forEach(r => { out[r.space_id] = r; }); return out;
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
      const close = App.closingTime(this.spaceRow(space), now);   // ends at closing time at the latest
      const until = Math.min(now + Math.min(3, Math.max(0.25, hours)) * HOUR, close || Infinity);
      const c = { id: now, user_id: userId, space_id: spaceId, uses_outlet: !!usesOutlet,
        started_at: new Date(now).toISOString(), expires_at: new Date(until).toISOString(), left_at: null };
      this.db.checkins.push(c); this.db.activity[spaceId] = now; this.save(this.db);
      return c;
    }
    async leave(checkInId) {
      const c = this.db.checkins.find(x => x.id === checkInId);
      if (c && !c.left_at) { c.left_at = new Date().toISOString(); this.db.activity[c.space_id] = Date.now(); this.save(this.db); }
    }
    async extendCheckIn(checkInId) {   // same rules as extend_check_in() in the database
      const now = Date.now(), c = this.db.checkins.find(x => x.id === checkInId);
      if (!c || c.left_at || Date.parse(c.expires_at) <= now) throw new Error(T("checkin_ended"));
      const space = this.seed.spaces.find(s => s.id === c.space_id);
      const close = App.closingTime(this.spaceRow(space), now);
      const next = Math.min(Date.parse(c.expires_at) + HOUR, now + 3 * HOUR, close || Infinity);
      if (next < Date.parse(c.expires_at) + MIN) throw new Error(T("ext_max"));
      c.expires_at = new Date(next).toISOString(); this.db.activity[c.space_id] = now; this.save(this.db);
      return c.expires_at;
    }
    async getBusyHours(universityId) {   // from the same generated history as the database
      if (!window.ORYNTAP_DEMO_HISTORY) await loadScript("js/demo-history.js");
      const now = Date.now(), today = Math.floor((now + 5 * HOUR) / (24 * HOUR)) * 24 * HOUR - 5 * HOUR;
      const mine = new Set(this.seed.spaces.filter(s => s.university_id === universityId).map(s => s.id));
      const by = {}, n = {};
      for (const [space, d, hm, , stayed] of window.ORYNTAP_DEMO_HISTORY) {
        if (!mine.has(space) || d > 56) continue;
        const [h, m] = hm.split(":").map(Number), start = today - d * 24 * HOUR + (h * 60 + m) * MIN, end = start + stayed * MIN;
        if (end > now) continue;
        n[space] = (n[space] || 0) + 1;
        for (let t = Math.floor((start + 5 * HOUR) / HOUR) * HOUR - 5 * HOUR; t < end; t += HOUR) {
          const hour = new Date(t + 5 * HOUR).getUTCHours(), k = space + ":" + hour; by[k] = (by[k] || 0) + 1;
        }
      }
      return Object.entries(by).filter(([k]) => n[+k.split(":")[0]] >= 15).map(([k, v]) => {
        const [space_id, hour_of_day] = k.split(":").map(Number); return { space_id, hour_of_day, presence: v, check_ins: n[space_id] };
      });
    }
    async reportCount(spaceId, kind, shownFree) {
      const u = this.currentUser(), space = this.seed.spaces.find(s => s.id === spaceId);
      if (!u || !space || u.university_id !== space.university_id) throw new Error(T("err_own_uni"));
      this.db.reports = this.db.reports || [];
      if (this.db.reports.some(r => r.user_id === u.id && r.space_id === spaceId && Date.now() - r.at < 10 * MIN)) throw new Error(T("rep_too_soon"));
      this.db.reports.push({ user_id: u.id, space_id: spaceId, kind, shown_free: shownFree, at: Date.now() });
      this.save(this.db);
    }
    async adminCountReports() {
      const u = this.currentUser(); if (!u || u.role !== "admin") return [];
      const by = {};
      for (const r of this.db.reports || []) {
        const s = this.seed.spaces.find(x => x.id === r.space_id);
        if (!s || s.university_id !== u.university_id || Date.now() - r.at > 7 * 24 * HOUR) continue;
        const row = by[s.id] = by[s.id] || { space_id: s.id, space_name: this.spaceRow(s).name, full_n: 0, empty_n: 0, closed_n: 0, last_at: 0 };
        row[r.kind + "_n"] += 1; row.last_at = Math.max(row.last_at, r.at);
      }
      return Object.values(by).sort((a, b) => b.last_at - a.last_at).map(r => ({ ...r, last_at: new Date(r.last_at).toISOString() }));
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
    // Demo statistics use the same 640 generated check-ins as database/02_seed.sql
    // (js/demo-history.js, loaded only when an admin opens the profile).
    async history() {
      const u = this.currentUser(); if (!u || u.role !== "admin") return null;
      if (!window.ORYNTAP_DEMO_HISTORY) await loadScript("js/demo-history.js");
      const now = Date.now();
      const today = Math.floor((now + 5 * HOUR) / (24 * HOUR)) * 24 * HOUR - 5 * HOUR; // 00:00 in Astana
      const mine = new Set(this.seed.spaces.filter(s => s.university_id === u.university_id).map(s => s.id));
      return window.ORYNTAP_DEMO_HISTORY.map(([space, d, hm, planned, stayed, outlet]) => {
        const [h, m] = hm.split(":").map(Number);
        return { space, start: today - d * 24 * HOUR + (h * 60 + m) * MIN, hour: h, planned, stayed, outlet: !!outlet };
      }).filter(r => mine.has(r.space) && r.start + r.stayed * MIN <= now);   // finished check-ins only
    }
    async usageByHour() {
      const rows = await this.history(); if (!rows) return [];
      const by = {};
      rows.forEach(r => { const k = r.space + ":" + r.hour; by[k] = (by[k] || 0) + 1; });
      return Object.entries(by).map(([k, n]) => {
        const [id, h] = k.split(":").map(Number);
        return { space_id: id, space_name: this.seed.spaces.find(s => s.id === id).name, hour_of_day: h, check_ins: n };
      });
    }
    async spaceStats() {
      const rows = await this.history(); if (!rows) return [];
      const u = this.currentUser();
      return this.seed.spaces.filter(s => s.university_id === u.university_id).map(s => {
        const mine = rows.filter(r => r.space === s.id);
        return { space_id: s.id, space_name: s.name, seats: s.seat_capacity, check_ins: mine.length,
          per_100_seats: Math.round(1000 * mine.length / s.seat_capacity) / 10,
          pct_with_outlet: mine.length ? Math.round(100 * mine.filter(r => r.outlet).length / mine.length) : null };
      }).sort((a, b) => b.per_100_seats - a.per_100_seats);
    }
    async stayStats() {
      const rows = await this.history(); if (!rows) return [];
      return [1, 2, 3].map(h => {
        const g = rows.filter(r => r.planned === h * 60); if (!g.length) return null;
        const early = g.filter(r => r.stayed < r.planned).length;
        return { planned_hours: h, check_ins: g.length,
          avg_stay_min: Math.round(g.reduce((a, r) => a + r.stayed, 0) / g.length),
          pct_left_early: Math.round(100 * early / g.length), pct_ended_by_itself: Math.round(100 * (g.length - early) / g.length) };
      }).filter(Boolean);
    }
    // Demo of the smart extension (Part D): a simulated door counter at the AITU Library,
    // returning the same fields as the view space_sensor_now. A sensor also counts people who
    // did not check in, so it shows a bit more than the check-ins. New value every 10 s.
    async getSensorNow() {
      const aitu = this.unis.find(x => x.code === "AITU"); if (!aitu) return {};
      const s = this.seed.spaces.find(x => x.university_id === aitu.id && x.name === "Library"); if (!s) return {};
      const row = this.withCounts(s);
      const closed = App.statusOf(row).state === "closed";          // closed: a real counter shows ~0
      const tick = Math.floor(Date.now() / 10000), inside = s.seat_capacity - row.free_seats;
      const n = closed ? 0 : Math.min(s.seat_capacity, Math.max(0, Math.round(inside * 1.3 + 4 * Math.sin(tick / 5))));
      return { [s.id]: { space_id: s.id, people_inside: n < 3 ? null : n, few: n < 3, measured_at: new Date(tick * 10000).toISOString(),
        space_name: s.name, seat_capacity: s.seat_capacity, free_seats: n < 3 ? null : Math.max(s.seat_capacity - n, 0) } };
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
