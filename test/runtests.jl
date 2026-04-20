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
