#!/usr/bin/env julia
# scripts/register.jl — build/update the custom registry for the Planar.jl monorepo.
#
# The Planar.jl monorepo hosts nine Julia packages (Planar, PlanarCore, …). They are
# not part of the General registry, so to `Pkg.add("Planar")` users need a custom
# registry that points at the monorepo. This script generates (or updates) that
# registry from the git tree of this repository.
#
# How it works
# ------------
# Each registered version maps to the git tree SHA of the package subdirectory at a
# git ref (`git rev-parse <ref>:<subdir>`). GitHub serves tarballs for arbitrary
# tree SHAs, so `https://github.com/<owner>/<repo>/archive/<tree-sha>.tar.gz`
# downloads exactly the package subtree — the same mechanism the General registry
# uses for monorepos (`subdir` entries like `AppEnv`, `ACEradials`).
#
# Usage
# -----
#   julia scripts/register.jl                          # publish current HEAD
#   julia scripts/register.jl --ref v1.7.2             # publish a tagged commit
#   julia scripts/register.jl --registry /tmp/reg      # output elsewhere
#   julia scripts/register.jl --repo-url https://github.com/<you>/Planar.jl.git
#   julia scripts/register.jl --commit                 # also git-commit the registry
#
# See PACKAGING.md at the repository root for the full release/registration flow.

using TOML
using UUIDs
using Pkg: Pkg

const ROOT = dirname(@__DIR__)
const REGISTRY_NAME = "PlanarRegistry"
const REGISTRY_UUID = UUID("55da71c0-fafb-41ae-8249-1bb3b7066f5d")
const DEFAULT_REPO_URL = "https://github.com/BubbleParticles/Planar.jl.git"
const DEFAULT_REGISTRY_REPO = "https://github.com/BubbleParticles/PlanarRegistry.git"

# All packages hosted in the monorepo, in registration order.
const PACKAGES = [
    "PlanarCore",
    "StrategyStats",
    "Planar",
    "FeatureSelection",
    "DownloadTool",
    "Python",
    "StrategyTools",
    "PlanarOptim",
    "PlanarDev",
]

@doc "Run `git` and return the trimmed stdout."
function git(args::AbstractVector{<:AbstractString}; cwd=ROOT)
    out = read(setenv(`git $args`; dir=cwd), String)
    return strip(out)
end

@doc "Git tree SHA of `subdir` at `ref`."
function tree_sha(ref::String, subdir::String)
    sha = git(["rev-parse", "$ref:$subdir"])
    isempty(sha) && error("cannot resolve tree for $ref:$subdir")
    return sha
end

@doc "Read a TOML file as a plain Dict (empty when missing)."
function read_toml(path::String)
    isfile(path) || return Dict{String,Any}()
    return TOML.parsefile(path)
end

@doc "Merge `new` into `old` (nested dicts merged recursively, scalars overwritten)."
function merge_toml!(old::Dict{String,Any}, new::Dict{String,Any})
    for (k, v) in new
        if v isa AbstractDict && get(old, k, nothing) isa AbstractDict
            merge_toml!(old[k], v)
        else
            old[k] = v
        end
    end
    return old
end

@doc "Write `data` to `path`, creating parent directories."
function write_toml!(path::String, data::AbstractDict)
    mkpath(dirname(path))
    open(path, "w") do io
        TOML.print(io, data; sorted=true)
    end
end

@doc """ Version-range key used in `Deps.toml`/`Compat.toml`.

Versions of a package are grouped by major version; all 1.x versions of `Planar`
share one dependency set unless a future release changes it.
"""
function range_key(version::VersionNumber)
    return string(version.major)
end

