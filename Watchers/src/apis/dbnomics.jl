module DBNomics
    using Dates
    using ....Scrapers.DBNomicsData: dbnomicsdownload
    using ..Watchers

    function watcher(
        ids::Vector{String};
        fetch_interval=Second(3600), # 1 hour
        kwargs...
    )
        Watchers.watcher(
            Vector{String},
            "dbnomics",
            Val(:DBNomics);
            fetch_interval=fetch_interval,
            attrs=Dict{Symbol,Any}(:ids => ids),
            kwargs...
        )
    end

    function Watchers._fetch!(w::Watchers.Watcher, ::Val{:DBNomics})
        ids = w.attrs[:ids]
        try
            dbnomicsdownload(ids)
            return true
        catch e
            Watchers.logerror(w, e)
            return false
        end
    end

    Watchers._init!(w::Watchers.Watcher, ::Val{:DBNomics}) = Watchers.default_init(w)
    Watchers._load!(w::Watchers.Watcher, ::Val{:DBNomics}) = Watchers.default_loader(w)
    Watchers._process!(w::Watchers.Watcher, ::Val{:DBNomics}) = Watchers.default_process(w)
end
