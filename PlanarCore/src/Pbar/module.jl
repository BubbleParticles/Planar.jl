using Term.Progress
using Term: Term
using ..TimeTicks: now, Millisecond, Second, DateTime, Lang
using ..Lang: toggle!, @preset, @precomp
using ..Lang.DocStringExtensions

@doc "Stores the timestamp of the last render in the progress bar."
const last_render = Ref(DateTime(0))
@doc "Stores the minimum time difference required between two render updates."
const min_delta = Ref(Millisecond(0))
@doc "Holds a reference to the current progress bar or `nothing` if no progress bar is active."
const pbar = Ref{Union{Nothing,ProgressBar}}(nothing)
@doc "Holds a lock to avoid flickering when updating the progress bar."
const pbar_lock = ReentrantLock()
@doc "Stores whether the progress bar has been initialized."
const pbar_initialized = Ref(false)

@doc """
Represents a job that is currently running in the progress bar.
$(FIELDS)
The `RunningJob` struct holds a `ProgressJob`, a counter, and a timestamp of when it was last updated.
The `job` field is of type `ProgressJob` which represents the job that is currently running.
The `counter` field is an integer that defaults to 1 and is used to keep track of the progress of the job.
The `updated_at` field is a `DateTime` object that stores the timestamp of when the job was last updated.
"""
@kwdef mutable struct RunningJob
    job::ProgressJob
    counter::Int = 1
    updated_at::DateTime = now()
end

@doc """
Clears the current progress bar.
$(TYPEDSIGNATURES)
The `clearpbar` function stops all jobs in the current progress bar, empties the job list, and then stops the progress bar itself.
It uses a lock to ensure thread safety during these operations.
"""
function clearpbar(pb=pbar[])
    isnothing(pb) && return
    try
        @lock pbar_lock begin
            for j in pb.jobs
                try
                    stop!(j)
                catch e
                    e isa InterruptException && rethrow(e)
                    @error "pbar: stop! job failed" exception=(e, catch_backtrace())
                end
            end
            empty!(pb.jobs)
            try
                stop!(pb)
            catch e
                e isa InterruptException && rethrow(e)
                @error "pbar: stop! pbar failed" exception=(e, catch_backtrace())
            end
        end
    catch e
        e isa InterruptException && rethrow(e)
        @error "pbar: clearpbar failed" exception=(e, catch_backtrace())
    end
end

@doc """
Initializes a new progress bar.
$(TYPEDSIGNATURES)
The `pbar!` function first clears any existing progress bar, then creates a new `ProgressBar` with the provided arguments.
The `transient` argument defaults to `true`, and `columns` defaults to `:default`.
"""
function pbar!(; transient=true, columns=:default, kwargs...)
    try
        clearpbar()
        pbar[] = ProgressBar(; transient, columns, kwargs...)
        pbar_initialized[] = true
    catch e
        e isa InterruptException && rethrow(e)
        @error "pbar: pbar! failed" exception=(e, catch_backtrace())
        pbar[] = nothing
        pbar_initialized[] = false
    end
end

function _doinit()
    pbar_initialized[] && return
    pbar!()
    @debug "Pbar: Loaded."
end

@doc "Initializes the progress bar."
macro pbinit!()
    :($(_doinit)())
end

@doc "The last update timestamp."
const plu = esc(:pb_last_update)
@doc "The current job being rendered."
const pbj = esc(:pb_job)

@doc "Toggles pbar transient flag"
function transient!(pb=pbar[])
    isnothing(pb) && return
    @lock pbar_lock toggle!(pb, :transient)
end

@doc "Set the update frequency globally."
function frequency!(v)
    @lock pbar_lock min_delta[] = v
end

