module EngineTests

using Test
using Engine

using Engine.Misc.TimeTicks: @tf_str

# ══════════════════════════════════════════════════════════════
# _check_timeframes
# ══════════════════════════════════════════════════════════════

@testset "_check_timeframes valid" begin
    tf1 = tf"1m"
    tf2 = tf"5m"
    tf3 = tf"1h"
    Engine._check_timeframes((tf1, tf2, tf3), tf1)
    @test true
end

@testset "_check_timeframes invalid" begin
    tf1 = tf"1m"
    tf2 = tf"5m"
    @test_throws ArgumentError Engine._check_timeframes((tf1, tf2), tf2)
end

@testset "_check_timeframes unsorted" begin
    tf1 = tf"1h"
    tf2 = tf"5m"
    Engine._check_timeframes((tf1, tf2), tf2)
    @test true
end

end # module EngineTests
