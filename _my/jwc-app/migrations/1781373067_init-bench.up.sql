-- Bench DB tier: World table for /db, /queries, /updates (TechEmpower shape).
-- Seeded with 10,000 rows so the benchmark hits a uniform distribution of IDs.
--
-- `randomnumber` is deliberately lower-case and unquoted. jwc's native backend
-- reads rows positionally (`SELECT *` + `try_get(1)`) and takes the JSON key
-- from the entity field name, so the column's case never affects reads — but
-- its UPDATE codegen lower-cases the column name, so a quoted "randomNumber"
-- column makes `update BenchDb.World set randomNumber = ...` fail to prepare.
-- Folding the column to lower case keeps writes working while every stack still
-- answers with `randomNumber`, matching the TechEmpower shape.
CREATE TABLE IF NOT EXISTS "world" (
    "id" integer NOT NULL,
    randomnumber integer NOT NULL,
    PRIMARY KEY ("id")
);

INSERT INTO "world" ("id", randomnumber)
SELECT g, floor(random() * 10000)::int
FROM generate_series(1, 10000) g
ON CONFLICT ("id") DO NOTHING;
