#!/usr/bin/env sh

echo "COMPILE_SCRIPT: $COMPILE_SCRIPT"
if [ -e "$COMPILE_SCRIPT" ]; then
    cp $COMPILE_SCRIPT /tmp/compile.jl
elif [ -n "$COMPILE_SCRIPT" ]; then
    /usr/bin/echo -e "$COMPILE_SCRIPT" > /tmp/compile.jl;
fi

# Execute the compile script
echo "Running compile script..."
cd /planar
$JULIA_CMD --project=/planar/user/Load /tmp/compile.jl