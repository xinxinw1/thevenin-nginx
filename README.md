# Xin-Xin's server

## Initialize certificate

```
$ docker compose up
$ docker compose run --rm certbot certonly --webroot --webroot-path /var/www/certbot/ -d new.xin-xin.me
$ curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf | sudo tee -a "/mnt/thevenin_data/certbot/conf/options-ssl-nginx.conf"
$ curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem | sudo tee -a "/mnt/thevenin_data/certbot/conf/ssl-dhparams.pem"
```

### Manual renew

```
$ docker compose run --rm certbot renew
```
