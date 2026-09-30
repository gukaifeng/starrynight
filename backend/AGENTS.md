# Independent Go backend

- This directory is a standalone Go module and Docker build context. It must build and test without iOS, Xcode, Unity, licensed characters, or the Python AI worker.
- Public contract: `/v1` HTTP API and generated `api/openapi.json`. Additive fields and namespaced JSON extensions preserve compatibility; incompatible changes require a new API version.
- PostgreSQL is authoritative. Redis holds revocable SCS sessions and distributed rate limits. Never substitute process-local maps or SQLite in integration tests.
- Read the architecture and runbook in `docs/` before changing persistence. Use versioned Goose migrations, explicit ownership predicates, optimistic versions, and cursor pagination. Keep secrets, database files and test captures in ignored `.local/`.
- Guest authentication is opt-in for development/testing and must fail startup in production. No hard-coded privileged/test identity or client-supplied account identity is trusted.
- Use `make test`, `make integration`, and `make build`; document actual measurements rather than claiming an unmeasured concurrency ceiling. Do not invoke paid AI providers in tests.
