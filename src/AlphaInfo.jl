"""
    AlphaInfo

Julia client for the alphainfo.io Structural Intelligence API — detect
regime changes in any time series. Honest fingerprint contract
(returns `missing` when the engine cannot decompose, never silent
zeros) and public constants kept in sync with the server.

```julia
using AlphaInfo

client = AlphaInfoClient(ENV["ALPHAINFO_API_KEY"])
result = analyze(client, signal=[...], sampling_rate=100.0)
println(result.confidence_band, "  ", result.structural_score)
```

Get a free API key: https://alphainfo.io/register
"""
module AlphaInfo

import HTTP
import JSON3

export AlphaInfoClient,
       analyze, fingerprint,
       analyze_batch, analyze_matrix, analyze_vector,
       audit_list, audit_replay,
       guide, health, plans,
       MIN_FINGERPRINT_SAMPLES, MIN_FINGERPRINT_SAMPLES_WITH_BASELINE,
       AlphaInfoError, AuthError, RateLimitError,
       ValidationError, NotFoundError, ApiError, NetworkError

const DEFAULT_BASE_URL = "https://www.alphainfo.io"
const SDK_VERSION = "1.5.10"

"""
    MIN_FINGERPRINT_SAMPLES

Minimum signal length for a full 5-dimensional fingerprint when no
baseline is provided (value: 192).
"""
const MIN_FINGERPRINT_SAMPLES = 192

"""
    MIN_FINGERPRINT_SAMPLES_WITH_BASELINE

Minimum signal length when a comparable baseline is provided (value: 50).
"""
const MIN_FINGERPRINT_SAMPLES_WITH_BASELINE = 50

# ---------------------------------------------------------------------------
# Errors
# ---------------------------------------------------------------------------

abstract type AlphaInfoError <: Exception end

struct AuthError <: AlphaInfoError
    message::String
    status_code::Int
    response_data::Any
end
struct RateLimitError <: AlphaInfoError
    message::String
    retry_after::Int
    status_code::Int
    response_data::Any
end
struct ValidationError <: AlphaInfoError
    message::String
    status_code::Int
    response_data::Any
end
struct NotFoundError <: AlphaInfoError
    message::String
    status_code::Int
    response_data::Any
end
struct ApiError <: AlphaInfoError
    message::String
    status_code::Int
    response_data::Any
end
struct NetworkError <: AlphaInfoError
    message::String
end

Base.showerror(io::IO, e::AlphaInfoError) = print(io, typeof(e), ": ", e.message)

# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------

"""
    AlphaInfoClient(api_key; base_url=DEFAULT_BASE_URL, timeout=150)

Create a client bound to an API key.

    julia> client = AlphaInfoClient("ai_...")
"""
mutable struct AlphaInfoClient
    api_key::String
    base_url::String
    timeout::Int
    rate_limit::Union{Nothing,NamedTuple{(:limit,:remaining,:reset),Tuple{Int,Int,Int}}}
end

function AlphaInfoClient(api_key::AbstractString;
                         base_url::AbstractString = DEFAULT_BASE_URL,
                         timeout::Integer = 150)
    if isempty(api_key)
        throw(ValidationError(
            "api_key is required. Get one at https://alphainfo.io/register (format: 'ai_...')",
            0, nothing))
    end
    AlphaInfoClient(String(api_key), rstrip(String(base_url), '/'), Int(timeout), nothing)
end

# ---------------------------------------------------------------------------
# HTTP plumbing
# ---------------------------------------------------------------------------

function _request(client::AlphaInfoClient, method::String, path::String;
                  body::Union{Nothing,Any} = nothing)
    url = client.base_url * path
    headers = [
        "X-API-Key" => client.api_key,
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "User-Agent" => "alphainfo-julia/$SDK_VERSION",
    ]
    payload = body === nothing ? UInt8[] : Vector{UInt8}(JSON3.write(body))

    local response
    try
        response = HTTP.request(method, url, headers, payload;
                                readtimeout = client.timeout,
                                status_exception = false,
                                retry = false)
    catch err
        throw(NetworkError("Network error on $path: $(sprint(showerror, err))"))
    end

    _capture_rate_limit!(client, response)
    body_str = String(HTTP.payload(response))

    if response.status >= 400
        throw(_map_error(response.status, response.headers, body_str))
    end
    return body_str
end

