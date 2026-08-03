#!/bin/sh
# Install the packaged chart with Helm over SSH.
#
# No image import step: unlike the build-then-deploy pipelines in this homelab, the
# Crafty image is pulled from registry.gitlab.com by the node itself. This only puts
# the validated chart artifact on the host and runs helm.
set -e

: "${DEPLOY_HOST:?DEPLOY_HOST is required (user@host)}"
: "${RELEASE:?RELEASE is required (helm release name)}"
: "${NAMESPACE:?NAMESPACE is required}"

apk add --no-cache openssh-client

mkdir -p ~/.ssh
echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
ssh-keyscan -H "${DEPLOY_HOST#*@}" >> ~/.ssh/known_hosts 2>/dev/null || true

# Resolve the package step's bundle dir by the artifact it alone produces.
INPUT_DIR=$(dirname "$(ls /input/*/version.txt | head -1)")
VERSION=$(cat "$INPUT_DIR/version.txt")
echo "Deploying $RELEASE ($VERSION) to $NAMESPACE on $DEPLOY_HOST"

REMOTE="/tmp/$RELEASE-$NAMESPACE-$VERSION.tgz"
scp -o StrictHostKeyChecking=no "$INPUT_DIR/chart.tgz" "$DEPLOY_HOST:$REMOTE"

# Optional environment-specific overrides (VALUES_FILE, e.g. values-homelab.yaml).
# Absent by default so a fork deploys the generic chart.
HELM_VALUES=""
if [ -n "$VALUES_FILE" ]; then
  [ -f "$INPUT_DIR/$VALUES_FILE" ] || { echo "VALUES_FILE $VALUES_FILE not in bundle"; exit 1; }
  REMOTE_VALUES="/tmp/$RELEASE-$NAMESPACE-$VERSION-values.yaml"
  scp -o StrictHostKeyChecking=no "$INPUT_DIR/$VALUES_FILE" "$DEPLOY_HOST:$REMOTE_VALUES"
  HELM_VALUES="-f $REMOTE_VALUES"
  echo "Using overrides: $VALUES_FILE"
fi

# --wait gates on the rollout, so a CrashLooping pod fails the pipeline here rather
# than being reported green. Necessary but NOT sufficient — see verify.sh.
ssh -o StrictHostKeyChecking=no "$DEPLOY_HOST" \
  "helm upgrade --install $RELEASE $REMOTE -n $NAMESPACE --create-namespace $HELM_VALUES --wait --timeout 10m"
ssh -o StrictHostKeyChecking=no "$DEPLOY_HOST" "rm -f $REMOTE $REMOTE_VALUES"

echo "Deployed $RELEASE:$VERSION"
