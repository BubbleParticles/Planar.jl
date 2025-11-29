# Legacy BlackBoxOptim functions for backward compatibility

using BlackBoxOptim

@doc """ Determines the fitness scheme for a given strategy and number of objectives.

$(TYPEDSIGNATURES)

This function takes a strategy and a number of objectives as input. It checks if the strategy has a custom weights function defined in its attributes. If it does, this function is used as the aggregator in the ParetoFitnessScheme. If not, a default ParetoFitnessScheme is returned.
"""
function bbo_fitness_scheme(s::Strategy, n_obj)
    let weightsfunc = get(s.attrs, :opt_weighted_fitness, missing)
        ParetoFitnessScheme{n_obj}(;
            is_minimizing=false,
            (weightsfunc isa Function ? (; aggregator=weightsfunc) : ())...,
        )
    end
end

@doc """ Returns a set of optimization methods supported by BlackBoxOptim.

$(TYPEDSIGNATURES)

This function filters the methods based on the `multi` parameter and excludes the methods listed in `disabled_methods`.
If `multi` is `true`, it returns multi-objective methods, otherwise it returns single-objective methods.
"""
function bbomethods(multi=false)
    Set(
        k for k in keys(
            getglobal(
                BlackBoxOptim,
                ifelse(multi, :MultiObjectiveMethods, :SingleObjectiveMethods),
            ),
        ) if k ∉ disabled_methods
    )
end

@doc "A set of optimization methods that are disabled and not used with the `BlackBoxOptim` package."
const disabled_methods = Set((
    :simultaneous_perturbation_stochastic_approximation,
    :resampling_memetic_search,
    :resampling_inheritance_memetic_search,
))

export bbo_fitness_scheme, bbomethods, disabled_methods 