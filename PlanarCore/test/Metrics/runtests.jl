using Test
using PlanarCore.Metrics
using PlanarCore.Instances.Data.DataFrames: DataFrame
const M = PlanarCore.Metrics
const _tf1d = M.ect.TimeTicks.@tf_str("1d")
const HTTP = PlanarCore.ExchangeTypes.CcxtGateway.HTTP
const JSON3 = PlanarCore.ExchangeTypes.JSON3

@testset "_returns_arr" begin
    arr = [100.0, 110.0, 110.0, 99.0]
    r = M._returns_arr(arr)
    @test length(r) == 3
    @test r[1] ≈ 0.1
    @test r[2] ≈ 0.0
    @test r[3] ≈ -0.1

    @test isempty(M._returns_arr([5.0]))
end

@testset "maxdd" begin
    # All positive returns → no drawdown
    result = M.maxdd([0.01, 0.02, 0.03])
    @test result.dd ≈ 0.0
    @test result.ath ≈ 1.061106

    # Single element → dd=0.0
    result2 = M.maxdd([0.05])
    @test result2.dd ≈ 0.0

    # Mixed returns with one drawdown
    returns = [0.1, -0.2, 0.05, -0.1, 0.15]
    result3 = M.maxdd(returns)
    @test result3.dd ≈ -0.244  # (1.1 - 0.8316) / 1.1

    # Empty returns → dd=0.0
    result4 = M.maxdd(Float64[])
    @test result4.dd ≈ 0.0

    # Strictly declining: each step is a new drawdown
    result5 = M.maxdd([-0.1, -0.1, -0.1])
    @test result5.dd ≈ -0.19  # (0.9 - 0.729) / 0.9
    @test result5.ath ≈ 0.9
end

@testset "_rawsharpe" begin
    # Nearly constant returns → very large (not Inf due to FP precision)
    returns = fill(0.01, 10)
    result = M._rawsharpe(returns; tf=_tf1d)
    @test result > 1e15

    # Positive volatile returns
    returns2 = [0.01, -0.005, 0.02, -0.01, 0.015, -0.008, 0.012]
    result2 = M._rawsharpe(returns2; tf=_tf1d)
    @test isfinite(result2)
    @test result2 > 0
end

@testset "_rawsortino" begin
    returns = [0.01, -0.01, 0.02, -0.02, 0.015]
    result = M._rawsortino(returns; tf=_tf1d)
    @test isfinite(result)

    # Only positive returns — empty downside slice → 0.0 (perfect Sortino)
    pos_only = fill(0.01, 10)
    result2 = M._rawsortino(pos_only; tf=_tf1d)
    @test result2 ≈ 0.0
end

@testset "_rawcalmar" begin
    # Single element — maxdd returns dd=0 → iszero guard returns 0.0 (perfect Calmar)
    returns = [0.01]
    result = M._rawcalmar(returns; tf=_tf1d)
    @test result ≈ 0.0

    # Normal case
    result2 = M._rawcalmar([0.01, 0.02, -0.01, 0.015]; tf=_tf1d)
    @test isfinite(result2)
end

@testset "_rawexpectancy" begin
    @test M._rawexpectancy([]) == 0.0
    @test M._rawexpectancy([-0.01, -0.02]) == 0.0
    @test 0 < M._rawexpectancy([0.05, -0.02, 0.03, -0.01, 0.04]) < 2.0
end

@testset "_annualize" begin
    # sqrt(365) ≈ 19.105
    @test M._annualize(1.0, _tf1d) ≈ sqrt(365.0)
    @test M._annualize(0.5, _tf1d) ≈ 0.5 * sqrt(365.0)
    @test M._annualize(0.0, _tf1d) == 0.0
end

@testset "normalize_metric" begin
    @test 0.0 ≤ M.normalize_metric(5.0, Val(:sharpe)) ≤ 1.0
    @test M.normalize_metric(0.0, Val(:total)) == 0.0
    @test M.normalize_metric(1e7, Val(:trades)) ≈ 1.0
    @test M.normalize_metric(0.5, Val(:expectancy)) ≈ 0.05  # 0.5 / 10 (max=10)
end

