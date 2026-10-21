# syntax=docker/dockerfile:1

# Floating release channels are intentional. build.sh refreshes them on every run.
ARG PHP_IMAGE=php:fpm-alpine
ARG NODE_IMAGE=node:lts-alpine
ARG COMPOSER_IMAGE=composer:latest
ARG EXTENSION_INSTALLER_IMAGE=ghcr.io/mlocati/php-extension-installer:latest

FROM ${NODE_IMAGE} AS nodejs
FROM ${COMPOSER_IMAGE} AS composer
FROM ${EXTENSION_INSTALLER_IMAGE} AS extension-installer

FROM ${PHP_IMAGE} AS without-node

ARG APKMIRROR=dl-cdn.alpinelinux.org
ARG IMAGE_SOURCE=https://github.com/deadcxap/nginx-php8-fpm
ARG IMAGE_REVISION=unknown
ARG IMAGE_CREATED
ARG IMAGE_VERSION=local
ARG IPE_PROCESSOR_COUNT=4

LABEL org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.url="${IMAGE_SOURCE}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${IMAGE_CREATED}" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.licenses="BSD-3-Clause" \
      org.opencontainers.image.title="nginx + PHP-FPM" \
      org.opencontainers.image.authors="deadcxap; original project by tangramor"

ENV TZ=UTC \
    COMPOSERMIRROR="" \
    NPMMIRROR=""

WORKDIR /var/www/html

COPY --from=extension-installer /usr/bin/install-php-extensions /usr/local/bin/
COPY --from=composer /usr/bin/composer /usr/local/bin/composer
COPY --chmod=755 scripts/install-nginx.sh /usr/local/bin/install-nginx

# No version constraints: always install available updates, including base OS fixes.
# hadolint ignore=DL3018
RUN set -eux; \
    if [ "$APKMIRROR" != "dl-cdn.alpinelinux.org" ]; then \
        sed -i "s|dl-cdn.alpinelinux.org|${APKMIRROR}|g" /etc/apk/repositories; \
    fi; \
    apk upgrade --no-cache; \
    apk add --no-cache \
        bash bash-completion ca-certificates coreutils curl gettext git \
        icu-data-full imagemagick jpegoptim libstdc++ libwebp-tools \
        mysql-client openldap-clients openssl postgresql-client shadow \
        sqlite supervisor tzdata unzip zip; \
    install-nginx; \
    rm /usr/local/bin/install-nginx

# The installer manages build/runtime dependencies and removes build tools.
# Stable PECL releases replace the old version-specific Imagick source patch.
RUN install-php-extensions \
        bcmath exif gd gettext intl ldap mysqli opcache pdo_mysql pdo_pgsql \
        pgsql soap sockets zip \
        amqp-stable brotli-stable igbinary-stable imagick-stable imap-stable \
        memcached-stable mongodb-stable msgpack-stable redis-stable \
    && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && rm -rf /tmp/pear /root/.cache

COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY conf/default.conf /etc/nginx/conf.d/default.conf
COPY conf/supervisord.conf /etc/supervisord.conf
COPY conf/php-fpm.conf /etc/supervisor/conf.d/php-fpm.conf
COPY conf/php-pool.conf /usr/local/etc/php-fpm.d/zzz-app.conf
COPY conf/php-defaults.ini /usr/local/etc/php/conf.d/docker-vars.ini
COPY --chmod=755 start.sh /start.sh
COPY LICENSE /usr/share/licenses/nginx-php8-fpm/LICENSE

RUN mkdir -p /var/log/supervisor /var/cache/nginx /run \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    && nginx -t \
    && php-fpm -t \
    && composer --version

EXPOSE 80 443
STOPSIGNAL SIGTERM
CMD ["/start.sh"]

FROM without-node AS with-node

LABEL org.opencontainers.image.title="nginx + PHP-FPM + Node.js"

# Copy Node/npm only, without overwriting the PHP installation in /usr/local.
COPY --from=nodejs /etc/alpine-release /tmp/node-alpine-release
COPY --from=nodejs /usr/local/bin/node /usr/local/bin/node
COPY --from=nodejs /usr/local/lib/node_modules/ /usr/local/lib/node_modules/

# build.sh selects a Node image for the same Alpine release automatically.
# Direct docker builds fail explicitly if upstream floating tags diverge.
RUN set -eux; \
    test "$(cut -d. -f1,2 /etc/alpine-release)" = "$(cut -d. -f1,2 /tmp/node-alpine-release)"; \
    rm /tmp/node-alpine-release; \
    ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm; \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx; \
    node --version; \
    npm --version
