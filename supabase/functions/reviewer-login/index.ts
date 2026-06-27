// App Store reviewer demo login. The app uses passwordless email OTP, which a
// reviewer can't receive. When the correct reviewer code is supplied (given to
// Apple in App Review notes), this sets a known internal password on the
// pre-seeded DEMO account (via the GoTrue admin REST API) and returns a real
// session via password grant. The reviewer never sees the password.
//
// Deployed with verify_jwt = false (the reviewer isn't authenticated yet); the
// function does its own auth via the reviewer code.
const DEMO_EMAIL = "appreview@prestigeitsolutions.tech";
const DEMO_USER_ID = "d0d00000-0000-4000-a000-000000000001";
const DEMO_PASSWORD = "Prestige-Review-2026-xQ7";
const REVIEWER_CODE = "246810";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};
const j = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { code } = await req.json().catch(() => ({}));
    if (code !== REVIEWER_CODE) return j({ error: "Invalid code" }, 401);

    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    // 1) Set the known password on the demo user via GoTrue admin REST.
    const upResp = await fetch(`${url}/auth/v1/admin/users/${DEMO_USER_ID}`, {
      method: "PUT",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ password: DEMO_PASSWORD, email_confirm: true }),
    });
    if (!upResp.ok) {
      return j({ error: "set_password_failed", status: upResp.status, detail: await upResp.text() }, 500);
    }

    // 2) Password grant → real session.
    const tokResp = await fetch(`${url}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { apikey: anonKey, "Content-Type": "application/json" },
      body: JSON.stringify({ email: DEMO_EMAIL, password: DEMO_PASSWORD }),
    });
    const session = await tokResp.json();
    if (!session?.refresh_token) {
      return j({ error: "signin_failed", status: tokResp.status, detail: JSON.stringify(session) }, 500);
    }
    return j({ access_token: session.access_token, refresh_token: session.refresh_token });
  } catch (e) {
    return j({ error: String(e) }, 500);
  }
});
