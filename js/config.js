// =====================================================================
// OrynTap configuration
// ---------------------------------------------------------------------
// Leave both values empty  -> the site runs in DEMO MODE (data is kept in
//                             this browser only; great for a quick look).
// Fill them in             -> the site uses your Supabase PostgreSQL database.
//
// Where to find them: Supabase dashboard -> Project Settings -> API
//   * Project URL           -> SUPABASE_URL
//   * anon / public key     -> SUPABASE_ANON_KEY
// The anon key is MEANT to be public: what it can do is limited by the
// Row-Level Security policies in database/01_schema.sql.
// NEVER put the service_role key here.
// =====================================================================
window.ORYNTAP_CONFIG = {
  SUPABASE_URL: "https://ausnycqeqjydsesppdud.supabase.co/rest/v1/",
  SUPABASE_ANON_KEY: "sb_publishable_qrXjBqJlhlxtUoNoUZNcEQ_vdWU2fC2",
  GOOGLE_SIGN_IN: true,
};

