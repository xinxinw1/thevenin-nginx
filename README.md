# Xin-Xin's server

Runs on the `thevenin` droplet, provisioned from
[cloud-config](https://github.com/xinxinw1/cloud-config)'s `thevenin/cloud-init.yaml`.
That cloud-init installs Docker and drops a `~/setup.sh` that mounts the
`thevenin-data` volume, clones this repo, and brings the stack up. The commands
below are for day-to-day operation and for recovering by hand.

## Which domain it runs on

Nothing in `templates-insecure/` or `templates-secure/` names a domain. Both
directories are nginx *templates*: the nginx image renders
`/etc/nginx/templates/*.template` into `/etc/nginx/conf.d` on every container
start, substituting the `SITE_*` environment variables. So the same checkout
serves `xin-xin.me`, `dev.xin-xin.me`, `xin-xin-dev.me` or `localhost` depending
only on the env file it is started with.

| Variable | Meaning |
| --- | --- |
| `SITE_DOMAIN` | The domain this instance answers on. `server_name`, the `unsafe.` and `stage.` vhosts and phpmyadmin's absolute URI are all derived from it. |
| `SITE_ALT_NAMES` | Extra names the main vhost also answers to, space separated. Optional. Spelled out in full, not derived from `SITE_DOMAIN`. |
| `SITE_CERT_NAME` | The certbot lineage name, i.e. the directory under `certbot/conf/live` holding `fullchain.pem` and `privkey.pem`. Defaults to `SITE_DOMAIN`. |

`SITE_CERT_NAME` is separate from `SITE_DOMAIN` because a lineage is named once,
when certbot first issues it, and renaming one means re-issuing it. Production
still serves from a lineage named after the old `new.xin-xin.me` hostname, so
`.env` pins it.

To bring the stack up on a different domain, copy `.env` and edit the `SITE_*`
lines. `--env-file` replaces `.env` rather than layering on top of it, so the
copy needs `DATA_DIR` too.

```
$ cp .env .env.local    # .env.local is gitignored
$ $EDITOR .env.local
$ docker compose --env-file .env.local up -d --remove-orphans
```

A new domain still needs DNS pointing at the droplet and a certificate of its
own — see [Initialize certificate](#initialize-certificate) — but no file in
this repo has to change for it.

The envsubst step is filtered to variables matching `^SITE_`, so nginx's own
`$host`, `$request_uri` and `$http_upgrade` pass through the templates
untouched. Adding a new variable means naming it `SITE_*` and adding it to
`x-site-env` in `docker-compose.yml`.

## Update and start server

```
$ docker compose pull
$ docker compose up -d --remove-orphans
```

### First-time initialization

Copy `.env.secrets.example` to `.env.secrets` and set a mysql root password
before the first `docker compose up`. It is only applied while the mysql data
directory is still empty — on a volume that already holds a database, mysql
keeps its existing password and this file is ignored.

Then go to `https://<SITE_DOMAIN>/phpmyadmin` and log in as root.

### Locally

```
$ docker compose --env-file .env.dev up -d --remove-orphans
```

`--env-file` is a `docker compose` flag, not an `up` flag, so it goes before the
subcommand.

## Restart all services (update nginx config)

```
$ docker compose restart
```

A restart re-runs the nginx entrypoint, so edits to `templates-insecure/` and
`templates-secure/` are picked up. Changes to the `SITE_*` variables are not: an
environment change needs the containers recreated.

```
$ docker compose up -d --force-recreate webserver-insecure webserver-secure
```

## Stop server

```
$ docker compose down
```

## Initialize certificate

`templates-secure/` needs four files to exist before nginx will load its config:
the certificate, the private key, `options-ssl-nginx.conf` and `ssl-dhparams.pem`.
The last two ship in this repo; copy them into the data directory, then bring
the stack up and issue the certificate.

```
$ sudo cp data/certbot/conf/options-ssl-nginx.conf data/certbot/conf/ssl-dhparams.pem /mnt/thevenin_data/certbot/conf/
$ docker compose up -d
$ docker compose run --rm --entrypoint sh certbot -c 'certbot certonly --webroot --webroot-path /var/www/certbot/ --cert-name "$SITE_CERT_NAME" -d "$SITE_DOMAIN"'
$ docker compose restart webserver-secure
```

The certbot container gets the same `SITE_*` variables as nginx, so running the
command through `sh -c` lets it read the domain out of whichever env file the
stack was started with instead of repeating it here. Add another `-d <name>` for
each name in `SITE_ALT_NAMES` that should be on the certificate.

Between the second and third commands `webserver-secure` restart-loops, because
the certificate it references does not exist yet. That is expected and harmless:
`webserver-insecure` on `:80` is what serves the ACME challenge, and
`restart: unless-stopped` would bring the secure container up on its own even
without the explicit `restart`. Nothing on `:443` works until issuance completes.

`--cert-name` pins the lineage name. Without it certbot derives the name from
`renewal/<name>.conf` and falls back to `<name>-0001` if one already exists.

**Do not clear `live/<name>/` by hand to "make room" for a new certificate.**
certbot names a lineage from `renewal/<name>.conf`, not from `live/`. With the
live files gone it can no longer load the old lineage to recognise it as a
duplicate, but the renewal conf still blocks reuse of the name — so it issues
into `live/<name>-0001/`, which `SITE_CERT_NAME` does not point at, and nginx
serves the stale certificate with no obvious error.

To remove a lineage, use certbot, which clears the renewal conf, archive and
live directory together:

```
$ docker compose run --rm certbot certificates
$ docker compose run --rm certbot delete --cert-name new.xin-xin.me
```

`options-ssl-nginx.conf` and `ssl-dhparams.pem` come from this repo rather than
from certbot's GitHub. Both are public certbot defaults, and copying them keeps
a fresh droplet off the network for this step. They were fetched from
`certbot/src/certbot/_internal/plugins/nginx/tls_configs/` and
`certbot/src/certbot/` -- upstream has moved those paths at least once, so pin a
release tag rather than a branch if you ever re-sync them.

### Manual renew

```
$ docker compose run --rm certbot renew
```

## Set up local env

`.env.dev` points `DATA_DIR` at `./data`, which already contains
`options-ssl-nginx.conf` and `ssl-dhparams.pem` — two of the four files
`templates-secure/` needs. The certificate and key are gitignored, so generate a
self-signed pair once per checkout. `.env.dev` sets `SITE_DOMAIN` and
`SITE_CERT_NAME` to `localhost`, so that is the lineage directory to create:

```
$ mkdir -p data/certbot/conf/live/localhost
$ openssl req -x509 -nodes -newkey rsa:4096 -days 365 \
    -keyout data/certbot/conf/live/localhost/privkey.pem \
    -out data/certbot/conf/live/localhost/fullchain.pem \
    -subj '/CN=localhost'
```

Then `docker compose --env-file .env.dev up -d` brings `webserver-secure` up on
`https://localhost`. Browsers will warn about the certificate, which is fine
locally. Nothing generates this for you — production gets a real certificate
from certbot, so the self-signed pair exists only for local dev.

If you point `.env.dev` at some other name, create the lineage directory under
whatever `SITE_CERT_NAME` says and pass the same name to `-subj '/CN=...'`.
