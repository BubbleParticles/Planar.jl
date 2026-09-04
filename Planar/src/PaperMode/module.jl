using PlanarCore
using PlanarCore.Fetch: Fetch
using PlanarCore.SimMode
using PlanarCore.SimMode.Executors
using Base: with_logger
using PlanarCore.Executors: orders, orderscount
using PlanarCore.Executors.OrderTypes
using PlanarCore.Executors.TimeTicks
using PlanarCore.Executors.Instances
using PlanarCore.Executors.Misc
using PlanarCore.Executors.Instruments: compactnum as cnum
using PlanarCore.Misc.ConcurrentCollections: ConcurrentDict
using PlanarCore.Misc.TimeToLive: safettl
using PlanarCore.Misc.LoggingExtras
using PlanarCore.Misc.Lang: @lget!, @ifdebug, @deassert, Option, @writeerror, @debug_backtrace
using PlanarCore.Executors.Strategies: MarginStrategy, Strategy, Strategies as st, call!
using PlanarCore.Executors.Strategies
using PlanarCore.Instances: MarginInstance
using PlanarCore.Instances.Exchanges: CcxtTrade
using PlanarCore.Instances.Data.DataStructures: CircularBuffer
using PlanarCore.SimMode: AnyMarketOrder, AnyLimitOrder
import PlanarCore.Executors: call!
import PlanarCore.Misc: start!, stop!, isrunning, sleep_pad, LOGGING_GROUPS, kill_task, start_task

# Compat: define InstrumentInstance in this module regardless of core version
if !isdefined(@__MODULE__, :InstrumentInstance)
    if isdefined(PlanarCore.Instances, :InstrumentInstance)
        const InstrumentInstance = PlanarCore.Instances.InstrumentInstance
    elseif isdefined(PlanarCore.Executors.Instances, :InstrumentInstance)
        const InstrumentInstance = PlanarCore.Executors.Instances.InstrumentInstance
    elseif isdefined(PlanarCore.Instances, :AssetInstance)
        const InstrumentInstance = PlanarCore.Instances.AssetInstance
    elseif isdefined(PlanarCore.Executors.Instances, :AssetInstance)
        const InstrumentInstance = PlanarCore.Executors.Instances.AssetInstance
    else
        const InstrumentInstance = Any
    end
end
@doc "A constant `TradesCache` that is a dictionary mapping `InstrumentInstance` to a circular buffer of `CcxtTrade`."
const TradesCache = Dict{InstrumentInstance,CircularBuffer{CcxtTrade}}()

_maintf(s) = string(s.timeframe)
_opttf(s) = string(attr(s, :timeframe, nothing))
_timeframes(s) = join(string.(s.config.timeframes), " ")
_cash_total(s) = cnum(st.current_total(s, lastprice; local_bal=true))
_assets(s) =
    let str = join(getproperty.(st.assets(s), :raw), ", ")
        str[begin:min(length(str), displaysize()[2] - 1)]
    end

@doc """
Generates a formatted string representing the configuration of a given strategy.

$(TYPEDSIGNATURES)

The function takes a strategy and a throttle as input and returns a string detailing the strategy's configuration including its name, mode, throttle, timeframes, cash, assets, and margin mode.
NOTE: ensure this doesn't use the strategy lock.
"""
function header(s::Strategy, throttle)
    """Starting strategy $(nameof(s)) in $(nameof(typeof(execmode(s)))) mode!

        throttle: $throttle
        timeframes: $(_maintf(s)) (main), $(_maintf(s)) (optional), $(_timeframes(s)...) (extras)
        cash: $(cash(s)) [$(_cash_total(s))]
        assets: $(_assets(s))
        margin: $(marginmode(s))
        """
end
@doc """
Logs the current state of a given strategy.

$(TYPEDSIGNATURES)

The function takes a strategy as input and logs the current state of the strategy including the number of long, short, and liquidation trades, the cash committed, the total balance, and the number of increase and reduce orders.
"""
function log(s::Strategy)
    long, short, liq = st.trades_count(s, Val(:positions))
    cv = s.cash
    comm = s.cash_committed
    inc, red = orderscount(s, Val(:inc_red))
    tot = st.current_total(s; price_func=lastprice, local_bal=true)
    @info string(nameof(s), "@", nameof(exchange(s))) time = TimeTicks.now() cash = cv committed =
        comm balance = tot inc_orders = inc red_orders = red long_trades = long short_trades =
        short liquidations = liq
end