function _capture_rate_limit!(client::AlphaInfoClient, response::HTTP.Response)
    headers = Dict(response.headers)
    limit_s = get(headers, "X-RateLimit-Limit", get(headers, "x-ratelimit-limit", ""))
    isempty(limit_s) && return
    limit = tryparse(Int, limit_s)
    limit === nothing && return
    remaining = tryparse(Int, get(headers, "X-RateLimit-Remaining", get(headers, "x-ratelimit-remaining", "0")))
    reset = tryparse(Int, get(headers, "X-RateLimit-Reset", get(headers, "x-ratelimit-reset", "0")))
    client.rate_limit = (limit = limit,
                         remaining = remaining === nothing ? 0 : remaining,
                         reset = reset === nothing ? 0 : reset)
    return nothing
end

function _map_error(status::Integer, raw_headers, body::String)
    parsed = try JSON3.read(body, Dict) catch; Dict{String,Any}() end
    detail = get(parsed, "detail", nothing)
    msg = if detail isa AbstractString
        detail
    elseif detail isa AbstractDict && haskey(detail, "message")
        string(detail["message"])
    else
        "HTTP $status"
    end
    headers = Dict(raw_headers)

    if status == 401
        return AuthError(
            isempty(msg) || msg == "HTTP 401" ?
                "Invalid or missing API key. Get a free key at https://alphainfo.io/register and pass it to AlphaInfoClient." :
                msg,
            status, parsed)
    elseif status == 429
        retry_after = tryparse(Int, get(headers, "Retry-After", get(headers, "retry-after", "0")))
        return RateLimitError(msg, retry_after === nothing ? 0 : retry_after, status, parsed)
    elseif status in (400, 413, 422)
        return ValidationError(msg, status, parsed)
    elseif status == 404
        return NotFoundError(msg, status, parsed)
    elseif status >= 500
        return ApiError("Server error: $msg", status, parsed)
    else
        return ApiError(msg, status, parsed)
    end
end

# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

"Run a full structural analysis on a single signal."
function analyze(client::AlphaInfoClient; signal, sampling_rate,
                 domain::AbstractString = "generic",
                 baseline = nothing,
                 include_semantic = nothing,
                 use_multiscale = nothing)
    body = Dict{String,Any}(
        "signal" => collect(Float64, signal),
        "sampling_rate" => Float64(sampling_rate),
        "domain" => domain,
    )
    baseline === nothing || (body["baseline"] = collect(Float64, baseline))
    include_semantic === nothing || (body["include_semantic"] = Bool(include_semantic))
    use_multiscale === nothing || (body["use_multiscale"] = Bool(use_multiscale))
    raw = _request(client, "POST", "/v1/analyze/stream"; body)
    return JSON3.read(raw, Dict)
end

"""
    fingerprint(client; signal, sampling_rate, domain="generic", baseline=nothing)

Extract the 5D structural fingerprint. Emits `@warn` when the signal
is shorter than the threshold (the response will come back with
`fingerprint_available=false`).

Returns a `NamedTuple`:

  * `analysis_id`, `structural_score`, `confidence_band`
  * `sim_local`, `sim_spectral`, `sim_fractal`, `sim_transition`,
    `sim_trend` — each is either a `Float64` or `missing`
  * `fingerprint_available::Bool`
  * `fingerprint_reason::Union{String,Missing}`
  * `vector::Union{Vector{Float64},Nothing}` — `nothing` when incomplete
"""
function fingerprint(client::AlphaInfoClient; signal, sampling_rate,
                     domain::AbstractString = "generic", baseline = nothing)
    n = length(signal)
    threshold = baseline === nothing ? MIN_FINGERPRINT_SAMPLES : MIN_FINGERPRINT_SAMPLES_WITH_BASELINE
    if n < threshold
        qualifier = baseline === nothing ? "without baseline" : "with baseline"
        @warn "Signal has $n samples; the 5D fingerprint needs >=$threshold $qualifier. " *
              "Response will likely come back with fingerprint_available=false " *
              "(reason=\"signal_too_short\"). Use analyze() for shorter signals."
    end

    body = Dict{String,Any}(
        "signal" => collect(Float64, signal),
        "sampling_rate" => Float64(sampling_rate),
        "domain" => domain,
        "include_semantic" => false,
        "use_multiscale" => false,
    )
    baseline === nothing || (body["baseline"] = collect(Float64, baseline))
    raw = _request(client, "POST", "/v1/analyze/stream"; body)
    parsed = JSON3.read(raw, Dict)

    metrics = get(parsed, "metrics", Dict{String,Any}())
    _sim(k) = begin
        v = get(metrics, k, nothing)
        v === nothing ? missing : Float64(v)
    end
    sims = (_sim("sim_local"), _sim("sim_spectral"), _sim("sim_fractal"),
            _sim("sim_transition"), _sim("sim_trend"))

    available::Bool = haskey(metrics, "fingerprint_available") ?
        Bool(metrics["fingerprint_available"]) :
        all(!ismissing, sims)
    reason = haskey(metrics, "fingerprint_reason") ?
        (metrics["fingerprint_reason"] === nothing ? missing : String(metrics["fingerprint_reason"])) :
        (available ? missing : "internal_error")

    vec = available ? Float64[sims...] : nothing

    return (
        analysis_id = get(parsed, "analysis_id", ""),
        structural_score = Float64(get(parsed, "structural_score", 0.0)),
        confidence_band = String(get(parsed, "confidence_band", "")),
        sim_local = sims[1],
        sim_spectral = sims[2],
        sim_fractal = sims[3],
        sim_transition = sims[4],
        sim_trend = sims[5],
        fingerprint_available = available,
        fingerprint_reason = reason,
        vector = vec,
    )
