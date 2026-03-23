import Foundation

/// Public Supabase configuration.
///
/// `supabaseURL` and `supabaseAnonKey` are intentionally public — the anon key
/// is a row-level-security token, not a secret. It identifies the project but
/// grants only the permissions defined by your Supabase RLS policies.
///
/// All third-party API keys (API Ninjas, WeatherStack, etc.) live exclusively in
/// Supabase Vault and are never transmitted to the client. The app calls Supabase
/// Edge Functions, which fetch the real keys server-side and proxy the request.
///
/// `appSecret` is a shared secret injected at build time via an Xcode User-Defined
/// Build Setting (APP_SECRET). It is NOT stored in source control — each developer
/// sets it locally. The Edge Functions verify this header to reject calls that
/// didn't originate from the legitimate RPT app build.
enum Secrets {
    /// Supabase project URL — safe to commit.
    static let supabaseURL = "https://erghbsnxtsbnmfuycnyb.supabase.co"

    /// Supabase anon key — safe to commit (public by design).
    /// Set this value from your Supabase project dashboard → Settings → API.
    static let supabaseAnonKey: String = {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
    }()

    /// Shared secret that Edge Functions verify to ensure requests come from RPT.
    /// Value is injected via the APP_SECRET Xcode build setting — never commit
    /// the actual value to source control.
    static let appSecret: String = {
        Bundle.main.object(forInfoDictionaryKey: "APP_SECRET") as? String ?? ""
    }()
}
