using Test
using Planar.Engine.LiveMode.Watchers
using Planar.Engine.LiveMode.Watchers.WatchersImpls

@testset "Blockchain Watchers" begin
    # It's better to use a known address with many transactions for testing.
    # These addresses are for demonstration purposes.
    # Replace with addresses that are known to be active.

    btc_address = "bc1qeppvcnauqak9xn7mmekw4crr79tl9c8lnxpp2k"
    eth_address = "0x77dce4813eC15650e57E1b999c197aad00bEc1c2"
    sol_address = "So11111111111111111111111111111111111111112"

    etherscan_api_key = get(ENV, "ETHERSCAN_API_KEY", "")
    helius_api_key = get(ENV, "HELIUS_API_KEY", "")

    @testset "Bitcoin Watcher" begin
        w = blockchain_address_watcher(:bitcoin, btc_address)
        @test w isa Watcher
        Watchers._fetch!(w, Watchers._val(w))
        @test length(w.buffer) > 0
        @test first(w.buffer).value isa Vector{Dict}
        Watchers.stop!(w)
    end

    if !isempty(etherscan_api_key)
        @testset "Ethereum Watcher" begin
            w = blockchain_address_watcher(:ethereum, eth_address, api_key=etherscan_api_key)
            @test w isa Watcher
            Watchers._fetch!(w, Watchers._val(w))
            @test length(w.buffer) > 0
            @test first(w.buffer).value isa Vector{Dict}
            Watchers.stop!(w)
        end
    else
        @warn "Skipping Ethereum watcher test: ETHERSCAN_API_KEY not set"
    end

    if !isempty(helius_api_key)
        @testset "Solana Watcher" begin
            w = blockchain_address_watcher(:solana, sol_address, api_key=helius_api_key)
            @test w isa Watcher
            Watchers._fetch!(w, Watchers._val(w))
            @test length(w.buffer) > 0
            @test first(w.buffer).value isa Vector{Dict}
            Watchers.stop!(w)
        end
    else
        @warn "Skipping Solana watcher test: HELIUS_API_KEY not set"
    end
end
