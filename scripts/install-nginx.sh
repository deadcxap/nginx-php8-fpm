#!/bin/sh
set -eu

case "$(apk --print-arch)" in
    x86_64|aarch64) ;;
    *) echo 'Official nginx packages require amd64 or arm64.' >&2; exit 1 ;;
esac

addgroup -g 101 -S nginx
adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx nginx

# Trust anchor from https://nginx.org/en/linux_packages.html#Alpine.
# This is a signing-key checksum, not a pinned nginx release.
key_file=$(mktemp)
trap 'rm -f "$key_file"' EXIT
curl --fail --show-error --silent --location --retry 3 \
    https://nginx.org/keys/nginx_signing.rsa.pub -o "$key_file"
actual=$(openssl rsa -pubin -in "$key_file" -text -noout | openssl sha512 -r)
expected='de7031fdac1354096d3388d6f711a508328ce66c168967ee0658c294226d6e7a161ce7f2628d577d56f8b63ff6892cc576af6f7ef2a6aa2e17c62ff7b6bf0d98 *stdin'
if [ "$actual" != "$expected" ]; then
    echo 'nginx signing key verification failed.' >&2
    exit 1
fi
cp "$key_file" /etc/apk/keys/nginx_signing.rsa.pub

alpine_release=$(cut -d. -f1,2 /etc/alpine-release)
printf '@nginx https://nginx.org/packages/mainline/alpine/v%s/main\n' \
    "$alpine_release" >> /etc/apk/repositories
apk add --no-cache \
    nginx@nginx nginx-module-xslt@nginx nginx-module-geoip@nginx \
    nginx-module-image-filter@nginx nginx-module-njs@nginx nginx-module-acme@nginx
