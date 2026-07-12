// PayMongo webhook: activates a store's subscription once payment succeeds.
//
// Auth is by PayMongo's HMAC signature (deployed with verify_jwt = false so
// PayMongo can reach it without a Supabase JWT). On a paid checkout session we
// read metadata.request_id and call activate_subscription_by_request() with
// the service role.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const enc = (s: string) => new TextEncoder().encode(s);

function toHex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Constant-time-ish string compare. */
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}

/** Verify the "Paymongo-Signature: t=..,te=..,li=.." header. */
async function verifySignature(raw: string, header: string, secret: string): Promise<boolean> {
  const parts: Record<string, string> = {};
  for (const kv of header.split(",")) {
    const [k, v] = kv.split("=");
    if (k && v) parts[k.trim()] = v.trim();
  }
  const t = parts["t"];
  const expected = parts["te"] || parts["li"];
  if (!t || !expected) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    enc(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, enc(`${t}.${raw}`));
  return safeEqual(toHex(mac), expected);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("ok");

  const raw = await req.text();
  const secret = Deno.env.get("PAYMONGO_WEBHOOK_SECRET") ?? "";
  const sig = req.headers.get("paymongo-signature") ?? "";
  if (secret) {
    const ok = await verifySignature(raw, sig, secret);
    if (!ok) return new Response("invalid signature", { status: 401 });
  }

  let body: any;
  try {
    body = JSON.parse(raw);
  } catch {
    return new Response("bad json", { status: 400 });
  }

  const evt = body?.data?.attributes;
  const type: string = evt?.type ?? "";

  if (type === "checkout_session.payment.paid" || type === "payment.paid") {
    const resource = evt?.data?.attributes ?? {};
    const requestId: string | undefined = resource?.metadata?.request_id;
    const ref: string | undefined = evt?.data?.id;
    if (requestId) {
      const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );
      const { error } = await supabase.rpc("activate_subscription_by_request", {
        p_id: requestId,
        p_ref: ref ?? null,
      });
      if (error) {
        console.error("activate failed", error.message);
        return new Response("activate failed", { status: 500 });
      }
    }
  }

  return new Response(JSON.stringify({ received: true }), {
    headers: { "content-type": "application/json" },
  });
});
