import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-app-secret",
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
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  try {
    const body = await req.json();
    const { muscle, type, name, difficulty, offset } = body;

    const apiKey = Deno.env.get("API_NINJAS_KEY");
    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: "Server configuration error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const params = new URLSearchParams();
    if (muscle)         params.set("muscle", muscle);
    if (type)           params.set("type", type);
    if (name)           params.set("name", name);
    if (difficulty)     params.set("difficulty", difficulty);
    if (offset != null) params.set("offset", String(offset));

    const query = params.toString();
    const upstreamURL = `https://api.api-ninjas.com/v1/exercises${query ? "?" + query : ""}`;

    const upstreamResponse = await fetch(upstreamURL, {
      method: "GET",
      headers: { "X-Api-Key": apiKey },
    });

    const data = await upstreamResponse.json();

    return new Response(JSON.stringify(data), {
      status: upstreamResponse.status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