@doc "Update the registry entry for one package at `ref`."
function register_package!(
    reg::String, ref::String, repo_url::String, pkgdir::String
)
    project = read_toml(joinpath(ROOT, pkgdir, "Project.toml"))
    name = project["name"]
    uuid = UUID(project["uuid"])
    version = VersionNumber(project["version"])
    deps = get(project, "deps", Dict{String,Any}())
    compat = get(project, "compat", Dict{String,Any}())

    @info "registering" name version ref subdir=pkgdir

    sha = tree_sha(ref, pkgdir)
    dir = joinpath(reg, "Packages", uppercasefirst(name[1:1]), name)
    mkpath(dir)

    # Package.toml — repo URL + subdir for monorepo tarballs
    write_toml!(joinpath(dir, "Package.toml"), Dict(
        "name" => name,
        "uuid" => string(uuid),
        "repo" => repo_url,
        "subdir" => pkgdir,
    ))

    # Versions.toml — merge so re-runs add new versions without clobbering old ones
    versions = read_toml(joinpath(dir, "Versions.toml"))
    versions[string(version)] = Dict("git-tree-sha1" => sha)
    write_toml!(joinpath(dir, "Versions.toml"), versions)

    # Deps.toml — one key per version range, mapping dep name -> uuid
    deps_file = joinpath(dir, "Deps.toml")
    deps_toml = isfile(deps_file) ? read_toml(deps_file) : Dict{String,Any}()
    deps_toml[range_key(version)] = Dict{String,Any}(name => string(uuid) for (name, uuid) in deps)
    write_toml!(deps_file, deps_toml)

    # Compat.toml — compat constraints per version range
    compat_file = joinpath(dir, "Compat.toml")
    compat_toml = isfile(compat_file) ? read_toml(compat_file) : Dict{String,Any}()
    compat_toml[range_key(version)] = Dict{String,Any}(string(k) => string(v) for (k, v) in compat)
    write_toml!(compat_file, compat_toml)

    return (name, uuid)
end

function main(args::Vector{String}=ARGS)
    ref = "HEAD"
    reg = joinpath(ROOT, REGISTRY_NAME)
    repo_url = DEFAULT_REPO_URL
    registry_repo = DEFAULT_REGISTRY_REPO
    do_commit = false

    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--ref"
            ref = args[i+1]; i += 1
        elseif a == "--registry"
            reg = args[i+1]; i += 1
        elseif a == "--repo-url"
            repo_url = args[i+1]; i += 1
        elseif a == "--registry-repo"
            registry_repo = args[i+1]; i += 1
        elseif a == "--commit"
            do_commit = true
        else
            error("unknown argument: $a\nusage: register.jl [--ref <ref>] [--registry <path>] [--repo-url <url>] [--registry-repo <url>] [--commit]")
        end
        i += 1
    end

    # Sanity check: the ref must resolve for every package subdir.
    for pkg in PACKAGES
        isdir(joinpath(ROOT, pkg)) || error("package dir missing: $pkg")
    end

    reg = abspath(reg)
    mkpath(reg)

    packages = Dict{String,Any}()
    for pkg in PACKAGES
        name, uuid = register_package!(reg, ref, repo_url, pkg)
        packages[string(uuid)] = Dict{String,Any}(
            "name" => name,
            "path" => joinpath("Packages", uppercasefirst(name[1:1]), name),
        )
    end

    write_toml!(joinpath(reg, "Registry.toml"), Dict(
        "name" => REGISTRY_NAME,
        "uuid" => string(REGISTRY_UUID),
        "repo" => registry_repo,
        "description" => "Registry for the Planar.jl ecosystem (packages of the BubbleParticles/Planar.jl monorepo)",
        "packages" => packages,
    ))

    if do_commit
        isdir(joinpath(reg, ".git")) || run(`git -C $reg init -q`)
        run(`git -C $reg add -A`)
        run(`git -C $reg commit -q -m "update $REGISTRY_NAME from Planar.jl @ $ref"`)
    end

    @info "registry written" registry=reg ref packages=length(packages)
    println()
    println("To publish: cd $reg && git remote add origin $registry_repo && git push -u origin HEAD")
    println("Then users can install with:")
    println("  julia -e 'using Pkg; Pkg.Registry.add(RegistrySpec(url=\"$registry_repo\"))'")
    println("  julia -e 'using Pkg; Pkg.add(\"Planar\")'")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