@doc """
Executes the main loop of the strategy.

$(TYPEDSIGNATURES)

This function executes the main loop of the strategy, logging the state, pinging the strategy, and sleeping for the throttle duration. It handles exceptions and ensures the strategy stops running when an interrupt exception is thrown.
"""
function _doping(s; throttle, fail_fast=false)
    is_running = attr(s, :is_running)
    @assert isassigned(is_running)
    setattr!(s, TimeTicks.now(), :is_start)
    setattr!(s, missing, :is_stop)
    ping_start = TimeTicks.DateTime(0)
    prev_cash = s.cash.value
    s_cash = s.cash
    event!(s, StrategyEvent, :strategy_started, s; start_time=s.is_start)
    try
        while is_running[]
            try
                if s_cash.value != prev_cash
                    log(s)
                    prev_cash = s_cash.value
                end
                ping_start = TimeTicks.now()
                call!(s, TimeTicks.now(), nothing)
                # Check stop condition: no orders and no active positions
                if orderscount(s) == 0 && isempty(s.holdings)
                    @debug "_doping: no active orders or positions, stopping"
                    is_running[] = false
                    break
                end
                # Use interruptible sleep that checks is_running flag
                sleep_pad_interruptible(ping_start, throttle, is_running)
            catch e
                e isa InterruptException && begin
                    is_running[] = false
                    rethrow(e)
                end
                @error "doping: error in strategy loop" exception = (e, catch_backtrace())
                fail_fast && rethrow(e)
                if is_running[]
                    sleep_pad_interruptible(ping_start, throttle, is_running)
                end
            end
        end
    catch e
        e isa InterruptException && rethrow(e)
        @error "doping: unrecoverable error" exception = (e, catch_backtrace())
        fail_fast && rethrow(e)
    finally
        is_running[] = false
        setattr!(s, TimeTicks.now(), :is_stop)
        event!(s, StrategyEvent, :strategy_stopped, s; start_time=s.is_stop)
        # Notify the task's condition variable to allow graceful shutdown
        t = current_task()
        if !isnothing(t.storage) && haskey(t.storage, :notify)
            cond = t.storage[:notify]
            if cond isa Threads.Condition
                safenotify(cond)
            end
        end
    end
end

@doc """
Starts the execution of a given strategy.

$(TYPEDSIGNATURES)

This function starts the execution of a strategy in either foreground or background mode. It sets up the necessary attributes, logs, and tasks for the strategy execution. If the strategy is already running, it throws an error.
"""
function start!(
    s::Strategy{<:Union{Paper,Live}}; throttle=throttle(s), doreset=false, foreground=false, with_stdout=true, fail_fast=false
)
    call!(s, StartStrategy())
    local startinfo
    s[:stopped] = false
    @debug "start: locking"
    @lock s begin
        @debug "start: locked"
        attrs = s.attrs
        first_start = !haskey(attrs, :is_running)
        # The lock is reentrant; default! and reset! can be called safely within the lock.
        if doreset
            @debug "start: reset"
            reset!(s)
        elseif first_start
            # only set defaults on first run
            @debug "start: defaults"
            default!(s)
        end

        if first_start
            @debug "start: first start"
            s[:is_running] = Ref(true)
        elseif s[:is_running][]
            @error "start: strategy already running" s = nameof(s)
            t = attr(s, :run_task, nothing)
            if t isa Task && istaskstarted(t) && !istaskdone(t)
                @debug "start: returning existing running task" s = nameof(s)
                return t
            else
                @warn "start: strategy was marked running but task is dead, allowing restart" s = nameof(s)
                # Clean up the dead task's condition variable to prevent stale notifications
                if t isa Task && !isnothing(t.storage) && haskey(t.storage, :notify)
                    cond = t.storage[:notify]
                    if cond isa Threads.Condition
                        safenotify(cond)
                    end
                    # Clear the notify key to prevent stale state
                    delete!(t.storage, :notify)
                end
                # Fall through to restart
            end
        else
            @debug "start: is_running set"
            s[:is_running][] = true
        end
        @deassert attr(s, :is_running)[]

        @debug "start: header"
        startinfo = header(s, throttle)
        
        if foreground
            s[:run_task] = nothing
            @debug "start: unlocked (foreground)"
            # Release lock before running foreground
        else
            # Create and register task atomically within the lock to prevent race with stop!
            logger = s[:logger]
            task = @task begin
                try
                    with_logger(logger) do
                        @info startinfo
                        _doping(s; throttle, fail_fast)
                    end
                catch e
                    e isa InterruptException && rethrow(e)
                    @error "PaperMode: doping loop crashed" exception = (e, catch_backtrace())
                    # Do NOT rethrow - log and exit gracefully to prevent silent task death
                end
            end
            s[:run_task] = start_task(task, IdDict())
            @debug "start: unlocked (background)"
        end
    end
    if foreground
        logger = s[:logger]
        with_logger(logger) do
            @info startinfo
            _doping(s; throttle, fail_fast)
        end
    else
        return nothing
    end
end

