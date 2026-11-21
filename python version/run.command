#!/bin/bash
set -e
cd "$(dirname "$0")"
if [ ! -f "config.json" ]; then
    python3 setup.py
fi
exec python3 server.py
