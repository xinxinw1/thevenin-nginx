# Xin-Xin's server

## Update and start server

```
$ docker compose pull
$ docker compose up -d --remove-orphans
```

### Locally

```
$ docker compose up --env-file .env.dev -d --remove-orphans
```

## Restart all services (update nginx config)

```
$ docker compose restart
```

## Stop server

```
$ docker compose down
```

## Initialize certificate

```
$ docker compose up -d
$ docker compose run --rm certbot certonly --webroot --webroot-path /var/www/certbot/ -d new.xin-xin.me
$ curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf | sudo tee -a "/mnt/thevenin_data/certbot/conf/options-ssl-nginx.conf"
$ curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem | sudo tee -a "/mnt/thevenin_data/certbot/conf/ssl-dhparams.pem"
```

### Manual renew

```
$ docker compose run --rm certbot renew
```

## Set up local env

### Create certificate

```
$ sudo mkdir -p data/certbot/conf/live/new.xin-xin.me
$ sudo openssl req -x509 -nodes -newkey rsa:4096 -days 1 -keyout data/certbot/conf/live/new.xin-xin.me/privkey.pem -out data/certbot/conf/live/new.xin-xin.me/fullchain.pem -subj '/CN=localhost'
```
