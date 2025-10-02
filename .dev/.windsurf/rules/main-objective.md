---
trigger: always_on
description: 
globs: 
---
For any task on Planar.jl, consider the entire framework's integrity. Integrate new code seamlessly by utilizing pre-defined types and functions from existing packages.
When you need to define float types, use the type `DFT` defined in the Misc package.
Whenever we are implementing functions that deal with OHLCV, other data based on timestamps and indicators, remember that they have to support *streaming* data, look at how OnlineTechnicalIndicators is used in the StrategyTools package for reference, because in LiveMode we usually have to recompute(update) values based on fresh data (tick by tick). 
Remember that when we are calculating indicators involving multiple assets the data needs to be aligned by date.
When slicing or selecting rows in a DataFrame make use of DateTime indexing (as implemented in Data.DFUtils) whenever possible.
