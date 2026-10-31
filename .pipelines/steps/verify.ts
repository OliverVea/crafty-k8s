import { implement, sshSession, step, HelmRelease } from "@olivervea/pipelines";
import { HOST, SSH_PRIVATE_KEY } from "../shared";
import * as M from "../models";

const PANEL = "crafty-private.ovea.pro";
// Public DNS can resolve to another entrypoint from inside the cluster; pin the request to the node's ingress.
const INGRESS_IP = "192.168.11.8";

export const verify = implement(step({
  name: "verify",
  description: "The deployment runs the checked image, and the panel answers at crafty-private.ovea.pro.",
  image: "alpine:3.22",
  input: { chart: M.CheckedChart, release: HelmRelease },
  secrets: [SSH_PRIVATE_KEY],
  timeoutSeconds: 300,
}), async ({ chart, release }, ctx) => {
  const ssh = await sshSession(ctx, { host: HOST, key: ctx.secrets.SSH_PRIVATE_KEY });
  // Single quotes for the host's login shell (zsh), which would glob-expand the bare [0].
  const running = await ssh.text(`kubectl -n ${release.namespace} get deploy/${release.release} -o 'jsonpath={.spec.template.spec.containers[0].image}'`);
  if (running !== chart.image) throw new Error(`deploy/${release.release} runs ${running}, not ${chart.image}`);
  ctx.log("running the checked image", { image: running });

  await ctx.exec(["apk", "add", "--no-cache", "curl"]);
  // -k: the panel serves a self-signed certificate.
  const code = await ctx.sh.text(`curl -sk --resolve ${PANEL}:443:${INGRESS_IP} -o /dev/null -w '%{http_code}' --max-time 30 https://${PANEL}/login`);
  if (code !== "200") throw new Error(`https://${PANEL}/login answered ${code}`);
  ctx.log("panel answers", { url: `https://${PANEL}/login` });
});
