module Types

using HTTP
using JSON3

export GatewayResponse, parse_response, has_error, get_result

struct GatewayResponse
    result::Any
    error::Union{String, Nothing}
    error_code::Union{String, Nothing}
end

function GatewayResponse(body::AbstractDict)
    body_dict = Dict{String, Any}(string(k) => v for (k, v) in pairs(body))
    if haskey(body_dict, "status") && !haskey(body_dict, "result")
        GatewayResponse(get(body_dict, "status", nothing), nothing, nothing)
    elseif haskey(body_dict, "result")
        GatewayResponse(
            get(body_dict, "result", nothing),
            get(body_dict, "error", nothing),
            get(body_dict, "error_code", nothing),
        )
    else
        GatewayResponse(body_dict, nothing, nothing)
    end
end

function parse_response(resp::HTTP.Response)
    body = JSON3.parse(String(resp.body))
    if body isa JSON3.Object
        GatewayResponse(Dict{String, Any}(string(k) => v for (k, v) in pairs(body)))
    elseif body isa AbstractVector
        GatewayResponse(body, nothing, nothing)
    else
        GatewayResponse(body, nothing, nothing)
    end
end

function has_error(response::GatewayResponse)
    response.error !== nothing || response.error_code !== nothing
end

function get_result(response::GatewayResponse)
    if has_error(response)
        error("Gateway error: $(response.error)")
    end
    response.result
end

end # module Types
