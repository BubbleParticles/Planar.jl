import Base: length, iterate, collect

@doc """A type representing a date range.

$(FIELDS)

This type is used to store information about a range of dates, including the current date within the range, the start and stop dates, and the step size between dates.

"""
mutable struct DateRange
    current_date::OptDate
    const start::OptDate
    stop::OptDate
    const step::Union{Nothing,Period}
    function DateRange(start::OptDate=nothing, stop::OptDate=nothing, step=nothing)
        new(start, start, stop, step)
    end
    function DateRange(start::OptDate, stop::OptDate, tf::TimeFrame)
        new(start, start, stop, tf.period)
    end
end

@doc """Convert a DateRange object d to a DateTuple object.

$(TYPEDSIGNATURES)

Example:

```julia
d = DateRange(Date(2022, 1, 1), Date(2022, 12, 31))
date_tuple = convert(DateTuple, d)  # returns a DateTuple with the start and stop dates of the DateRange
```
"""
function Base.convert(::Type{DateTuple}, d::DateRange)
    DateTuple((
        @something(d.start, typemin(DateTime)), @something(d.stop, typemax(DateTime))
    ))
end

Base.similar(dr::DateRange) = begin
    DateRange(dr.start, dr.stop, dr.step)
end

# `iterate` stops are EXCLUSIVE (`stop` itself is never yielded) and the cursor
# (`current_date`) is mutable, so `length(dr)` (inclusive, from `start`) does NOT
# equal the iteration count. Preallocating `Vector{T}(undef, length(dr))` in
# `collect`/comprehensions then leaks the unwritten tail slot as garbage.
# Declare the size unknown so collections grow by push! and never read undef slots.
Base.IteratorSize(::Type{DateRange}) = Base.SizeUnknown()

function Base.print(io::IO, dr::DateRange)
    print(io, "start: ", dr.start, "\nstop:  ", dr.stop, "\nstep:  ", dr.step, "\n")
end
Base.display(dr::DateRange) = Base.print(dr)

function iterate(dr::DateRange)
    isnothing(dr.start) && return nothing
    isnothing(dr.stop) && return nothing
    isnothing(dr.step) && return nothing
    dr.step.value == 0 && return nothing
    # Respect an explicit cursor set via `current!` (defaults to start).
    start = something(dr.current_date, dr.start)
    dr.current_date = start
    (start, start)
end

function iterate(dr::DateRange, cur::DateTime)
    isnothing(dr.stop) && return nothing
    sv = dr.step.value
    nxt = cur + dr.step
    # `stop` is EXCLUSIVE: yield `nxt` only while the following step stays within.
    (sv > 0 && nxt + dr.step > dr.stop) && return nothing
    (sv < 0 && nxt + dr.step < dr.stop) && return nothing
    dr.current_date = nxt
    (nxt, nxt)
end

function length(dr::DateRange)::Int
    isnothing(dr.start) && return 0
    isnothing(dr.stop) && return 0
    isnothing(dr.step) && return 0
    sv = dr.step.value
    sv == 0 && return 0
    # Step without converting to Millisecond so Month/Week periods don't crash
    # on the `Millisecond ÷ Month` promotion error.
    n = 0
    cur = dr.start
    while true
        nxt = cur + dr.step
        (sv > 0 && nxt > dr.stop) && break
        (sv < 0 && nxt < dr.stop) && break
        n += 1
        cur = nxt
    end
    n
end

collect(dr::DateRange) = begin
    out = []
    for d in dr
        push!(out, d)
    end
    out
end

@doc "Starts the current date of the DateRange (defaults to `start` value.)"
current!(dr::DateRange, d=dr.start) = dr.current_date = d
function Base.isequal(dr1::DateRange, dr2::DateRange)
    dr1.start === dr2.start && dr1.stop === dr2.stop
end

function Base.isapprox(dr1::DateRange, dr2::DateRange)
    dr1.start >= dr2.start && dr1.stop <= dr2.stop
end

function Base.parse(::Type{DateRange}, s::AbstractString)
    local to = step = ""
    (from, tostep) = split(s, "..")
    if !isempty(tostep)
        try
            (to, step) = split(tostep, ";")
        catch error
            if error isa BoundsError
                to = tostep
                step = ""
            else
                rethrow(error)
            end
        end
    end
    args::Vector{Any} = [isempty(v) ? nothing : todatetime(v) for v in (from, to)]
    if !isempty(step)
        push!(args, convert(TimeFrame, step))
    end
    DateRange(args...)
end

@doc """Create a `DateRange` using notation `FROM..TO;STEP`.

example:
1999-..2000-;1d
1999-12-01..2000-02-01;1d
1999-12-01T12..2000-02-01T10;1d
"""
macro dtr_str(s::String)
    :($(Base.parse(DateRange, s)))
end

export DateRange, DateTuple, @dtr_str, current!