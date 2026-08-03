#!/bin/sh
# Deploy the Crafty chart with Helm over SSH.
#
# No image import step: unlike the build-then-deploy pipelines in this homelab, the
# Crafty image is pulled from registry.gitlab.com by the node itself. All this does is
# put the chart on the host and run helm.
set -e

# Config comes from the step's env block in config.yaml. Fail loudly rather than
# deploying something unintended if a fork forgets one.
: "${DEPLOY_HOST:?DEPLOY_HOST is required (user@host)}"
: "${RELEASE:?RELEASE is required (helm release name)}"
: "${NAMESPACE:?NAMESPACE is required}"
: "${REPO:?REPO is required (owner/name on GitHub)}"
BRANCH="${BRANCH:-main}"
CHART_PATH="${CHART_PATH:-helm}"

apk add --no-cache openssh-client curl

# SSH key auth. The key is mounted from the pipeline's own k8s secret.
mkdir -p ~/.ssh
echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
HOST_ONLY="${DEPLOY_HOST#*@}"
ssh-keyscan -H "$HOST_ONLY" >> ~/.ssh/known_hosts 2>/dev/null || true

# Fetch this repo for the chart. GITHUB_TOKEN is only needed if the repo is private;
# a public repo (the default for this one) needs no credentials at all.
mkdir -p /tmp/repo
cd /tmp/repo
if [ -n "$GITHUB_TOKEN" ]; then
  curl -fsSL -H "Authorization: token $GITHUB_TOKEN" \
    -o repo.tar.gz "https://api.github.com/repos/$REPO/tarball/$BRANCH"
else
  curl -fsSL -o repo.tar.gz "https://api.github.com/repos/$REPO/tarball/$BRANCH"
fi
tar xzf repo.tar.gz --strip-components=1
rm repo.tar.gz

[ -d "/tmp/repo/$CHART_PATH" ] || { echo "chart not found at $CHART_PATH"; exit 1; }

REMOTE_CHART="/tmp/$RELEASE-helm-$NAMESPACE"
ssh -o StrictHostKeyChecking=no "$DEPLOY_HOST" "rm -rf $REMOTE_CHART"
scp -o StrictHostKeyChecking=no -r "/tmp/repo/$CHART_PATH" "$DEPLOY_HOST:$REMOTE_CHART"

# --wait so a failed rollout fails the pipeline instead of reporting a green deploy
# over a CrashLooping pod. The timeout is generous: a panel upgrade restarts the pod,
# and the pod does not go ready until Crafty has finished its migrations.
ssh -o StrictHostKeyChecking=no "$DEPLOY_HOST" \
  "cd $REMOTE_CHART && helm upgrade --install $RELEASE . -n $NAMESPACE --create-namespace \
     --wait --timeout 10m \
   && cd / && rm -rf $REMOTE_CHART"

echo "Deployed $RELEASE to $NAMESPACE on $DEPLOY_HOST"
