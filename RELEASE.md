# Vela: release and GoatCounter migration

This fork keeps GoatCounter’s database schema, CLI name, tracking endpoint, and import/export formats. The Vela Docker Compose project deliberately keeps the project name `goatcounter` so the existing named volume remains `goatcounter_goatcounter-data`.

## Before production

1. Build and run this release against a copy of the current database.
2. Compare dashboard totals and confirm the existing site code still reaches the same `/count` endpoint.
3. Back up the production database and configuration. Keep the old image available for rollback.
4. Deploy Vela behind the existing HTTPS reverse proxy and retain the current analytics hostname where possible. The website tracker then needs no endpoint change.

The container still runs the `goatcounter` executable and uses its existing `serve -automigrate` startup, so database migrations run as they do for GoatCounter. Do not point the old binary at a database after a migration it does not support; restore the pre-upgrade backup before rollback.

## SQLite with Docker Compose

Run these commands from the Vela repository. Stop the service before copying the SQLite file so the backup is consistent:

```sh
docker compose --profile goatcounter-sqlite stop goatcounter-sqlite
docker run --rm \
  -v goatcounter_goatcounter-data:/data \
  -v "$PWD:/backup" \
  alpine:3.24.3 \
  cp /data/db.sqlite3 /backup/goatcounter-before-vela.sqlite3
docker compose --profile goatcounter-sqlite up -d --build goatcounter-sqlite
```

The Compose project name and `goatcounter-data` volume key must remain unchanged to reuse the current data. Check the volume name on the host before upgrading if the existing install set a custom Compose project name or volume.

## PostgreSQL with Docker Compose

Back up the database first, then build and restart the Vela service:

```sh
docker compose exec -T postgres pg_dump -U goatcounter -Fc goatcounter > goatcounter-before-vela.dump
docker compose --profile goatcounter-postgres up -d --build goatcounter-postgres
```

For an existing PostgreSQL installation outside this Compose project, keep its connection string and point Vela at the same database. Do not create an empty database for the cutover.

## Website tracker

If the public stats hostname stays the same, keep the existing `data-goatcounter` URL and point its reverse proxy to Vela. If the hostname changes, update only the endpoint and script URL, for example:

```html
<script data-goatcounter="https://stats.example.org/count"
        async src="https://stats.example.org/count.js"></script>
```

The current `count.js` does not send query strings unless `track_query: true` is set. This also disables UTM campaign attribution by default. Frozen SRI scripts (`count.v1.js` through `count.v5.js`) retain their historical behavior; move to the current `count.js` to get the safer default.

## Reverse proxy and checks

Expose the app only through the existing HTTPS proxy; keep the app listener private to the host/network. Preserve the original `Host` header and configure forwarded IP headers as documented for GoatCounter before enabling IP-based features. The health endpoint is `/status`.

The analytics service does not use cookies for visitor tracking. Its current visit counting temporarily uses IP and User-Agent in memory, while path names, referrers, event names, and campaign values can still reveal personal information if the site sends it. For sites visited by minors, review data collection, URL and event contents, retention, public dashboard access, and the applicable legal requirements before enabling production collection.

## Release status

The builder uses a pinned Go toolchain and installs the C compiler required by SQLite CGO. The runtime image includes CA certificates for HTTPS and GeoIP database downloads. This repository is prepared for a local Docker build. A production image has not been built or published, and the deployment steps have not been exercised against a real GoatCounter database. Do a staging migration and verify the backup/rollback procedure before the live cutover.
