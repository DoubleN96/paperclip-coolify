#!/bin/sh
set -e

# Capture runtime UID/GID from environment variables, defaulting to 1000
PUID=${USER_UID:-1000}
PGID=${USER_GID:-1000}

# Adjust the node user's UID/GID if they differ from the runtime request
# and fix volume ownership only when a remap is needed
changed=0

if [ "$(id -u node)" -ne "$PUID" ]; then
    echo "Updating node UID to $PUID"
    usermod -o -u "$PUID" node
    changed=1
fi

if [ "$(id -g node)" -ne "$PGID" ]; then
    echo "Updating node GID to $PGID"
    groupmod -o -g "$PGID" node
    usermod -g "$PGID" node
    changed=1
fi

if [ "$changed" = "1" ]; then
    chown -R node:node /paperclip
fi

# Fix npm cache permissions (may be left by root-owned build layers)
rm -rf /paperclip/.npm 2>/dev/null || true

# Wait for Postgres to be ready (if DATABASE_URL is set)
if [ -n "$DATABASE_URL" ]; then
    DB_HOST=$(echo "$DATABASE_URL" | sed -n 's|.*@\([^:]*\):.*|\1|p')
    DB_PORT=$(echo "$DATABASE_URL" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
    DB_PORT=${DB_PORT:-5432}
    echo "Waiting for database at $DB_HOST:$DB_PORT..."
    for i in $(seq 1 30); do
        if gosu node node -e "const net=require('net');const s=net.connect($DB_PORT,'$DB_HOST',()=>{s.end();process.exit(0)});s.on('error',()=>process.exit(1))" 2>/dev/null; then
            echo "Database ready!"
            break
        fi
        echo "  Attempt $i/30 - waiting..."
        sleep 2
    done
fi

exec gosu node "$@"
