# nginx + PHP-FPM + Node.js

An independently built image published from this fork to
`ghcr.io/deadcxap/nginx-php8-fpm`. It includes nginx, PHP-FPM, Composer, common PHP
extensions and, by default, Node.js/npm. Both `linux/amd64` and `linux/arm64` are
built and tested on native GitHub runners.

The original project is [tangramor/nginx-php8-fpm](https://github.com/tangramor/nginx-php8-fpm).
Its BSD-3-Clause license and attribution are retained. The build no longer uses
the original author's prebuilt image.

## Update policy

| Component | Default source |
| --- | --- |
| PHP | Official `php:fpm-alpine`, latest stable PHP and default Alpine release |
| Node.js | Official `node:lts-alpine<release>`, latest LTS on the same Alpine release as PHP |
| npm | Latest stable `npm@latest`, with fresh dependencies within its declared version ranges |
| nginx and dynamic modules | Latest packages from the official nginx mainline repository |
| Composer | Official `composer:latest` |
| PHP extensions | Bundled PHP extensions and stable PECL releases |
| System packages | Latest available packages in the selected stable Alpine repositories |

There are no fixed runtime version numbers in the build. `build.sh` pulls the
current PHP image, resolves its digest for that build, reads its Alpine release,
and selects the matching Node.js Alpine variant. This digest is resolved again
on every invocation; it is not a permanent pin. Builds use `--pull --no-cache`
and `apk upgrade --no-cache` so both base images and installed packages refresh.

PHP extensions are installed with
[mlocati/docker-php-extension-installer](https://github.com/mlocati/docker-php-extension-installer),
using the latest installer image. It manages their native dependencies and removes
temporary build tools. Imagick uses a stable release without the previous local
source patch. Composer is copied from its official image instead of downloading
an installer over HTTP. npm and its bundled runtime dependencies are refreshed
separately because even the newest npm release can contain outdated dependencies.
This respects npm's declared version ranges and enforces Node engine compatibility;
it does not force incompatible dependency versions. Optional mirrors are disabled
by default.

Floating channels also bring major upgrades. A new PHP release may temporarily
be incompatible with an extension, or the matching Node/nginx Alpine packages
may not yet exist. The build then fails and the published tags stay on the last
successful release. There is no fallback to an older release or prerelease.
Keep an eye on failed Actions runs: `latest` means the latest **successful** build,
not a guarantee that all known vulnerabilities have been fixed.

## Image tags

| Tag | Contents |
| --- | --- |
| `latest` | nginx + PHP-FPM + Composer + Node.js/npm |
| `without-node` | nginx + PHP-FPM + Composer |
| `build-<run-id>-<attempt>` | A particular successful build with Node.js |
| `build-<run-id>-<attempt>-without-node` | The corresponding build without Node.js |

Both moving tags and the build tags contain amd64/arm64 manifests. The workflow
also retains architecture-specific build tags. Build tags are unique per workflow
attempt and are never reused by this workflow, even when the source commit has
not changed. To roll back, use an earlier build tag or an image digest. Only
`latest` and `without-node` move automatically.

After the first successful publication:

```sh
docker pull ghcr.io/deadcxap/nginx-php8-fpm:latest
docker run --rm -p 8080:80 \
  -v "$PWD:/var/www/html" \
  -e WEBROOT=/var/www/html/public \
  ghcr.io/deadcxap/nginx-php8-fpm:latest
```

The repository does not include an application or TLS certificates. Supply your
application under `/var/www/html`; use port 443 with your own nginx TLS config.
An already running container is not updated by a new image publication: pull
the new image and recreate the container in your deployment.

## GitHub Actions and first publication

The workflow in `.github/workflows/images.yml` runs:

- on pushes to `master`;
- on pull requests, with testing only and no package write permission;
- daily at **03:17 UTC** (06:17 Moscow time);
- manually through **Actions → Build, test and publish images → Run workflow**;
- through an authenticated `repository_dispatch` event of type `rebuild`.

For each variant and architecture it builds once, records installed versions,
tests the image, saves that same image as an archive, and scans it with Trivy.
The gate rejects **HIGH/CRITICAL vulnerabilities with available fixes**. The full
JSON report also retains lower-severity and unfixed issues. Scanner/database
errors fail the job; they do not bypass the gate. Reports are Actions artifacts
retained for 30 days.

Only after all four builds pass does a separate publishing job load those
archives and push them to GHCR. It does not rebuild them. It creates unique build
tags before updating the moving tags. A build, test or scan failure does not
update either moving tag. Registry operations are not a transaction: a network
error during the final two tag updates can leave them on different builds.

To activate publication:

1. Commit and push these files to `master` in your fork.
2. Enable GitHub Actions for the fork if GitHub requests it. The repository's
   Actions policy must allow the GitHub/Docker actions used by the workflow.
3. Run the workflow or let the push trigger it. The publish job uses the automatic
   `GITHUB_TOKEN` with `packages: write`; no Docker Hub account or custom PAT is
   needed for publishing from Actions.
4. Open the new package under your GitHub account. If anonymous pulls are desired,
   change its visibility to **Public** in the package settings. New GHCR packages
   are private by default, even when the repository is public.

The workflow derives the GHCR namespace and OCI source label from the repository
running it. For this fork that is `ghcr.io/deadcxap/nginx-php8-fpm`. If a package
with that name already exists, grant the repository Actions access to it in the
package settings before publishing.

GitHub Actions are pinned to specific commit identifiers, independently of the
floating runtime channels. Dependabot checks those action references weekly.
Review and merge its update PRs to refresh the workflow tools.

### Keeping an inactive repository building

GitHub can disable scheduled workflows in public repositories after 60 days
without repository activity. Daily builds do not provide a reliable exception
to this rule. For unattended operation, use a scheduler outside this repository
to send a `rebuild` event, or re-enable the schedule when GitHub disables it.

For example, run this on your existing scheduler with an authenticated GitHub
CLI identity that can dispatch events to the repository:

```sh
gh api --method POST repos/deadcxap/nginx-php8-fpm/dispatches \
  -f event_type=rebuild
```

The workflow must exist on the default branch. The external scheduler and its
credentials are configured separately; no external job is created by this repo.
If GitHub has disabled the entire workflow, re-enable it before dispatching.
See [GitHub's schedule documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).

## Local build and checks

Requires Bash, Docker Engine and Docker Buildx. The scripts build for the local
Docker architecture by default; use native runners or configured emulation for
another platform.

```sh
# Full image; every invocation refreshes dependencies.
./build.sh

# Same Dockerfile, without-node target.
./build.withoutNodejs.sh

# Choose the newest Current Node.js channel instead of LTS.
NODE_CHANNEL=current IMAGE=nginx-php8-fpm:current ./build.sh

# Use a local tag and run the same checks as CI.
IMAGE=nginx-php8-fpm:test ./build.sh
./scripts/smoke-test.sh nginx-php8-fpm:test with-node
./scripts/image-info.sh nginx-php8-fpm:test

# Scan the exact exported image; exits nonzero if the publication gate fails.
docker image save -o /tmp/nginx-php8-fpm.tar nginx-php8-fpm:test
./scripts/scan-image.sh /tmp/nginx-php8-fpm.tar ./reports
```

`IMAGE`, `TARGET`, `PLATFORM`, `PHP_IMAGE`, `NODE_CHANNEL`, `NODE_IMAGE`,
`APKMIRROR`, and OCI `IMAGE_*` metadata can be overridden through environment
variables. Extra `build.sh` arguments are passed to Buildx. For example, reduce
extension compilation parallelism with `--build-arg IPE_PROCESSOR_COUNT=2`.

Direct `docker build --pull --no-cache --target with-node .` also works when
the default floating PHP and Node tags use the same Alpine release. The script
is preferred because it automatically matches Alpine releases. A mismatched
direct build fails rather than publishing potentially incompatible binaries.

The former `Dockerfile.withoutNodejs` and duplicated startup script have been
replaced by the shared `without-node` target and `start.sh`. The old
`build.withoutNodejs.sh` command remains available as a wrapper.

## Runtime configuration

| Variable | Default / behavior |
| --- | --- |
| `WEBROOT` | `/var/www/html`; use `/var/www/html/public` for Laravel |
| `TZ` | `UTC`; accepts installed timezone names such as `Europe/Moscow` |
| `PHP_MEM_LIMIT` | `128` MiB; integer |
| `PHP_POST_MAX_SIZE` | `100` MiB; integer |
| `PHP_UPLOAD_MAX_FILESIZE` | `100` MiB; integer |
| `ERRORS` | Set to `1` to display PHP errors; disabled by default |
| `HIDE_NGINX_HEADERS` | `1`; set to `0` to expose nginx/PHP versions |
| `PHP_REDIS_SESSION_HOST` | Optional hostname/IPv4 for Redis sessions on port 6379 |
| `COMPOSERMIRROR` | Optional Composer repository URL |
| `NPMMIRROR` | Optional npm registry URL; requires the Node variant |
| `REAL_IP_HEADER` | Set to `1` to trust `X-Forwarded-For` from `REAL_IP_FROM` |
| `REAL_IP_FROM` | One trusted address/hostname/CIDR; default `172.16.0.0/12` |
| `CREATE_LARAVEL_STORAGE` | Set to `1` to create writable Laravel storage directories and the `sail` user |
| `RUN_SCRIPTS` | Set to `1` to run files in `/var/www/html/scripts/` in filename order |
| `ENABLE_XDEBUG` | Set to `1` only in a derived image with Xdebug installed; use current `XDEBUG_MODE` / `XDEBUG_CONFIG` settings |

PHP/nginx errors and access logs go to container logs. PHP error logging to stderr
is always enabled, so `PHP_ERRORS_STDERR` is no longer needed. The default timezone
changed from `Asia/Shanghai` to `UTC`. Mirror overrides are opt-in. Node/npm are
included; Yarn is not bundled.

On startup, the following optional application files are copied before applying
environment overrides:

| Application file | Destination |
| --- | --- |
| `/var/www/html/conf/nginx.conf` | `/etc/nginx/nginx.conf` |
| `/var/www/html/conf/nginx-site.conf` | `/etc/nginx/conf.d/default.conf` |
| `/var/www/html/conf/nginx-site-ssl.conf` | `/etc/nginx/conf.d/default-ssl.conf` |

nginx and PHP-FPM workers run as `nginx`; Supervisor starts as root. PHP-FPM
listens on `/var/run/php-fpm.sock`. Make application files readable by the worker
and writable application directories writable by it. Runtime PHP settings are
regenerated on startup, so restarting does not accumulate duplicate directives.

## PHP extensions and derived images

Besides the official PHP image's built-in extensions, the image installs:

```text
amqp bcmath brotli exif gd gettext igbinary imagick imap intl ldap
memcached mongodb msgpack mysqli opcache pdo_mysql pdo_pgsql pgsql
redis soap sockets zip
```

The smoke test checks required modules, GD JPEG/FreeType/WebP support, PNG
encoding with Imagick, a Brotli round trip and SQLite through PDO. It also tests
Node crypto, offline npm packing/installation and npx execution, HTTP execution of PHP, static files, missing PHP files,
runtime overrides, Laravel directory permissions and container restart.

To install another extension in your own image:

```dockerfile
FROM ghcr.io/deadcxap/nginx-php8-fpm:latest
RUN install-php-extensions xdebug-stable
COPY . /var/www/html
ENV WEBROOT=/var/www/html/public
```

Application Composer/npm dependencies remain your application's responsibility.
Use the version reports and build tags to test application compatibility before
deploying a newly built base image.
