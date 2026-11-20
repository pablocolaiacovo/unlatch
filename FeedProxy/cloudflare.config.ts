// See Design/feed-usage-counting.md.
import { bindings, defineConfig, triggers } from "cf/config";

export default defineConfig({
  accountId: "b98fb9acbf20073fc4132c77a83c3c1d",
  worker: {
    name: "unlatch-feed",
    entrypoint: "./src/index.ts",
    compatibilityDate: "2026-11-01",
    workersDev: true,
    previewUrls: false,
    // Off on purpose: invocation logs would keep request metadata, including client IPs.
    observability: { enabled: false },
    env: {
      DB: bindings.d1({ id: "994bad9e-05a3-4fe1-b1bf-247d67e4ffdb", name: "unlatch-telemetry" }),
      SALT_KEY: bindings.secret(),
    },
    triggers: [triggers.scheduled({ schedule: "15 0 * * *" })],
  },
});
