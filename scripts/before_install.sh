#!/bin/bash

set -e

echo "Preparing application deployment..."

systemctl start docker

mkdir -p /opt/telecom-cicd

docker stop telecom-cicd-pipeline || true
docker rm telecom-cicd-pipeline || true

echo "Previous application container removed."