@doc "Control the bot remotely."
module Remote

    include("module.jl")
    if occursin("Remote", get(ENV, "JULIA_PRECOMP", ""))
        include("precompile.jl")
    end

end
