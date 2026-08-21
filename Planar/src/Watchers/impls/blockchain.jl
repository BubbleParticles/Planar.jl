# DefiLlama and Glassnode are imported in impls.jl as dfl and gn
# DefiLlama and Glassnode are imported in impls.jl as dfl and gn

# Helper to convert JSON numeric values (may be Int64) to Float64 for Option{Float64} fields
_tofloat(x) = x === nothing ? nothing : Float64(x)

# =============================================================================
# =============================================================================
# DefiLlama TVL Watcher
# =============================================================================

const DflTvl = @NamedTuple begin
    protocol::String
    timestamp::DateTime
    tvl::Option{Float64}
    change_1d::Option{Float64}
    change_7d::Option{Float64}
    change_30d::Option{Float64}
    category::Option{String}
    chain::Option{String}
end

const DefillamaTvlVal = Val{:defillama_tvl}

@doc """ Create a `Watcher` instance that tracks Total Value Locked (TVL) for DeFi protocols from DefiLlama.
"""
function defillama_tvl_watcher(protocols::AbstractVector{String}; 
    interval=Second(3600),
    start=true,
    load=true,
    process=false,
    flush=false,
    threads=false,
    fetch_timeout=Second(5),
    fetch_interval=interval,
    flush_interval=Second(3600),
    buffer_capacity=100,
    view_capacity=1000,
    kwargs...)
    attrs = Dict{Symbol,Any}()
    sort!(protocols)
    attrs[:protocols] = protocols
    attrs[:key] = join(("defillama_tvl", protocols...), "_")
    attrs[:serialized] = true
    attrs[:names] = Symbol.(protocols)
    watcher_type = NamedTuple{tuple(attrs[:names]...),NTuple{length(protocols),DflTvl}}
    wid = string(DefillamaTvlVal.parameters[1], "-", hash(protocols))
    watcher(
        watcher_type,
        wid,
        DefillamaTvlVal();
        start=start,
        load=load,
        process=process,
        flush=flush,
        threads=threads,
        fetch_timeout=fetch_timeout,
        fetch_interval=fetch_interval,
        flush_interval=flush_interval,
        buffer_capacity=buffer_capacity,
        view_capacity=view_capacity,
        attrs,
    )
end
defillama_tvl_watcher(protocols::Vararg{String}; kwargs...) = defillama_tvl_watcher([protocols...]; kwargs...)

function _fetch!(w::Watcher, ::DefillamaTvlVal)
    protocols = w[:protocols]
    names = w[:names]
    
    parsed_data = Dict{Symbol,DflTvl}()
    
    for proto in protocols
        try
            json = dfl.protocol_tvl(proto)
            
            if haskey(json, "tvl") && !isempty(json["tvl"])
                # Get latest TVL entry
                latest = json["tvl"][end]
                tvl_val = _tofloat(get(latest, "totalLiquidityUSD", nothing))
                
                # Calculate changes if historical data available
                change_1d = nothing
                change_7d = nothing
                change_30d = nothing
                if length(json["tvl"]) >= 2
                    prev_1d = json["tvl"][end-1]["totalLiquidityUSD"]
                    if tvl_val !== nothing && prev_1d !== nothing && prev_1d != 0
                        change_1d = (tvl_val - prev_1d) / prev_1d * 100
                    end
                end
                if length(json["tvl"]) >= 8
                    prev_7d = json["tvl"][end-7]["totalLiquidityUSD"]
                    if tvl_val !== nothing && prev_7d !== nothing && prev_7d != 0
                        change_7d = (tvl_val - prev_7d) / prev_7d * 100
                    end
                end
                if length(json["tvl"]) >= 31
                    prev_30d = json["tvl"][end-30]["totalLiquidityUSD"]
                    if tvl_val !== nothing && prev_30d !== nothing && prev_30d != 0
                        change_30d = (tvl_val - prev_30d) / prev_30d * 100
                    end
                end
                
                ts = DateTime(latest["date"])
                parsed_data[Symbol(proto)] = DflTvl((
                    proto,
                    ts,
                    _tofloat(tvl_val),
                    _tofloat(change_1d),
                    _tofloat(change_7d),
                    _tofloat(change_30d),
                    get(json, "category", nothing),
                    get(json, "chain", nothing),
                ))
            end
        catch e
            @error "defillama_tvl: failed to fetch TVL" protocol=proto exception=e
            continue
        end
    end
    
    if isempty(parsed_data)
        @warn "defillama_tvl: no data returned" protocols
        return false
    end
    
    value = NamedTuple{tuple(names...)}(
        [get(parsed_data, name, DflTvl((string(name), DateTime(0), nothing, nothing, nothing, nothing, nothing, nothing))) for name in names]
    )
    
    pushnew!(w, value)
    true
