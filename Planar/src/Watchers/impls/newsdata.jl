const NewsDataVal = Val{:newsdata}

const NewsArticle = @NamedTuple begin
    title::String
    description::String
    content::String
    url::String
    image_url::String
    source_id::String
    source_name::String
    source_url::String
    category::Vector{String}
    language::String
    country::String
    published_at::DateTime
end

@doc """ Create a `Watcher` instance that tracks news articles from NewsData.io.
"""
function newsdata_watcher(;
    apikey::String,
    q=nothing,
    category=nothing,
    country=nothing,
    language=nothing,
    interval=Second(3600),  # 1 hour default
    start=true,
    load=true,
    process=false,
    flush=false,
    threads=false,
    fetch_timeout=Second(5),
    fetch_interval=interval,
    flush_interval=Second(3600),
    buffer_capacity=1000,
    view_capacity=5000,
    kwargs...
)
    attrs = Dict{Symbol,Any}()
    attrs[:apikey] = apikey
    attrs[:q] = q
    attrs[:category] = category
    attrs[:country] = country
    attrs[:language] = language
    attrs[:key] = "newsdata_watcher"
    attrs[:serialized] = true
    attrs[:names] = Symbol[]

    watcher_type = NewsArticle
    wid = string(NewsDataVal.parameters[1], "-", hash(apikey))
    watcher(
        watcher_type,
        wid,
        NewsDataVal();
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
        kwargs...
    )
end

function _fetch!(w::Watcher, ::NewsDataVal)
    apikey = w[:apikey]
    q = get(w.attrs, :q, nothing)
    category = get(w.attrs, :category, nothing)
    country = get(w.attrs, :country, nothing)
    language = get(w.attrs, :language, nothing)

    json = nd.latest(; apikey, q, category, country, language)
    articles = nd.parse_articles(json)

    if length(articles) > 0
        # Push all new articles to the buffer
        for article in articles
            pushnew!(w, article)
        end
        true
    else
        false
    end
end

function _newsdata_append_buffer(dict, buf, maxlen)
    data = @collect_buffer_data buf String NewsArticle
    @append_dict_data dict data maxlen
end

_init!(w::Watcher, ::NewsDataVal) = default_init(w, Dict{String,DataFrame}())
_process!(w::Watcher, ::NewsDataVal) = default_process(w, _newsdata_append_buffer)