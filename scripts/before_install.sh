#!/usr/bin/env bash
set -euo pipefail

echo 'Preparing instance for deployment...'
systemctl start docker
mkdir -p /opt/telecom-cicd
# Do not stop the old container here; after_install.sh pulls before replacement.
