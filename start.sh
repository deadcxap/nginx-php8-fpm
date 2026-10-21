#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -n "${COMPOSERMIRROR:-}" ]]; then
    composer config --global repos.packagist composer "$COMPOSERMIRROR"
fi
if [[ -n "${NPMMIRROR:-}" ]]; then
    if command -v npm >/dev/null; then
        npm config set registry "$NPMMIRROR"
    else
        echo 'NPMMIRROR requires the image with Node.js.' >&2
        exit 1
    fi
fi

# Apply user-provided configuration before environment overrides.
for pair in 'nginx.conf:/etc/nginx/nginx.conf' \
            'nginx-site.conf:/etc/nginx/conf.d/default.conf' \
            'nginx-site-ssl.conf:/etc/nginx/conf.d/default-ssl.conf'; do
    source_file="/var/www/html/conf/${pair%%:*}"
    if [[ -f "$source_file" ]]; then
        cp "$source_file" "${pair#*:}"
    fi
done

if [[ -n "${WEBROOT:-}" ]]; then
    escaped_webroot=$(printf '%s' "$WEBROOT" | sed 's/[\\&|]/\\&/g')
    for config in /etc/nginx/conf.d/default*.conf; do
        [[ -f "$config" ]] || continue
        sed -i -E "s|^([[:space:]]*root[[:space:]]+)[^;]*;|\\1${escaped_webroot};|" "$config"
    done
fi

if [[ "${HIDE_NGINX_HEADERS:-1}" == 0 ]]; then
    sed -i 's/server_tokens off;/server_tokens on;/' /etc/nginx/nginx.conf
else
    sed -i 's/server_tokens on;/server_tokens off;/' /etc/nginx/nginx.conf
fi

# Restarting must not append duplicate settings.
runtime_ini=/usr/local/etc/php/conf.d/zz-runtime.ini
{
    printf 'display_errors = %s\n' "$([[ "${ERRORS:-0}" == 1 ]] && echo On || echo Off)"
    printf 'expose_php = %s\n' "$([[ "${HIDE_NGINX_HEADERS:-1}" == 0 ]] && echo On || echo Off)"
    for setting in PHP_MEM_LIMIT:memory_limit PHP_POST_MAX_SIZE:post_max_size \
                   PHP_UPLOAD_MAX_FILESIZE:upload_max_filesize; do
        variable=${setting%%:*}
        value=${!variable:-}
        if [[ -n "$value" ]]; then
            if [[ ! "$value" =~ ^[0-9]+$ ]]; then
                echo "$variable must be an integer number of MiB." >&2
                exit 1
            fi
            printf '%s = %sM\n' "${setting#*:}" "$value"
        fi
    done
    if [[ -n "${PHP_REDIS_SESSION_HOST:-}" ]]; then
        if [[ ! "$PHP_REDIS_SESSION_HOST" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
            echo 'PHP_REDIS_SESSION_HOST must be a hostname or IPv4 address.' >&2
            exit 1
        fi
        printf 'session.save_handler = redis\nsession.save_path = "tcp://%s:6379"\n' "$PHP_REDIS_SESSION_HOST"
    fi
    if [[ -n "${TZ:-}" ]]; then
        if [[ "$TZ" == /* || "$TZ" == *..* || ! -f "/usr/share/zoneinfo/$TZ" ]]; then
            echo "Unknown timezone: $TZ" >&2
            exit 1
        fi
        printf 'date.timezone = "%s"\n' "$TZ"
        ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime
        printf '%s\n' "$TZ" > /etc/timezone
    fi
} > "$runtime_ini"

real_ip_conf=/etc/nginx/conf.d/00-real-ip.conf
rm -f "$real_ip_conf"
if [[ "${REAL_IP_HEADER:-0}" == 1 ]]; then
    trusted_proxy=${REAL_IP_FROM:-172.16.0.0/12}
    if [[ ! "$trusted_proxy" =~ ^[a-zA-Z0-9.:/_-]+$ ]]; then
        echo 'REAL_IP_FROM must contain one trusted address, hostname or CIDR.' >&2
        exit 1
    fi
    printf 'real_ip_header X-Forwarded-For;\nset_real_ip_from %s;\n' "$trusted_proxy" > "$real_ip_conf"
fi

# Xdebug is optional; install it in a derived development image if needed.
if [[ "${ENABLE_XDEBUG:-0}" == 1 ]]; then
    docker-php-ext-enable xdebug
fi

if [[ "${CREATE_LARAVEL_STORAGE:-0}" == 1 ]]; then
    mkdir -p /var/www/html/storage/{logs,app/public,framework/{cache/data,sessions,testing,views}}
    chown -R nginx:nginx /var/www/html/storage
    if ! id sail >/dev/null 2>&1; then
        adduser -s /bin/bash -G www-data -D sail
    fi
fi

if [[ "${RUN_SCRIPTS:-0}" == 1 ]]; then
    shopt -s nullglob
    for script in /var/www/html/scripts/*; do
        [[ -f "$script" ]] || continue
        chmod 750 "$script"
        "$script"
    done
fi

nginx -t
php-fpm -t
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
