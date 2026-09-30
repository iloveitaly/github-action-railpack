#!/bin/bash
set -e

REGISTRY_PORT=5001
REGISTRY_NAME="kind-registry-test"
IMAGE_NAME="localhost:$REGISTRY_PORT/railpack-test/app:latest"

# Cleanup function
cleanup() {
  echo "🧹 Cleaning up..."
  docker stop $REGISTRY_NAME 2>/dev/null || true
  docker rm $REGISTRY_NAME 2>/dev/null || true
  docker buildx rm $BUILDER_NAME 2>/dev/null || true
}
trap cleanup EXIT

# 1. Start local registry
echo "🚀 Starting local registry on port $REGISTRY_PORT..."
cleanup # Pre-cleanup
docker run -d -p $REGISTRY_PORT:5000 --name $REGISTRY_NAME registry:2

# 2. Setup environment for entrypoint.sh
export INPUT_PLATFORMS="linux/amd64,linux/arm64"
export INPUT_TAGS="$IMAGE_NAME"
export INPUT_PUSH="true"
export INPUT_CONTEXT="example"
export GITHUB_REPOSITORY="railpack-test/app"
export GITHUB_SHA="test-sha"
export INPUT_CACHE="false"
export INPUT_ENV="EXAMPLE_SECRET=secret
EXAMPLE_URL=http://localhost:8080"

# Create a dummy builder to isolate test
BUILDER_NAME="railpack-test-builder"
docker buildx create --name $BUILDER_NAME --driver docker-container --use --driver-opt network=host

# 3. Run the entrypoint script
echo "▶️  Running entrypoint.sh..."
./entrypoint.sh

# 4. Verify the manifest list
echo "🔍 Verifying manifest list..."
INSPECT_OUTPUT=$(docker buildx imagetools inspect $IMAGE_NAME)
echo "$INSPECT_OUTPUT"

if echo "$INSPECT_OUTPUT" | grep -q "linux/amd64" && echo "$INSPECT_OUTPUT" | grep -q "linux/arm64"; then
  echo "✅ Success! Manifest list contains both AMD64 and ARM64 platforms."
else
  echo "❌ Failure! Manifest list missing expected platforms."
  exit 1
fi
