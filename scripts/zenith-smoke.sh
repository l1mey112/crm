#!/usr/bin/env bash
set -Eeuo pipefail

image=${1:?usage: scripts/zenith-smoke.sh IMAGE}
network="zenith-smoke-$RANDOM"
postgres="zenith-smoke-postgres-$RANDOM"
api="zenith-smoke-api-$RANDOM"
app="zenith-smoke-app-$RANDOM"
host_port="${ZENITH_SMOKE_PORT:-$((30000 + RANDOM % 1000))}"
app_host_port="$((host_port + 1))"
cleanup() {
  docker rm -f "$app" "$api" "$postgres" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$network" >/dev/null
docker run -d --name "$postgres" --network "$network" \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=crm \
  postgres:17-alpine >/dev/null

for _ in $(seq 1 60); do
  if docker exec "$postgres" pg_isready -U postgres -d crm >/dev/null 2>&1; then break; fi
  sleep 2
done

docker run -d --name "$api" --network "$network" --network-alias api \
  -e NODE_ENV=production \
  -e PORT=3001 \
  -e DATABASE_URL=postgresql://postgres:postgres@"$postgres":5432/crm?schema=public \
  -e BETTER_AUTH_SECRET=smoke-only-secret-regenerate-for-runtime \
  -e ALLOWED_SIGN_IN=smoke@example.test \
  -e API_URL=http://api:3001 \
  -e APP_URL=http://app:3000 \
  -p "$host_port:3001" \
  "$image" sh -c 'bun run db:deploy && bun run --filter=api start' >/dev/null

for _ in $(seq 1 60); do
  if curl --fail --silent --show-error http://127.0.0.1:"$host_port"/health >/dev/null 2>&1; then break; fi
  if ! docker inspect -f '{{.State.Running}}' "$api" 2>/dev/null | grep -q true; then
    docker logs "$api"
    exit 1
  fi
  sleep 2
done

if ! curl --fail --silent --show-error http://127.0.0.1:"$host_port"/health >/dev/null 2>&1; then
  docker logs "$api"
  exit 1
fi

docker run -d --name "$app" --network "$network" --network-alias app \
  -e NODE_ENV=production \
  -e PORT=3000 \
  -e DATABASE_URL=postgresql://postgres:postgres@"$postgres":5432/crm?schema=public \
  -e BETTER_AUTH_SECRET=smoke-only-secret-regenerate-for-runtime \
  -e ALLOWED_SIGN_IN=smoke@example.test \
  -e API_URL=http://api:3001 \
  -e NEXT_PUBLIC_API_URL=http://api:3001 \
  -p "$app_host_port:3000" \
  "$image" bun run --filter=app start >/dev/null

for _ in $(seq 1 60); do
  if curl --fail --silent --show-error http://127.0.0.1:"$app_host_port"/sign-in >/dev/null 2>&1; then exit 0; fi
  if ! docker inspect -f '{{.State.Running}}' "$app" 2>/dev/null | grep -q true; then
    docker logs "$app"
    exit 1
  fi
  sleep 2
done

docker logs "$app"
exit 1
