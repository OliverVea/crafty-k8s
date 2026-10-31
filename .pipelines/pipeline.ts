// Every push deploys to apps.
import { pipeline, steps } from "@olivervea/pipelines";
import * as M from "./models";
import { HOST, SSH_PRIVATE_KEY } from "./shared";
import { check } from "./steps/check";
import { verify } from "./steps/verify";

const source = steps.gitHubSource({
  name: "source",
  description: "Fetches the pushed commit from GitHub.",
});

const deploy = steps.helmDeployOverSsh({
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
