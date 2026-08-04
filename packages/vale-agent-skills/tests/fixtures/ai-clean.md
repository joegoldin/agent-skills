# Rate limiting in the ingest path

The ingest service drops requests once the per-tenant bucket empties. Each bucket
refills at 200 tokens a second. We picked 200 after a week of load tests: at 150
the p99 climbed past our 400ms budget, and at 300 the database connection pool
started to thrash.

Buckets live in Redis. A Lua script does the check and the decrement in one round
trip, so two concurrent requests cannot both pass a bucket with one token left.

When a tenant runs out, the service returns 429 with a `Retry-After` header. The
SDK backs off and retries twice. If both retries fail, the caller sees the error.

We have not solved the noisy-neighbour problem for shared clusters. That work is
tracked in ING-4412.
