isdefined(Main, :da) || using Data: Data as da
using Pkg
Pkg.activate(joinpath(dirname(@__DIR__), "..", "PlanarDownloadTool"))
using PlanarDownloadTool: PlanarDownloadTool as scr
isdefined(Main, :Revise) && Revise.track(scr)
const bb = scr.BybitData
const bn = scr.BinanceData
