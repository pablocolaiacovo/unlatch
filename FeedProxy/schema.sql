-- D1 database `unlatch-telemetry`. See Design/feed-usage-counting.md.
-- One row per copy per day; deleted once the day is rolled up into `daily`.
CREATE TABLE IF NOT EXISTS seen (
  day TEXT NOT NULL,
  hash TEXT NOT NULL,
  version TEXT NOT NULL,
  PRIMARY KEY (day, hash)
);
-- Kept: unique copies per day and app version.
CREATE TABLE IF NOT EXISTS daily (
  day TEXT NOT NULL,
  version TEXT NOT NULL,
  copies INTEGER NOT NULL,
  PRIMARY KEY (day, version)
);
