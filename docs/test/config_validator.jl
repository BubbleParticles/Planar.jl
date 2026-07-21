"""
Configuration Validator

This module validates and provides default configurations for the documentation testing framework.
"""
module ConfigValidator

using TOML

export validate_config_or_default, load_default_config, ConfigValidationError

struct ConfigValidationError <: Exception
    message::String
end

"""
    load_default_config() -> Dict

Load the default configuration for documentation testing.
"""
function load_default_config()
    return Dict(
        "general" => Dict(
            "project_path" => "Planar",
            "docs_path" => "docs/src",
            "default_timeout" => 30,
            "parallel" => false
        ),
        "code_examples" => Dict(
            "enabled" => true,
            "skip_files" => String[],
            "skip_patterns" => ["# DOCTEST_SKIP", "# Example only", "# Pseudo-code"],
            "global_requirements" => ["Planar", "Test"]
        ),
        "output_validation" => Dict(
            "enabled" => true,
            "on_mismatch" => "warn",
            "normalize_whitespace" => true,
            "ignore_patterns" => ["\\d+\\.\\d+s", "@ \\w+", "\\d{4}-\\d{2}-\\d{2}", "\\d{2}:\\d{2}:\\d{2}"]
        ),
        "link_validation" => Dict(
            "enabled" => true,
            "check_external" => true,
            "external_timeout" => 10,
            "skip_patterns" => ["localhost", "127.0.0.1", "example.com", "placeholder.com"],
            "retry_failed" => true,
            "retry_count" => 2
        ),
        "content_consistency" => Dict(
            "enabled" => true,
            "terminology" => Dict(
                "rules" => Dict(
                    "Planar" => ["planar", "PLANAR"],
                    "Julia" => ["julia", "JULIA"],
                    "CCXT" => ["ccxt", "Ccxt"],
                    "API" => ["api", "Api"],
                    "OHLCV" => ["ohlcv", "Ohlcv"],
                    "JSON" => ["json", "Json"],
                    "HTTP" => ["http", "Http"],
                    "URL" => ["url", "Url"],
                    "CSV" => ["csv", "Csv"],
                    "DataFrame" => ["dataframe", "Dataframe", "data frame"],
                    "backtesting" => ["back-testing", "back testing"],
                    "live trading" => ["livetrading", "live-trading"],
                    "paper trading" => ["papertrading", "paper-trading"],
                    "cryptocurrency" => ["crypto-currency", "crypto currency"],
                    "exchange" => ["Exchange"]
                )
            ),
            "format" => Dict(
                "check_headings" => true,
                "check_code_blocks" => true,
                "check_lists" => true,
                "check_links" => true,
                "check_images" => true,
                "prefer_atx_headings" => true,
                "require_space_after_hash" => true,
                "require_language_specification" => true,
                "prefer_fenced_over_indented" => true,
                "prefer_dash_for_unordered" => true,
                "require_space_after_number" => true
            )
        ),
        "reporting" => Dict(
            "generate_html" => true,
            "generate_json" => true,
            "generate_summary" => true,
            "html_output" => "results/report.html",
            "json_output" => "results/report.json",
            "summary_output" => "results/summary.txt",
            "include_failure_details" => true,
            "include_suggestions" => true
        ),
        "ci" => Dict(
            "fail_on_warnings" => false,
            "fail_on_external_link_failures" => false,
            "fail_on_consistency_warnings" => false,
            "generate_step_summary" => true,
            "annotate_files" => true
        )
    )
end

"""
    validate_config_or_default(config_path::String) -> Dict

Load configuration from file or return default if file doesn't exist or is invalid.
"""
function validate_config_or_default(config_path::String)
    if isfile(config_path)
        try
            config = TOML.parsefile(config_path)
            @info "Loaded configuration from $config_path"
            return merge_with_defaults(config)
        catch e
            @warn "Failed to load configuration from $config_path: $e"
            @info "Using default configuration"
            return load_default_config()
        end
    else
        @info "Configuration file not found at $config_path, using defaults"
        return load_default_config()
    end
end

"""
    merge_with_defaults(user_config::Dict) -> Dict

Merge user configuration with defaults, ensuring all required keys exist.
"""
function merge_with_defaults(user_config::Dict)
    default_config = load_default_config()
    
    # Deep merge function
    function deep_merge(default::Dict, user::Dict)
        result = copy(default)
        for (key, value) in user
            if haskey(result, key) && isa(result[key], Dict) && isa(value, Dict)
                result[key] = deep_merge(result[key], value)
            else
                result[key] = value
            end
        end
        return result
    end
    
    return deep_merge(default_config, user_config)
end

"""
    validate_config(config_path::String) -> Bool

Validate the testing configuration file.
Throws ConfigValidationError if validation fails.
"""
function validate_config(config_path::String)
    if !isfile(config_path)
        throw(ConfigValidationError("Configuration file not found: $config_path"))
    end
    
    try
        config = TOML.parsefile(config_path)
    catch e
        throw(ConfigValidationError("Failed to parse TOML configuration: $e"))
    end
    
    config = TOML.parsefile(config_path)
    
    # Validate required sections
    required_sections = ["general", "code_examples", "output_validation"]
    for section in required_sections
        if !haskey(config, section)
            throw(ConfigValidationError("Missing required section: $section"))
        end
    end
    
    # Validate general section
    general = config["general"]
    required_general = ["project_path", "docs_path", "default_timeout"]
    for key in required_general
        if !haskey(general, key)
            throw(ConfigValidationError("Missing required key in [general]: $key"))
        end
    end
    
    # Validate timeout is positive integer
    if !isa(general["default_timeout"], Int) || general["default_timeout"] <= 0
        throw(ConfigValidationError("default_timeout must be a positive integer"))
    end
    
    # Validate code_examples section
    code_examples = config["code_examples"]
    if !haskey(code_examples, "enabled") || !isa(code_examples["enabled"], Bool)
        throw(ConfigValidationError("code_examples.enabled must be a boolean"))
    end
    
    # Validate arrays are actually arrays
    array_keys = ["skip_files", "skip_patterns", "global_requirements"]
    for key in array_keys
        if haskey(code_examples, key) && !isa(code_examples[key], Vector)
            throw(ConfigValidationError("code_examples.$key must be an array"))
        end
    end
    
    # Validate output_validation section
    output_validation = config["output_validation"]
    if haskey(output_validation, "on_mismatch")
        valid_values = ["error", "warn", "ignore"]
        if !(output_validation["on_mismatch"] in valid_values)
            throw(ConfigValidationError("output_validation.on_mismatch must be one of: $(join(valid_values, ", "))"))
        end
    end
    
    if haskey(output_validation, "normalize_whitespace") && !isa(output_validation["normalize_whitespace"], Bool)
        throw(ConfigValidationError("output_validation.normalize_whitespace must be a boolean"))
    end
    
    @info "Configuration validation passed: $config_path"
    return true
end

end # module ConfigValidator