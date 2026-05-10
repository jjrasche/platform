// Mint short-lived HS256 side-tokens for supabase-realtime channel auth.
//
// Why this exists: GoTrue mints user JWTs as ES256, but supabase-realtime's
// Joken-based validator only accepts a plain HS256 secret (API_JWT_SECRET).
// Until upstream Realtime parses JWKS, the browser must hand Realtime an
// HS256 token signed against the legacy shared JWT_SECRET. The user's real
// session stays ES256 for PostgREST/Edge-Functions; this token is scoped
// purely to the Realtime websocket via supabase-js's sb.realtime.setAuth().

import * as jose from "https://deno.land/x/jose@v5.9.6/index.ts";

// JWT_SECRET holds JWKS JSON post-OIDC-cutover (used to verify the caller's
// ES256 token). LEGACY_HS256_SECRET is the plain HS256 string Realtime still
// validates against (used to sign the side-token we hand back).
const JWKS_OR_SECRET = Deno.env.get("JWT_SECRET");
const HS256_SIGNING_SECRET = Deno.env.get("LEGACY_HS256_SECRET") ??
  Deno.env.get("JWT_SECRET");

const REALTIME_TOKEN_TTL_SECONDS = 3600;
const TOKEN_ISSUER = "supabase";
const TOKEN_AUDIENCE = "authenticated";
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type VerifyContext =
  | { kind: "jwks"; keys: any[] }
  | { kind: "secret"; key: Uint8Array }
  | null;

const verifyContext = parseVerifyContext(JWKS_OR_SECRET);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return errorResponse(405, "Method not allowed");
  }
  if (!HS256_SIGNING_SECRET) {
    return errorResponse(500, "Server misconfigured: missing LEGACY_HS256_SECRET");
  }
  if (!verifyContext) {
    return errorResponse(500, "Server misconfigured: missing JWT_SECRET");
  }

  const callerToken = extractBearerToken(req);
  if (!callerToken) {
    return errorResponse(401, "Missing Authorization header");
  }

  const userId = await verifyCallerSubject(callerToken);
  if (!userId) {
    return errorResponse(401, "Invalid or expired session");
  }

  const realtimeToken = await mintRealtimeToken(userId);

  return new Response(
    JSON.stringify({
      access_token: realtimeToken,
      token_type: "bearer",
      expires_in: REALTIME_TOKEN_TTL_SECONDS,
    }),
    {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    },
  );
});

function parseVerifyContext(raw: string | undefined): VerifyContext {
  if (!raw) return null;
  const trimmed = raw.trimStart();
  if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
    try {
      const parsed = JSON.parse(raw);
      const keys = Array.isArray(parsed) ? parsed : (parsed.keys ?? [parsed]);
      return { kind: "jwks", keys };
    } catch (_) {
      // fall through to plain-secret
    }
  }
  return { kind: "secret", key: new TextEncoder().encode(raw) };
}

function extractBearerToken(req: Request): string | null {
  const authHeader = req.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return null;
  }
  return authHeader.slice(7);
}

async function verifyCallerSubject(jwt: string): Promise<string | null> {
  if (!verifyContext) return null;

  if (verifyContext.kind === "secret") {
    return await verifyAndExtractSub(jwt, verifyContext.key);
  }

  // JWKS — match by alg fallback (some legacy tokens lack `kid`).
  for (const jwk of verifyContext.keys) {
    const sub = await tryVerifyWithJwk(jwt, jwk);
    if (sub) return sub;
  }
  return null;
}

async function tryVerifyWithJwk(jwt: string, jwk: any): Promise<string | null> {
  try {
    const key = await jose.importJWK(jwk, jwk.alg ?? "HS256");
    return await verifyAndExtractSub(jwt, key);
  } catch (_) {
    return null;
  }
}

async function verifyAndExtractSub(
  jwt: string,
  key: jose.KeyLike | Uint8Array,
): Promise<string | null> {
  try {
    const { payload } = await jose.jwtVerify(jwt, key);
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch (_) {
    return null;
  }
}

async function mintRealtimeToken(userId: string): Promise<string> {
  const secret = new TextEncoder().encode(HS256_SIGNING_SECRET);
  const now = Math.floor(Date.now() / 1000);

  return await new jose.SignJWT({
    sub: userId,
    role: "authenticated",
    aud: TOKEN_AUDIENCE,
    iss: TOKEN_ISSUER,
  })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuedAt(now)
    .setExpirationTime(now + REALTIME_TOKEN_TTL_SECONDS)
    .sign(secret);
}

function errorResponse(status: number, message: string): Response {
  return new Response(
    JSON.stringify({ error: message }),
    {
      status,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    },
  );
}
