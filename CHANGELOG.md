# Changelog

## 1.5.14 — Version parity bump

No code changes in this SDK. Bumped only to keep the version number in
sync with the Python SDK (which shipped 1.5.14 to fix a stale
`__version__` string that the other SDKs never had). All functional
behaviour is identical to 1.5.13.

## 1.5.13 — Response contract refinement and documentation improvements

Server response shape has been neutralised — the following keys have
new names:
  • metrics.scale_entropy                            → metrics.complexity_index
  • metrics.multiscale.curvature                     → metrics.multiscale.scale_profile
  • metrics.multiscale.summary.scale_curvature_score → metrics.multiscale.summary.profile_score

The 5D fingerprint contract (sim_local/sim_spectral/sim_fractal/
sim_transition/sim_trend + fingerprint_available + fingerprint_reason)
is unchanged.

## [1.5.12] - 2026-04-20

Added automatic domain inference; `domain` keyword now optional with
sensible default.

- `analyze()` docstring expanded to explain `domain="auto"` and the
  two extra response keys the server populates then:
  `"domain_applied"` (always) and `"domain_inference"` (only when the
  caller passed `domain="auto"`).
- New exported `analyze_auto()` wrapper — sugar for
  `analyze(...; domain="auto", ...)`.
- SDK_VERSION bumped 1.5.11 → 1.5.12.

Backwards-compatible.

## [1.5.11] - 2026-04-20

Connection cleanup improvements.

- `Base.close(::AlphaInfoClient)` is now defined. Marks the client as
  closed so subsequent calls throw `NetworkError("client is closed …")`.
- Idempotent — safe inside a `try/finally`.
- New `closed::Bool` field on `AlphaInfoClient` (default `false`).
- Julia's `HTTP.jl` uses a global connection pool, so `close()` is
  mostly a defensive marker for API parity with the other alphainfo
  SDKs; still useful to avoid accidental use of stale clients.

## [1.5.10] - 2026-04-20

Initial release — parity with Python SDK 1.5.10.

- `AlphaInfoClient` + `analyze`, `fingerprint`, `analyze_batch`,
  `analyze_matrix`, `analyze_vector`, `audit_list`, `audit_replay`.
- `guide()` / `health()` no-auth helpers.
- Constants `MIN_FINGERPRINT_SAMPLES` (192) and
  `MIN_FINGERPRINT_SAMPLES_WITH_BASELINE` (50).
- Honest fingerprint contract — `sim_*` fields are `missing` when
  not computable; `fp.vector` is `nothing` when incomplete.
- Abstract `AlphaInfoError` with concrete `AuthError`,
  `RateLimitError`, `ValidationError`, `NotFoundError`, `ApiError`,
  `NetworkError`.
- `@warn` when `fingerprint` called with a signal shorter than the
  threshold.
