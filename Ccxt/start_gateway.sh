#!/bin/bash
# Start ccxt-gateway as a daemon.
# Thin wrapper around daemon_gateway.py

exec /project/ccxt-gateway/.venv/bin/python /project/ccxt-gateway/daemon_gateway.py
