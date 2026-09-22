#!/usr/bin/env bash
set -Eeuo pipefail

: "${IMAGE_TAGS:?IMAGE_TAGS is required}"
: "${IMAGE_DIGEST:?IMAGE_DIGEST is required}"
: "${SOURCE_SHA:?SOURCE_SHA is required}"
: "${RUN_URL:?RUN_URL is required}"

image_tag=${IMAGE_TAGS%%$'\n'*}
image_ref="${image_tag%@*}@${IMAGE_DIGEST}"
mkdir -p zenith-image-update

verified=""
for _ in $(seq 1 12); do
  if verified=$(python3 scripts/zenith-check-image.py "$image_ref"); then break; fi
  sleep 10
done
if [[ -z "$verified" ]]; then
  echo "Published image failed anonymous registry verification."
  exit 1
fi

config=$(mktemp -d)
cleanup() { rm -rf "$config"; }
trap cleanup EXIT
DOCKER_CONFIG="$config" docker pull --platform linux/amd64 "$image_ref"
bash scripts/zenith-smoke.sh "$image_ref"

python3 - "$image_ref" "$SOURCE_SHA" "$RUN_URL" "$verified" <<'PY'
import json
import pathlib
import sys

image, source_sha, run_url, verified = sys.argv[1:]
pathlib.Path("zenith-image-update/image.json").write_text(json.dumps({
    "image": image,
    "source_sha": source_sha,
    "workflow_run": run_url,
    "verification": json.loads(verified),
}, indent=2) + "\n")
PY

if [[ -f zenith-compose.yml ]]; then
  cp zenith-compose.yml zenith-image-update/zenith-compose.yml
  python3 - "$image_ref" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path("zenith-image-update/zenith-compose.yml")
text = path.read_text()
images = list(re.finditer(r"(?m)^\s+image:\s+([^\s]+)\s*$", text))
app = [match for match in images if "ghcr.io/${{ github.repository }}" in match.group(1) or "ghcr.io/l1mey112/crm" in match.group(1)]
if len(app) != 1:
    raise SystemExit("Expected one application image in zenith-compose.yml")
start, end = app[0].span(1)
path.write_text(text[:start] + sys.argv[1] + text[end:])
PY
  docker compose -f zenith-image-update/zenith-compose.yml config --quiet
  diff -u zenith-compose.yml zenith-image-update/zenith-compose.yml > zenith-image-update/zenith-compose.patch || true
fi

echo "Verified $image_ref"
