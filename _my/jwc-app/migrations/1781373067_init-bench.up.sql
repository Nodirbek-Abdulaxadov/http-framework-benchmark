-- Bench DB tier: World table for /db, /queries, /updates (TechEmpower shape).
-- Seeded with 10,000 rows so the benchmark hits a uniform distribution of IDs.
CREATE TABLE IF NOT EXISTS "world" (
    "id" integer NOT NULL,
    "randomNumber" integer NOT NULL,
    PRIMARY KEY ("id")
);

INSERT INTO "world" ("id", "randomNumber")
SELECT g, floor(random() * 10000)::int
FROM generate_series(1, 10000) g
ON CONFLICT ("id") DO NOTHING;
