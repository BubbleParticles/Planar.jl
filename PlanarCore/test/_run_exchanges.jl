using Test
using PlanarCore
using PlanarCore.Exchanges
using PlanarCore.ExchangeTypes

# These consts are also defined in the test file (guarded by @isdefined)
const HTTP = PlanarCore.ExchangeTypes.CcxtGateway.HTTP
const JSON3 = PlanarCore.ExchangeTypes.JSON3

using PlanarCore.ExchangeTypes.CcxtGateway.Rest: set_http_get!, set_http_post!

function _my_mock_get(url; kwargs...)
    if occursin("/ping", url)
        return HTTP.Response(200, JSON3.write(Dict("result" => "pong", "error" => nothing)))
    elseif occursin("/exchanges/", url)
        return HTTP.Response(200, JSON3.write(Dict("result" => Dict("running" => true), "error" => nothing)))
    else
        error("Unexpected GET: $url")
    end
end
function _my_mock_post(url; kwargs...)
    if occursin("/exchanges/", url)
        return HTTP.Response(200, JSON3.write(Dict("result" => "started", "error" => nothing)))
    else
        error("Unexpected POST: $url")
    end
end

set_http_get!(_my_mock_get)
set_http_post!(_my_mock_post)

@info "Mock set up. Including test file..."
include("Exchanges/runtests.jl")
@info "Exchanges tests done."
