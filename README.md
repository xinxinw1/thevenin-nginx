# Xin-Xin's server

Runs on the `thevenin` droplet, provisioned from
[cloud-config](https://github.com/xinxinw1/cloud-config)'s `thevenin/cloud-init.yaml`.
That cloud-init installs Docker and drops a `~/setup.sh` that mounts the
`thevenin-data` volume, clones this repo, and brings the stack up. The commands
below are for day-to-day operation and for recovering by hand.

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

Then go to https://xin-xin.me/phpmyadmin and log in as root.

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

## Stop server

```
$ docker compose down
```

## Initialize certificate

`conf-secure/` needs four files to exist before nginx will load its config: the
certificate, the private key, `options-ssl-nginx.conf` and `ssl-dhparams.pem`.
The last two ship in this repo; copy them into the data directory, then bring
the stack up and issue the certificate.

```
$ sudo cp data/certbot/conf/options-ssl-nginx.conf data/certbot/conf/ssl-dhparams.pem /mnt/thevenin_data/certbot/conf/
$ docker compose up -d
$ docker compose run --rm certbot certonly --webroot --webroot-path /var/www/certbot/ --cert-name new.xin-xin.me -d new.xin-xin.me
$ docker compose restart webserver-secure
```

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
into `live/<name>-0001/`, which `conf-secure/` does not reference, and nginx
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
`conf-secure/` needs. The certificate and key are gitignored, so generate a
self-signed pair once per checkout:

```
$ mkdir -p data/certbot/conf/live/new.xin-xin.me
$ openssl req -x509 -nodes -newkey rsa:4096 -days 365 \
    -keyout data/certbot/conf/live/new.xin-xin.me/privkey.pem \
    -out data/certbot/conf/live/new.xin-xin.me/fullchain.pem \
    -subj '/CN=localhost'
```

Then `docker compose --env-file .env.dev up -d` brings `webserver-secure` up.
Browsers will warn about the certificate, which is fine locally. Nothing
generates this for you — production gets a real certificate from certbot, so the
self-signed pair exists only for local dev.
