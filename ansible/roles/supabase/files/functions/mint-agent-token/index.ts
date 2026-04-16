// Mint short-lived agent JWTs for peripheral devices (watches, phones)
// Auth architecture: memory/project_auth_architecture.md in platform repo
//
// Flow: device has user's session token → POST here → get 15-min agent JWT
// Agent JWT has role=agent, delegated_for=user_id — PostgREST + RLS validate natively

import { SignJWT } from "https://deno.land/x/jose@v5.9.6/index.ts";

const JWT_SECRET = Deno.env.get("JWT_SECRET");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "http://kong:8000";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const AGENT_TOKEN_TTL_SECONDS = 900; // 15 minutes
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return errorResponse(405, "Method not allowed");
  }

  if (!JWT_SECRET) {
    return errorResponse(500, "Server misconfigured: missing JWT_SECRET");
  }

  const sessionToken = extractBearerToken(req);
  if (!sessionToken) {
    return errorResponse(401, "Missing Authorization header");
  }

  const user = await fetchAuthenticatedUser(sessionToken);
  if (!user) {
    return errorResponse(401, "Invalid or expired session");
  }

  const body = await parseRequestBody(req);
  const allowedApps = body?.allowed_apps ?? [];
  const scope = body?.scope ?? "observations:write";

  const agentToken = await mintAgentToken(user.id, allowedApps, scope);

  return new Response(
    JSON.stringify({
      access_token: agentToken,
      token_type: "bearer",
      expires_in: AGENT_TOKEN_TTL_SECONDS,
    }),
    {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    },
  );
});

function extractBearerToken(req: Request): string | null {
  const authHeader = req.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return null;
  }
  return authHeader.slice(7);
}

async function fetchAuthenticatedUser(
  sessionToken: string,
): Promise<{ id: string } | null> {
  const response = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: {
      Authorization: `Bearer ${sessionToken}`,
      apikey: SUPABASE_ANON_KEY,
    },
  });

  if (!response.ok) {
    return null;
  }

  const user = await response.json();
  if (!user?.id) {
    return null;
  }

  return { id: user.id };
}

async function parseRequestBody(
  req: Request,
): Promise<{ allowed_apps?: string[]; scope?: string } | null> {
  try {
    return await req.json();
  } catch {
    return null;
  }
}

async function mintAgentToken(
  userId: string,
  allowedApps: string[],
  scope: string,
): Promise<string> {
  const secret = new TextEncoder().encode(JWT_SECRET);
  const now = Math.floor(Date.now() / 1000);

  return await new SignJWT({
    role: "agent",
    delegated_for: userId,
    allowed_apps: allowedApps,
    scope,
    iss: "supabase",
    sub: userId,
  })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuedAt(now)
    .setExpirationTime(now + AGENT_TOKEN_TTL_SECONDS)
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
