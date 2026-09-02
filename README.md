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
If any is missing, `webserver-secure` restart-loops.

On a fresh host the real certificate does not exist yet, so point nginx at a
throwaway directory holding a self-signed placeholder. `CERT_DIR` controls only
what `webserver-secure` mounts at `/etc/letsencrypt`; certbot always reads and
writes the real `${DATA_DIR}/certbot/conf` tree, so issuance is unaffected.

```
$ mkdir -p placeholder-certs/live/new.xin-xin.me
$ openssl req -x509 -nodes -newkey rsa:4096 -days 365 \
    -keyout placeholder-certs/live/new.xin-xin.me/privkey.pem \
    -out placeholder-certs/live/new.xin-xin.me/fullchain.pem \
    -subj '/CN=new.xin-xin.me'
$ cp data/certbot/conf/options-ssl-nginx.conf data/certbot/conf/ssl-dhparams.pem placeholder-certs/
$ sudo cp data/certbot/conf/options-ssl-nginx.conf data/certbot/conf/ssl-dhparams.pem /mnt/thevenin_data/certbot/conf/
$ CERT_DIR=$PWD/placeholder-certs docker compose up -d
```

Both copies are needed: `conf-secure/` includes those two files from
`/etc/letsencrypt/` whichever directory `CERT_DIR` points at, and certbot never
writes them itself under `certonly --webroot`. So the real tree needs them for
after the switch-back, and the placeholder tree needs them for right now.

The whole stack now comes up on the first attempt, serving a browser trust
warning on `:443` until the real certificate lands.

With DNS for `new.xin-xin.me` pointing at this droplet, issue it and switch back
to the real tree:

```
$ docker compose run --rm certbot certonly --webroot --webroot-path /var/www/certbot/ --cert-name new.xin-xin.me -d new.xin-xin.me
$ docker compose up -d
```

The second `up -d` is not a typo for `restart`: changing `CERT_DIR` changes a
volume mount, and `docker compose restart` reuses the existing container with
its original mounts. Only `up -d` recreates it. Dropping the override falls back
to `CERT_DIR` from `.env`, which points at the real tree.

Nothing is ever written into certbot's `live/` directory by hand. That matters:
certbot derives a lineage name from `renewal/<name>.conf`, not from `live/`, so
deleting `live/<name>/` while the renewal conf survives makes certbot unable to
recognise the existing lineage but still unable to reuse its name — it then
issues into `live/<name>-0001/`, which `conf-secure/` does not reference, and
nginx serves the stale certificate with no obvious error. Keeping the
placeholder in a separate directory removes that whole failure mode, and
`--cert-name` pins the name regardless.

To remove a lineage, use certbot rather than deleting directories — it clears
the renewal conf, archive and live directory together:

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

`.env.dev` points both `DATA_DIR` and `CERT_DIR` at `./data/certbot/conf`, which
already contains `options-ssl-nginx.conf` and `ssl-dhparams.pem`. The
certificate and key are gitignored, so generate a self-signed pair:

```
$ sudo mkdir -p data/certbot/conf/live/new.xin-xin.me
$ sudo openssl req -x509 -nodes -newkey rsa:4096 -days 365 -keyout data/certbot/conf/live/new.xin-xin.me/privkey.pem -out data/certbot/conf/live/new.xin-xin.me/fullchain.pem -subj '/CN=localhost'
```