# This prevents flickering when we render too frequently
@doc "Renders the progress bar if enough time has passed since the last render."
function dorender(pb, t=now())
    isnothing(pb) && return false
    try
        @lock pbar_lock begin
            # Handle epoch-zero last_render (first render)
            last_t = last_render[]
            if last_t == DateTime(0) || t - last_t > min_delta[]
                try
                    render(pb)
                catch e
                    e isa InterruptException && rethrow(e)
                    @error "pbar: render failed" exception=(e, catch_backtrace())
                    return false
                end
                last_render[] = t
                try
                    yield()
                catch e
                    e isa InterruptException && rethrow(e)
                    @error "pbar: yield failed" exception=(e, catch_backtrace())
                end
                return true
            end
            return false
        end
    catch e
        e isa InterruptException && rethrow(e)
        @error "pbar: dorender failed" exception=(e, catch_backtrace())
        return false
    end
end

function startjob!(pb, desc="", N=nothing)
    isnothing(pb) && return nothing
    try
        @lock pbar_lock begin
            job = try
                let j = addjob!(pb; description=desc, N, transient=true)
                    RunningJob(; job=j)
                end
            catch e
                e isa InterruptException && rethrow(e)
                @error "pbar: addjob! failed" exception=(e, catch_backtrace())
                return nothing
            end
            try
                if !pb.running
                    start!(pb)
                    dorender(pb)
                end
            catch e
                e isa InterruptException && rethrow(e)
                @error "pbar: start! pbar failed" exception=(e, catch_backtrace())
            end
            try
                yield()
            catch e
                e isa InterruptException && rethrow(e)
                @error "pbar: yield failed in startjob!" exception=(e, catch_backtrace())
            end
            job
        end
    catch e
        e isa InterruptException && rethrow(e)
        @error "pbar: startjob! failed" exception=(e, catch_backtrace())
        return nothing
    end
end

@doc "Instantiate a progress bar:

$(TYPEDSIGNATURES)

- `data`: `length(data)` determines the bar total
- `unit`: what unit the display
- `desc`: description will appear over the progressbar
"
macro pbar!(data, desc="", unit="") # use_finalizer=false)
    @pbinit!
    data = esc(data)
    desc = esc(desc)
    unit = esc(unit)
    quote
        pb = $pbar[]
        isnothing(pb) && return nothing
        $pbj = startjob!(pb, $desc, length($data))
    end
end

@doc "Complete a job."
function complete!(pb, j, force=true)
    isnothing(pb) && return nothing
    isnothing(j) && return nothing
    isnothing(j.N) && return nothing
    try
        # Avoid division by zero: only update if N > 0 and not already finished
        if !j.finished && j.N > 0 && j.N != j.i
            try
                update!(j; i=j.N - j.i)
            catch e
                e isa InterruptException && rethrow(e)
                @error "pbar: update! in complete! failed" exception=(e, catch_backtrace())
            end
            try
                dorender(pb)
            catch e
                e isa InterruptException && rethrow(e)
                @error "pbar: dorender in complete! failed" exception=(e, catch_backtrace())
            end
        end
        if force || !j.transient
            try
                @lock pbar_lock if j in pb.jobs
                    removejob!(pb, j)
                end
            catch e
                e isa InterruptException && rethrow(e)
                @error "pbar: removejob! failed" exception=(e, catch_backtrace())
            end
        end
    catch e
        e isa InterruptException && rethrow(e)
        @error "pbar: complete! failed" exception=(e, catch_backtrace())
    end
    nothing
end

@doc "Stops the progress bar."
macro pbstop!()
    quote
        @lock pbar_lock begin
            pb = $pbar[]
            isnothing(pb) && return nothing
            isempty(pb.jobs) && stop!(pb)
        end
        nothing
    end
end

@doc "Same as `@pbar!` but with implicit closing.

$(TYPEDSIGNATURES)

