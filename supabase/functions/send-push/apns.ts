// Sends through Apple's push service with a token-based (.p8) key.

export interface ApnsConfig {
  keyId: string;
  teamId: string;
  privateKey: string;
  topic: string;
}

export interface ApnsMessage {
  title: string;
  body: string;
  tab: string;
  collapseId: string;
}

export type ApnsResult = "sent" | "gone" | "retry" | "rejected";

const HOSTS: Record<string, string> = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};

const base64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const encodeJson = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));

async function importKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/\\n/g, "\n").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

// Apple refuses a token that changes more than once every 20 minutes. It accepts one up to an hour old.
// A cold start shouldn't count as a change, so the issue time is pinned to a 30-minute window.
const TOKEN_WINDOW_SECONDS = 30 * 60;
let cached: { window: number; jwt: string } | null = null;

export async function providerToken(config: ApnsConfig, nowSeconds = Math.floor(Date.now() / 1000)): Promise<string> {
  const window = Math.floor(nowSeconds / TOKEN_WINDOW_SECONDS);
  if (cached?.window === window) return cached.jwt;
  const signingInput = `${encodeJson({ alg: "ES256", kid: config.keyId })}.${encodeJson({ iss: config.teamId, iat: window * TOKEN_WINDOW_SECONDS })}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    await importKey(config.privateKey),
    new TextEncoder().encode(signingInput),
  );
  const jwt = `${signingInput}.${base64url(new Uint8Array(signature))}`;
  cached = { window, jwt };
  return jwt;
}

export async function sendToDevice(config: ApnsConfig, device: { token: string; environment: string }, message: ApnsMessage): Promise<ApnsResult> {
  const headers: Record<string, string> = {
    authorization: `bearer ${await providerToken(config)}`,
    "apns-topic": config.topic,
    "apns-push-type": "alert",
    "apns-priority": "10",
    // A phone that's off or out of signal still gets it if it comes back within a day.
    "apns-expiration": String(Math.floor(Date.now() / 1000) + 24 * 60 * 60),
  };
  if (new TextEncoder().encode(message.collapseId).length <= 64) headers["apns-collapse-id"] = message.collapseId;

  let response: Response;
  try {
    response = await fetch(`${HOSTS[device.environment]}/3/device/${device.token}`, {
      method: "POST",
      headers,
      body: JSON.stringify({ aps: { alert: { title: message.title, body: message.body }, sound: "default" }, tab: message.tab }),
    });
  } catch (error) {
    console.error("APNs request failed:", error);
    return "retry";
  }
  if (response.ok) {
    await response.body?.cancel();
    return "sent";
  }
  const reason = await response.json().then((j) => j.reason as string).catch(() => "unknown");
  console.error(`APNs ${response.status} ${reason} (${device.environment})`);
  if (response.status === 410) return "gone";
  // A bad key or a server hiccup isn't this notification's fault. BadDeviceToken can just mean the wrong
  // environment for that build, so the token stays: the app re-registers it with the right one on launch.
  return response.status === 429 || response.status === 403 || response.status >= 500 ? "retry" : "rejected";
}
