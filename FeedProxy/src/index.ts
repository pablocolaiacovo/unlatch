// Serves the Sparkle appcast from GitHub Pages and counts unique copies per day.
// See Design/feed-usage-counting.md.

import { stats } from "./stats";

const ORIGIN = "https://pablocolaiacovo.github.io/unlatch";

interface Env {
  DB: D1Database;
  SALT_KEY: string;
  // Optional: without it, /stats is a 404.
  DASHBOARD_PASSWORD?: string;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/stats" && request.method === "GET") return stats(request, env);
    if (url.pathname !== "/appcast.xml" || (request.method !== "GET" && request.method !== "HEAD")) {
      return new Response("Not found", { status: 404 });
    }
    const upstream = await fetch(ORIGIN + url.pathname + url.search, { method: request.method });

    // Only Sparkle's own checks count; curl (the release workflow), browsers and crawlers don't.
    const userAgent = request.headers.get("User-Agent") ?? "";
    const ip = request.headers.get("CF-Connecting-IP");
    if (userAgent.includes("Sparkle/") && ip) {
      // Counting must never affect the feed, so failures are dropped.
      ctx.waitUntil(record(env, userAgent, ip).catch(() => {}));
    }
    return new Response(upstream.body, upstream);
  },

  // Rolls finished days into `daily`, then deletes their hashes.
  async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
    const today = utcDay();
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO daily (day, version, copies)
         SELECT day, version, COUNT(*) FROM seen WHERE day < ?1 GROUP BY day, version
         ON CONFLICT (day, version) DO UPDATE SET copies = daily.copies + excluded.copies`,
      ).bind(today),
      env.DB.prepare("DELETE FROM seen WHERE day < ?1").bind(today),
    ]);
  },
};

async function record(env: Env, userAgent: string, ip: string): Promise<void> {
  const day = utcDay();
  // Sparkle's User-Agent is "<app>/<version> Sparkle/<version>".
  const version = (userAgent.split(" ")[0].split("/")[1] || "unknown").slice(0, 32);
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw", encoder.encode(env.SALT_KEY), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(`${day}|${ip}`));
  const hash = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
  await env.DB.prepare("INSERT OR IGNORE INTO seen (day, hash, version) VALUES (?1, ?2, ?3)")
    .bind(day, hash, version)
    .run();
}

function utcDay(): string {
  return new Date().toISOString().slice(0, 10);
}
