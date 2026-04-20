# Changelog

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