end

"Run analysis on multiple signals in one request (up to 100)."
function analyze_batch(client::AlphaInfoClient; signals, sampling_rate,
                       domain::AbstractString = "generic", baselines = nothing,
                       include_semantic = nothing, use_multiscale = nothing)
    body = Dict{String,Any}(
        "signals" => [collect(Float64, s) for s in signals],
        "sampling_rate" => Float64(sampling_rate),
        "domain" => domain,
    )
    baselines === nothing || (body["baselines"] = [b === nothing ? nothing : collect(Float64, b) for b in baselines])
    include_semantic === nothing || (body["include_semantic"] = Bool(include_semantic))
    use_multiscale === nothing || (body["use_multiscale"] = Bool(use_multiscale))
    return JSON3.read(_request(client, "POST", "/v1/analyze/batch"; body), Dict)
end

"Pairwise similarity matrix for N signals."
function analyze_matrix(client::AlphaInfoClient; signals, sampling_rate,
                        domain::AbstractString = "generic", use_multiscale = nothing)
    body = Dict{String,Any}(
        "signals" => [collect(Float64, s) for s in signals],
        "sampling_rate" => Float64(sampling_rate),
        "domain" => domain,
    )
    use_multiscale === nothing || (body["use_multiscale"] = Bool(use_multiscale))
    return JSON3.read(_request(client, "POST", "/v1/analyze/matrix"; body), Dict)
end

"Multi-channel (vector) analysis."
function analyze_vector(client::AlphaInfoClient; channels, sampling_rate,
                        domain::AbstractString = "generic", baselines = nothing,
                        include_semantic = nothing, use_multiscale = nothing)
    body = Dict{String,Any}(
        "channels" => Dict(String(k) => collect(Float64, v) for (k, v) in channels),
        "sampling_rate" => Float64(sampling_rate),
        "domain" => domain,
    )
    baselines === nothing || (body["baselines"] = Dict(String(k) => collect(Float64, v) for (k, v) in baselines))
    include_semantic === nothing || (body["include_semantic"] = Bool(include_semantic))
    use_multiscale === nothing || (body["use_multiscale"] = Bool(use_multiscale))
    return JSON3.read(_request(client, "POST", "/v1/analyze/vector"; body), Dict)
end

"List recent analyses from the audit trail."
function audit_list(client::AlphaInfoClient; limit::Integer = 100)
    return JSON3.read(_request(client, "GET", "/v1/audit/list?limit=$(Int(limit))"), Dict)
end

"Replay a past analysis by its UUID."
function audit_replay(client::AlphaInfoClient, analysis_id::AbstractString)
    isempty(analysis_id) &&
        throw(ValidationError("analysis_id cannot be empty", 0, nothing))
    return JSON3.read(_request(client, "GET", "/v1/audit/replay/" * HTTP.escapeuri(analysis_id)), Dict)
end

# ---------------------------------------------------------------------------
# No-auth helpers
# ---------------------------------------------------------------------------

"Fetch the public encoding guide. No API key required."
function guide(; base_url::AbstractString = DEFAULT_BASE_URL)
    return _fetch_noauth(rstrip(base_url, '/') * "/v1/guide")
end

"Fetch API health status. No API key required."
function health(; base_url::AbstractString = DEFAULT_BASE_URL)
    return _fetch_noauth(rstrip(base_url, '/') * "/health")
end

"List available billing plans."
function plans(client::AlphaInfoClient)
    return JSON3.read(_request(client, "GET", "/api/plans"), Any)
end

function _fetch_noauth(url::AbstractString)
    local response
    try
        response = HTTP.request("GET", url,
            ["Accept" => "application/json",
             "User-Agent" => "alphainfo-julia/$SDK_VERSION"];
            readtimeout = 30, status_exception = false, retry = false)
    catch err
        throw(NetworkError("Network error on $url: $(sprint(showerror, err))"))
    end
    body = String(HTTP.payload(response))
    response.status >= 400 && throw(_map_error(response.status, response.headers, body))
    return JSON3.read(body, Dict)
end

end # module
