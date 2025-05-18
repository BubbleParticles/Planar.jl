#!/usr/bin/bash
#
project_path=~/dev/Planar.jl
jl_script=~/scripts/strategies.jl

cd "$project_path" || { echo "couldn't cd to $project_path"; exit 1; }

eval "$(direnv export bash)"

exec julia -iL $jl_script
