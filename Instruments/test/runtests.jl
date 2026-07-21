using Test
using Instruments
using Instruments: splitpair, isleveragedpair, deleverage_pair, isfiatpair, isfiatquote
using Instruments.Derivatives: Derivative, DerivativeKind

# ──────────────────────────────────────────────
# Asset type
# ──────────────────────────────────────────────
@testset "Asset type" begin
    a = a"BTC/USDT"
    @test a isa Asset
    @test a isa AbstractAsset
    @test raw(a) == "BTC/USDT"
    @test bc(a) == :BTC
    @test qc(a) == :USDT
    @test !a.fiat
    @test !a.leveraged

    b = a"USDT/USDC"
    @test b.fiat

    c = a"ETH3L/USDT"
    @test c.leveraged
    @test c.unleveraged_bc == :ETH
end

@testset "Asset parsing" begin
    a = parse(Asset, "ETH/BTC")
    @test a isa Asset
    @test raw(a) == "ETH/BTC"

    a2 = parse(AbstractAsset, "XRPUSDT", "USDT")
    @test !isnothing(a2)
    @test bc(a2) == :XRP
end

@testset "Asset equality" begin
    @test a"BTC/USDT" == a"BTC/USDT"
    @test a"BTC/USDT" == "BTC/USDT"
    @test a"BTC/USDT" != a"ETH/USDT"
    @test a"BTC/USDT" in (b=:BTC, q=:USDT)
end

# ──────────────────────────────────────────────
# splitpair
# ──────────────────────────────────────────────
@testset "splitpair" begin
    @test splitpair("BTC/USDT") == ["BTC", "USDT"]
    @test splitpair("ETH-BTC") == ["ETH", "BTC"]
    @test splitpair("XRP_USDT") == ["XRP", "USDT"]
    @test splitpair("BNB.USDT") == ["BNB", "USDT"]
end

# ──────────────────────────────────────────────
# Leveraged pair detection
# ──────────────────────────────────────────────
@testset "Leveraged pairs" begin
    @test isleveragedpair("ETH3L/USDT")
    @test isleveragedpair("BTC3S/USDT")
    @test isleveragedpair("XRPBULL/USDT")
    @test isleveragedpair("ETHBEAR/USDT")
    @test !isleveragedpair("BTC/USDT")
    @test !isleveragedpair("ETH/BTC")

    dl = deleverage_pair("ETH3L/USDT")
    @test dl == "ETH/USDT"

    dl2 = deleverage_pair("XRPBULL/USDT")
    @test dl2 == "XRP/USDT"
end

# ──────────────────────────────────────────────
# Fiat detection
# ──────────────────────────────────────────────
@testset "Fiat detection" begin
    @test isfiatpair("USDT/USDC")
    @test !isfiatpair("BTC/USDT")
    @test isfiatquote(a"ETH/USDT")
    @test !isfiatquote(a"ETH/BTC")
end

# ──────────────────────────────────────────────
# Cash type
# ──────────────────────────────────────────────
@testset "Cash type" begin
    ca = c"USDT"
    @test ca isa Cash
    @test value(ca) ≈ 0.0

    ca2 = Cash(:BTC, 1.5)
    @test value(ca2) ≈ 1.5

    ca3 = Cash(:ETH, 10.0)
    @test value(ca3) > value(ca2)
end

# ──────────────────────────────────────────────
# String macro
# ──────────────────────────────────────────────
@testset "String macros" begin
    @test a"BTC/USDT" isa Asset
end

# ──────────────────────────────────────────────
# Derivatives (ported from PlanarDev/test/test_derivatives.jl)
# ──────────────────────────────────────────────
@testset "Derivatives" begin
    example = "ETH/USDT:USDT-210625-5000-C"
    d = parse(Derivative, example)
    @test d isa Derivative
    @test d.bc == :ETH
    @test d.qc == :USDT
    @test d.sc == :USDT
    @test d.id == "210625"
    @test d.strike == 5000.0
    @test d.kind == DerivativeKind(1)  # Call
end
