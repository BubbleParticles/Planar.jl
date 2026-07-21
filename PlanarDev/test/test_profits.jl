using Test

const profits_sml = Planar.Engine.Simulations

_highfirst_1() = begin
    @test profits_sml.ishighfirst(100, 50) == true
    @test profits_sml.ishighfirst(100, 100) == true
    @test profits_sml.ishighfirst(50, 100) == false
end

_profitat() = begin
    open = 100
    close = 90
    fee = 0.01
    digits = 4
    p = profits_sml.profitat(open, close, fee; digits)
    @test p ≈ -0.1178
    spl = string(p)
    parts = split(spl, ".", limit=2)
    @test length(parts[2]) == digits
end

test_profits() = @testset "profits" begin
    _highfirst_1()
    _profitat()
end