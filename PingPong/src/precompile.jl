# NOTE: (TOPLEVEL) Packages that get compiled in a sysimage should not have precompile statements like these
# because of pythoncall
# using .Lang: @preset, @precomp

# @preset let
#     using Stubs
#     @precomp let
#         s = Stubs.stub_strategy()
#         Engine.SimMode.backtest!(s)
#         ai = first(s.universe)
#     end
# end
