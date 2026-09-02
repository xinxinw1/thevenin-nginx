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
If any is missing, `webserver-secure` restart-loops. So seed a self-signed
placeholder first and let the stack come up cleanly, then swap in the real
certificate.

```
$ sudo mkdir -p /mnt/thevenin_data/certbot/conf/live/new.xin-xin.me
$ sudo openssl req -x509 -nodes -newkey rsa:4096 -days 365 \
    -keyout /mnt/thevenin_data/certbot/conf/live/new.xin-xin.me/privkey.pem \
    -out /mnt/thevenin_data/certbot/conf/live/new.xin-xin.me/fullchain.pem \
    -subj '/CN=new.xin-xin.me'
$ sudo cp data/certbot/conf/options-ssl-nginx.conf /mnt/thevenin_data/certbot/conf/
$ sudo cp data/certbot/conf/ssl-dhparams.pem /mnt/thevenin_data/certbot/conf/
$ docker compose up -d
```

With DNS for `new.xin-xin.me` pointing at this droplet, clear the placeholder
and issue the real certificate:

```
$ sudo rm -rf /mnt/thevenin_data/certbot/conf/live/new.xin-xin.me
$ docker compose run --rm certbot certonly --webroot --webroot-path /var/www/certbot/ --cert-name new.xin-xin.me -d new.xin-xin.me
$ docker compose restart webserver-secure
```

**Only run that `rm -rf` when no lineage exists yet** — that is, when
`certbot/conf/renewal/new.xin-xin.me.conf` is absent and the only thing in
`live/` is the self-signed placeholder. It is needed because certbot refuses to
create a lineage over a non-empty live directory.

If a renewal conf already exists, deleting `live/` is what *causes* a
`new.xin-xin.me-0001` lineage. certbot picks the name from
`renewal/<name>.conf`, not from `live/`: it opens that conf `O_EXCL` and falls
back to `<name>-0001` when it already exists. With the live files gone certbot
can no longer load the old lineage to recognise it as a duplicate, but the
renewal conf still blocks reuse of the name — so it issues into `-0001`, which
nothing in `conf-secure/` references, and nginx keeps serving the placeholder
with no obvious error. `--cert-name` pins the name so this cannot happen
silently.

To remove a lineage, use certbot rather than deleting directories — it clears
the renewal conf, archive and live directory together, and it is that asymmetry
that causes the problem above:

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
`options-ssl-nginx.conf` and `ssl-dhparams.pem`. The certificate and key are
gitignored, so generate a self-signed pair:

```
$ sudo mkdir -p data/certbot/conf/live/new.xin-xin.me
$ sudo openssl req -x509 -nodes -newkey rsa:4096 -days 365 -keyout data/certbot/conf/live/new.xin-xin.me/privkey.pem -out data/certbot/conf/live/new.xin-xin.me/fullchain.pem -subj '/CN=localhost'
```
