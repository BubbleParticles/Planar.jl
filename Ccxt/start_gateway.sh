#!/bin/bash
# Start ccxt-gateway with proper daemonization

# Activate venv
source /project/ccxt-gateway/venv/bin/activate

# Set environment variables
export CCXT_GATEWAY_SERVER_PORT=8999
export CCXT_GATEWAY_SERVER_USE_SSL=true
export CCXT_GATEWAY_SERVER_SSL_CERT=/project/Ccxt/certs/server.crt
export CCXT_GATEWAY_SERVER_SSL_KEY=/project/Ccxt/certs/server.key

# Change to gateway directory
cd /project/ccxt-gateway/

# Start the gateway in background using nohup and disown
nohup python -c "import sys; sys.path.insert(0, 'src'); from ccxt_gateway.main import main; main()" > /tmp/gateway.log 2>&1 &

# Disown the process so it survives shell exit
disown

# Save PID
echo $! > /tmp/ccxt_gateway.pid
echo "Gateway started with PID $(cat /tmp/ccxt_gateway.pid)"
