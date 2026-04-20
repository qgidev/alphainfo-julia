# AlphaInfo.jl

[![CI](https://github.com/qgidev/alphainfo-julia/actions/workflows/CI.yml/badge.svg)](https://github.com/qgidev/alphainfo-julia/actions/workflows/CI.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Julia client for the [alphainfo.io](https://alphainfo.io) Structural Intelligence API.

## Install

```julia
using Pkg
Pkg.add("AlphaInfo")
```

## 30-second try

**Step 1 — [get a free API key](https://alphainfo.io/register)**.

**Step 2**:

```julia
using AlphaInfo

client = AlphaInfoClient(ENV["ALPHAINFO_API_KEY"])

signal = vcat(sin.((0:199) ./ 10), sin.((0:199) ./ 10) .* 3)

result = analyze(client; signal = signal, sampling_rate = 100.0)
println(result["confidence_band"])   # stable | transition | unstable
println(result["structural_score"])  # 0 (changed) → 1 (preserved)
```

## Structural fingerprint

```julia
fp = fingerprint(client; signal = signal, sampling_rate = 250.0)

if fp.fingerprint_available
    fp.vector   # Vector{Float64} of length 5 — for pgvector / Qdrant / Faiss
else
    println("unavailable: ", fp.fingerprint_reason)
end
```

**Minimum signal length:**

| Case | Minimum samples | Constant |
|---|---|---|
| No baseline | 192 | `AlphaInfo.MIN_FINGERPRINT_SAMPLES` |
| With baseline | 50 | `AlphaInfo.MIN_FINGERPRINT_SAMPLES_WITH_BASELINE` |

Below the threshold, `fp.vector` is `nothing` (never filled with zeros) and the package emits a `@warn` at call time.

## Error handling

Errors subtype `AlphaInfo.AlphaInfoError`:

```julia
try
    analyze(client; signal = signal, sampling_rate = 1.0)
catch e
    if e isa AlphaInfo.AuthError
        # Get a key at https://alphainfo.io/register
    elseif e isa AlphaInfo.RateLimitError
        sleep(e.retry_after)
    elseif e isa AlphaInfo.ValidationError
        # Bad input
    elseif e isa AlphaInfo.NotFoundError
        # analysis_id not found
    elseif e isa AlphaInfo.ApiError
        # 5xx
    elseif e isa AlphaInfo.NetworkError
        # Transport
    end
end
```

## Zero-auth exploration

```julia
g = AlphaInfo.guide()
h = AlphaInfo.health()
```

## DataFrames integration

Works seamlessly with `DataFrames.jl` — pass columns directly:

```julia
using DataFrames, AlphaInfo

df = DataFrame(signal = rand(400), t = 1:400)
fp = fingerprint(client; signal = df.signal, sampling_rate = 1.0)
```

## Links

- [Web](https://alphainfo.io)
- [Python SDK](https://pypi.org/project/alphainfo/)
- [JS/TS SDK](https://www.npmjs.com/package/alphainfo)

## About

Built by **QGI Quantum Systems LTDA** — São Paulo, Brazil.
Contact: contato@alphainfo.io · api@alphainfo.io

## License

MIT
