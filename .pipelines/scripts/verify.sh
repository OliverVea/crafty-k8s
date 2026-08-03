#!/bin/sh
# Post-deploy verification.
#
# `helm --wait` proves the pod reached Ready. It does not prove Crafty actually serves,
# and it does not prove the running image is the one the chart specifies. Assert both,
# and fail the pipeline if either is wrong.
set -e

: "${DEPLOY_HOST:?DEPLOY_HOST is required (user@host)}"
: "${RELEASE:?RELEASE is required}"
: "${NAMESPACE:?NAMESPACE is required}"

apk add --no-cache openssh-client curl

mkdir -p ~/.ssh
echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
ssh-keyscan -H "${DEPLOY_HOST#*@}" >> ~/.ssh/known_hosts 2>/dev/null || true

INPUT_DIR=$(dirname "$(ls /input/*/version.txt | head -1)")
EXPECTED_IMAGE=$(cat "$INPUT_DIR/image.txt")

echo "--- rollout ---"
ssh -o StrictHostKeyChecking=no "$DEPLOY_HOST" \
  "kubectl -n $NAMESPACE rollout status deploy/$RELEASE --timeout=5m"

echo "--- running image ---"
# The jsonpath MUST stay single-quoted for the remote shell: the deploy host's login
# shell is zsh, which glob-expands the bare [0] and dies with "no matches found".
RUNNING=$(ssh -o StrictHostKeyChecking=no "$DEPLOY_HOST" \
  "kubectl -n $NAMESPACE get deploy/$RELEASE -o 'jsonpath={.spec.template.spec.containers[0].image}'")
echo "expected: $EXPECTED_IMAGE"
echo "running:  $RUNNING"
[ "$RUNNING" = "$EXPECTED_IMAGE" ] || { echo "image mismatch"; exit 1; }

# Pod-Ready is a TCP check. This asserts the panel actually answers HTTP.
if [ -n "$PANEL_URL" ]; then
  echo "--- panel responds ---"
  # -k: the panel serves a self-signed certificate by design.
  CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 30 "$PANEL_URL/login" || echo 000)
  echo "GET $PANEL_URL/login -> $CODE"
  [ "$CODE" = "200" ] || { echo "panel did not return 200"; exit 1; }
else
  echo "PANEL_URL unset — skipping HTTP check"
fi

echo "Verified $RELEASE in $NAMESPACE"