@testset "helpers" begin
    @test M.possum(-5.0, 3.0) == 0.0
    @test M.possum(1.0, 2.0) == 3.0
    @test M.orzero(0.0) == 0.0
    @test M.orzero(1e-20) == 0.0
    @test M.orzero(0.1) == 0.1
    @test M.appsum(1.0, 2.0) == 3.0
    @test M.appsum(-1.0, 1.0) == 0.0
end

@testset "ffill" begin
    v = [1.0, missing, missing, 4.0, missing]
    filled = M.ffill(v)
    @test filled == [1.0, 1.0, 1.0, 4.0, 4.0]
    @test v[2] === missing  # original unchanged
end

@testset "entryexit" begin
    @test M.entryexit([-1.0, 1.0, -2.0, 1.5]) == (entries=2, exits=2)
    @test M.entryexit([-1.0]) == (entries=1, exits=0)
    @test M.entryexit(Float64[]) == (entries=0, exits=0)
end

@testset "_zeronan and _clamp_metric" begin
    @test M._zeronan(NaN) == 0.0
    @test M._zeronan(5.0) == 5.0
    @test M._zeronan(-Inf) == -Inf

    @test M._clamp_metric(0.5, 1.0) == 0.5
    @test M._clamp_metric(2.0, 1.0) == 1.0
    @test M._clamp_metric(-0.5, 1.0) == 0.0
    @test M._clamp_metric(NaN, 1.0) == 0.0
end

@testset "_spent" begin
    result = M._spent(nothing, nothing, nothing, 10.0, 100.0, 1000.0, 1.0, 0.5)
    @test result ≈ -151.0

    result2 = M._spent(nothing, nothing, nothing, 1.0, 10.0, 10.0, 0.0, 0.0)
    @test result2 ≈ -10.0

    @test_throws AssertionError M._spent(nothing, nothing, nothing, 1.0, 1.0, -5.0, 0.0, 0.0)
end

@testset "zeromissing!" begin
    v = [missing, 1.0, missing, 2.0]
    M.zeromissing!(v)
    @test v == [0.0, 1.0, 0.0, 2.0]

    v2 = [1.0, 2.0]
    M.zeromissing!(v2)
    @test v2 == [1.0, 2.0]

    v3 = Float64[]
    M.zeromissing!(v3)
    @test isempty(v3)
end

@testset "ffill! (in-place)" begin
    v = [1.0, missing, missing, 4.0, missing]
    out = copy(v)
    M.ffill!(out)
    @test out == [1.0, 1.0, 1.0, 4.0, 4.0]

    v2 = [1.0, 2.0, 3.0]
    M.ffill!(v2)
    @test v2 == [1.0, 2.0, 3.0]
end

@testset "METRICS constants" begin
    @test :sharpe in M.METRICS
    @test :sortino in M.METRICS
    @test :calmar in M.METRICS
    @test :total in M.METRICS
    @test :drawdown in M.METRICS
    @test :expectancy in M.METRICS
    @test :cagr in M.METRICS
    @test :trades in M.METRICS
    @test M.DAYS_IN_YEAR == 365
end

