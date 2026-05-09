// Edge Runtime gateway — JWKS-aware replacement for the upstream main/index.ts.
// Validates incoming JWTs against either a plain HS256 secret OR a JWKS JSON
// passed via JWT_SECRET. JWKS support unblocks ES256 user tokens from GoTrue
// while keeping HS256 anon/service_role/agent tokens valid during the cutover.

import * as jose from "https://deno.land/x/jose@v4.14.4/index.ts";

console.log("main function started");

const JWT_SECRET = Deno.env.get("JWT_SECRET");
const VERIFY_JWT = Deno.env.get("VERIFY_JWT") === "true";

const verifyContext = parseVerifyContext(JWT_SECRET);

type VerifyContext =
  | { kind: "jwks"; keys: jose.KeyLike[] | Uint8Array[] }
  | { kind: "secret"; key: Uint8Array }
  | null;

function parseVerifyContext(raw: string | undefined): VerifyContext {
  if (!raw) return null;
  const trimmed = raw.trimStart();
  if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
    try {
      const parsed = JSON.parse(raw);
      const jwks = Array.isArray(parsed) ? parsed : (parsed.keys ?? [parsed]);
      return { kind: "jwks", keys: jwks };
    } catch (_) {
      // fall through — treat as plain string
    }
  }
  return { kind: "secret", key: new TextEncoder().encode(raw) };
}

async function importKey(jwk: any): Promise<jose.KeyLike | Uint8Array> {
  return await jose.importJWK(jwk, jwk.alg ?? "HS256");
}

async function verifyJWT(jwt: string): Promise<boolean> {
  if (!verifyContext) return false;

  if (verifyContext.kind === "secret") {
    try {
      await jose.jwtVerify(jwt, verifyContext.key);
      return true;
    } catch (err) {
      console.error(err);
      return false;
    }
  }

  // JWKS — try each key until one validates. Tokens without `kid` (legacy
  // anon/service_role/agent) match the right key by alg fallback.
  for (const jwk of verifyContext.keys as any[]) {
    try {
      const key = await importKey(jwk);
      await jose.jwtVerify(jwt, key);
      return true;
    } catch (_) {
      // try next key
    }
  }
  return false;
}

function getAuthToken(req: Request) {
  const authHeader = req.headers.get("authorization");
  if (!authHeader) {
    throw new Error("Missing authorization header");
  }
  const [bearer, token] = authHeader.split(" ");
  if (bearer !== "Bearer") {
    throw new Error(`Auth header is not 'Bearer {token}'`);
  }
  return token;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "OPTIONS" && VERIFY_JWT) {
    try {
      const token = getAuthToken(req);
      const isValidJWT = await verifyJWT(token);

      if (!isValidJWT) {
        return new Response(JSON.stringify({ msg: "Invalid JWT" }), {
          status: 401,
          headers: { "Content-Type": "application/json" },
        });
      }
    } catch (e) {
      console.error(e);
      return new Response(JSON.stringify({ msg: e.toString() }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }
  }

  const url = new URL(req.url);
  const { pathname } = url;
  const path_parts = pathname.split("/");
  const service_name = path_parts[1];

  if (!service_name || service_name === "") {
    const error = { msg: "missing function name in request" };
    return new Response(JSON.stringify(error), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const servicePath = `/home/deno/functions/${service_name}`;
  console.error(`serving the request with ${servicePath}`);

  const memoryLimitMb = 150;
  const workerTimeoutMs = 1 * 60 * 1000;
  const noModuleCache = false;
  const importMapPath = null;
  const envVarsObj = Deno.env.toObject();
  const envVars = Object.keys(envVarsObj).map((k) => [k, envVarsObj[k]]);

  try {
    const worker = await EdgeRuntime.userWorkers.create({
      servicePath,
      memoryLimitMb,
      workerTimeoutMs,
      noModuleCache,
      importMapPath,
      envVars,
    });
    return await worker.fetch(req);
  } catch (e) {
    const error = { msg: e.toString() };
    return new Response(JSON.stringify(error), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
