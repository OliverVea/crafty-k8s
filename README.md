# crafty-k8s

A Helm chart and CD pipeline that run [Crafty Controller 4](https://craftycontrol.com/) — a
self-hosted Minecraft server panel — on a k3s cluster.

## What this does and does not manage

**It manages the panel.** One pod, two volumes (worlds on NVMe, backups on the bulk HDD) and one
LoadBalancer service. That is the whole scope.

**It does not manage modpacks, versions, or worlds.** Which servers exist, what Minecraft version
and mod loader they run, and which modpack is installed are all created from Crafty's web UI and
live in the PVC as runtime state. None of it is in git.

That split is the point, not an omission:

- Modpacks change on someone else's release schedule. A modpack in git means a commit and a
  reconcile cycle every time you want to try one.
- Worlds are state. Git is for config. Backing a world with a git history is the wrong tool.
- It makes this repo reusable. Nothing here knows what you intend to play.

If you want declarative, pack-in-git Minecraft servers instead, use
[`itzg/minecraft-server`](https://github.com/itzg/docker-minecraft-server) directly with the pack
ID in your values file. That is a legitimate and simpler choice — it is just a different one.

## Deploy

```sh
helm upgrade --install crafty ./helm -n apps --create-namespace
```

Then open `https://<node-ip>:8443`. The panel serves a self-signed certificate, so expect a browser
warning. The first-boot admin password is written inside the pod:

```sh
kubectl exec -n apps deploy/crafty -- cat /crafty/app/config/default-creds.txt
```

Change it immediately; that file is written once on a fresh install and is not rotated.

## Configuration

See [`helm/values.yaml`](helm/values.yaml) — every value is commented with the reasoning, not just
the type. The ones that matter:

| Value | Default | Why |
|---|---|---|
| `image.tag` | `4.10.8` | Pinned. `latest` means a silent panel upgrade on every pod restart. |
| `persistence.storageClass` | `local-path` | Node NVMe for worlds. **Never** use NFS or network storage — chunk saves are latency-sensitive and produce hitching that reads as a mod bug. |
| `persistence.size` | `100Gi` | Worlds, panel database and logs. The PVC is annotated `helm.sh/resource-policy: keep`, so uninstalling the release does not delete your worlds. |
| `persistence.backups.storageClass` | `bulk` | Backups live on their own volume, off the NVMe. `bulk` is a **local** HDD, so the network-storage warning above does not apply — backups are large sequential writes that tolerate the latency. |
| `persistence.backups.size` | `50Gi` | Backup retention headroom. Also `keep`-annotated, so backups survive an uninstall. |
| `service.type` | `LoadBalancer` | On k3s, servicelb binds these ports on the node, which is how you get a real `25565`. NodePort's 30000-32767 range cannot. |
| `service.serverPorts` | `25565`, `25566` | One entry per Minecraft server you host. Add an entry when you add a server. |
| `resources.limits.memory` | `12Gi` | Must cover Crafty **plus every server JVM it spawns**. JVM metaspace and direct buffers live outside `-Xmx`, so a limit equal to the heap gets the pod OOM-killed mid-session. |
| `resources.requests.cpu` | `2` | Requests, but deliberately **no CPU limit**: CFS quota throttling mid-tick is the top cause of phantom TPS stutter on containerized Minecraft servers. |
| `podSecurityContext.fsGroup` | `0` | Crafty runs as a non-root user relying on root-group permissions on its `/crafty` mounts. Without this the volume is not writable. |
| `modsManifest.enabled` | `false` | Opt-in daily CronJob that writes a `mods-manifest.txt` (sha256 + size of every `*.jar`) into each server dir, so a fingerprint of the installed modpack rides along in every backup. Off by default to keep the chart mod-agnostic; on in `values-homelab.yaml`. |
| `logoutBackup.enabled` | `false` | Opt-in poller that fires a backup config when the last player leaves a server (Crafty only schedules backups on time intervals — there is no native "last logout" hook). Needs `serverId`, `backupConfigId`, and a scoped API key in a secret. See [Last-logout backups](#last-logout-backups). |

### Last-logout backups

`logoutBackup` runs a tiny in-cluster poller that watches a server's online-player count
over the Crafty API and triggers a chosen backup config the moment it drops to zero. It is
a pure API client — no PVC, no server-log access.

It needs a **scoped API key**, which is runtime state and never lives in git (like the panel's
admin password). Create a least-privilege service account in Crafty and put its token in a
secret. The key needs `COMMANDS` on the target server (that both grants server visibility and
satisfies the backup-trigger permission check) and **no** global/crafty permissions:

```sh
# 1. A role scoped to the server (mask bit 0 = COMMANDS, bit 4 = BACKUP):
#    POST /api/v2/roles  {"name":"logout-backup-role",
#      "servers":[{"server_id":"<SID>","permissions":"10001000"}], "mfa_required":false}
# 2. A non-superuser user with that role:
#    POST /api/v2/users  {"username":"logoutbackupbot","password":"<random>",
#      "roles":[<role_id>], "superuser":false}
# 3. An API key under that user (no global perms, not full access):
#    PATCH /api/v2/users/<uid>/key  {"name":"logoutbackupbot",
#      "server_permissions_mask":"10001000","crafty_permissions_mask":"000","full_access":false}
# 4. Retrieve the token:  GET /api/v2/users/<uid>/key/<key_id>  -> data
kubectl -n apps create secret generic crafty-api-key --from-literal=token='<the-token>'
```

Note: an API-key token is rejected if its issue time is in the same second as the user's
creation (Crafty compares them at one-second resolution), so retrieve the token a moment
after creating the user. The token is durable across restarts but dies if the admin password
is changed or tokens are invalidated — regenerate and update the secret if that happens.

### Java versions

The Crafty image ships JDK 8, 11, 17, 21 and 25, so Minecraft 1.21+ (which requires Java 21) runs
without a custom image. Set the Java path per server in the Crafty UI; the 21 runtime is at
`/usr/lib/jvm/java-21-openjdk-amd64/bin/java`.

### A note on exposure

This chart renders a `LoadBalancer` Service, which departs from the house convention that charts
render ClusterIP only and public exposure is added at the Olve.Homelab edge chart. The reason:
Minecraft is raw TCP on 25565, and the edge is an HTTP router — it cannot carry this traffic. The
service is reachable on the LAN. Do not port-forward it to the internet without putting a whitelist
and real authentication in front of it first.

## CD

[`.pipelines/config.yaml`](.pipelines/config.yaml) defines an Olve.Pipelines pipeline:

```
package (production) ──(ArtifactBundle)──> deploy ──> verify
```

| Step | Does | Fails the pipeline when |
|---|---|---|
| **package** | `helm lint`, `helm template` with the real release/namespace, asserts a Deployment + Service + PVC render, asserts the image tag is **pinned**, then `helm package` into the bundle | a template is broken, a resource stops rendering, or the chart would ship `:latest` |
| **deploy** | scp's the packaged chart to the host and `helm upgrade --install --wait` | the rollout does not complete |
| **verify** | `kubectl rollout status`, asserts the **running image equals the packaged image**, and `GET /login` on the panel returns 200 | a stale ReplicaSet survived, or the panel is Ready but not serving |

Two things worth calling out, because both are easy to get wrong:

- **There is no build step, but there is still a production step.** Crafty is a third-party image,
  so nothing is compiled — but the chart is still validated and packaged into the bundle. Deploy
  installs *that artifact*, not a fresh fetch of the repo, so what ships is exactly what passed the
  gate.
- **`helm --wait` is not verification.** It proves a pod reached Ready, which is a TCP-level fact.
  It does not prove the panel serves HTTP, and it does not catch a deploy that silently left the
  previous image running. `verify` asserts both.

To point it at a different cluster, edit the `env` blocks on the steps; nothing host-specific is
baked into the scripts. Unset `PANEL_URL` to skip the HTTP check. The only secret is
`SSH_PRIVATE_KEY`, the key used to reach the cluster host; `GITHUB_TOKEN` is optional and only
needed if you make your fork private.
