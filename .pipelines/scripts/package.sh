#!/bin/sh
# Validate the chart and package it into the ArtifactBundle.
#
# This is the gate. Everything checkable without a cluster is checked here, so a typo
# in a template fails in a job rather than halfway through a helm upgrade against the
# live panel.
set -e

: "${REPO:?REPO is required (owner/name on GitHub)}"
BRANCH="${BRANCH:-main}"
CHART_PATH="${CHART_PATH:-helm}"

apk add --no-cache curl tar

# Fetch this repo. GITHUB_TOKEN is only needed for a private fork; this repo is public.
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

CHART="/tmp/repo/$CHART_PATH"
[ -d "$CHART" ] || { echo "chart not found at $CHART_PATH"; exit 1; }

echo "--- helm lint ---"
helm lint "$CHART"

# Render with the real release name and namespace. Catches template errors that lint
# alone does not, e.g. a bad range or an undefined value reference.
echo "--- helm template ---"
helm template crafty "$CHART" -n apps > /tmp/rendered.yaml
grep -q "kind: Deployment" /tmp/rendered.yaml || { echo "no Deployment rendered"; exit 1; }
grep -q "kind: Service" /tmp/rendered.yaml || { echo "no Service rendered"; exit 1; }
grep -q "kind: PersistentVolumeClaim" /tmp/rendered.yaml || { echo "no PVC rendered"; exit 1; }

# The image tag must be pinned. A chart resolving to :latest would silently upgrade the
# panel on every pod restart, so fail the build rather than ship it.
IMAGE=$(awk '/^[[:space:]]+image:/ {print $2; exit}' /tmp/rendered.yaml | tr -d '"')
echo "Chart image: $IMAGE"
case "$IMAGE" in
  *:latest) echo "refusing to ship an unpinned :latest image"; exit 1 ;;
  *:*) ;;
  *) echo "image has no tag: $IMAGE"; exit 1 ;;
esac

# Package into the bundle. The deploy step installs THIS artifact — the one just
# validated — instead of re-fetching the repo.
mkdir -p /output
helm package "$CHART" -d /output
mv /output/*.tgz /output/chart.tgz
date +%Y%m%d-%H%M%S > /output/version.txt
echo "$IMAGE" > /output/image.txt

echo "Packaged $(cat /output/version.txt) with $IMAGE"
ls -l /output
