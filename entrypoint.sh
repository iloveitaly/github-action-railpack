#!/bin/bash

set -e

if ! command -v railpack &>/dev/null; then
  echo "Installing RailPack..."
  curl -sSL https://railpack.com/install.sh | bash
fi

repository_author() {
  local repo=$1
  local owner_login owner_name owner_email owner_info

  if [ -z "$repo" ]; then
    echo "Error: Repository not specified."
    return 1
  fi

  # Fetch the owner's login (username)
  owner_login=$(gh repo view "$repo" --json owner --jq '.owner.login' | tr -d '[:space:]')

  # Fetch the owner's name, remove trailing and leading whitespace
  owner_name=$(gh api "users/$owner_login" --jq '.name' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Attempt to fetch the owner's publicly available email
  owner_email=$(gh api "users/$owner_login" --jq '.email' | tr -d '[:space:]')

  # Check if an email was fetched; if not, use just the name
  if [ -z "$owner_email" ] || [ "$owner_email" = "null" ]; then
    owner_info="$owner_name"
  else
    owner_info="$owner_name <$owner_email>"
  fi

  echo "$owner_info"
}

repository_license() {
  local repo=$1
  gh api /repos/$repo/license 2>/dev/null | jq -r '.license.key // ""'
}

GHCR_IMAGE_NAME="ghcr.io/$GITHUB_REPOSITORY"
RAILPACK_PLAN_FILE="/tmp/railpack-plan.json"

# Incorporate provided input parameters from actions.yml
if [ -n "${INPUT_TAGS}" ]; then
  read -ra TAGS <<<"$(echo "$INPUT_TAGS" | tr ',\n' ' ')"
else
  # if no tags are provided, assume ghcr.io as the default registry
  echo "No tags provided. Defaulting to ghcr.io registry."
  BUILD_DATE_TIMESTAMP=$(date +%s)
  TAGS=("$GHCR_IMAGE_NAME:$GIT_SHA" "$GHCR_IMAGE_NAME:latest" "$GHCR_IMAGE_NAME:$BUILD_DATE_TIMESTAMP")
fi

if [ -n "${INPUT_LABELS}" ]; then
  read -ra LABELS <<<"$(echo "$INPUT_LABELS" | tr ',\n' ' ')"
fi

# TODO should check if these labels are already defined
LABELS+=("org.opencontainers.image.source=$GITHUB_REPOSITORY_URL")
LABELS+=("org.opencontainers.image.revision=$GITHUB_SHA")
LABELS+=("org.opencontainers.image.created=\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"")

REPO_AUTHOR=$(repository_author "$GITHUB_REPOSITORY")
if [ -n "$REPO_AUTHOR" ]; then
  LABELS+=("org.opencontainers.image.authors=\"$REPO_AUTHOR\"")
fi

REPO_LICENSE=$(repository_license "$GITHUB_REPOSITORY")
if [ -n "$REPO_LICENSE" ]; then
  LABELS+=("org.opencontainers.image.licenses=\"$REPO_LICENSE\"")
fi

if [ -n "${INPUT_PLATFORMS}" ]; then
  read -ra PLATFORMS <<<"$(echo "$INPUT_PLATFORMS" | tr ',\n' ' ')"
fi

if [ "${#PLATFORMS[@]}" -gt 1 ] && [ "$INPUT_PUSH" != "true" ]; then
  echo "Multi-platform builds *must* be pushed to a registry. Please set 'push: true' in your action configuration or do a single architecture build."
  exit 1
fi

# Setup RailPack apt packages environment variable
# By default, install apt packages at runtime (deploy) which is what most users expect
if [ -n "${INPUT_APT}" ]; then
  # Convert comma/newline separated list to space-separated
  APT_PACKAGES=$(echo "$INPUT_APT" | tr ',\n' ' ')
  export RAILPACK_DEPLOY_APT_PACKAGES="$APT_PACKAGES"
  echo "Installing apt packages: $APT_PACKAGES"
fi

# Prepare environment variables to pass to railpack
PREPARE_ARGS=()
if [ -n "${INPUT_ENV}" ]; then
  IFS=',' read -ra ENVS <<<"$INPUT_ENV"
  for env_var in "${ENVS[@]}"; do
    PREPARE_ARGS+=("--env" "$env_var")
  done
fi

# Run railpack prepare to generate the build plan
echo "Running railpack prepare..."
# Use --plan-out to save the JSON plan to a file
railpack prepare "${PREPARE_ARGS[@]}" --plan-out "$RAILPACK_PLAN_FILE" "$INPUT_CONTEXT"

# Build docker buildx command
COMMON_ARGS="--build-arg BUILDKIT_SYNTAX=ghcr.io/railwayapp/railpack-frontend"
COMMON_ARGS="$COMMON_ARGS -f $RAILPACK_PLAN_FILE"

# Add labels
for label in "${LABELS[@]}"; do
  COMMON_ARGS="$COMMON_ARGS --label $label"
done

# Handle caching
if [[ "$INPUT_CACHE" == "true" ]]; then
  if [ -z "$INPUT_CACHE_TAG" ]; then
    INPUT_CACHE_TAG=$(echo "$GHCR_IMAGE_NAME" | tr '[:upper:]' '[:lower:]')
  fi
  COMMON_ARGS="$COMMON_ARGS --cache-from type=registry,ref=$INPUT_CACHE_TAG"
  COMMON_ARGS="$COMMON_ARGS --cache-to type=inline"
fi

if [ "${#PLATFORMS[@]}" -gt 1 ]; then
  echo "Detected multi-platform build. Building for each platform sequentially..."
  
  # 1. Build and push platform-specific images
  for plat in "${PLATFORMS[@]}"; do
    echo "Building for platform: $plat"
    SANITIZED_PLAT=$(echo "$plat" | tr '/' '-')
    
    PLAT_ARGS=""
    for tag in "${TAGS[@]}"; do
      PLAT_ARGS="$PLAT_ARGS --tag ${tag}-${SANITIZED_PLAT}"
    done
    
    # Multi-platform builds via this method must be pushed
    BUILD_CMD="docker buildx build $COMMON_ARGS --platform $plat $PLAT_ARGS --push $INPUT_CONTEXT"
    echo "Running: $BUILD_CMD"
    eval "$BUILD_CMD"
  done
  
  # 2. Create manifest lists
  echo "Merging platform images into manifest lists..."
  for tag in "${TAGS[@]}"; do
    SOURCES=""
    for plat in "${PLATFORMS[@]}"; do
      SANITIZED_PLAT=$(echo "$plat" | tr '/' '-')
      SOURCES="$SOURCES ${tag}-${SANITIZED_PLAT}"
    done
    
    MANIFEST_CMD="docker buildx imagetools create -t $tag $SOURCES"
    echo "Running: $MANIFEST_CMD"
    eval "$MANIFEST_CMD"
  done

else
  # Single platform or no platform specified
  BUILD_CMD="docker buildx build $COMMON_ARGS"

  # Add tags
  for tag in "${TAGS[@]}"; do
    BUILD_CMD="$BUILD_CMD --tag $tag"
  done

  # Add platforms if specified
  if [ -n "${PLATFORMS[*]}" ]; then
    PLATFORM_LIST=$(IFS=,; echo "${PLATFORMS[*]}")
    BUILD_CMD="$BUILD_CMD --platform $PLATFORM_LIST"
  fi

  # Handle push
  if [[ "$INPUT_PUSH" == "true" ]]; then
    BUILD_CMD="$BUILD_CMD --push"
  else
    BUILD_CMD="$BUILD_CMD --load"
  fi

  # Add context
  BUILD_CMD="$BUILD_CMD $INPUT_CONTEXT"

  echo "Executing RailPack build command via docker buildx:"
  echo "$BUILD_CMD"

  eval "$BUILD_CMD"
fi

echo "RailPack Build & Push completed successfully."
