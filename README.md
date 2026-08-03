# crafty-k8s

A Helm chart and CD pipeline that run [Crafty Controller 4](https://craftycontrol.com/) — a
self-hosted Minecraft server panel — on a k3s cluster.

## What this does and does not manage

**It manages the panel.** One pod, one volume, one LoadBalancer service. That is the whole scope.

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
| `persistence.storageClass` | `local-path` | Node NVMe. **Never** use NFS or network storage — chunk saves are latency-sensitive and produce hitching that reads as a mod bug. |
| `persistence.size` | `100Gi` | Worlds plus backups. The PVC is annotated `helm.sh/resource-policy: keep`, so uninstalling the release does not delete your worlds. |
| `service.type` | `LoadBalancer` | On k3s, servicelb binds these ports on the node, which is how you get a real `25565`. NodePort's 30000-32767 range cannot. |
| `service.serverPorts` | `25565`, `25566` | One entry per Minecraft server you host. Add an entry when you add a server. |
| `resources.limits.memory` | `12Gi` | Must cover Crafty **plus every server JVM it spawns**. JVM metaspace and direct buffers live outside `-Xmx`, so a limit equal to the heap gets the pod OOM-killed mid-session. |
| `resources.requests.cpu` | `2` | Requests, but deliberately **no CPU limit**: CFS quota throttling mid-tick is the top cause of phantom TPS stutter on containerized Minecraft servers. |
| `podSecurityContext.fsGroup` | `0` | Crafty runs as a non-root user relying on root-group permissions on its `/crafty` mounts. Without this the volume is not writable. |

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

[`.pipelines/config.yaml`](.pipelines/config.yaml) defines an Olve.Pipelines pipeline. It has no
production step — nothing is built, since Crafty is a third-party image — just a single `deploy`
step that fetches this repo and runs `helm upgrade`.

To point it at a different cluster, edit the `env` block on the deploy step; nothing host-specific
is baked into the script. The only secret is `SSH_PRIVATE_KEY`, the key used to reach the cluster
host. `GITHUB_TOKEN` is optional and only needed if you make your fork private.
