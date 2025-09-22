module DBNomicsData

using DBnomics
using ..Data.DataFrames
using ..Pbar
using ..Data: Cache as ca, zi, save_ohlcv, load_ohlcv
using ..TimeTicks
using ..Lang
using ..Scrapers: selectsyms, timeframe!, workers!, WORKERS, TF, SEM, HTTP_PARAMS, mergechunks, dofetchfiles, _tempdir, @acquire, @fromassets
using ..DocStringExtensions

const NAME = "DBNomics"

# Helper: Convert DBnomics DataFrame to standard OHLCV format
function to_ohlcv_dbnomics(df)
    # Try to infer columns, fallback to missing if not found
    ts_col = hasproperty(df, :period) ? :period : (hasproperty(df, :date) ? :date : :timestamp)
    open_col = hasproperty(df, :open) ? :open : (hasproperty(df, :Open) ? :Open : nothing)
    high_col = hasproperty(df, :high) ? :high : (hasproperty(df, :High) ? :High : nothing)
    low_col  = hasproperty(df, :low)  ? :low  : (hasproperty(df, :Low)  ? :Low  : nothing)
    close_col= hasproperty(df, :close) ? :close : (hasproperty(df, :Close) ? :Close : nothing)
    vol_col  = hasproperty(df, :volume) ? :volume : (hasproperty(df, :Volume) ? :Volume : nothing)

    # Fallback: if only one price column, use it for all OHLC
    if isnothing(open_col) && hasproperty(df, :value)
        open_col = high_col = low_col = close_col = :value
    end

    # Parse timestamp
    ts = DateTime.(df[!, ts_col])
    open = open_col === nothing ? df[!, close_col] : df[!, open_col]
    high = high_col === nothing ? df[!, close_col] : df[!, high_col]
    low  = low_col  === nothing ? df[!, close_col] : df[!, low_col]
    close= close_col === nothing ? df[!, open_col] : df[!, close_col]
    volume = vol_col === nothing ? fill(0.0, nrow(df)) : df[!, vol_col]

    DataFrame(timestamp=ts, open=open, high=high, low=low, close=close, volume=volume)
end

"""
Fetches data from DBNomics for a given series id and saves it as a DataFrame.
"""
function dbnomicsdownload(ids::AbstractVector{String}; reset=false, kwargs...)
    out = Dict{String,DataFrame}()
    @withpbar! ids desc = "DBNomics Series" begin
        fetchandsave(id) = @except begin
            df = DBnomics.rdb(ids=id)
            if !isempty(df)
                ohlcv = to_ohlcv_dbnomics(df)
                out[id] = ohlcv
                ca.save_cache("$(NAME)/$(id)", ohlcv)
            end
            @pbupdate!
        end "dbnomics scraper: failed to fetch $id" ()
        @acquire SEM asyncmap(fetchandsave, ids; ntasks=WORKERS[])
    end
    nothing
end

"""
Loads previously downloaded DBNomics data for given series ids.
"""
function dbnomicsload(ids::AbstractVector{String}; zi=zi[], kwargs...)
    dfs = [ca.load_cache("$(NAME)/$(id)", raise=false) for id in ids]
    dfs = filter(!isnothing, dfs)
    isempty(dfs) && return nothing
    vcat(dfs...)
end

@fromassets dbnomicsdownload
@fromassets dbnomicsload

export dbnomicsdownload, dbnomicsload

end # module DBNomicsData
