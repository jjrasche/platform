// Login portal for JMR Platform SSO
// GoTrue OAuth 2.1 Server redirects here for authentication and consent.
//
// Flow:
// 1. Tenant app redirects to GoTrue /oauth/authorize
// 2. GoTrue redirects to this portal at /authorize if no session
// 3. User signs in or signs up via email/password
// 4. GoTrue sets session cookie, redirects back to tenant app with auth code

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

function parseAuthorizeParams() {
  const params = new URLSearchParams(window.location.search);
  const clientId = params.get("client_id");
  const redirectUri = params.get("redirect_uri");
  const state = params.get("state");
  const codeChallenge = params.get("code_challenge");
  if (!clientId) return null;
  return { clientId, redirectUri, state, codeChallenge };
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
      flowType: "pkce",
      autoRefreshToken: true,
      persistSession: true,
    },
  });
}

async function init() {
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

  // Recovery flow: GoTrue's /auth/v1/verify redirects here with the
  // session in the URL fragment and `type=recovery`. supabase-js parses
  // the fragment automatically when persistSession is on; we just need to
  // detect the recovery type and show the reset form.
  const recoveryType = parseRecoveryFragment();
  if (recoveryType === "expired") {
    history.replaceState(null, "", window.location.pathname);
    showLoginView();
    showError('Recovery link has expired — click "Forgot your password?" to request a new one.');
    return;
  }
  if (recoveryType === "recovery") {
    // Wait briefly for supabase-js to parse the fragment into a session.
    const recoverySession = await waitForRecoverySession(sb);
    if (recoverySession) {
      // Strip fragment so a refresh doesn't re-trigger the flow.
      history.replaceState(null, "", window.location.pathname);
      return showResetView();
    }
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

async function waitForRecoverySession(sb, attempts = 10) {
  for (let i = 0; i < attempts; i++) {
    const { data: { session } } = await sb.auth.getSession();
    if (session) return session;
    await new Promise((r) => setTimeout(r, 100));
  }
  return null;
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

async function handleAuthorize(sb, session) {
  const params = parseAuthorizeParams();
  if (!params) {
    // No OAuth params — show login or signed-in state
    if (session) return showSignedIn(sb, session);
    return showLoginView();
  }

  if (!session) {
    // Store OAuth params, show login. After login, redirect back to /authorize with same params.
    sessionStorage.setItem("oauth_authorize_params", window.location.search);
    showLoginView();
    return;
  }

  // User is authenticated — GoTrue handles consent automatically.
  // Redirect back to GoTrue's authorize endpoint with the session.
  // GoTrue will check the session cookie and proceed with the code grant.
  showView("authorize");
  document.getElementById("authorize-app").textContent = params.clientId;

  // Re-trigger the authorize flow — GoTrue should now see the session
  // and redirect back to the client with an auth code.
  const authorizeUrl = new URL(
    `${SUPABASE_URL}/auth/v1/oauth/authorize${window.location.search}`
  );
  window.location.href = authorizeUrl.toString();
}

async function handlePostLogin(sb, session) {
  const savedParams = sessionStorage.getItem("oauth_authorize_params");
  if (savedParams) {
    sessionStorage.removeItem("oauth_authorize_params");
    window.location.href = `/authorize${savedParams}`;
    return;
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
