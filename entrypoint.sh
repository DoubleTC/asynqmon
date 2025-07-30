#!/bin/sh

set -e

echo "🚀 Starting Asynqmon with Basic Auth..."
echo "Version: $(cat /etc/alpine-release 2>/dev/null || echo 'N/A')"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

validate_auth() {
    if [ -z "$AUTH_USERNAME" ] && [ -z "$AUTH_USERS" ]; then
        log "❌ ERROR: Authentication not configured!"
        echo ""
        echo "Please set one of the following:"
        echo "  Single user:"
        echo "    AUTH_USERNAME=admin"
        echo "    AUTH_PASSWORD=your-secure-password"
        echo ""
        echo "  Multiple users:"
        echo "    AUTH_USERS=admin:pass123,user1:pass1,viewer:readonly"
        echo ""
        echo "Example:"
        echo "  docker run -e AUTH_USERNAME=admin -e AUTH_PASSWORD=secret123 ..."
        exit 1
    fi
}

setup_auth() {
    log "🔐 Setting up authentication..."

    rm -f /etc/nginx/.htpasswd
    touch /etc/nginx/.htpasswd

    if [ ! -z "$AUTH_USERNAME" ]; then
        if [ -z "$AUTH_PASSWORD" ]; then
            log "❌ ERROR: AUTH_PASSWORD is required when using AUTH_USERNAME"
            exit 1
        fi
        log "👤 Creating single user: $AUTH_USERNAME"
        htpasswd -cb /etc/nginx/.htpasswd "$AUTH_USERNAME" "$AUTH_PASSWORD"
    fi

    if [ ! -z "$AUTH_USERS" ]; then
        log "👥 Setting up multiple users..."
        > /etc/nginx/.htpasswd

        echo "$AUTH_USERS" | tr ',' '\n' | while IFS=':' read -r username password; do
            if [ ! -z "$username" ] && [ ! -z "$password" ]; then
                log "   ➕ Adding user: $username"
                htpasswd -b /etc/nginx/.htpasswd "$username" "$password"
            else
                log "   ⚠️  WARNING: Invalid format: $username:$password"
            fi
        done
    fi

    if [ ! -s /etc/nginx/.htpasswd ]; then
        log "❌ ERROR: No valid authentication credentials created"
        exit 1
    fi

    local user_count=$(wc -l < /etc/nginx/.htpasswd)
    log "✅ Authentication configured for $user_count user(s)"
}

# Start nginx
start_nginx() {
    log "🌐 Testing nginx configuration..."
    nginx -t
    if [ $? -ne 0 ]; then
        log "❌ ERROR: Nginx configuration test failed"
        exit 1
    fi

    log "🌐 Starting nginx..."
    nginx

    sleep 2
    if ! pgrep nginx > /dev/null; then
        log "❌ ERROR: Nginx failed to start"
        exit 1
    fi
    log "✅ Nginx started successfully"
}

start_asynqmon() {
    log "📊 Starting asynqmon..."

    export ASYNQMON_PORT=${ASYNQMON_PORT:-"8080"}

    log "📊 Configuration:"
    log "   Port: $ASYNQMON_PORT"

    ASYNQMON_CMD="/usr/local/bin/asynqmon --port=$ASYNQMON_PORT"

    if [ ! -z "$REDIS_CLUSTER_NODES" ]; then
        log "   Redis mode: Cluster"
        log "   Cluster nodes: $REDIS_CLUSTER_NODES"
        ASYNQMON_CMD="$ASYNQMON_CMD --redis-cluster-nodes=$REDIS_CLUSTER_NODES"
        if [ ! -z "$REDIS_PASSWORD" ]; then
            ASYNQMON_CMD="$ASYNQMON_CMD --redis-password=$REDIS_PASSWORD"
        fi

    elif [ ! -z "$REDIS_URL" ]; then
        log "   Redis mode: URL"
        log "   Redis URL: $REDIS_URL"
        ASYNQMON_CMD="$ASYNQMON_CMD --redis-url=$REDIS_URL"

    else
        export REDIS_ADDR=${REDIS_ADDR:-"localhost:6379"}
        export REDIS_DB=${REDIS_DB:-"0"}
        log "   Redis mode: Standalone"
        log "   Redis addr: $REDIS_ADDR"
        log "   DB: $REDIS_DB"
        ASYNQMON_CMD="$ASYNQMON_CMD --redis-addr=$REDIS_ADDR --redis-db=$REDIS_DB"
        if [ ! -z "$REDIS_PASSWORD" ]; then
            ASYNQMON_CMD="$ASYNQMON_CMD --redis-password=$REDIS_PASSWORD"
        fi
    fi

    if [ $# -gt 0 ]; then
        ASYNQMON_CMD="$ASYNQMON_CMD $@"
    fi

    log "🚀 Ready! Access Asynqmon at http://localhost (with basic auth)"

    exec $ASYNQMON_CMD
}


trap 'log "🛑 Shutting down..."; kill $(jobs -p) 2>/dev/null; exit 0' TERM INT

main() {
    validate_auth
    setup_auth
    start_nginx
    start_asynqmon "$@"
}

main "$@"