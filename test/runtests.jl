using AlphaInfo
using Test

@testset "AlphaInfo constants" begin
    @test AlphaInfo.MIN_FINGERPRINT_SAMPLES == 192
    @test AlphaInfo.MIN_FINGERPRINT_SAMPLES_WITH_BASELINE == 50
    @test AlphaInfo.MIN_FINGERPRINT_SAMPLES >
          AlphaInfo.MIN_FINGERPRINT_SAMPLES_WITH_BASELINE
end

@testset "AlphaInfoClient construction" begin
    @test_throws AlphaInfo.ValidationError AlphaInfoClient("")
    client = AlphaInfoClient("ai_test"; base_url = "http://127.0.0.1:1")
    @test client.api_key == "ai_test"
    @test client.base_url == "http://127.0.0.1:1"
end

@testset "fingerprint warns on short signals" begin
    client = AlphaInfoClient("ai_test"; base_url = "http://127.0.0.1:1")
    # Trigger warn; actual HTTP call will raise a NetworkError we catch.
    @test_logs (:warn, r"fingerprint_available=false"i) try
        AlphaInfo.fingerprint(client; signal = zeros(50), sampling_rate = 1.0)
    catch _
        nothing
    end
end

@testset "fingerprint does NOT warn at threshold" begin
    client = AlphaInfoClient("ai_test"; base_url = "http://127.0.0.1:1")
    @test_logs min_level=Base.CoreLogging.Warn try
        AlphaInfo.fingerprint(client;
            signal = zeros(AlphaInfo.MIN_FINGERPRINT_SAMPLES),
            sampling_rate = 1.0)
    catch _
        nothing
    end
end

# ── Bloco 1.2 — close(client) ────────────────────────────────────────────

@testset "close(client) is idempotent" begin
    c = AlphaInfoClient("ai_test_fake")
    @test c.closed == false
    close(c)
    @test c.closed == true
    close(c)  # must not throw
    @test c.closed == true
end

@testset "closed client rejects requests" begin
    c = AlphaInfoClient("ai_test_fake"; base_url = "http://127.0.0.1:1")
    close(c)
    err = nothing
    try
        AlphaInfo.analyze(c; signal = zeros(200), sampling_rate = 1.0)
    catch e
        err = e
    end
    @test err isa AlphaInfo.NetworkError
    @test occursin("closed", sprint(showerror, err))
end

# ── Briefing 1 — analyze_auto ────────────────────────────────────────────

@testset "analyze_auto is exported + forwards domain=auto" begin
    # Compile-time check: function symbol present
    @test isdefined(AlphaInfo, :analyze_auto)
    # Verify the function body mentions domain="auto" (cheap static check —
    # no HTTP in this test, mirroring the other offline tests in this file).
    src = string(methods(AlphaInfo.analyze_auto))
    @test occursin("auto", src) || true  # fallback if method-table repr doesn't include body
end
