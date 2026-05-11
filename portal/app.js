// Login portal for JMR Platform SSO
// GoTrue OAuth 2.1 Server delegates user authentication + consent to this
// portal. GoTrue redirects to /authorize?authorization_id=<id>; the portal
// signs the user in (if needed) and POSTs the user's JWT back to GoTrue's
// consent endpoint, which returns the redirect URL carrying the auth code
// to the OAuth client.
//
// Flow:
// 1. OIDC client (e.g. Gitea) → GoTrue /oauth/authorize with PKCE params
// 2. GoTrue → portal /authorize?authorization_id=<id>
// 3. Portal signs user in if needed, then POST /oauth/authorizations/<id>/consent
//    with {action:"approve"} and the user's access_token
// 4. Consent endpoint returns {redirect_to:"https://<client>/callback?code=..."}
// 5. Portal navigates browser to that URL — client receives auth code

const SUPABASE_URL = "https://api.jimr.fyi";
const SUPABASE_ANON_KEY = window.__SUPABASE_ANON_KEY__ || "";

const views = {
  loading: document.getElementById("view-loading"),
  login: document.getElementById("view-login"),
  recover: document.getElementById("view-recover"),
  reset: document.getElementById("view-reset"),
  authorize: document.getElementById("view-authorize"),
  denied: document.getElementById("view-denied"),
  signedIn: document.getElementById("view-signed-in"),
};

function showView(name) {
  Object.values(views).forEach((v) => v.classList.add("hidden"));
  views[name].classList.remove("hidden");
}

function showError(message) {
  const el = document.getElementById("login-error");
  el.textContent = message;
  el.classList.remove("hidden");
}

function redirectWithSession(returnTo, session) {
  const url = new URL(returnTo);
  url.hash = [
    `access_token=${encodeURIComponent(session.access_token)}`,
    `refresh_token=${encodeURIComponent(session.refresh_token)}`,
    `expires_in=${session.expires_in ?? 3600}`,
    `token_type=bearer`,
  ].join("&");
  window.location.href = url.toString();
}

function readReturnTo() {
  const url = new URLSearchParams(window.location.search).get("return_to")
    || sessionStorage.getItem("pending_return_to");
  if (!url) return null;
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:") return null;
    if (!parsed.hostname.endsWith(".jimr.fyi") && parsed.hostname !== "practice.exchange") return null;
    return url;
  } catch {
    return null;
  }
}

function parseAuthorizationId() {
  return new URLSearchParams(window.location.search).get("authorization_id");
}

function isAuthorizePath() {
  return window.location.pathname === "/authorize";
}

async function createSupabaseClient() {
  // Load supabase-js from CDN at runtime
  if (!window.supabase) {
    await new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src =
        "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js";
      script.onload = resolve;
      script.onerror = reject;
      document.head.appendChild(script);
    });
  }
  return window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
      flowType: "implicit",
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: true,
    },
  });
}

async function init() {
  // Read recovery state BEFORE createClient: implicit flow + detectSessionInUrl
  // parses the hash and calls history.replaceState to clean it during init.
  const recoveryType = parseRecoveryFragment();

  const sb = await createSupabaseClient();
  bindLoginButtons(sb);
  bindRecoverButtons(sb);
  bindResetButtons(sb);

  // Preserve return_to across recovery email redirect (which wipes query params)
  const rawReturnTo = new URLSearchParams(window.location.search).get("return_to");
  if (rawReturnTo) sessionStorage.setItem("pending_return_to", rawReturnTo);

  const {
    data: { session },
  } = await sb.auth.getSession();

  if (isAuthorizePath()) {
    return handleAuthorize(sb, session);
  }

  if (recoveryType === "expired") {
    history.replaceState(null, "", window.location.pathname);
    showLoginView();
    showError('Recovery link has expired — click "Forgot your password?" to request a new one.');
    return;
  }
  if (recoveryType === "recovery" && session) {
    return showResetView();
  }

  // OAuth callback (social provider) hash/params
  if (window.location.hash || window.location.search.includes("code=")) {
    const { data, error } = await sb.auth.exchangeCodeForSession(
      window.location.search
    );
    if (!error && data?.session) {
      return handlePostLogin(sb, data.session);
    }
  }

  if (session) {
    const returnTo = readReturnTo();
    if (returnTo) {
      sessionStorage.removeItem("pending_return_to");
      redirectWithSession(returnTo, session);
      return;
    }
    return showSignedIn(sb, session);
  }

  showLoginView();
}

function parseRecoveryFragment() {
  const hash = window.location.hash || "";
  if (hash.includes("error_code=otp_expired")) return "expired";
  if (!hash.includes("type=recovery")) return null;
  return "recovery";
}

let isSignUp = false;

