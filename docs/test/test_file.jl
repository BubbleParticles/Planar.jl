#!/usr/bin/env julia

"""
Test Individual Documentation File

This script allows testing a single documentation file for code examples.

Usage:
    julia docs/test/test_file.jl <file_path> [options]

Options:
    --project=PATH    Path to Julia project (default: Planar)
    --verbose         Enable verbose output
    --timeout=N       Set timeout for code blocks (default: 30)
    --help            Show this help message

Examples:
    julia docs/test/test_file.jl docs/src/strategy.md
    julia docs/test/test_file.jl docs/src/getting-started/quick-start.md --verbose
"""

using Pkg

# Add the test directory to load path
push!(LOAD_PATH, @__DIR__)

using DocTestFramework

function parse_args(args)
    if isempty(args)
        println("Error: No file specified")
        show_help()
        exit(1)
    end
    
    file_path = args[1]
    options = Dict(
        :file_path => file_path,
        :project_path => "Planar",
        :config_path => "docs/test/config.toml",
        :verbose => false,
        :timeout => 30,
        :help => false
    )
    
    for arg in args[2:end]
        if startswith(arg, "--project=")
            options[:project_path] = arg[11:end]
        elseif startswith(arg, "--config=")
            options[:config_path] = arg[10:end]
        elseif arg == "--verbose"
            options[:verbose] = true
        elseif startswith(arg, "--timeout=")
            options[:timeout] = parse(Int, arg[11:end])
        elseif arg == "--help"
            options[:help] = true
        else
            @warn "Unknown option: $arg"
        end
    end
    
    return options
end

function show_help()
    println(__doc__)
end

function main()
    options = parse_args(ARGS)
    
    if options[:help]
        show_help()
        return
    end
    
    file_path = options[:file_path]
    
    if !isfile(file_path)
        @error "File not found: $file_path"
        exit(1)
    end
    
    if options[:verbose]
        ENV["JULIA_DEBUG"] = "DocTestFramework"
    end
    
    @info "Testing documentation file: $file_path"
    @info "Project path: $(options[:project_path])"
    @info "Config path: $(options[:config_path])"
    
    # Load configuration
    config = load_config(options[:config_path])
    
    try
        # Extract code blocks
        blocks = extract_code_blocks(file_path; config=config)
        @info "Found $(length(blocks)) code blocks"
        
        if isempty(blocks)
            @info "No code blocks found in file"
            return
        end
        
        # Test each block
        all_passed = true
        for (i, block) in enumerate(blocks)
            @info "Testing code block $i at line $(block.line)"
            
            if options[:verbose]
                println("Code:")
                println("=" ^ 40)
                println(block.code)
                println("=" ^ 40)
            end
            
            # Override timeout if specified
            if options[:timeout] != 30
                block = CodeBlock(block.code, block.file, block.line;
                                expected_output=block.expected_output,
                                requirements=block.requirements,
                                skip_test=block.skip_test,
                                timeout=options[:timeout])
            end
            
            result = test_code_block(block; project_path=options[:project_path], config=config)
            
            if result.output == "SKIPPED"
                @info "  ⏭️  Skipped ($(result.execution_time)s)"
            elseif result.success
                @info "  ✅ Passed ($(result.execution_time)s)"
                if options[:verbose] && !isempty(result.output)
                    println("Output:")
                    println(result.output)
                end
            else
                @error "  ❌ Failed ($(result.execution_time)s)"
                if result.error !== nothing
                    println("Error: $(result.error)")
                end
                if !isempty(result.output)
                    println("Output:")
                    println(result.output)
                end
                all_passed = false
            end
            
            println()
        end
        
        if all_passed
            @info "All code blocks passed! ✅"
        else
            @error "Some code blocks failed! ❌"
            exit(1)
        end
        
    catch e
        @error "Error testing file: $e"
        exit(1)
    end
end

# Run main function if script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end