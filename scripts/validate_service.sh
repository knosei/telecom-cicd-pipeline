#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source /opt/telecom-cicd/deployment.env

running_image=$(docker inspect --format '{{.Config.Image}}' telecom-cicd-pipeline 2>/dev/null || true)
if [[ "$running_image" != "$IMAGE_URI" ]]; then
    echo "Wrong or missing application container: expected ${IMAGE_URI}, found ${running_image}" >&2
    exit 1
fi

for i in {1..12}; do
    if curl --fail --silent --show-error --max-time 5 http://127.0.0.1:5000/health >/dev/null; then
        echo 'Application health check passed.'
        exit 0
    fi
    echo "Application not ready (attempt $i/12)."
    sleep 5
done

echo 'Application health check failed.' >&2
exit 1
