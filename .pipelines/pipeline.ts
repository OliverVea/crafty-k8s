// Every push deploys to apps. config.yaml beside it is the old v1 config.
import { HelmRelease, pipeline, secret, step, steps, Source } from "@olivervea/pipelines";
import * as M from "./models";

export const SSH_PRIVATE_KEY = secret("SSH_PRIVATE_KEY", "SSH key for running helm and kubectl on the cluster host.");

export const HOST = "oliver@bulwark-m2";

export const source = steps.gitHubSource({
  name: "source",
  description: "Fetches the pushed commit from GitHub.",
});

export const check = step({
  name: "check",
  description: "Lints and renders the chart; it must render a Deployment, Service and PVC with a pinned image tag.",
  image: "alpine/helm:3.21.3",
  input: { source: Source },
  output: M.CheckedChart,
  timeoutSeconds: 300,
});

export const deploy = steps.helmDeployOverSsh({
  name: "deploy",
  description: "Deploys the chart to apps with Helm and waits for the rollout. The node pulls the Crafty image itself.",
  host: HOST,
  sshKey: SSH_PRIVATE_KEY,
  release: "crafty",
  namespace: "apps",
  chart: "helm",
  values: ["values-homelab.yaml"],
  images: {},
  deployments: ["crafty"],
  rolloutTimeoutSeconds: 600,
  timeoutSeconds: 900,
});

export const verify = step({
  name: "verify",
  description: "The deployment runs the checked image, and the panel answers at crafty-private.ovea.pro.",
  image: "alpine:3.22",
  input: { chart: M.CheckedChart, release: HelmRelease },
  secrets: [SSH_PRIVATE_KEY],
  timeoutSeconds: 300,
});

export default pipeline({
  name: "crafty",
  description: "Check the Crafty Controller chart, deploy it to apps with Helm, then verify the running image and that the panel answers.",
  input: M.DeployRequest,
})
  .onPush(e => ({ repo: e.repository.full_name, sha: e.after }))
  .stage([source, from => ({ repo: from.input.repo, sha: from.input.sha })])
  .stage(check)
  .stage(deploy)
  .stage(verify);
