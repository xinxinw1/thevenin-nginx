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
$ curl -fsSL https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf \
    | sudo tee /mnt/thevenin_data/certbot/conf/options-ssl-nginx.conf
$ curl -fsSL https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem \
    | sudo tee /mnt/thevenin_data/certbot/conf/ssl-dhparams.pem
$ docker compose up -d
```

With DNS for `new.xin-xin.me` pointing at this droplet, remove the placeholder
and issue the real certificate:

```
$ sudo rm -rf /mnt/thevenin_data/certbot/conf/live/new.xin-xin.me
$ docker compose run --rm certbot certonly --webroot --webroot-path /var/www/certbot/ -d new.xin-xin.me
$ docker compose restart webserver-secure
```

The `rm -rf` matters: certbot treats an existing `live/new.xin-xin.me/` as a
lineage name that is already taken and issues into `live/new.xin-xin.me-0001/`
instead, which nothing in `conf-secure/` references — so nginx would keep
serving the placeholder with no obvious error.

Use `tee`, not `tee -a`, for the two config files. Appending on a re-run
duplicates the nginx directives and concatenates a second PEM block onto
`ssl-dhparams.pem`.

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
