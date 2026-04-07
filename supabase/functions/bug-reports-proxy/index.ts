import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// bug-reports-proxy
// ------------------
// Intake + triage support for the System Trainer bug pipeline. Handles four
// actions: submit_in_app (called from the iOS Settings "Report a Bug" button),
// import_testflight (called by the auto-triage Claude Code cron every 4 hours
// to pull new App Store Connect TestFlight beta feedback), list_pending and
// update_status (also used by the cron). All third-party API keys live in
// Supabase Vault — never in the iOS binary.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-app-secret",
};

const ALLOWED_STATUSES = new Set([
  "new",
  "in_progress",
  "needs_design",
  "needs_info",
  "resolved",
  "closed",
  "claude_stop",
]);

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Base64URL encode raw bytes (no padding) — used for JWT segments.
function base64UrlEncode(bytes: Uint8Array): string {
  let str = "";
  for (let i = 0; i < bytes.length; i++) str += String.fromCharCode(bytes[i]);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlEncodeString(s: string): string {
  return base64UrlEncode(new TextEncoder().encode(s));
}

// Decode standard base64 string to bytes.
function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

// Strip PEM armor and base64-decode the body to raw PKCS8 bytes.
function pemToPkcs8Bytes(pem: string): Uint8Array {
  const cleaned = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  return base64ToBytes(cleaned);
}

// Sign an App Store Connect JWT using ES256. The .p8 file Apple gives you is
// already PKCS8-wrapped, so we can hand it straight to Web Crypto.
async function signAppStoreConnectJWT(
  keyId: string,
  issuerId: string,
  privateKeyPem: string,
): Promise<string> {
  const header = { alg: "ES256", kid: keyId, typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: issuerId,
    iat: now,
    exp: now + 20 * 60, // 20 min — Apple's max is 20 min
    aud: "appstoreconnect-v1",
  };

  const headerB64 = base64UrlEncodeString(JSON.stringify(header));
  const payloadB64 = base64UrlEncodeString(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;

  const keyBytes = pemToPkcs8Bytes(privateKeyPem);
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  // Web Crypto returns a raw r||s 64-byte signature for ECDSA P-256, which
  // is the JOSE format JWT expects — no DER unwrapping needed.
  const sigBuf = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );
  const sigB64 = base64UrlEncode(new Uint8Array(sigBuf));
  return `${signingInput}.${sigB64}`;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Defense in depth — every proxy validates the shared app secret.
  const appSecret = Deno.env.get("RPT_APP_SECRET");
  const incomingSecret = req.headers.get("x-app-secret");
  if (!appSecret || !incomingSecret || incomingSecret !== appSecret) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    const body = await req.json().catch(() => ({}));
    const action = body.action ?? "";

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("DB_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );

    // ----------------------------------------------------------------------
    // submit_in_app — called by the iOS "Report a Bug" button
    // ----------------------------------------------------------------------
    if (action === "submit_in_app") {
      const description = (body.description ?? "").toString().trim();
      if (!description) {
        return jsonResponse({ error: "description is required" }, 400);
      }

      const cloudkitUserId = body.cloudkit_user_id ?? null;
      const appVersion = body.app_version ?? "";
      const buildNumber = body.build_number ?? "";
      const deviceModel = body.device_model ?? "";
      const osVersion = body.os_version ?? "";

      // Optional screenshot — base64 JPEG. Decode and upload to storage.
      let screenshotUrl: string | null = null;
      if (body.screenshot_base64 && typeof body.screenshot_base64 === "string") {
        try {
          // Tolerate data URL prefix like "data:image/jpeg;base64,..."
          const raw = body.screenshot_base64.replace(/^data:[^;]+;base64,/, "");
          const bytes = base64ToBytes(raw);
          const userFolder = cloudkitUserId
            ? cloudkitUserId.replace(/[^A-Za-z0-9_-]/g, "_")
            : "anonymous";
          const path = `app/${userFolder}/${crypto.randomUUID()}.jpg`;
          const { error: uploadErr } = await supabase.storage
            .from("bug-screenshots")
            .upload(path, bytes, {
              contentType: "image/jpeg",
              upsert: false,
            });
          if (!uploadErr) {
            const { data: pub } = supabase.storage
              .from("bug-screenshots")
              .getPublicUrl(path);
            screenshotUrl = pub?.publicUrl ?? null;
          } else {
            console.error("screenshot upload failed:", uploadErr);
          }
        } catch (e) {
          // Don't fail the whole submission just because the screenshot
          // couldn't be decoded — the description is the important part.
          console.error("screenshot decode failed:", e);
        }
      }

      const { data: inserted, error: insertErr } = await supabase
        .from("bug_reports")
        .insert({
          source: "app",
          source_id: null,
          app_version: appVersion,
          build_number: buildNumber,
          device_model: deviceModel,
          os_version: osVersion,
          cloudkit_user_id: cloudkitUserId,
          description,
          screenshot_url: screenshotUrl,
          status: "new",
          priority: 0,
        })
        .select("id")
        .single();

      if (insertErr) {
        console.error("bug_reports insert failed:", insertErr);
        return jsonResponse({ error: "Insert failed" }, 500);
      }

      return jsonResponse({ success: true, id: inserted?.id });
    }

    // ----------------------------------------------------------------------
    // import_testflight — called by the auto-triage cron every 4 hours
    // ----------------------------------------------------------------------
    if (action === "import_testflight") {
      const keyId = Deno.env.get("RPT_APP_STORE_CONNECT_KEY_ID") ?? "";
      const issuerId = Deno.env.get("RPT_APP_STORE_CONNECT_ISSUER_ID") ?? "";
      const privateKey = Deno.env.get("RPT_APP_STORE_CONNECT_PRIVATE_KEY") ?? "";

      if (!keyId || !issuerId || !privateKey) {
        // Bootstrap state — owner hasn't added the key yet. Return a
        // friendly success-shape so the cron doesn't blow up.
        return jsonResponse({
          success: false,
          error:
            "App Store Connect API not configured. Add RPT_APP_STORE_CONNECT_KEY_ID / ISSUER_ID / PRIVATE_KEY to Supabase Vault.",
          imported: 0,
        });
      }

      let jwt: string;
      try {
        jwt = await signAppStoreConnectJWT(keyId, issuerId, privateKey);
      } catch (e) {
        console.error("JWT signing failed:", e);
        return jsonResponse({
          success: false,
          error: `JWT signing failed: ${(e as Error).message}`,
          imported: 0,
        });
      }

      const authHeaders = {
        Authorization: `Bearer ${jwt}`,
        "Content-Type": "application/json",
      };

      // Resolve app id from bundle id.
      let appId: string | null = null;
      try {
        const appsRes = await fetch(
          "https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=com.SpiroTechnologies.RPT",
          { headers: authHeaders },
        );
        if (!appsRes.ok) {
          const txt = await appsRes.text();
          return jsonResponse({
            success: false,
            error: `App lookup failed: ${appsRes.status} ${txt.slice(0, 200)}`,
            imported: 0,
          });
        }
        const appsJson = await appsRes.json();
        appId = appsJson?.data?.[0]?.id ?? null;
        if (!appId) {
          return jsonResponse({
            success: false,
            error: "App not found for bundle id com.SpiroTechnologies.RPT",
            imported: 0,
          });
        }
      } catch (e) {
        return jsonResponse({
          success: false,
          error: `App lookup network error: ${(e as Error).message}`,
          imported: 0,
        });
      }

      // Fetch screenshot + crash submissions in parallel.
      const endpoints = [
        `https://api.appstoreconnect.apple.com/v1/apps/${appId}/betaFeedbackScreenshotSubmissions?limit=50&sort=-createdDate`,
        `https://api.appstoreconnect.apple.com/v1/apps/${appId}/betaFeedbackCrashSubmissions?limit=50&sort=-createdDate`,
      ];

      const allItems: Array<Record<string, unknown>> = [];
      for (const url of endpoints) {
        try {
          const res = await fetch(url, { headers: authHeaders });
          if (!res.ok) {
            console.error(`feedback fetch failed ${url}:`, res.status);
            continue;
          }
          const json = await res.json();
          if (Array.isArray(json?.data)) {
            for (const item of json.data) allItems.push(item);
          }
        } catch (e) {
          console.error("feedback fetch error:", e);
        }
      }

      // Cap at 50 inserts per call (safety rule #10).
      const capped = allItems.slice(0, 50);
      let imported = 0;

      for (const item of capped) {
        const sourceId = (item.id as string) ?? null;
        if (!sourceId) continue;
        const attrs = (item.attributes as Record<string, unknown>) ?? {};
        const comment =
          (attrs.comment as string) ||
          (attrs.crashLogFileName as string) ||
          "(no comment provided)";
        const deviceModel = (attrs.deviceModel as string) ?? "";
        const osVersion = (attrs.osVersion as string) ?? "";
        const appVersion =
          (attrs.appVersion as string) ||
          (attrs.bundleShortVersionString as string) ||
          "";
        const buildNumber =
          (attrs.buildNumber as string) ||
          (attrs.bundleVersion as string) ||
          "";
        const testerEmail = (attrs.testerEmail as string) ?? null;

        const { error: insertErr } = await supabase
          .from("bug_reports")
          .insert({
            source: "testflight",
            source_id: sourceId,
            app_version: appVersion,
            build_number: buildNumber,
            device_model: deviceModel,
            os_version: osVersion,
            cloudkit_user_id: null,
            tester_email: testerEmail,
            description: comment,
            screenshot_url: null,
            status: "new",
            priority: 0,
          });

        if (!insertErr) {
          imported += 1;
        } else {
          // Duplicate-key on (source, source_id) is the expected dedupe path.
          const code = (insertErr as { code?: string }).code;
          if (code !== "23505") {
            console.error("testflight insert failed:", insertErr);
          }
        }
      }

      return jsonResponse({
        success: true,
        imported,
        total_fetched: allItems.length,
      });
    }

    // ----------------------------------------------------------------------
    // list_pending — cron pulls the next bug to triage
    // ----------------------------------------------------------------------
    if (action === "list_pending") {
      const limit = Math.min(
        Math.max(parseInt(body.limit ?? "1", 10) || 1, 1),
        50,
      );

      // Global stop switch — if ANY row is in claude_stop, the cron aborts.
      const { data: stopRows, error: stopErr } = await supabase
        .from("bug_reports")
        .select("id")
        .eq("status", "claude_stop")
        .limit(1);
      if (stopErr) {
        console.error("stop check failed:", stopErr);
        return jsonResponse({ error: "Query failed" }, 500);
      }
      if (stopRows && stopRows.length > 0) {
        return jsonResponse({ stop: true });
      }

      const { data: reports, error } = await supabase
        .from("bug_reports")
        .select("*")
        .eq("status", "new")
        .order("priority", { ascending: false })
        .order("created_at", { ascending: true })
        .limit(limit);

      if (error) {
        console.error("list_pending query failed:", error);
        return jsonResponse({ error: "Query failed" }, 500);
      }

      return jsonResponse({ stop: false, reports: reports ?? [] });
    }

    // ----------------------------------------------------------------------
    // update_status — cron marks progress / attaches PR url + triage notes
    // ----------------------------------------------------------------------
    if (action === "update_status") {
      const id = body.id;
      const status = body.status;
      if (!id) return jsonResponse({ error: "id required" }, 400);
      if (!status || !ALLOWED_STATUSES.has(status)) {
        return jsonResponse({ error: "invalid status" }, 400);
      }

      const update: Record<string, unknown> = {
        status,
        updated_at: new Date().toISOString(),
      };
      if (typeof body.claude_pr_url === "string") {
        update.claude_pr_url = body.claude_pr_url;
      }
      if (typeof body.triage_notes === "string") {
        update.triage_notes = body.triage_notes;
      }

      const { error } = await supabase
        .from("bug_reports")
        .update(update)
        .eq("id", id);

      if (error) {
        console.error("update_status failed:", error);
        return jsonResponse({ error: "Update failed" }, 500);
      }

      return jsonResponse({ success: true });
    }

    return jsonResponse({ error: "Unknown action" }, 400);
  } catch (err) {
    console.error("bug-reports-proxy error:", err);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