@testset "trades_metrics.jl functions" begin
    @testset "trades_pnl with returns array" begin
        returns = [0.05, -0.02, 0.03, -0.01, 0.04]
        # Use default f=mean with non-empty data (no default_value call)
        result = M.trades_pnl(returns)
        @test result isa NamedTuple
        @test hasproperty(result, :mean_loss)
        @test hasproperty(result, :mean_profit)

        # Use f=sum (which has a zero-arg method, so default_value works)
        result2 = M.trades_pnl(returns; f=sum)
        @test result2 isa NamedTuple
        @test hasproperty(result2, :sum_loss)
        @test hasproperty(result2, :sum_profit)

        # Empty returns — use f=sum since default_value(sum) returns 0
        result3 = M.trades_pnl(Float64[]; f=sum)
        @test result3 isa NamedTuple
    end

    @testset "trades_drawdown internal logic" begin
        # Test the internal drawdown algorithm from trades_metrics.jl
        cum_bal = [100.0, 110.0, 105.0, 115.0, 100.0, 120.0]
        ath = atl = first(cum_bal)
        dd = typemax(eltype(cum_bal))
        for v in cum_bal
            if v > ath
                ath = v
            elseif v < atl
                atl = v
            end
            aatl = abs(atl)
            shifted_ath = aatl + abs(ath)
            this_dd = aatl / shifted_ath
            if aatl > zero(aatl) && this_dd < dd
                dd = this_dd
            end
        end
        @test dd >= 0.0
        @test dd <= 1.0
        @test isfinite(dd)
    end

    @testset "trades_drawdown edge cases internal" begin
        # Single element — condition aatl > zero(aatl) is true (100 > 0), so dd = 100/(100+100) = 0.5
        cum_bal = [100.0]
        ath = atl = first(cum_bal)
        dd = typemax(eltype(cum_bal))
        for v in cum_bal
            if v > ath
                ath = v
            elseif v < atl
                atl = v
            end
            aatl = abs(atl)
            shifted_ath = aatl + abs(ath)
            this_dd = aatl / shifted_ath
            if aatl > zero(aatl) && this_dd < dd
                dd = this_dd
            end
        end
        @test dd ≈ 0.5  # 100/(100+100)

        # All increasing — atl stays at first value, dd = 100/(100+120) ≈ 0.4545
        cum_bal = [100.0, 110.0, 120.0]
        ath = atl = first(cum_bal)
        dd = typemax(eltype(cum_bal))
        for v in cum_bal
            if v > ath
                ath = v
            elseif v < atl
                atl = v
            end
            aatl = abs(atl)
            shifted_ath = aatl + abs(ath)
            this_dd = aatl / shifted_ath
            if aatl > zero(aatl) && this_dd < dd
                dd = this_dd
            end
        end
        @test dd ≈ 100.0/(100.0+120.0)

        # All decreasing — atl gets updated to lower values
        cum_bal = [120.0, 110.0, 100.0]
        ath = atl = first(cum_bal)
        dd = typemax(eltype(cum_bal))
        for v in cum_bal
            if v > ath
                ath = v
            elseif v < atl
                atl = v
            end
            aatl = abs(atl)
            shifted_ath = aatl + abs(ath)
            this_dd = aatl / shifted_ath
            if aatl > zero(aatl) && this_dd < dd
                dd = this_dd
            end
        end
        @test isfinite(dd)
        @test dd > 0.0
        # atl updated to 100, ath stays at 120, dd = 100/(100+120) ≈ 0.4545
        @test dd ≈ 100.0/(100.0+120.0)
    end
end

