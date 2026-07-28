-- Bench DB tier: World table for /db, /queries, /updates (TechEmpower shape).
-- Seeded with 10,000 rows so the benchmark hits a uniform distribution of IDs.
--
-- `"randomNumber"` keeps the entity's declared casing, which is what
-- `jwc gen-sql` emits. It had to be folded to lower case before, because the
-- native UPDATE codegen lower-cased the column name while `gen-sql` and the
-- interpreter quoted it as declared — so one schema could satisfy reads or
-- writes, but not both backends at once.
CREATE TABLE IF NOT EXISTS "world" (
    "id" integer NOT NULL,
    "randomNumber" integer NOT NULL,
    PRIMARY KEY ("id")
);

INSERT INTO "world" ("id", "randomNumber")
SELECT g, floor(random() * 10000)::int
FROM generate_series(1, 10000) g
ON CONFLICT ("id") DO NOTHING;
