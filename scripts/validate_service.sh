#!/bin/bash

set -e

echo "Validating application..."

for i in {1..10}
do
    if curl -f http://localhost:5000/health; then
        echo "Application health check passed."
        exit 0
    fi

    echo "Application not ready yet. Attempt $i/10..."
    sleep 5
done

echo "Application health check failed."
exit 1