# Xin-Xin's server

Runs on the `thevenin` droplet, provisioned from
[cloud-config](https://github.com/xinxinw1/cloud-config)'s `thevenin/cloud-init.yaml`,
and on `thevenin-dev` from `thevenin-dev/cloud-init.yaml` — the same stack on
`xin-xin-test.me`, backed by its own NFS share. That cloud-init installs Docker
and drops a `~/setup.sh` that mounts the share, clones this repo along with
`xin-xin.me` and `text-edit` beside it, writes a `.env` for the host it is on,
and builds and brings the stack up. The commands below are for day-to-day
operation and for recovering by hand.

## Which domain it runs on

Nothing in `templates-insecure/` or `templates-secure/` names a domain. Both
directories are nginx *templates*: the nginx image renders
`/etc/nginx/templates/*.template` into `/etc/nginx/conf.d` on every container
start, substituting environment variables. One variable drives all of it:

| Variable | Meaning |
| --- | --- |
| `SITE_DOMAIN` | The single name this instance answers on. `server_name`, the `unsafe.` vhost, the certbot lineage under `certbot/conf/live` and phpmyadmin's absolute URI are all derived from it. |

So the same checkout serves `new.xin-xin.me`, `xin-xin-test.me` or `localhost`
depending only on the env file it is started with. The main vhost answers on
exactly that one name — no `www.` alias, no second spelling — and
anything else reaching the droplet falls through to `default.conf` and is
dropped with a 444 — with one deliberate exception, the health check below.

## Health check

`GET /healthcheck` on `:80` returns `200` with a body of exactly `ok`:

```
$ curl -i http://<droplet-ip>/healthcheck
```

It lives on `default.conf`, the catch-all, rather than on a named vhost,
because that is where a load balancer's probe lands: it reaches the droplet by
IP, so it arrives with an address for a `Host` header, some internal hostname,
or no `Host` header at all, and the catch-all answers to all three. The named
vhosts are unaffected and still answer on `SITE_DOMAIN` alone — which does mean
a probe sent *with* `Host: $SITE_DOMAIN` gets the 301 to `https://` instead, so
point the health check at the IP.

`:443` has no equivalent: a probe by IP could not match the certificate anyway.

Because the certbot lineage is named after `SITE_DOMAIN` too, a domain change is
also a new certificate: certbot names a lineage once, at issuance, and renaming
one means re-issuing it. See [Initialize certificate](#initialize-certificate).

Neither `SITE_DOMAIN` nor `DATA_DIR` has a value in this repo — they are inputs
to the stack, not properties of it. On a droplet `~/setup.sh` writes a `.env`
holding the pair its host type calls for, so `docker compose` there needs no
flags. Everywhere else, pass a file explicitly or copy `.env.example` to `.env`.

`--env-file` replaces `.env` rather than layering on top of it, so any such file
needs both variables.

```
$ cp .env.example .env.local    # .env.local is gitignored
$ $EDITOR .env.local
$ docker compose --env-file .env.local up -d --remove-orphans
```

A new domain still needs DNS pointing at the droplet, but no file in this repo
has to change for it.

The envsubst step is filtered to variables matching `^SITE_`, so nginx's own
`$host`, `$request_uri` and `$http_upgrade` pass through the templates
untouched. Adding a new variable means naming it `SITE_*` and adding it to
`x-site-env` in `docker-compose.yml`.

## Application images

`main-website` and `text-edit` are not pulled from a registry. They are built
from the two application repos, which have to sit **beside this checkout**:

```
~/git/
├── thevenin-nginx/   <- this repo
├── xin-xin.me/       <- built as main-website, listens on 8080
└── text-edit/        <- built as text-edit, listens on 80
```

`docker-compose.yml` names them as `../xin-xin.me` and `../text-edit`, relative
to this file, so the layout is the whole contract — there is no variable to
point somewhere else. On a droplet `~/setup.sh` clones all three into `~/git`;
everywhere else, clone them yourself.

Clone `xin-xin.me` with `--recurse-submodules`. Its `static/code/*` demos are
submodules and its Dockerfile copies the working tree, so a non-recursive clone
builds an image with empty directories instead of failing.

Three things `xin-xin.me` keeps out of git — `static/music`, `static/files` and
`email-config.json` — are therefore absent from a build. The compose file mounts
them from `${DATA_DIR}/xin-xin-me/` instead, so they live on the share rather
than in an image and survive every rebuild. `~/setup.sh` creates the two
directories and seeds an empty `email-config.json`; filling them in is a manual
copy onto the share. Until it happens `/music/*` and `/files/*` are 404 and the
contact form answers "Email not configured".

## Update and start server

```
$ ./deploy.sh
```

That is the whole deploy: pull the sibling app checkouts, run this, done. On a
droplet `~/deploy.sh` finds it without a `cd`, and `~/setup.sh` runs it
as its last step. It does two things:

```
$ docker compose up -d --build --pull always --remove-orphans
$ docker compose restart webserver-insecure webserver-secure
```

`up` takes `--pull`, so the first needs no separate `pull` pass. `--pull always`
refreshes the registry images; `main-website` and `text-edit` have no registry
image to pull, and compose builds those rather than failing on them. `--build`
rebuilds both from the sibling checkouts. A no-change rebuild is cheap — it is
all layer cache.

The restart is what keeps the site up. nginx resolves the hostname in a
`proxy_pass` once, at config load, and caches that address for the life of the
worker — the same load-time resolution that makes an unresolvable name fail
config load with "host not found in upstream". A rebuild gives `main-website` and
`text-edit` new IPs on the compose network, and nothing about that recreates the
webservers, so without the restart they go on dialing the old addresses and
answer 502. `webserver-secure` recovers on its own within 6h from its reload
loop; `webserver-insecure` never does.

### First-time initialization

Copy `.env.secrets.example` to `.env.secrets` and set a mysql root password
before the first `docker compose up`. (`~/setup.sh` does this for you on a
droplet, alongside the `.env` it generates.) It is only applied while the mysql data
directory is still empty — on a volume that already holds a database, mysql
keeps its existing password and this file is ignored.

Then go to `https://<SITE_DOMAIN>/phpmyadmin` and log in as root.

### Locally

```
$ ./deploy.sh --env-file .env.dev
```

Arguments go to `docker compose` ahead of the subcommand, which is where
`--env-file` has to be: it is a `docker compose` flag, not an `up` flag.

## Restart all services (update nginx config)

```
$ docker compose restart
```

A restart re-runs the nginx entrypoint, so edits to `templates-insecure/` and
`templates-secure/` are picked up — by `./deploy.sh` too, which restarts
both webservers. Changes to the `SITE_*` variables are not: those are baked into
a container's environment when it is created, so an environment change needs the
containers recreated.

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
$ docker compose run --rm --entrypoint sh certbot -c 'certbot certonly --webroot --webroot-path /var/www/certbot/ --cert-name "$SITE_DOMAIN" -d "$SITE_DOMAIN"'
$ docker compose restart webserver-secure
```

The certbot container gets the same `SITE_DOMAIN` as nginx, so running the
command through `sh -c` lets it read the domain out of whichever env file the
stack was started with instead of repeating it here.

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
into `live/<name>-0001/`, which `SITE_DOMAIN` does not point at, and nginx
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

First put the two application repos beside this one and create the asset paths
the compose file mounts into `main-website`:

```
$ git clone --recurse-submodules https://github.com/xinxinw1/xin-xin.me.git ../xin-xin.me
$ git clone https://github.com/xinxinw1/text-edit.git ../text-edit
$ mkdir -p data/xin-xin-me/music data/xin-xin-me/files
$ echo '{}' > data/xin-xin-me/email-config.json
```

The `echo` is load-bearing. `email-config.json` is a single-file bind mount, and
docker creates a *directory* at a host path that does not exist yet — which is
not something `require()` can load.

`.env.dev` points `DATA_DIR` at `./data`, which already contains
`options-ssl-nginx.conf` and `ssl-dhparams.pem` — two of the four files
`templates-secure/` needs. The certificate and key are gitignored, so generate a
self-signed pair once per checkout. `.env.dev` sets `SITE_DOMAIN` to
`localhost`, so that is the lineage directory to create:

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
whatever `SITE_DOMAIN` says and pass the same name to `-subj '/CN=...'`.
