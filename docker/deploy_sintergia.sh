#!/usr/bin/env bash
#
# Deploys a Sintergia image on the VPS. Run it here, by hand, when you want to
# update -- there is no push-based deploy and nothing needs SSH access inward.
#
#   ./deploy_sintergia.sh latest    # newest build on the produccion branch
#   ./deploy_sintergia.sh 9d1ea6b   # a specific build
#   ./deploy_sintergia.sh v1.0.0    # a release
#
# Passing `latest` is a request for "whatever is newest", not a request to run
# an image called latest: the script pulls it, reads the immutable tag out of
# the image labels, and pins THAT in .env. So `docker compose ps` always names
# a real build, a reboot can never swap the running version underneath you, and
# rolling back is this same script with the previous tag.
#
# Lives in /opt/sintergia next to docker-compose.production.yaml and .env.

set -euo pipefail

IMAGE="ghcr.io/alnroot/sintergia"

TAG="${1:-}"
if [ -z "$TAG" ]; then
  echo "usage: $0 <latest|short-sha|v1.2.3>" >&2
  exit 1
fi

APP_DIR="${SINTERGIA_DIR:-/opt/sintergia}"
cd "$APP_DIR"

compose() {
  docker compose -f docker-compose.production.yaml "$@"
}

PREVIOUS_TAG="$(grep -oP '(?<=^SINTERGIA_TAG=).*' .env || echo 'none')"
echo "==> currently deployed: ${PREVIOUS_TAG}"

# Resolve :latest to the build it currently points at, so what lands in .env is
# always something we can come back to.
if [ "$TAG" = "latest" ]; then
  echo "==> resolving ${IMAGE}:latest"
  docker pull "${IMAGE}:latest"
  RESOLVED="$(docker image inspect --format \
    '{{index .Config.Labels "org.opencontainers.image.version"}}' \
    "${IMAGE}:latest" 2>/dev/null || true)"

  if [ -z "$RESOLVED" ] || [ "$RESOLVED" = "<no value>" ]; then
    echo "ERROR: this image carries no org.opencontainers.image.version label, so" >&2
    echo "there is no immutable tag to pin. It predates the labelled build."       >&2
    echo "Pass an explicit tag instead: $0 <short-sha>"                            >&2
    exit 1
  fi
  echo "==> :latest is currently ${RESOLVED}"
else
  RESOLVED="$TAG"
fi

if [ "$RESOLVED" = "$PREVIOUS_TAG" ]; then
  echo "==> ${RESOLVED} is already deployed, nothing to do"
  exit 0
fi

echo "==> deploying ${IMAGE}:${RESOLVED}"

if grep -q '^SINTERGIA_TAG=' .env; then
  sed -i "s|^SINTERGIA_TAG=.*|SINTERGIA_TAG=${RESOLVED}|" .env
else
  printf '\nSINTERGIA_TAG=%s\n' "$RESOLVED" >> .env
fi

echo "==> pulling"
compose pull rails sidekiq

# Old workers must not process jobs against a schema that is mid-migration.
echo "==> stopping sidekiq"
compose stop sidekiq

# docker/entrypoints/rails.sh does NOT migrate, so this has to be explicit.
# chatwoot_prepare loads the schema + seeds on a fresh database and runs
# db:migrate on an existing one, so it is correct for both cases.
echo "==> migrating"
compose run --rm rails bundle exec rails db:chatwoot_prepare

echo "==> starting"
compose up -d rails sidekiq

compose ps
echo
echo "==> deployed ${RESOLVED}"
echo "    rollback: $0 ${PREVIOUS_TAG}"
