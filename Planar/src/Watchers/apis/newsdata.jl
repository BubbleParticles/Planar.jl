module NewsData
using PlanarCore.Ccxt: HTTP, JSON3
using PlanarCore.Ccxt.URIs
using ..Watchers
using PlanarCore.Lang: Option
using PlanarCore.Misc
using PlanarCore.TimeTicks
using PlanarCore.TimeTicks: timestamp
using ..Watchers: jsontodict

const API_URL = "https://newsdata.io/api/1"
const API_HEADERS = ["Accept-Encoding" => "deflate,gzip", "Accept" => "application/json"]
const ApiPaths = (;
    latest="/latest",
    archive="/archive",
    sources="/sources",
)

const last_query = Ref(DateTime(0))
const RATE_LIMIT = Ref(Millisecond(2500))
const STATUS = Ref{Int}(0)
const RETRY_COUNT = Ref(0)
const MAX_RETRIES = 10
const BACKOFF_BASE = 1000

# Injectable HTTP function for testing
const _http_get = Ref{Function}(HTTP.get)

@doc """
Set the HTTP GET function for testing/mocking.
"""
function set_http_get!(f::Function)
    _http_get[] = f
end

@doc "Allows only 1 query every $(RATE_LIMIT[]) seconds."
ratelimit() = sleep(max(Second(0), (last_query[] - now()) + RATE_LIMIT[]))

function get(path, query=nothing)
    ratelimit()
    resp = try
        _http_get[](absuri(path, API_URL); query, headers=API_HEADERS)
    catch e
        e
    end
    last_query[] = now()
    if hasproperty(resp, :status)
        STATUS[] = resp.status
        if resp.status == 429
            RETRY_COUNT[] += 1
            if RETRY_COUNT[] <= MAX_RETRIES
                wait_time = RATE_LIMIT[] + Millisecond(BACKOFF_BASE * RETRY_COUNT[])
                @warn "newsdata: 429 retrying" path retry=RETRY_COUNT[] wait_time
                sleep(wait_time)
                return get(path, query)
            else
                @error "newsdata: max retries exceeded" path retries=RETRY_COUNT[]
                RETRY_COUNT[] = 0
            end
        elseif resp.status == 401 || resp.status == 403
            @warn "newsdata: auth error" path status=resp.status
        end
        @assert resp.status == 200 "newsdata: $path failed with status $(resp.status)"
        RETRY_COUNT[] = 0
        json = JSON3.read(resp.body)
        return json
    else
        throw(resp)
    end
end

function absuri(path, base)
    URI(base * path)
end

"""
Fetches latest news articles from NewsData.io.

# Arguments
- `apikey::String`: Your NewsData.io API key.
- `q=nothing`: Search query.
- `category=nothing`: News category (e.g., "technology", "business", "sports").
- `country=nothing`: Country code (e.g., "us", "gb").
- `language=nothing`: Language code (e.g., "en", "es").
- `page=nothing`: Page number for pagination.

# Returns
JSON response from the API.
"""
function latest(; apikey::String, q=nothing, category=nothing, country=nothing, language=nothing, page=nothing)
    query = Dict{String,Any}("apikey" => apikey)
    q !== nothing && (query["q"] = q)
    category !== nothing && (query["category"] = category)
    country !== nothing && (query["country"] = country)
    language !== nothing && (query["language"] = language)
    page !== nothing && (query["page"] = page)
    get(ApiPaths.latest, query)
end

"""
Parses the articles from NewsData.io JSON response into a vector of NamedTuples.

Each article has fields: title, description, content, url, image_url, source_id, source_name, source_url, category, language, country, published_at (DateTime).
"""
function parse_articles(json)
    results = Base.get(json, "results", Any[])
    articles = Vector{NamedTuple}(undef, length(results))
    for (i, article) in enumerate(results)
        articles[i] = (
            title = Base.get(article, "title", ""),
            description = Base.get(article, "description", ""),
            content = Base.get(article, "content", ""),
            url = Base.get(article, "link", ""),
            image_url = Base.get(article, "image_url", ""),
            source_id = Base.get(article, "source_id", ""),
            source_name = Base.get(article, "source_name", ""),
            source_url = Base.get(article, "source_url", ""),
            category = Base.get(article, "category", String[]),
            language = Base.get(article, "language", ""),
            country = Base.get(article, "country", ""),
            published_at = parse_datetime(Base.get(article, "pubDate", ""))
        )
    end
    return articles
end

"""
Parse a datetime string from NewsData.io (format: "YYYY-MM-DD HH:MM:SS").
"""
function parse_datetime(str::String)
    if isempty(str)
        return DateTime(0)
    end
    try
        return DateTime(str, "yyyy-mm-dd HH:MM:SS")
    catch
        try
            return DateTime(str, "yyyy-mm-dd HH:MM:SS.s")
        catch
            try
                return DateTime(str, "yyyy-mm-ddTHH:MM:SS")
            catch
                return DateTime(0)
            end
        end
    end
end

export latest, parse_articles, ratelimit, get, set_http_get!

end # module NewsData