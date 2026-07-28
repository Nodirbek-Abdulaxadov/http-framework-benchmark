// Reset the DB-tier world table to a pristine, deterministic state.
//
// /updates rewrites ~500k rows per 15 s window, so across a full 8-stack
// session the table accumulates enough dead tuples to trigger autovacuum
// mid-measurement. Whichever stack happens to overlap a vacuum pays for it —
// in one session that cost dotnet-minimal 5x on /db and 5x on /queries purely
// from run order. Resetting before every server removes that confound.
//
// Autovacuum is left disabled on the table so nothing kicks in during a run;
// this script is what keeps the table from growing without bound instead.
//
// Usage: node .dist/reset-db.js   (pg is resolved from node-fastify's install)

const path = require("path");

const DSN = process.env.DATABASE_URL
    || "postgres://postgres:1234@localhost:5432/BenchJWCDB";

let Client;
try {
    ({ Client } = require(path.join(__dirname, "..", "node-fastify", "node_modules", "pg")));
} catch {
    try {
        ({ Client } = require("pg"));
    } catch {
        console.error("reset-db: pg module not found — run `npm install` in node-fastify/");
        process.exit(2);
    }
}

(async () => {
    const c = new Client(DSN);
    await c.connect();

    await c.query("ALTER TABLE world SET (autovacuum_enabled = false)");
    await c.query("TRUNCATE world");
    await c.query(`INSERT INTO world (id, randomnumber)
                   SELECT g, floor(random() * 10000)::int
                   FROM generate_series(1, 10000) g`);
    // FULL rewrites the heap, so every server starts against the same physical
    // layout rather than inheriting the previous server's bloat.
    await c.query("VACUUM (FULL, ANALYZE) world");

    const { rows } = await c.query(
        `SELECT count(*)::int AS n, pg_size_pretty(pg_total_relation_size('world')) AS size
         FROM world`);
    console.log(`reset-db: ${rows[0].n} rows, ${rows[0].size}`);

    await c.end();
})().catch((e) => {
    console.error("reset-db failed:", e.message);
    process.exit(1);
});
