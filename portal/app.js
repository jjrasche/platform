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

  const {
    data: { session },
  } = await sb.auth.getSession();

  if (isAuthorizePath()) {
    return handleAuthorize(sb, session);
  }

  // Handle OAuth callback hash/params from social provider login
  if (window.location.hash || window.location.search.includes("code=")) {
    const { data, error } = await sb.auth.exchangeCodeForSession(
      window.location.search
    );
    if (!error && data?.session) {
      return handlePostLogin(sb, data.session);
    }
  }

  if (session) {
    return showSignedIn(sb, session);
  }

  showLoginView();
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
  // Check if we need to complete an OAuth authorize flow
  const savedParams = sessionStorage.getItem("oauth_authorize_params");
  if (savedParams) {
    sessionStorage.removeItem("oauth_authorize_params");
    window.location.href = `/authorize${savedParams}`;
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
