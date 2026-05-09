// Diagnostic probe for the Cloudflare → Caddy → Kong → edge-runtime chain.
// ?sleep=N (capped at 180) holds the response open for N seconds so we can
// discover which layer's read timeout bites first. Plain text body so curl
// reads cleanly without jq.
//
// Auth: edge-runtime has VERIFY_JWT=true; pass the anon key as a Bearer
// token (or `apikey` header) to satisfy it. JWT verification is essentially
// zero-latency, so it doesn't perturb the timeout measurement.
//
// Delete after Step 0 of the dungeon-master V1.2 architectural migration.

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const requested = Math.min(parseInt(url.searchParams.get("sleep") ?? "0", 10) || 0, 180);
  const start = Date.now();
  await new Promise((r) => setTimeout(r, requested * 1000));
  const elapsed = ((Date.now() - start) / 1000).toFixed(2);
  return new Response(
    `requested=${requested}s elapsed=${elapsed}s ok\n`,
    { headers: { "content-type": "text/plain" } },
  );
});
