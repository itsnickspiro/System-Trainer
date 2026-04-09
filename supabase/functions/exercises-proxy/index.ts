import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-app-secret",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Verify the request comes from the RPT app
  const appSecret = Deno.env.get("RPT_APP_SECRET");
  const incomingSecret = req.headers.get("x-app-secret");
  if (!appSecret || !incomingSecret || incomingSecret !== appSecret) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  try {
    const body = await req.json();

    // Input parameters (all optional)
    const query: string     = (body.query     ?? body.name  ?? "").trim();
    const category: string  = (body.category  ?? body.type  ?? "").trim();
    const muscle: string    = (body.muscle                  ?? "").trim();
    const level: string     = (body.level     ?? body.difficulty ?? "").trim();
    const equipment: string = (body.equipment               ?? "").trim();
    const limit: number     = Math.min(parseInt(body.limit ?? "30", 10), 100);
    const offset: number    = Math.max(parseInt(body.offset ?? "0",  10), 0);

    // Create a Supabase client with the service role key so RLS is bypassed
    // (the exercises table has a public read policy, but service role is
    //  slightly faster since it skips the policy check entirely)
    const supabaseUrl  = Deno.env.get("SUPABASE_URL")!;
    const serviceKey   = Deno.env.get("DB_SERVICE_ROLE_KEY")!;
    const supabase     = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false },
    });

    // Call the search_exercises RPC defined in the migration
    const { data, error } = await supabase.rpc("search_exercises", {
      p_query:     query,
      p_category:  category,
      p_level:     level,
      p_equipment: equipment,
      p_muscle:    muscle,
      lim:         limit,
      off:         offset,
    });

    if (error) {
      console.error("RPC error:", error);
      return new Response(
        JSON.stringify({ error: "Database query failed", detail: error.message }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Map DB rows to the shape the iOS app expects
    // Keeps backwards-compat with existing Exercise struct while adding new fields
    const exercises = (data ?? []).map((row: Record<string, unknown>) => ({
      // Core fields (backwards-compatible with old API Ninjas shape)
      name:              row.name,
      type:              row.category,
      muscle:            (row.primary_muscles as string[])?.[0] ?? null,
      secondaryMuscle:   (row.secondary_muscles as string[])?.[0] ?? null,
      equipment:         row.equipment ?? null,
      difficulty:        row.level ?? null,
      instructions:      Array.isArray(row.instructions)
                           ? (row.instructions as string[]).join("\n")
                           : null,

      // Extended fields (new in this version)
      slug:              row.slug,
      primaryMuscles:    row.primary_muscles   ?? [],
      secondaryMuscles:  row.secondary_muscles ?? [],
      force:             row.force   ?? null,
      level:             row.level   ?? null,
      mechanic:          row.mechanic ?? null,
      category:          row.category ?? null,
      instructionSteps:  row.instructions ?? [],
      tips:              row.tips ?? null,
      imageUrls:         row.image_urls ?? [],
      gifUrl:            row.gif_url ?? null,
      youtubeSearchUrl:  row.youtube_search_url ?? null,
    }));

    return new Response(JSON.stringify(exercises), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("exercises-proxy error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