end

function _defillama_tvl_append_buffer(dict, buf, maxlen)
    data = @collect_buffer_data buf Symbol DflTvl
    @append_dict_data dict data maxlen
end

_init!(w::Watcher, ::DefillamaTvlVal) = default_init(w, Dict{Symbol,DataFrame}())
_process!(w::Watcher, ::DefillamaTvlVal) = default_process(w, _defillama_tvl_append_buffer)

# =============================================================================
# DefiLlama Stablecoins Watcher
# =============================================================================

const DflStablecoin = @NamedTuple begin
    stablecoin::String
    timestamp::DateTime
    total_circulating::Option{Float64}
    total_unreleased::Option{Float64}
    total_bridged::Option{Float64}
    circulating_pegged_usd::Option{Float64}
    peg_type::Option{String}
    chain::Option{String}
end

const DefillamaStablecoinsVal = Val{:defillama_stablecoins}

@doc """ Create a `Watcher` instance that tracks stablecoin metrics from DefiLlama.
"""
function defillama_stablecoins_watcher(stablecoins::AbstractVector{String}; 
    interval=Second(3600),
    start=true,
    load=true,
    process=false,
    flush=false,
    threads=false,
    fetch_timeout=Second(5),
    fetch_interval=interval,
    flush_interval=Second(3600),
    buffer_capacity=100,
    view_capacity=1000,
    kwargs...)
    attrs = Dict{Symbol,Any}()
    sort!(stablecoins)
    attrs[:stablecoins] = stablecoins
    attrs[:key] = join(("defillama_stablecoins", stablecoins...), "_")
    attrs[:serialized] = true
    attrs[:names] = Symbol.(stablecoins)
    watcher_type = NamedTuple{tuple(attrs[:names]...),NTuple{length(stablecoins),DflStablecoin}}
    wid = string(DefillamaStablecoinsVal.parameters[1], "-", hash(stablecoins))
    watcher(
        watcher_type,
        wid,
        DefillamaStablecoinsVal();
        start=start,
        load=load,
        process=process,
        flush=flush,
        threads=threads,
        fetch_timeout=fetch_timeout,
        fetch_interval=fetch_interval,
        flush_interval=flush_interval,
        buffer_capacity=buffer_capacity,
        view_capacity=view_capacity,
        attrs,
    )
end
defillama_stablecoins_watcher(stablecoins::Vararg{String}; kwargs...) = defillama_stablecoins_watcher([stablecoins...]; kwargs...)

function _fetch!(w::Watcher, ::DefillamaStablecoinsVal)
    stablecoins = w[:stablecoins]
    names = w[:names]
    
    parsed_data = Dict{Symbol,DflStablecoin}()
    
    for sc in stablecoins
        try
            json = dfl.stablecoin_charts(sc)
            
            if haskey(json, "totalCirculating") && !isempty(json["totalCirculating"])
                latest_circ = json["totalCirculating"][end]
                latest_unrel = json["totalUnreleased"][end]
                latest_bridged = json["totalBridgedToCirculating"][end]
                
                ts = unix2datetime(latest_circ["date"] / 1000)
                parsed_data[Symbol(sc)] = DflStablecoin((
                    sc,
                    ts,
                    _tofloat(latest_circ["totalCirculating"]),
                    _tofloat(latest_unrel["totalUnreleased"]),
                    _tofloat(latest_bridged["totalBridgedToCirculating"]),
                    _tofloat(get(latest_circ, "peggedUSD", nothing)),
                    get(json, "pegType", nothing),
                    get(json, "chain", nothing),
                ))
            end
        catch e
            @error "defillama_stablecoins: failed to fetch data" stablecoin=sc exception=e
            continue
        end
    end
    
    if isempty(parsed_data)
        @warn "defillama_stablecoins: no data returned" stablecoins
        return false
    end
    
    value = NamedTuple{tuple(names...)}(
        [get(parsed_data, name, DflStablecoin((string(name), DateTime(0), nothing, nothing, nothing, nothing, nothing, nothing))) for name in names]
    )
    
    pushnew!(w, value)
    true
