#!/usr/bin/bash
#
project_path=~/dev/Planar.jl
jl_script=~/scripts/strategies.jl

cd "$project_path" || { echo "couldn't cd to $project_path"; exit 1; }

# Check that $project_path/user/keys points to a valid directory (or symlink to directory)
keys_dir="$project_path/user/keys"
if [ ! -e "$keys_dir" ]; then
    echo "Error: $keys_dir does not exist"
    exit 1
elif [ -L "$keys_dir" ]; then
    # It's a symlink, check if it's valid and points to a directory
    if [ ! -L "$keys_dir" ] || [ ! -d "$keys_dir" ]; then
        echo "Error: $keys_dir is not a valid symlink to a directory"
        exit 1
    fi
elif [ ! -d "$keys_dir" ]; then
    echo "Error: $keys_dir is not a valid directory"
    exit 1
fi

# Check that the keys directory has at least 1 JSON file
if [ -z "$(find "$keys_dir" -name "*.json" -type f | head -1)" ]; then
    echo "Error: $keys_dir does not contain any JSON files"
fi

eval "$(direnv export bash)"

exec julia -iL $jl_script
