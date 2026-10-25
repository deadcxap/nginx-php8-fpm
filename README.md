[Русская документация](README.ru.md)

# nginx + PHP-FPM + Node.js

An independently built image published from this fork to
`ghcr.io/deadcxap/nginx-php8-fpm`. It includes nginx, PHP-FPM, Composer, common PHP
extensions and, by default, Node.js/npm. Both `linux/amd64` and `linux/arm64` are
built and tested on native GitHub runners.

The original project is [tangramor/nginx-php8-fpm](https://github.com/tangramor/nginx-php8-fpm).
Its BSD-3-Clause license and attribution are retained. The build no longer uses
the original author's prebuilt image.

## Quick start with Docker Compose

Two standalone examples are included:

- [compose.yaml](compose.yaml) — nginx + PHP-FPM + Composer + Node.js/npm.
- [compose.without-node.yaml](compose.without-node.yaml) — the same stack without Node.js/npm.

Requires Docker Engine and the Docker Compose plugin (`docker compose`). Put your
PHP application in `app/` next to the Compose files; it is mounted at
`/var/www/html`. For Laravel or another application with a `public/` directory,
change `WEBROOT` in the chosen file to `/var/www/html/public`.

From the repository root, run one of the examples:

```sh
# With Node.js/npm:
docker compose up -d

# Or without Node.js/npm:
docker compose -f compose.without-node.yaml up -d
```

Open [http://localhost:8080](http://localhost:8080). Compose downloads the image
on first launch; see [first publication](#github-actions-and-first-publication)
if the GHCR image is not yet available or requires registry access.

Edit the host port (`8080`), timezone and worker IDs directly in the Compose file.
The examples use `PUID=1000`, `PGID=1000`, `UMASK=022`; on Linux, use the application
owner's `id -u` and `id -g`, or `PUID=99`, `PGID=100` on Unraid. Keep the default
root startup user so the image can apply these IDs before starting the workers.
Application dependency installation follows your project's own instructions.

Both files contain an optional MariaDB example **in comments**. To enable it,
uncomment the `db` service, the `db-data` volume and the application's `DB_*`
settings, and change the example passwords. The application connects to
`db:3306`; MariaDB data is kept in a named volume across `down`/`up`.

```sh
docker compose logs -f app
docker compose down

# Update the image and recreate the container:
docker compose pull
docker compose up -d
```

For the variant without Node.js, add `-f compose.without-node.yaml` to each
`docker compose` command. See [runtime configuration](#runtime-configuration)
for additional environment settings and writable-directory permissions.

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
| `latest-without-node` | nginx + PHP-FPM + Composer |
| `nginx<version>_php<version>_node<version>` | Image with the specified nginx, PHP and Node.js versions |
| `nginx<version>_php<version>` | Image with the specified nginx and PHP versions, without Node.js |

Version tags use the actual installed versions, including patch versions, for
example `nginx1.28.0_php8.5.2_node25.6.0` or `nginx1.28.0_php8.5.2`. These names
illustrate the format; available tags depend on successful builds. Versions must
match between amd64 and arm64 for each variant before publication.

Both the version tags and `latest` / `latest-without-node` contain amd64/arm64
manifests. Architecture-specific images use the same version tag with an
`-amd64` or `-arm64` suffix. A rebuild with the same nginx/PHP/Node.js versions
updates the existing version tag, since extensions, npm or system packages may
have changed. To pin an exact image or guarantee a rollback, use an image digest.
The former `without-node` and `build-*` tags are no longer published or updated;
existing registry tags are not deleted automatically.

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
- every Monday at **03:17 UTC** (06:17 Moscow time);
- manually through **Actions → Build, test and publish images → Run workflow**;
- through an authenticated `repository_dispatch` event of type `rebuild`.

For each variant and architecture it builds once, records installed versions,
tests the image, saves that same image and its version tag as artifacts, and
scans it with Trivy. The gate rejects **HIGH/CRITICAL vulnerabilities with available fixes**. The full
JSON report also retains lower-severity and unfixed issues. Scanner/database
errors fail the job; they do not bypass the gate. Reports are Actions artifacts
retained for 30 days.

Only after all four builds pass does a separate publishing job load those
archives and push them to GHCR. It does not rebuild them. It checks the version
tags recorded on the native runners, publishes both versioned manifests, then
updates `latest` and `latest-without-node`. A build, test, scan or version mismatch
failure does not update either moving tag. Registry operations are not a
transaction: a network error during the final two tag updates can leave them
on different builds.

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
without repository activity. Scheduled builds do not provide a reliable exception
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
| `PUID` | `101`; numeric user ID for nginx and PHP-FPM workers |
| `PGID` | `101`; numeric primary group ID for nginx and PHP-FPM workers |
| `UMASK` | `022`; mask for startup scripts and supervised processes, e.g. `002` or `0002` for group-writable files |
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

On every start and restart, the container also logs the installed Alpine, nginx,
PHP and Composer versions, Node.js/npm versions when present, and the version tag
derived from nginx/PHP/Node.js. The report lists enabled PHP modules, nginx build
options and installed nginx dynamic-module packages. View it with
`docker compose logs app`, or print it again with
`docker compose exec app runtime-info`. `runtime-info --tag` prints only the
version tag and is used by the publishing workflow.

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

For Unraid, set `PUID=99`, `PGID=100` and `UMASK=022` in the container template.
The `nginx` account uses those numeric IDs, including when the group ID already
exists in Alpine. IDs must be decimal integers from 1 to 4294967294; UID/GID 0
are rejected. `UMASK` accepts three octal digits with an optional leading zero.
Restarting preserves these settings. Keep the container's default root startup
user so it can configure the accounts before nginx/PHP-FPM drop privileges.

Application bind mounts are not automatically chowned or chmodded. Their writable
directories must already permit the selected UID/GID to write. The existing opt-in
`CREATE_LARAVEL_STORAGE=1` still creates and chowns Laravel's storage directory.
The mask affects newly created files; it does not change permissions of existing
files or grant access to directories. Default file modes are 0644 with `022` and
0664 with `002`, unless the application explicitly requests stricter permissions.

### Overriding nginx, PHP and Node.js settings

Runtime settings can be changed without rebuilding the image. Use the environment
variables above for common options and mount your own files for other settings.
For example, create `compose.override.yaml` next to `compose.yaml`:

```yaml
services:
  app:
    environment:
      PHP_MEM_LIMIT: "512"
      PHP_POST_MAX_SIZE: "128"
      PHP_UPLOAD_MAX_FILESIZE: "120"
      NODE_OPTIONS: "--max-old-space-size=1024"
    volumes:
      - ./docker/php.ini:/usr/local/etc/php/conf.d/zzz-custom.ini:ro
      - ./docker/nginx-site.conf:/var/www/html/conf/nginx-site.conf:ro
```

Compose automatically merges this file with `compose.yaml`, keeping the existing
application mount, ports and other environment variables. Create both mounted
files before starting the container so missing paths are not created as
directories.

Prepare the nginx site configuration from the repository root:

```sh
mkdir -p docker
cp conf/default.conf docker/nginx-site.conf
```

Edit `docker/nginx-site.conf` and add the following inside its existing `server`
block to allow the larger PHP uploads from the example:

```nginx
client_max_body_size 128m;
```

The site file replaces the complete default site configuration; it is not a
snippet. The nginx body limit and PHP `post_max_size` must accommodate the upload
and its request overhead, so the example leaves room above the 120 MiB file
limit. To replace the main nginx configuration, start from `conf/nginx.conf`
and mount your file at `/var/www/html/conf/nginx.conf`. The SSL site path is
listed in the table above.

On each start, `start.sh` copies these nginx files and then applies environment
overrides: `WEBROOT` rewrites `root` directives in `default*.conf`, and
`HIDE_NGINX_HEADERS` adjusts `server_tokens` in the main configuration. Mount
the source files at `/var/www/html/conf/` as shown; mounting the working files
directly at `/etc/nginx/nginx.conf` or `/etc/nginx/conf.d/default.conf` read-only
would prevent the startup script from updating them.

Create `docker/php.ini` with additional PHP settings, for example:

```ini
max_execution_time = 120
max_input_vars = 5000
opcache.memory_consumption = 256
```

The three `PHP_*` size variables in the Compose example accept integer MiB
values without an `M` suffix. PHP loads additional INI files in alphabetical
order, so `zzz-custom.ini` loads after the image defaults and the generated
`zz-runtime.ini`. If the same directive is set both by an environment variable
and in `zzz-custom.ini`, the custom file takes precedence. Do not edit
`zz-runtime.ini` directly: it is regenerated at every start. See the
[PHP configuration documentation](https://www.php.net/manual/en/configuration.file.php).

PHP-FPM pool settings such as `pm.max_children` belong in a separate `.conf`
file, not in `php.ini`. For example, create `docker/php-fpm.conf`:

```ini
[www]
pm.max_children = 32
pm.start_servers = 4
pm.min_spare_servers = 4
pm.max_spare_servers = 16
```

Add this entry to `services.app.volumes` in the override file:

```yaml
- ./docker/php-fpm.conf:/usr/local/etc/php-fpm.d/zzzz-custom.conf:ro
```

The filename places it after the bundled `zzz-app.conf`, overriding the specified
pool settings while keeping the existing worker user and socket configuration.

For Node.js, use [`NODE_OPTIONS`](https://nodejs.org/api/cli.html#node_optionsoptions)
for supported runtime flags. The example limits V8's old memory section to
1024 MiB; it does not set a limit for the entire container. Set `NPMMIRROR` to
change the npm registry. The image includes Node.js/npm but does not automatically
start a Node.js application. Configure a long-running application separately,
for example with a Supervisor program file in `/etc/supervisor/conf.d/`.

After editing Compose or the mounted files, validate the merged configuration
and recreate the container:

```sh
docker compose config --quiet
docker compose up -d --force-recreate app
docker compose logs app
```

For the variant without Node.js, omit `NODE_OPTIONS` and specify both files
explicitly on each command, for example:

```sh
docker compose -f compose.without-node.yaml -f compose.override.yaml up -d --force-recreate app
```

The startup script checks nginx and PHP-FPM configuration before starting their
processes. Use `docker compose exec app php --ini` to inspect the loaded PHP INI
files and `docker compose exec app nginx -T` to inspect the nginx configuration.

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
runtime overrides, Laravel directory permissions and container restart. Bind-mount
checks verify PHP worker IDs, ownership and modes of created files/directories,
nginx access, unchanged application ownership and invalid runtime settings.
It also checks version-tag generation and the startup report before and after
a restart. `python3 tests/publish-check.py` verifies publication tags and failure
handling without contacting a registry.

To install another extension in your own image:

```dockerfile
FROM ghcr.io/deadcxap/nginx-php8-fpm:latest
RUN install-php-extensions xdebug-stable
COPY . /var/www/html
ENV WEBROOT=/var/www/html/public
```

Application Composer/npm dependencies remain your application's responsibility.
Use the version reports and version tags to test application compatibility before
deploying a newly built base image.