end

function _defillama_stablecoins_append_buffer(dict, buf, maxlen)
    data = @collect_buffer_data buf Symbol DflStablecoin
    @append_dict_data dict data maxlen
end

_init!(w::Watcher, ::DefillamaStablecoinsVal) = default_init(w, Dict{Symbol,DataFrame}())
_process!(w::Watcher, ::DefillamaStablecoinsVal) = default_process(w, _defillama_stablecoins_append_buffer)

# =============================================================================
# DefiLlama Supply Ratio Watcher
# =============================================================================

const DflSupplyRatio = @NamedTuple begin
    protocol::String
    timestamp::DateTime
    stablecoin_supply::Option{Float64}
    total_supply::Option{Float64}
    supply_ratio::Option{Float64}
    chain::Option{String}
end

const DefillamaSupplyRatioVal = Val{:defillama_supply_ratio}

@doc """ Create a `Watcher` instance that tracks stablecoin supply ratio for protocols from DefiLlama.
"""
function defillama_supply_ratio_watcher(protocols::AbstractVector{String}; 
    interval=Second(3600),
    start=true,
    load=true,
    process=false,
    flush=false,
    threads=false,
    fetch_timeout=Second(5),
    fetch_interval=interval,
    flush_interval=Second(3600),
    buffer_capacity=100,
    view_capacity=1000,
    kwargs...)
    attrs = Dict{Symbol,Any}()
    sort!(protocols)
    attrs[:protocols] = protocols
    attrs[:key] = join(("defillama_supply_ratio", protocols...), "_")
    attrs[:serialized] = true
    attrs[:names] = Symbol.(protocols)
    watcher_type = NamedTuple{tuple(attrs[:names]...),NTuple{length(protocols),DflSupplyRatio}}
    wid = string(DefillamaSupplyRatioVal.parameters[1], "-", hash(protocols))
    watcher(
        watcher_type,
        wid,
        DefillamaSupplyRatioVal();
        start=start,
        load=load,
        process=process,
        flush=flush,
        threads=threads,
        fetch_timeout=fetch_timeout,
        fetch_interval=fetch_interval,
        flush_interval=flush_interval,
        buffer_capacity=buffer_capacity,
        view_capacity=view_capacity,
        attrs,
    )
end
defillama_supply_ratio_watcher(protocols::Vararg{String}; kwargs...) = defillama_supply_ratio_watcher([protocols...]; kwargs...)

function _fetch!(w::Watcher, ::DefillamaSupplyRatioVal)
    protocols = w[:protocols]
    names = w[:names]
    
    parsed_data = Dict{Symbol,DflSupplyRatio}()
    
    for proto in protocols
        try
            json = dfl.protocol_supply_ratio(proto)
            
            if haskey(json, "stablecoinSupply") && haskey(json, "totalSupply")
                stablecoin_supply = json["stablecoinSupply"]
                total_supply = json["totalSupply"]
                supply_ratio = total_supply !== nothing && total_supply != 0 ? stablecoin_supply / total_supply : nothing
                
                ts = now()
                parsed_data[Symbol(proto)] = DflSupplyRatio((
                    proto,
                    ts,
                    _tofloat(stablecoin_supply),
                    _tofloat(total_supply),
                    _tofloat(supply_ratio),
                    get(json, "chain", nothing),
                ))
            end
        catch e
            @error "defillama_supply_ratio: failed to fetch data" protocol=proto exception=e
            continue
        end
    end
    
    if isempty(parsed_data)
        @warn "defillama_supply_ratio: no data returned" protocols
        return false
    end
    
    value = NamedTuple{tuple(names...)}(
        [get(parsed_data, name, DflSupplyRatio((string(name), DateTime(0), nothing, nothing, nothing, nothing))) for name in names]
    )
    
    pushnew!(w, value)
    true
