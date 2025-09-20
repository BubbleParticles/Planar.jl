module Frankfurter
using HTTP
using URIs
using JSON3
using ..Watchers
using ..Lang: Option, @kget!
using ..Misc
using ..Misc.TimeToLive
using ..TimeTicks
using ..TimeTicks: timestamp
using ..Watchers: jsontodict

const API_URL = "https://api.frankfurter.app"
const API_HEADERS = ["Accept-Encoding" => "deflate,gzip", "Accept" => "application/json"]

const ApiPaths = (;
    latest="/latest",
    historical="/",
    currencies="/currencies",
    time_series="/",
)

const DEFAULT_BASE = "EUR"
const DEFAULT_SYMBOLS = ["USD", "GBP", "JPY", "CHF", "CAD", "AUD"]

const last_query = Ref(DateTime(0))
const RATE_LIMIT = Ref(Millisecond(1000))  # 1 second between requests
const STATUS = Ref{Int}(0)

@doc "Allows only 1 query every $(RATE_LIMIT[]) seconds."
ratelimit() = sleep(max(Second(0), (last_query[] - now()) + RATE_LIMIT[]))

function get(path, query=nothing)
    ratelimit()
    resp = try
        HTTP.get(absuri(path, API_URL); query, headers=API_HEADERS)
    catch e
        e
    end
    last_query[] = now()
    if hasproperty(resp, :status)
        STATUS[] = resp.status
        @assert resp.status == 200 "Frankfurter API error: $(resp.status)"
        json = JSON3.read(resp.body)
        return json
    else
        throw(resp)
    end
end

@doc "Get latest exchange rates for specified base currency and symbols."
function latest(; base=DEFAULT_BASE, symbols=DEFAULT_SYMBOLS, amount=nothing, from=nothing, to=nothing)
    query = Dict{String,Any}()
    
    # Support both parameter styles: base/symbols and from/to
    if !isnothing(from) && !isnothing(to)
        query["from"] = from
        query["to"] = isa(to, Vector) ? join(to, ",") : to
    else
        if base != DEFAULT_BASE
            query["base"] = base
        end
        if symbols != DEFAULT_SYMBOLS
            query["symbols"] = join(symbols, ",")
        end
    end
    
    if !isnothing(amount)
        query["amount"] = amount
    end
    json = get(ApiPaths.latest, isempty(query) ? nothing : query)
    return jsontodict(json)
end

@doc "Get exchange rates for a specific date."
function historical(date::DateTime; base=DEFAULT_BASE, symbols=DEFAULT_SYMBOLS, amount=nothing, from=nothing, to=nothing)
    date_str = Dates.format(date, dateformat"yyyy-mm-dd")
    query = Dict{String,Any}()
    
    # Support both parameter styles: base/symbols and from/to
    if !isnothing(from) && !isnothing(to)
        query["from"] = from
        query["to"] = isa(to, Vector) ? join(to, ",") : to
    else
        if base != DEFAULT_BASE
            query["base"] = base
        end
        if symbols != DEFAULT_SYMBOLS
            query["symbols"] = join(symbols, ",")
        end
    end
    
    if !isnothing(amount)
        query["amount"] = amount
    end
    path = ApiPaths.historical * date_str
    json = get(path, isempty(query) ? nothing : query)
    return jsontodict(json)
end

@doc "Get exchange rates for a date range."
function timeseries(from_date::DateTime, to_date::DateTime; base=DEFAULT_BASE, symbols=DEFAULT_SYMBOLS, amount=nothing, from=nothing, to=nothing)
    from_str = Dates.format(from_date, dateformat"yyyy-mm-dd")
    to_str = Dates.format(to_date, dateformat"yyyy-mm-dd")
    
    # Frankfurter API uses date range format: YYYY-MM-DD..YYYY-MM-DD
    path = ApiPaths.time_series * from_str * ".." * to_str
    
    query = Dict{String,Any}()
    
    # Support both parameter styles: base/symbols and from/to
    if !isnothing(from) && !isnothing(to)
        query["from"] = from
        query["to"] = isa(to, Vector) ? join(to, ",") : to
    else
        if base != DEFAULT_BASE
            query["base"] = base
        end
        if symbols != DEFAULT_SYMBOLS
            query["symbols"] = join(symbols, ",")
        end
    end
    
    if !isnothing(amount)
        query["amount"] = amount
    end
    
    json = get(path, isempty(query) ? nothing : query)
    return jsontodict(json)
end

const currencies_cache = safettl(Nothing, Set{String}, Hour(24))

@doc "Get list of supported currencies."
function currencies()
    @kget! currencies_cache nothing begin
        json = get(ApiPaths.currencies)
        currency_set = Set{String}()
        for (code, name) in json
            push!(currency_set, string(code))
        end
        currency_set
    end
end

@doc "Check if a currency code is supported."
function is_supported_currency(code::String)
    code in currencies()
end

@doc "Get exchange rate between two currencies on a specific date."
function rate(from::String, to::String, date::DateTime=now())
    @assert is_supported_currency(from) "$from is not a supported currency"
    @assert is_supported_currency(to) "$to is not a supported currency"
    
    data = historical(date; base=from, symbols=[to])
    rates = data["rates"]
    return Float64(rates[to])
end

@doc "Get exchange rate between two currencies for latest available data."
function latest_rate(from::String, to::String)
    @assert is_supported_currency(from) "$from is not a supported currency"
    @assert is_supported_currency(to) "$to is not a supported currency"
    
    data = latest(; base=from, symbols=[to])
    rates = data["rates"]
    return Float64(rates[to])
end

@doc "Convert amount from one currency to another on a specific date."
function convert_amount(amount::Real, from::String, to::String, date::DateTime=now())
    rate_val = rate(from, to, date)
    return Float64(amount) * rate_val
end

@doc "Convert amount from one currency to another using latest rates."
function convert_amount_latest(amount::Real, from::String, to::String)
    rate_val = latest_rate(from, to)
    return Float64(amount) * rate_val
end

@doc "Convert amount using the API's built-in amount parameter (more efficient)."
function convert_amount_api(amount::Real, from::String, to::String; date=nothing)
    @assert is_supported_currency(from) "$from is not a supported currency"
    @assert is_supported_currency(to) "$to is not a supported currency"
    
    if isnothing(date)
        data = latest(; base=from, symbols=[to], amount=amount)
    else
        data = historical(date; base=from, symbols=[to], amount=amount)
    end
    
    return Float64(data["rates"][to])
end

@doc "Get historical exchange rates as time series data."
function historical_rates(from::String, to::String, start_date::DateTime, end_date::DateTime)
    @assert is_supported_currency(from) "$from is not a supported currency"
    @assert is_supported_currency(to) "$to is not a supported currency"
    
    data = timeseries(start_date, end_date; base=from, symbols=[to])
    rates = data["rates"]
    
    dates = DateTime[]
    values = Float64[]
    
    for (date_key, rate_data) in rates
        date_str = string(date_key)  # Convert Symbol to String if needed
        date = parse(DateTime, date_str)
        push!(dates, date)
        push!(values, Float64(rate_data[to]))
    end
    
    return (; dates, values)
end

@doc "Get the base currency used by Frankfurter API."
function get_base_currency()
    return DEFAULT_BASE
end

@doc "Get default supported symbols."
function get_default_symbols()
    return copy(DEFAULT_SYMBOLS)
end

export latest, historical, timeseries, currencies, is_supported_currency
export rate, latest_rate, convert_amount, convert_amount_latest, convert_amount_api, historical_rates
export get_base_currency, get_default_symbols

end
