// GET /stats: a password-protected page with the daily counts. See Design/feed-usage-counting.md.

interface StatsEnv {
  DB: D1Database;
  DASHBOARD_PASSWORD?: string;
}

const DAYS = 90;

export async function stats(request: Request, env: StatsEnv): Promise<Response> {
  // No password set: the page doesn't exist.
  if (!env.DASHBOARD_PASSWORD) return new Response("Not found", { status: 404 });
  if (!(await authorized(request, env.DASHBOARD_PASSWORD))) {
    return new Response("Sign in required", {
      status: 401,
      headers: { "WWW-Authenticate": 'Basic realm="Unlatch stats", charset="UTF-8"' },
    });
  }

  const today = new Date().toISOString().slice(0, 10);
  const days = [...Array(DAYS)].map((_, i) => isoDay(today, i - DAYS)); // oldest first, ends yesterday
  const [totals, todaySoFar, versions] = await env.DB.batch<Record<string, unknown>>([
    env.DB.prepare("SELECT day, SUM(copies) AS copies FROM daily WHERE day >= ?1 GROUP BY day").bind(days[0]),
    env.DB.prepare("SELECT COUNT(*) AS copies FROM seen WHERE day = ?1").bind(today),
    env.DB.prepare(
      "SELECT day, version, copies FROM daily WHERE day = (SELECT MAX(day) FROM daily) ORDER BY copies DESC",
    ),
  ]);
  const byDay = new Map(totals.results.map((r) => [String(r.day), Number(r.copies)]));
  const series = days.map((day) => ({ day, copies: byDay.get(day) ?? 0 }));
  const latest = series[series.length - 1];
  const last30 = series.slice(-30);
  const average30 = last30.reduce((sum, d) => sum + d.copies, 0) / last30.length;

  const html = page({
    today: Number(todaySoFar.results[0]?.copies ?? 0),
    latest,
    average30,
    series,
    versions: versions.results.map((r) => ({ day: String(r.day), version: String(r.version), copies: Number(r.copies) })),
  });
  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Robots-Tag": "noindex",
      "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'",
    },
  });
}

async function authorized(request: Request, password: string): Promise<boolean> {
  const header = request.headers.get("Authorization") ?? "";
  if (!header.startsWith("Basic ")) return false;
  let given = "";
  try {
    given = atob(header.slice(6)).split(":").slice(1).join(":");
  } catch {
    return false;
  }
  // Compare digests so the comparison is constant-time and length-independent.
  const digest = (s: string) => crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  const [a, b] = await Promise.all([digest(given), digest(password)]);
  return crypto.subtle.timingSafeEqual(a, b);
}

