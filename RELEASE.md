# Vela: production deployment and GoatCounter migration

This fork keeps GoatCounter’s database schema, CLI name, tracking endpoint, and import/export formats. The production Compose file deliberately keeps the project name `goatcounter` and volume key `goatcounter-data` so the default existing volume remains `goatcounter_goatcounter-data`.

## Production deployment with SQLite

`compose.production.yaml` binds the app to `127.0.0.1:8080`, reuses the existing Compose project and SQLite volume names, runs as the unprivileged container user, drops Linux capabilities, enables automatic restart, and checks `/status`. Put the existing HTTPS reverse proxy in front of this local port; do not expose port 8080 directly to the internet.

First test with a restored copy of the live volume on a staging host. Confirm the app reports healthy, login works, dashboards load, counts arrive at `/count`, and historical totals match. Keep the old image and a verified backup until the Vela instance has run successfully in production.

Run these commands from the Vela repository. Stop the old app before taking a consistent full-volume backup; the archive includes the database and other persisted files:

```sh
docker compose --profile goatcounter-sqlite stop goatcounter-sqlite
docker run --rm \
  -v goatcounter_goatcounter-data:/data:ro \
  -v "$PWD:/backup" \
  alpine:3.24.3 \
  tar -C /data -czf /backup/goatcounter-before-vela.tar.gz .
docker compose -f compose.production.yaml up -d --build
docker compose -f compose.production.yaml ps
docker compose -f compose.production.yaml logs --tail=100 vela
```

Keep `goatcounter-before-vela.tar.gz` outside Docker’s volume storage and verify it can be read before upgrading. The Compose project name and `goatcounter-data` volume key must remain unchanged to reuse the current data. Check the actual volume name on the host if the existing install set a custom Compose project name or volume. Never run the new container against a new empty volume and mistake it for a successful migration.

The container keeps the upstream `goatcounter` executable and `serve -automigrate` startup. Schema migrations run automatically. If you need to roll back after a schema migration, stop Vela and restore the pre-upgrade backup to a separate volume; start the old image against that restored volume. Do not point an older binary at a database schema it may not support, and do not overwrite the only backup.

## PostgreSQL

For an existing PostgreSQL installation, back up the database first, keep its connection string, and point Vela at the same database. Do not create an empty database for the cutover. The PostgreSQL service in `compose.yaml` uses a development password and is intended for local development; do not expose it or use it for production.

## Website tracker

If the public stats hostname stays the same, keep the existing `data-goatcounter` URL and point its reverse proxy to Vela. If the hostname changes, update only the endpoint and script URL, for example:

```html
<script data-goatcounter="https://stats.example.org/count"
        async src="https://stats.example.org/count.js"></script>
```

The current `count.js` does not send query strings unless `track_query: true` is set. This also disables UTM campaign attribution by default. Frozen SRI scripts (`count.v1.js` through `count.v5.js`) retain their historical behavior; move to the current `count.js` to get the safer default.

## Reverse proxy, health, and privacy

Preserve the original `Host` header and configure forwarded IP headers as documented for GoatCounter before enabling IP-based features. The health endpoint is `/status`; the Compose health check calls it through the local port. Block `/status` at the public reverse proxy because its response includes runtime and database version details. Check health after deployment and monitor container restarts and logs. Keep credentials out of source control and restrict access to the analytics dashboard.

The analytics service does not use cookies for visitor tracking. Its current visit counting temporarily uses IP and User-Agent in memory, while path names, referrers, event names, and campaign values can still reveal personal information if the site sends it. For sites visited by minors, review data collection, URL and event contents, retention, public dashboard access, and applicable legal requirements before enabling production collection. Privacy-friendly analytics does not by itself guarantee compliance in every jurisdiction or configuration.

## Release status

The builder uses a pinned Go toolchain and installs the C compiler required by SQLite CGO. The runtime image includes CA certificates for HTTPS and GeoIP database downloads. The Docker image has built locally, but no production image has been published and no migration has been exercised against a real GoatCounter database. Staging migration, restore, and rollback remain required before live cutover.