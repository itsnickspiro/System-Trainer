import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-app-secret",
};

serve(async (req) => {
  // Handle CORS preflight
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

    const query: string    = (body.query    ?? "").trim();
    const barcode: string  = (body.barcode  ?? "").trim();
    const limit: number    = Math.min(parseInt(body.limit ?? "25", 10), 200);
    const dataType: string = (body.dataType ?? "Foundation,SR Legacy,Branded").trim();

    const apiKey = Deno.env.get("USDA_API_KEY");
    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: "Server configuration error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    let upstreamURL: string;

    if (barcode && !query) {
      // Barcode lookup — search branded foods by GTIN/UPC
      const params = new URLSearchParams({
        query: barcode,
        pageSize: String(limit),
        dataType: "Branded",
        api_key: apiKey,
      });
      upstreamURL = `https://api.nal.usda.gov/fdc/v1/foods/search?${params}`;
    } else if (query) {
      const params = new URLSearchParams({
        query,
        pageSize: String(limit),
        dataType,
        api_key: apiKey,
      });
      upstreamURL = `https://api.nal.usda.gov/fdc/v1/foods/search?${params}`;
    } else {
      return new Response(
        JSON.stringify({ error: "Missing query or barcode parameter" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const upstreamResponse = await fetch(upstreamURL, { method: "GET" });
    const data = await upstreamResponse.json();

    // Pass through FDC JSON unchanged so the Swift USDASearchResponse decoder works as-is
    return new Response(JSON.stringify(data), {
      status: upstreamResponse.status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("usda-proxy error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