end

function _defillama_supply_ratio_append_buffer(dict, buf, maxlen)
    data = @collect_buffer_data buf Symbol DflSupplyRatio
    @append_dict_data dict data maxlen
end

_init!(w::Watcher, ::DefillamaSupplyRatioVal) = default_init(w, Dict{Symbol,DataFrame}())
_process!(w::Watcher, ::DefillamaSupplyRatioVal) = default_process(w, _defillama_supply_ratio_append_buffer)

# =============================================================================
# Glassnode Active Addresses Watcher
# =============================================================================

const GnActiveAddresses = @NamedTuple begin
    asset::String
    timestamp::DateTime
    active_addresses::Option{Float64}
    new_addresses::Option{Float64}
    zero_balance_addresses::Option{Float64}
end

const GlassnodeActiveAddressesVal = Val{:glassnode_active_addresses}

@doc """ Create a `Watcher` instance that tracks active addresses metrics from Glassnode.
"""
function glassnode_active_addresses_watcher(assets::AbstractVector{String}; 
    interval=Second(3600),
    start=true,
    load=true,
    process=false,
    flush=false,
    threads=false,
    fetch_timeout=Second(5),
    fetch_interval=interval,
    flush_interval=Second(3600),
    buffer_capacity=100,
    view_capacity=1000,
    kwargs...)
    attrs = Dict{Symbol,Any}()
    sort!(assets)
    attrs[:assets] = assets
    attrs[:key] = join(("glassnode_active_addresses", assets...), "_")
    attrs[:serialized] = true
    attrs[:names] = Symbol.(assets)
    watcher_type = NamedTuple{tuple(attrs[:names]...),NTuple{length(assets),GnActiveAddresses}}
    wid = string(GlassnodeActiveAddressesVal.parameters[1], "-", hash(assets))
    watcher(
        watcher_type,
        wid,
        GlassnodeActiveAddressesVal();
        start=start,
        load=load,
        process=process,
        flush=flush,
        threads=threads,
        fetch_timeout=fetch_timeout,
        fetch_interval=fetch_interval,
        flush_interval=flush_interval,
        buffer_capacity=buffer_capacity,
        view_capacity=view_capacity,
        attrs,
    )
end
glassnode_active_addresses_watcher(assets::Vararg{String}; kwargs...) = glassnode_active_addresses_watcher([assets...]; kwargs...)

function _fetch!(w::Watcher, ::GlassnodeActiveAddressesVal)
    assets = w[:assets]
    names = w[:names]
    
    parsed_data = Dict{Symbol,GnActiveAddresses}()
    
    for asset in assets
        try
            json = gn.active_addresses(asset)
            
            if haskey(json, "v") && !isempty(json["v"])
                latest = json["v"][end]
                parsed_data[Symbol(asset)] = GnActiveAddresses((
                    asset,
                    unix2datetime(latest["t"] / 1000),
                    _tofloat(latest["v"]),
                    _tofloat(get(latest, "newAddresses", nothing)),
                    _tofloat(get(latest, "zeroBalanceAddresses", nothing)),
                ))
            end
        catch e
            @error "glassnode_active_addresses: failed to fetch data" asset=asset exception=e
            continue
        end
    end
    
    if isempty(parsed_data)
        @warn "glassnode_active_addresses: no data returned" assets
        return false
    end
    
    value = NamedTuple{tuple(names...)}(
        [get(parsed_data, name, GnActiveAddresses((string(name), DateTime(0), nothing, nothing, nothing))) for name in names]
    )
    
    pushnew!(w, value)
    true
end