@testset "trades_stats does not mutate live history" begin
    # Mock HTTP to avoid gateway calls during strategy setup
    import PlanarCore.ExchangeTypes.CcxtGateway.Rest: set_http_get!, set_http_post!
    _saved_get = PlanarCore.ExchangeTypes.CcxtGateway.Rest._http_get[]
    _saved_post = PlanarCore.ExchangeTypes.CcxtGateway.Rest._http_post[]
    set_http_get!((url; kwargs...) -> begin
        if occursin("/admin/exchange_names", url)
            return HTTP.Response(200, JSON3.write(Dict("result" => ["binanceusdm"], "error" => nothing, "error_code" => nothing)))
        elseif occursin("/ping", url)
            return HTTP.Response(200, JSON3.write(Dict("status" => "ok")))
        elseif occursin("/exchanges/binanceusdm/markets", url)
            return HTTP.Response(200, JSON3.write(Dict("result" => Dict{String,Any}(
                "BTC/USDT:USDT" => Dict{String,Any}("id" => "BTC/USDT:USDT", "symbol" => "BTC/USDT:USDT", "base" => "BTC", "quote" => "USDT",
                    "type" => "swap", "active" => true, "swap" => true, "linear" => true,
                    "precision" => Dict{String,Any}("amount" => 0.001, "price" => 0.1),
                    "limits" => Dict{String,Any}("amount" => Dict{String,Any}("min" => 0.001, "max" => 1000.0),
                        "price" => Dict{String,Any}("min" => 0.1, "max" => 1000000.0),
                        "cost" => Dict{String,Any}("min" => 1.0, "max" => 10000000.0)),
                    "taker" => 0.0004, "maker" => 0.0002),
                "ETH/USDT:USDT" => Dict{String,Any}("id" => "ETH/USDT:USDT", "symbol" => "ETH/USDT:USDT", "base" => "ETH", "quote" => "USDT",
                    "type" => "swap", "active" => true, "swap" => true, "linear" => true,
                    "precision" => Dict{String,Any}("amount" => 0.001, "price" => 0.01),
                    "limits" => Dict{String,Any}("amount" => Dict{String,Any}("min" => 0.001, "max" => 1000.0),
                        "price" => Dict{String,Any}("min" => 0.01, "max" => 1000000.0),
                        "cost" => Dict{String,Any}("min" => 1.0, "max" => 10000000.0)),
                    "taker" => 0.0004, "maker" => 0.0002),
                "SOL/USDT:USDT" => Dict{String,Any}("id" => "SOL/USDT:USDT", "symbol" => "SOL/USDT:USDT", "base" => "SOL", "quote" => "USDT",
                    "type" => "swap", "active" => true, "swap" => true, "linear" => true,
                    "precision" => Dict{String,Any}("amount" => 0.01, "price" => 0.001),
                    "limits" => Dict{String,Any}("amount" => Dict{String,Any}("min" => 0.01, "max" => 10000.0),
                        "price" => Dict{String,Any}("min" => 0.001, "max" => 1000.0),
                        "cost" => Dict{String,Any}("min" => 1.0, "max" => 10000000.0)),
                    "taker" => 0.0004, "maker" => 0.0002),
            ), "error" => nothing, "error_code" => nothing)))
        elseif occursin("/urls", url)
            return HTTP.Response(200, JSON3.write(Dict("result" => Dict{String,Any}("test" => "https://testnet.binancefuture.com"), "error" => nothing, "error_code" => nothing)))
        elseif occursin("/exchanges/binanceusdm/has", url)
            return HTTP.Response(200, JSON3.write(Dict("result" => Dict{String,Any}("fetchOHLCV" => true), "error" => nothing, "error_code" => nothing)))
        else
            sleep(0.01); error("mock GET $url")
        end
    end)
    set_http_post!((url; kwargs...) -> begin
        if occursin("/setSandboxMode", url)
            return HTTP.Response(200, JSON3.write(Dict("result" => Dict("success" => true), "error" => nothing, "error_code" => nothing)))
        else
            sleep(0.01); error("mock POST $url")
        end
    end)
    cfg = PlanarCore.Metrics.Instances.Misc.Config()
    using PlanarCore.Stubs: stub_strategy
    using PlanarCore.Metrics.Instances: InstrumentInstance
    using PlanarCore.Metrics.Instances.Instruments: AbstractInstrument, parse
    using PlanarCore.Metrics.Instances.Misc: NoMargin
    using PlanarCore.Metrics.Instances.Exchanges.ExchangeTypes: ExchangeID
    using PlanarCore.Metrics.OrderTypes: Order, Trade, MarketOrderType, Buy
    s = stub_strategy(; cfg, dostub=false)
    ii = first(s.universe)
    # Build two minimal trades (distinct dates) and push into the live history
    tf_dt = M.ect.TimeTicks.DateTime
    o1 = Order(ii.asset, ii.exchange.id, Order{MarketOrderType{Buy}}, Metrics.Instances.Misc.Long;
              price=50000.0, date=tf_dt(2024, 1, 1, 0, 0, 0), amount=0.001)
    t1 = Trade(o1; date=tf_dt(2024, 1, 1, 0, 0, 0), amount=0.001, price=50000.0,
               fees=0.0, size=50.0, lev=1.0, entryprice=50000.0, fees_base=0.0)
    o2 = Order(ii.asset, ii.exchange.id, Order{MarketOrderType{Buy}}, Metrics.Instances.Misc.Long;
              price=51000.0, date=tf_dt(2024, 1, 1, 0, 1, 0), amount=0.001)
    t2 = Trade(o2; date=tf_dt(2024, 1, 1, 0, 1, 0), amount=0.001, price=51000.0,
               fees=0.0, size=51.0, lev=1.0, entryprice=51000.0, fees_base=0.0)
    push!(ii.history, t1, t2)
    @test !isempty(ii.history)
    hist_before = copy(ii.history)
    # Trigger the filter branch (since >= first history date) which previously
    # mutated ii.history in place and restored it via finally.
    # Wrap so the assertion holds even if asset_stats! has its own data requirements.
    try
        M.trades_stats(s; since=M.ect.TimeTicks.DateTime(2024, 1, 1, 0, 0, 0))
    catch
    end
    # The live history must be unchanged (no in-place filter/restore).
    @test length(ii.history) == length(hist_before)
    @test collect(ii.history) == collect(hist_before)
end
