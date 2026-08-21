const DbnSeries = @NamedTuple begin
    series_id::String
    timestamp::DateTime
    value::Option{Float64}
    frequency::Option{String}
    unit::Option{String}
    last_updated::Option{DateTime}
end
const DbnomicsVal = Val{:dbnomics}

@doc """ Create a `Watcher` instance that tracks economic series from DBNomics.
"""
function dbnomics_watcher(series_ids::AbstractVector{String}; 
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
    sort!(series_ids)
    attrs[:series_ids] = series_ids
    attrs[:key] = join(("dbnomics", series_ids...), "_")
    attrs[:serialized] = true
    attrs[:names] = Symbol.(replace.(series_ids, "/" => "_"))
    watcher_type = NamedTuple{tuple(attrs[:names]...),NTuple{length(series_ids),DbnSeries}}
    wid = string(DbnomicsVal.parameters[1], "-", hash(series_ids))
    watcher(
        watcher_type,
        wid,
        DbnomicsVal();
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
dbnomics_watcher(series_ids::Vararg; kwargs...) = dbnomics_watcher([series_ids...]; kwargs...)

using ..DBNomics: series_values, parse_series_values

function _fetch!(w::Watcher, ::DbnomicsVal)
    ids = w[:series_ids]
    names = w[:names]
    json = try
        series_values(ids)
    catch e
        @error "dbnomics: failed to fetch series values" exception = e
        rethrow(e)
    end
    parsed = parse_series_values(json)
    if !isempty(parsed)
        # Build the NamedTuple for each series
        values = DbnSeries[]
        for (i, id) in enumerate(ids)
            series_data = get(parsed, id, DbnSeries[])
            if !isempty(series_data)
                # Use the latest observation
                latest = series_data[end]
                push!(values, DbnSeries((
                    id,
                    latest.timestamp,
                    latest.value,
                    nothing,
                    nothing,
                    nothing,
                )))
            else
                push!(values, DbnSeries((
                    id,
                    DateTime(0),
                    nothing,
                    nothing,
                    nothing,
                    nothing,
                )))
            end
        end
        value = NamedTuple{tuple(names...)}(tuple(values...))
        pushnew!(w, value)
        true
    else
        false
    end
end

function _dbnomics_append_buffer(dict, buf, maxlen)
    data = @collect_buffer_data buf Symbol DbnSeries
    @append_dict_data dict data maxlen
end
_init!(w::Watcher, ::DbnomicsVal) = default_init(w, Dict{Symbol,DataFrame}())
_process!(w::Watcher, ::DbnomicsVal) = default_process(w, _dbnomics_append_buffer)