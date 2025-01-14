# TODO: add some stub data
test_collections() = @testset "collections" begin
    @eval begin
        using .Planar.Engine.Collections
        using .Planar.Engine.Misc
        using .Planar.Engine.Instruments
        using .Planar.Engine.Exchanges
    end
    prs = ["ETH/USDT", "BTC/USDT"]
    exc = getexchange!(EXCHANGE)
    let coll = AssetCollection()
        @test isempty(coll)
    end
    coll = AssetCollection(prs; exc, margin=Misc.NoMargin())
    @test size(coll.data)[1] == length(prs)
    @test Instruments.raw.(coll.data.instance) == prs
    @test !isnothing(coll[q=:USDT])
    @test !isnothing(coll[b=:BTC])
    @test !isnothing(coll[e=:kucoin])
    @test !isnothing(coll[b=:BTC, q=:USDT])
    @test !isnothing(coll[b=:BTC, q=:USDT, e=:kucoin])
end
