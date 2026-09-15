-- Hand-written data sidecar for 0001_init (applied in its data phase).
-- Seeds World with 10,000 rows so /db, /queries and /updates hit a uniform
-- spread of ids — the same seed the other seven stacks run against.
INSERT INTO public.world (id, randomnumber)
SELECT g, floor(random() * 10000)::int
FROM generate_series(1, 10000) g
ON CONFLICT (id) DO NOTHING;