_compressor(file) = run(`gzip $(file)`)
function strategy_logger!(s)
    with_stdout = attr!(s, :log_to_stdout, true)
    logdir, logname = let file = runlog(s)
        dirname(file), splitext(basename(file))[1]
    end
    esc_logname = replace(logname, r"(.)" => s"\\\1")

    all_levels = [Logging.Debug, Logging.Info, Logging.Warn, Logging.Error]

    # Create a logger for each level
    level_loggers = Dict{LogLevel, AbstractLogger}()
    for level in all_levels
        if level >= s[:log_level]
            level_str = lowercase(string(level))
            esc_level_str = replace(level_str, r"(.)" => s"\\\1")
            rotate_logger = DatetimeRotatingFileLogger(
                logdir,
                string(esc_logname, "-", esc_level_str, "-", raw"YYYY-mm-dd.\l\o\g");
                rotation_callback=_compressor,
            )
            ts_logger = timestamp_logger(rotate_logger)
            level_loggers[level] = ts_logger
        end
    end

    # Create a filtered logger for each level
    filtered_loggers = []
    for (level, logger) in level_loggers
        filtered_logger = EarlyFilteredLogger(logger) do log_args
            log_args.level == level
        end
        push!(filtered_loggers, filtered_logger)
    end

    # Combine all loggers
    file_logger = TeeLogger(filtered_loggers...)

    s[:logger] = if with_stdout
        # Create a MinLevelLogger for the global logger (stdout)
        min_level_global_logger = MinLevelLogger(global_logger(), s[:log_level])
        # Combine file logger with the min-level global logger
        TeeLogger(min_level_global_logger, file_logger)
    else
        file_logger
    end
end

@doc """
Calculates the elapsed time since the strategy started running.

$(TYPEDSIGNATURES)

This function calculates the time elapsed since the strategy started running. If the strategy has not started yet, it returns 0 milliseconds.
"""
function elapsed(s::Strategy{<:Union{Paper,Live}})
    attrs = s.attrs
    max(
        Millisecond(0),
        @coalesce(get(attrs, :is_stop, missing), TimeTicks.now()) -
        @coalesce(get(attrs, :is_start, missing), TimeTicks.now()),
    ) |> compact
end

@doc """
Stops the execution of a given strategy.

$(TYPEDSIGNATURES)

This function stops the execution of a strategy and logs the mode and elapsed time since the strategy started. If the strategy is running in the background, it waits for the task to finish.
"""
function stop!(s::Strategy{<:Union{Paper,Live}})
    s[:stopped] = true
    @debug "stop: locking" islocked(s)
    @lock s begin
        @debug "stop: locked"
        running = attr(s, :is_running, missing)
        task = attr(s, :run_task, missing)
        # Set is_running to false BEFORE waiting on task to prevent race with start!
        if running isa Ref{Bool}
            running[] = false
        end
        if istaskrunning(task)
            waitforcond(() -> istaskdone(task), throttle(s))
            if istaskrunning(task)
                @warn "strategy: hanging task, killing" task
                try
                    killed = kill_task(task)
                    if !killed && istaskrunning(task)
                        @warn "strategy: waiting for task to stop after kill"
                        waitforcond(() -> istaskdone(task), throttle(s))
                    end
                catch e
                    e isa InterruptException && rethrow(e)
                    @error "stop: failed to kill strategy task" exception = (e, catch_backtrace())
                end
            end
        end
        # Stop paper order and position tasks INSIDE the lock to prevent race with start!
        @debug "strategy: stopping paper order tasks" mode = execmode(s)
        try
            stop_all_paper_order_tasks!(s)
        catch e
            e isa InterruptException && rethrow(e)
            @error "strategy: error stopping paper order tasks" exception = (e, catch_backtrace()) s = nameof(s)
        end
        @debug "strategy: stopping paper position tasks" mode = execmode(s)
        try
            stop_paper_position_tasks!(s)
        catch e
            e isa InterruptException && rethrow(e)
            @error "strategy: error stopping paper position tasks" exception = (e, catch_backtrace()) s = nameof(s)
        end
    end
    @debug "strategy: calling StopStrategy" mode = execmode(s)
    call!(s, StopStrategy())
    @info "strategy: stopped" mode = execmode(s) elapsed(s)
end

@doc """
Returns the log file path for a given strategy.

$(TYPEDSIGNATURES)

This function returns the log file path for a given strategy. If the log file path is not set, it creates a new one based on the execution mode of the strategy.
"""
function runlog(s, name=lowercase(string(typeof(execmode(s)))))
    get!(s.attrs, :logfile, st.logpath(s; name))
end

function logmaxlines(s)
    get!(s.attrs, :logfile_maxlines, 10000)
end

@doc """
Checks if a given strategy is running.

$(TYPEDSIGNATURES)

This function checks if a given strategy is currently running. It returns `true` if the strategy is running, and `false` otherwise.
"""
function isrunning(s::Strategy{<:Union{Paper,Live}})
    running = attr(s, :is_running, nothing)
    if isnothing(running)
        false
    else
        running[]
    end
end

export start!, stop!

include("utils.jl")
include("orders/utils.jl")
include("orders/state.jl")
include("orders/limit.jl")
include("orders/call.jl")
include("positions/call.jl")