function _glassnode_active_addresses_append_buffer(dict, buf, maxlen)
    data = @collect_buffer_data buf Symbol GnActiveAddresses
    @append_dict_data dict data maxlen
end

_init!(w::Watcher, ::GlassnodeActiveAddressesVal) = default_init(w, Dict{Symbol,DataFrame}())
_process!(w::Watcher, ::GlassnodeActiveAddressesVal) = default_process(w, _glassnode_active_addresses_append_buffer)

# =============================================================================
# Glassnode Holders in Profit Watcher
# =============================================================================

const GnHoldersProfit = @NamedTuple begin
    asset::String
    timestamp::DateTime
    holders_profit_pct::Option{Float64}
    holders_loss_pct::Option{Float64}
    holders_breakeven_pct::Option{Float64}
    supply_in_profit_pct::Option{Float64}
    supply_in_loss_pct::Option{Float64}
end

const GlassnodeHoldersProfitVal = Val{:glassnode_holders_profit}

@doc """ Create a `Watcher` instance that tracks holders in profit metrics from Glassnode.
"""
function glassnode_holders_profit_watcher(assets::AbstractVector{String}; 
    interval=Second(3600),
    start=true,
    load=true,
    process=false,
    flush=false,
    threads=false,
    fetch_timeout=Second(5),
    fetch_interval=interval,
    flush_interval=Second(3600),
    buffer_capacity=100,
    view_capacity=1000,
    kwargs...)
    attrs = Dict{Symbol,Any}()
    sort!(assets)
    attrs[:assets] = assets
    attrs[:key] = join(("glassnode_holders_profit", assets...), "_")
    attrs[:serialized] = true
    attrs[:names] = Symbol.(assets)
    watcher_type = NamedTuple{tuple(attrs[:names]...),NTuple{length(assets),GnHoldersProfit}}
    wid = string(GlassnodeHoldersProfitVal.parameters[1], "-", hash(assets))
    watcher(
        watcher_type,
        wid,
        GlassnodeHoldersProfitVal();
        start=start,
        load=load,
        process=process,
        flush=flush,
        threads=threads,
        fetch_timeout=fetch_timeout,
        fetch_interval=fetch_interval,
        flush_interval=flush_interval,
        buffer_capacity=buffer_capacity,
        view_capacity=view_capacity,
        attrs,
    )
end
glassnode_holders_profit_watcher(assets::Vararg{String}; kwargs...) = glassnode_holders_profit_watcher([assets...]; kwargs...)

function _fetch!(w::Watcher, ::GlassnodeHoldersProfitVal)
    assets = w[:assets]
    names = w[:names]
    
    parsed_data = Dict{Symbol,GnHoldersProfit}()
    
    for asset in assets
        try
            json = gn.holders_profit(asset)
            
            if haskey(json, "v") && !isempty(json["v"])
                latest = json["v"][end]
                parsed_data[Symbol(asset)] = GnHoldersProfit((
                    asset,
                    unix2datetime(latest["t"] / 1000),
                    _tofloat(get(latest, "holdersProfitPercent", nothing)),
                    _tofloat(get(latest, "holdersLossPercent", nothing)),
                    _tofloat(get(latest, "holdersBreakevenPercent", nothing)),
                    _tofloat(get(latest, "supplyInProfitPercent", nothing)),
                    _tofloat(get(latest, "supplyInLossPercent", nothing)),
                ))
            end
        catch e
            @error "glassnode_holders_profit: failed to fetch data" asset=asset exception=e
            continue
        end
    end
    
    if isempty(parsed_data)
        @warn "glassnode_holders_profit: no data returned" assets
        return false
    end
    
    value = NamedTuple{tuple(names...)}(
        [get(parsed_data, name, GnHoldersProfit((string(name), DateTime(0), nothing, nothing, nothing, nothing, nothing))) for name in names]
    )
    
    pushnew!(w, value)
    true
end

function _glassnode_holders_profit_append_buffer(dict, buf, maxlen)
    data = @collect_buffer_data buf Symbol GnHoldersProfit
    @append_dict_data dict data maxlen
