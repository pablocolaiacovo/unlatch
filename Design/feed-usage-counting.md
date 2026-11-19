# Counting active copies through the update feed

Issue #121, option 1. Answers "do I have real users?" by counting the Sparkle update checks that
installed copies already make, without adding anything to the app beyond a new feed URL.

## Shape

```
Unlatch.app ──GET /appcast.xml──▶ Cloudflare Worker `unlatch-feed` (workers.dev)
                                    │  1. fetch https://pablocolaiacovo.github.io/unlatch/appcast.xml
                                    │     (query string passed through, so `?cb=` cache busting works)
                                    │  2. return that response unchanged
                                    │  3. in the background, record the hit in D1
                                    ▼
                                  D1 `unlatch-telemetry`
```

GitHub Pages stays the source of the feed. The release workflow keeps publishing there. Copies on
versions before this change keep reading Pages directly and are not counted until they update.

## What is recorded

Only requests whose User-Agent contains `Sparkle/` are counted. That excludes the release
workflow's `curl` checks, browsers and crawlers. Sparkle's User-Agent is
`<app>/<CFBundleShortVersionString> Sparkle/<version>`; the app version is the part after the first
`/`, capped at 32 characters.

```sql
-- One row per copy per day. Deleted once the day is rolled up.
CREATE TABLE seen (day TEXT NOT NULL, hash TEXT NOT NULL, version TEXT NOT NULL,
                   PRIMARY KEY (day, hash));
-- Kept: unique copies per day and app version.
CREATE TABLE daily (day TEXT NOT NULL, version TEXT NOT NULL, copies INTEGER NOT NULL,
                    PRIMARY KEY (day, version));
```

`hash` is `HMAC-SHA256(SALT_KEY, day + "|" + client IP)`, hex. `SALT_KEY` is a Worker secret, so a
copy of the database alone can't be brute-forced back to IPv4 addresses, and the day in the input
means hashes from different days can't be linked. Raw IPs are never written. A copy that updates
mid-day is counted once, under the first version seen that day.

A cron trigger at 00:15 UTC rolls every finished day from `seen` into `daily` and deletes those
`seen` rows. After that, only the counts remain.

## Failure behaviour

- The feed never depends on counting: the D1 write runs in `ctx.waitUntil` and its errors are
  swallowed. Over the D1 free limit (100,000 rows written a day), counts for that day are short and
  updates keep working.
- If GitHub Pages fails, the Worker passes its status through, exactly as Sparkle sees it today.
- Only `GET`/`HEAD /appcast.xml` and `GET /stats` are served; any other path is a 404.

## Reading the numbers

`GET /stats` on the Worker is a dashboard: copies yesterday, the 30-day daily average, today so
far, a 90-day chart, copies by version for the latest day, and the daily numbers as a table. It is
server-rendered HTML with no scripts or external requests (`src/stats.ts`).

It is behind HTTP Basic auth against the `DASHBOARD_PASSWORD` Worker secret (any user name). With
no secret set, `/stats` is a 404, so the page fails closed. The comparison hashes both values and
uses `crypto.subtle.timingSafeEqual`. Version strings come from User-Agent headers and are
HTML-escaped. Responses are `no-store` and `noindex`.

For ad hoc queries:

```bash
cf d1 query 994bad9e-05a3-4fe1-b1bf-247d67e4ffdb --sql "SELECT day, SUM(copies) FROM daily GROUP BY day ORDER BY day DESC LIMIT 30"
```

## Changes

| Where | Change | Owner |
| --- | --- | --- |
| `FeedProxy/` | Worker code and `cloudflare.config.ts`, deployed with `cf deploy` | devops |
| Cloudflare | D1 database and schema, `SALT_KEY` and `DASHBOARD_PASSWORD` secrets | devops |
| `Resources/Info.plist.template`, its test | `SUFeedURL` set to the Worker URL | macos-developer |
| `README.md`, `RELEASING.md` | Privacy section; feed URL references | macos-developer, project-owner |

The release workflow needs no change: it reads `SUFeedURL` from the built app, and its `curl`
checks pass through the Worker to Pages without being counted.

## Risks

- The `workers.dev` hostname is tied to this Cloudflare account. Renaming the account subdomain,
  deleting the Worker or moving accounts breaks updates for every copy with this URL until a release
  ships a new one.
- The opt-in usage-statistics toggle from #121 does not apply here: update checks were already being
  made, and nothing new is sent. The README discloses the counting.