The first argument should be the collection to iterate over.
Optional kw arguments:
- `desc`: description
"
macro withpbar!(data, args...)
    @pbinit!
    data = esc(data)
    desc = unit = ""
    code = nothing
    for a in args
        if a.head == :(=)
            if a.args[1] == :desc
                desc = esc(a.args[2])
            elseif a.args[1] == :unit
                unit = esc(a.args[2])
            end
        else
            code = esc(a)
        end
    end
    quote
        pb = $pbar[]
        isnothing(pb) && return nothing
        local $pbj = try
            startjob!(pb, $desc, length($data))
        catch e
            e isa InterruptException && rethrow(e)
            @error "pbar: startjob! in withpbar! failed" exception=(e, catch_backtrace())
            nothing
        end
        # If progress bar failed to start, run code without progress tracking
        if isnothing($pbj)
            try
                $code
            catch e
                e isa InterruptException && rethrow(e)
                @error "pbar: withpbar! body failed (no pbar)" exception=(e, catch_backtrace())
                rethrow(e)
            end
        else
            local iserror = false
            try
                $code
            catch e
                if e isa InterruptException
                    rethrow(e)
                else
                    iserror = true
                    @error "pbar: withpbar! body failed" exception=(e, catch_backtrace())
                    rethrow(e)
                end
            finally
                try
                    pb = $pbar[]
                    if !isnothing(pb) && !isnothing($pbj) && !isnothing($pbj.job)
                        pbclose!($pbj.job, pb)
                    end
                catch e
                    e isa InterruptException && rethrow(e)
                    @error "pbar: pbclose! in withpbar! failed" exception=(e, catch_backtrace())
                end
            end
        end
    end
end

macro pbupdate!(n=1, args...)
    n = esc(n)
    quote
        pb = $pbar[]
        isnothing(pb) && return nothing
        !pb.running && return nothing
        try
            let t = $now()
                try
                    $pbj.counter += $n
                catch e
                    e isa InterruptException && rethrow(e)
                    @error "pbar: counter increment failed" exception=(e, catch_backtrace())
                end
                # Use lock for checking and rendering to avoid race with dorender
                try
                    @lock $pbar_lock begin
                        pb = $pbar[]
                        isnothing(pb) && return nothing
                        last_t = $last_render[]
                        if last_t == DateTime(0) || t - last_t > $min_delta[]
                            try
                                update!($pbj.job; i=$pbj.counter)
                            catch e
                                e isa InterruptException && rethrow(e)
                                @error "pbar: update! failed" exception=(e, catch_backtrace())
                            end
                            try
                                dorender(pb, t)
                            catch e
                                e isa InterruptException && rethrow(e)
                                @error "pbar: dorender in pbupdate! failed" exception=(e, catch_backtrace())
                            end
                        end
                    end
                catch e
                    e isa InterruptException && rethrow(e)
                    @error "pbar: pbupdate! lock failed" exception=(e, catch_backtrace())
                end
            end
        catch e
            e isa InterruptException && rethrow(e)
            @error "pbar: pbupdate! failed" exception=(e, catch_backtrace())
        end
        nothing
    end
end

function pbclose!(pb::ProgressBar=pbar[], all=true)
    isnothing(pb) && return nothing
    try
        all && foreach(j -> complete!(pb, j), pb.jobs)
        try
            stop!(pb)
        catch e
            e isa InterruptException && rethrow(e)
            @error "pbar: stop! in pbclose! failed" exception=(e, catch_backtrace())
        end
    catch e
        e isa InterruptException && rethrow(e)
        @error "pbar: pbclose! failed" exception=(e, catch_backtrace())
    end
    nothing
end

function pbclose!(job, pb=pbar[])
    isnothing(pb) && return nothing
    isnothing(job) && return nothing
    try
        complete!(pb, job)
        @pbstop!
    catch e
        e isa InterruptException && rethrow(e)
        @error "pbar: pbclose! job failed" exception=(e, catch_backtrace())
    end
    nothing
end

@doc "Calls `pbclose!` on the global progress bar."
macro pbclose!()
    quote
        $pbclose!($pbj.job, $pbar[])
    end
end

export @pbar!, @pbupdate!, @pbclose!, @pbstop!, @pbinit!, transient!, @withpbar!, @track
