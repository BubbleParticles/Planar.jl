using TOML
using Pkg
include("../resolve.jl")

function tag_repo(; major=nothing, minor=nothing, patch=nothing)
    # Check for unstaged changes
    status = read(`git status --porcelain`, String)
    if !isempty(strip(status))
        error(
            "Working directory is not clean. Please commit or stash changes before tagging.\nUnstaged changes:\n$status",
        )
    end

    Pkg.activate("Planar")
    p = Pkg.project()
    v = p.version
    if isnothing(major)
        major = v.major
        patch = if isnothing(minor)
            minor = v.minor
            @something patch v.patch + 1
        else
            0
        end
    elseif isnothing(minor)
        minor = 0
        patch = 0
    else
    end
    toml = TOML.parsefile(p.path)
    v_string = string(VersionNumber(major, minor, patch))
    toml["version"] = v_string
    open(p.path, "w") do f
        TOML.print(f, toml)
    end
    # Update all projects including strategies
    recurse_projects(
        _update_project,
        ".";
        io=stdout,
        doupdate=false,
        inst=false,
        precomp=false,
        exclude=("test", "docs", "deps", ".conda", ".CondaPkg", ".git"),
        include=("PlanarDev/test",),
    )
    Pkg.activate("Planar")
    run(`git add -u`)
    run(`git commit -m "v$v_string"`)
    run(`git tag v$v_string`)
end