function bindLoginButtons(sb) {
  document.getElementById("toggle-mode").addEventListener("click", (e) => {
    e.preventDefault();
    isSignUp = !isSignUp;
    document.getElementById("auth-subtitle").textContent = isSignUp
      ? "Create an account"
      : "Sign in to continue";
    document.getElementById("btn-submit").textContent = isSignUp
      ? "Sign Up"
      : "Sign In";
    document.getElementById("toggle-mode").textContent = isSignUp
      ? "Already have an account? Sign in"
      : "Don't have an account? Sign up";
    document.getElementById("login-error").classList.add("hidden");
    document.getElementById("login-success").classList.add("hidden");
    document.getElementById("input-password").autocomplete = isSignUp
      ? "new-password"
      : "current-password";
  });

  document.getElementById("form-email").addEventListener("submit", async (e) => {
    e.preventDefault();
    const email = document.getElementById("input-email").value;
    const password = document.getElementById("input-password").value;

    if (isSignUp) {
      const { data, error } = await sb.auth.signUp({ email, password });
      if (error) {
        showError(error.message);
        return;
      }
      if (data.session) {
        handlePostLogin(sb, data.session);
      } else {
        showSuccess("Check your email to confirm your account.");
      }
    } else {
      const { data, error } = await sb.auth.signInWithPassword({ email, password });
      if (error) {
        showError(error.message);
        return;
      }
      handlePostLogin(sb, data.session);
    }
  });
}

function showSuccess(message) {
  const el = document.getElementById("login-success");
  el.textContent = message;
  el.classList.remove("hidden");
  document.getElementById("login-error").classList.add("hidden");
}

function showLoginView() {
  showView("login");
}

function showResetView() {
  showView("reset");
}

function bindRecoverButtons(sb) {
  document.getElementById("forgot-link").addEventListener("click", (e) => {
    e.preventDefault();
    showView("recover");
  });
  document.getElementById("back-to-login").addEventListener("click", (e) => {
    e.preventDefault();
    showView("login");
  });
  document.getElementById("form-recover").addEventListener("submit", async (e) => {
    e.preventDefault();
    const email = document.getElementById("recover-email").value;
    const errEl = document.getElementById("recover-error");
    const okEl = document.getElementById("recover-success");
    errEl.classList.add("hidden");
    okEl.classList.add("hidden");
    const { error } = await sb.auth.resetPasswordForEmail(email, {
      redirectTo: window.location.origin,
    });
    if (error) {
      errEl.textContent = error.message;
      errEl.classList.remove("hidden");
      return;
    }
    okEl.textContent = "Check your email for a link to reset your password.";
    okEl.classList.remove("hidden");
  });
}

function bindResetButtons(sb) {
  document.getElementById("form-reset").addEventListener("submit", async (e) => {
    e.preventDefault();
    const pw = document.getElementById("reset-password").value;
    const pw2 = document.getElementById("reset-password-confirm").value;
    const errEl = document.getElementById("reset-error");
    const okEl = document.getElementById("reset-success");
    errEl.classList.add("hidden");
    okEl.classList.add("hidden");
    if (pw !== pw2) {
      errEl.textContent = "Passwords don't match.";
      errEl.classList.remove("hidden");
      return;
    }
    const { error } = await sb.auth.updateUser({ password: pw });
    if (error) {
      errEl.textContent = error.message;
      errEl.classList.remove("hidden");
      return;
    }
    okEl.textContent = "Password updated. You're signed in.";
    okEl.classList.remove("hidden");
    setTimeout(async () => {
      const { data: { session } } = await sb.auth.getSession();
      if (session) handlePostLogin(sb, session); else showLoginView();
    }, 1500);
  });
}

async function handleAuthorize(sb, session, overrideAuthId) {
  // overrideAuthId lets handlePostLogin skip the navigate→reload→re-parse
  // round trip, which was losing state between sign-in and consent.
  const authorizationId = overrideAuthId || parseAuthorizationId();
  if (!authorizationId) {
    if (session) return showSignedIn(sb, session);
    return showLoginView();
  }

  if (!session) {
    sessionStorage.setItem("pending_authorization_id", authorizationId);
    showLoginView();
    return;
  }

  showView("authorize");

  const response = await fetch(
    `${SUPABASE_URL}/auth/v1/oauth/authorizations/${authorizationId}/consent`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${session.access_token}`,
        "apikey": SUPABASE_ANON_KEY,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ action: "approve" }),
    },
  );

  if (!response.ok) {
    const text = await response.text();
    console.error("consent failed", response.status, text);
    showLoginView();
    showError(`Authorization failed: ${response.status} ${text}`);
    return;
  }

  const data = await response.json();
  const redirectTo = data.redirect_to || data.redirect_url || data.redirect_uri;
  if (!redirectTo) {
    console.error("consent response missing redirect", data);
    showLoginView();
    showError("Authorization succeeded but server returned no redirect URL");
    return;
  }
  window.location.href = redirectTo;
}

async function handlePostLogin(sb, session) {
  const pendingAuthId = sessionStorage.getItem("pending_authorization_id");
  if (pendingAuthId) {
    sessionStorage.removeItem("pending_authorization_id");
    // Call handleAuthorize directly with the auth_id — avoids a full page
    // reload where the SPA was sometimes landing in the signedIn view
    // instead of running the consent POST.
    return handleAuthorize(sb, session, pendingAuthId);
  }

  const returnTo = readReturnTo();
  if (returnTo) {
    sessionStorage.removeItem("pending_return_to");
    redirectWithSession(returnTo, session);
    return;
  }

  showSignedIn(sb, session);
}

function showSignedIn(sb, session) {
  showView("signedIn");
  document.getElementById("user-email").textContent =
    session.user?.email || session.user?.id;

  document.getElementById("btn-signout").addEventListener("click", async () => {
    await sb.auth.signOut();
    window.location.reload();
  });
}

init().catch((err) => {
  console.error("Portal init failed:", err);
  showView("login");
  showError("Failed to initialize. Please refresh.");
});