end

_init!(w::Watcher, ::GlassnodeHoldersProfitVal) = default_init(w, Dict{Symbol,DataFrame}())
_process!(w::Watcher, ::GlassnodeHoldersProfitVal) = default_process(w, _glassnode_holders_profit_append_buffer)

# =============================================================================
# Glassnode Large Movements Watcher
# =============================================================================

const GnLargeMovements = @NamedTuple begin
    asset::String
    timestamp::DateTime
    tx_count::Option{Int64}
    volume_usd::Option{Float64}
    volume_native::Option{Float64}
    avg_tx_size_usd::Option{Float64}
    avg_tx_size_native::Option{Float64}
end

const GlassnodeLargeMovementsVal = Val{:glassnode_large_movements}

@doc """ Create a `Watcher` instance that tracks large transaction movements from Glassnode.
"""
function glassnode_large_movements_watcher(assets::AbstractVector{String}; 
    interval=Second(3600),
    start=true,
    load=true,
    process=false,
    flush=false,
    threads=false,
    fetch_timeout=Second(5),
    fetch_interval=interval,
    flush_interval=Second(3600),
    buffer_capacity=100,
    view_capacity=1000,
    kwargs...)
    attrs = Dict{Symbol,Any}()
    sort!(assets)
    attrs[:assets] = assets
    attrs[:key] = join(("glassnode_large_movements", assets...), "_")
    attrs[:serialized] = true
    attrs[:names] = Symbol.(assets)
    watcher_type = NamedTuple{tuple(attrs[:names]...),NTuple{length(assets),GnLargeMovements}}
    wid = string(GlassnodeLargeMovementsVal.parameters[1], "-", hash(assets))
    watcher(
        watcher_type,
        wid,
        GlassnodeLargeMovementsVal();
        start=start,
        load=load,
        process=process,
        flush=flush,
        threads=threads,
        fetch_timeout=fetch_timeout,
        fetch_interval=fetch_interval,
        flush_interval=flush_interval,
        buffer_capacity=buffer_capacity,
        view_capacity=view_capacity,
        attrs,
    )
end
glassnode_large_movements_watcher(assets::Vararg{String}; kwargs...) = glassnode_large_movements_watcher([assets...]; kwargs...)

function _fetch!(w::Watcher, ::GlassnodeLargeMovementsVal)
    assets = w[:assets]
    names = w[:names]
    
    parsed_data = Dict{Symbol,GnLargeMovements}()
    
    for asset in assets
        try
            json = gn.large_movements(asset)
            
            if haskey(json, "v") && !isempty(json["v"])
                latest = json["v"][end]
                parsed_data[Symbol(asset)] = GnLargeMovements((
                    asset,
                    unix2datetime(latest["t"] / 1000),
                    get(latest, "txCount", nothing),
                    _tofloat(get(latest, "volumeUSD", nothing)),
                    _tofloat(get(latest, "volumeNative", nothing)),
                    _tofloat(get(latest, "avgTxSizeUSD", nothing)),
                    _tofloat(get(latest, "avgTxSizeNative", nothing)),
                ))
            end
        catch e
            @error "glassnode_large_movements: failed to fetch data" asset=asset exception=e
            continue
        end
    end
    
    if isempty(parsed_data)
        @warn "glassnode_large_movements: no data returned" assets
        return false
    end
    
    value = NamedTuple{tuple(names...)}(
        [get(parsed_data, name, GnLargeMovements((string(name), DateTime(0), nothing, nothing, nothing, nothing, nothing))) for name in names]
    )
    
    pushnew!(w, value)
    true
end

function _glassnode_large_movements_append_buffer(dict, buf, maxlen)
    data = @collect_buffer_data buf Symbol GnLargeMovements
    @append_dict_data dict data maxlen
end

_init!(w::Watcher, ::GlassnodeLargeMovementsVal) = default_init(w, Dict{Symbol,DataFrame}())
_process!(w::Watcher, ::GlassnodeLargeMovementsVal) = default_process(w, _glassnode_large_movements_append_buffer)


