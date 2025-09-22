using Test

function _test_stablecoin_watcher()
    w = Watchers.stablecoin_watcher()
    @test w.name == "stablecoin_supply"
    Watchers._fetch!(w, Watchers._val(w))
    @test length(w.buffer) > 0
    @test last(w.buffer).value isa Watchers.WatchersImpls.StablecoinSupply
end

function _test_blockchain_watcher()
    w = Watchers.blockchain_watcher()
    @test w.name == "blockchain_tvl"
    Watchers._fetch!(w, Watchers._val(w))
    @test length(w.buffer) > 0
    @test last(w.buffer).value isa Watchers.WatchersImpls.BlockchainTVL
end

function test_stablecoin_watchers()
    @testset "stablecoin_watchers" begin
        _test_stablecoin_watcher()
        _test_blockchain_watcher()
    end
end
