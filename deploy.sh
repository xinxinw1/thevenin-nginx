#!/bin/bash
set -e
set -o pipefail

# Rebuild the stack and restart the nginx containers -- the whole deploy, once
# the app checkouts beside this one have been pulled.
#
# The restart is not redundant. nginx resolves a literal hostname in proxy_pass
# once, when it loads its config, and then caches that address for the life of
# the worker -- it never re-checks DNS. (That same load-time resolution is why a
# name that does not resolve fails config load outright with "host not found in
# upstream".) Rebuilding main-website or text-edit recreates the container with a
# new IP on the compose network, and nothing about that recreates the
# webservers, so they go on dialing the old address and answer 502. Nothing
# notices until someone reloads them: webserver-secure heals itself within 6h
# from the reload loop in docker-compose.yml, and webserver-insecure never does.
#
# On a fresh create the restart is redundant -- nginx resolved the new IPs on the
# way up anyway -- and costs a second, so this does not bother deciding.
#
# A restart also re-runs the nginx entrypoint, which re-renders
# templates-insecure/ and templates-secure/, so template edits ship too. What it
# does not pick up is a changed SITE_* value: those are baked into the
# container's environment at create time, so an .env change needs the containers
# recreated instead:
#
#   docker compose up -d --force-recreate webserver-insecure webserver-secure
#
# Arguments are passed to docker compose ahead of the subcommand, so a checkout
# without a .env can hand over the env file the stack needs:
#
#   ./deploy.sh --env-file .env.dev
cd "$(dirname "$0")"

echo "=== Building and starting the stack ==="
# up takes --pull, so this needs no separate pull pass. --pull always refreshes
# the registry images; main-website and text-edit have no registry image, and
# compose builds those rather than failing on them. --build on every run so
# source just pulled into the sibling checkouts actually ships; with nothing
# changed it is all layer cache and costs seconds. No --no-cache (it would
# discard that cache) and no --force-recreate (compose already recreates
# whatever changed; forcing it just bounces the containers that did not).
docker compose "$@" up -d --build --pull always --remove-orphans

echo "=== Restarting the nginx containers ==="
docker compose "$@" restart webserver-insecure webserver-secure