function isoDay(from: string, offset: number): string {
  const d = new Date(`${from}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + offset);
  return d.toISOString().slice(0, 10);
}

// Version strings come from User-Agent headers, so everything printed is escaped.
function esc(value: string): string {
  return value.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

type Day = { day: string; copies: number };

function page(data: {
  today: number;
  latest: Day;
  average30: number;
  series: Day[];
  versions: { day: string; version: string; copies: number }[];
}): string {
  const fmt = (n: number) => n.toLocaleString("en-US", { maximumFractionDigits: 1 });
  const versionRows = data.versions.length
    ? data.versions.map((v) => `<tr><td>${esc(v.version)}</td><td class="num">${fmt(v.copies)}</td></tr>`).join("")
    : `<tr><td colspan="2" class="muted">No data yet</td></tr>`;
  const versionDay = data.versions[0]?.day ?? "";
  const tableRows = [...data.series]
    .reverse()
    .map((d) => `<tr><td>${d.day}</td><td class="num">${fmt(d.copies)}</td></tr>`)
    .join("");

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Unlatch stats</title>
<style>
:root {
  color-scheme: light;
  --page: #f9f9f7; --surface: #fcfcfb; --ink: #0b0b0b; --ink-2: #52514e; --muted: #898781;
  --grid: #e1e0d9; --axis: #c3c2b7; --series: #2a78d6; --border: #e1e0d9;
}
@media (prefers-color-scheme: dark) {
  :root {
    color-scheme: dark;
    --page: #0d0d0d; --surface: #1a1a19; --ink: #f0efec; --ink-2: #c3c2b7; --muted: #898781;
    --grid: #2c2c2a; --axis: #383835; --series: #3987e5; --border: #2c2c2a;
  }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--page); color: var(--ink);
  font: 14px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
main { max-width: 960px; margin: 0 auto; padding: 24px 16px 48px; }
h1 { font-size: 20px; margin: 0 0 4px; }
h2 { font-size: 15px; margin: 0 0 12px; }
p.sub, .muted { color: var(--ink-2); margin: 0; }
.tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 12px; margin: 20px 0; }
.card { background: var(--surface); border: 1px solid var(--border); border-radius: 10px; padding: 16px; }
.tile .label { color: var(--ink-2); font-size: 13px; }
.tile .value { font-size: 32px; font-weight: 600; font-variant-numeric: tabular-nums; }
.tile .note { color: var(--muted); font-size: 12px; }
.chart { margin-bottom: 12px; }
.scroll { overflow-x: auto; }
svg { display: block; width: 100%; min-width: 640px; height: auto; }
svg text { fill: var(--muted); font-size: 11px; font-variant-numeric: tabular-nums; }
.bar { fill: var(--series); }
.hit { fill: transparent; }
.hit:hover + .bar, .hit:focus + .bar { opacity: .7; }
table { width: 100%; border-collapse: collapse; font-variant-numeric: tabular-nums; }
th, td { text-align: left; padding: 6px 0; border-bottom: 1px solid var(--border); }
th { color: var(--ink-2); font-weight: 500; }
.num { text-align: right; }
.two { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 12px; }
details summary { cursor: pointer; color: var(--ink-2); }
details table { margin-top: 8px; }
</style>
</head>
<body>
<main>
<h1>Unlatch active copies</h1>
<p class="sub">Unique copies that checked for updates, per UTC day. Copies with automatic checks off are not counted.</p>

<div class="tiles">
  <div class="card tile"><div class="label">Yesterday</div><div class="value">${fmt(data.latest.copies)}</div><div class="note">${data.latest.day}</div></div>
  <div class="card tile"><div class="label">30-day daily average</div><div class="value">${fmt(data.average30)}</div><div class="note">Ending yesterday</div></div>
  <div class="card tile"><div class="label">Today so far</div><div class="value">${fmt(data.today)}</div><div class="note">Rolls up at 00:15 UTC</div></div>
</div>

<section class="card chart">
  <h2>Copies per day, last ${DAYS} days</h2>
  <div class="scroll">${chart(data.series)}</div>
</section>

<div class="two">
  <section class="card">
    <h2>By version${versionDay ? `, ${versionDay}` : ""}</h2>
    <table><thead><tr><th>Version</th><th class="num">Copies</th></tr></thead><tbody>${versionRows}</tbody></table>
  </section>
  <section class="card">
    <h2>Daily numbers</h2>
    <details><summary>Show table</summary>
      <table><thead><tr><th>Day</th><th class="num">Copies</th></tr></thead><tbody>${tableRows}</tbody></table>
    </details>
  </section>
</div>
</main>
</body>
</html>`;
}

function chart(series: Day[]): string {
  const width = 900, height = 240, left = 36, right = 8, top = 12, bottom = 26;
  const plotW = width - left - right, plotH = height - top - bottom;
  const max = niceMax(Math.max(...series.map((d) => d.copies)));
  const slot = plotW / series.length;
  const barW = Math.min(24, Math.max(2, slot - 2)); // 2px gap between adjacent bars
  const y = (v: number) => top + plotH - (v / max) * plotH;
  const baseline = top + plotH;

  const grid = [0, max / 2, max]
    .map((v) => `<line x1="${left}" x2="${width - right}" y1="${y(v)}" y2="${y(v)}" stroke="var(${v === 0 ? "--axis" : "--grid"})" stroke-width="1"/>
      <text x="${left - 6}" y="${y(v) + 4}" text-anchor="end">${v.toLocaleString("en-US")}</text>`)
    .join("");

  const bars = series
    .map((d, i) => {
      const x = left + i * slot + (slot - barW) / 2;
      const h = baseline - y(d.copies);
      const r = Math.min(4, barW / 2, h);
      // Rounded data-end, square at the baseline.
      const path = h <= 0 ? "" :
        `M${x},${baseline} V${baseline - h + r} Q${x},${baseline - h} ${x + r},${baseline - h} H${x + barW - r} Q${x + barW},${baseline - h} ${x + barW},${baseline - h + r} V${baseline} Z`;
      return `<g><rect class="hit" x="${left + i * slot}" y="${top}" width="${slot}" height="${plotH}" tabindex="0" aria-label="${d.day}: ${d.copies} copies"><title>${d.day}: ${d.copies.toLocaleString("en-US")} copies</title></rect><path class="bar" d="${path}"/></g>`;
    })
    .join("");

  const labelAt = [0, Math.floor(series.length / 2), series.length - 1];
  const xLabels = labelAt
    .map((i, n) => `<text x="${left + i * slot + slot / 2}" y="${height - 8}" text-anchor="${["start", "middle", "end"][n]}">${series[i].day}</text>`)
    .join("");

  return `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Copies per day for the last ${series.length} days">${grid}${bars}${xLabels}</svg>`;
}

function niceMax(value: number): number {
  if (value <= 4) return 4;
  const step = 10 ** Math.floor(Math.log10(value));
  for (const m of [1, 2, 2.5, 5, 10]) if (m * step >= value) return m * step;
  return 10 * step;
}
