import { implement, sshSession } from "@olivervea/pipelines";
import { HOST, verify } from "../pipeline";

const PANEL = "crafty-private.ovea.pro";
// Public DNS can resolve to another entrypoint from inside the cluster; pin the request to the node's ingress.
const INGRESS_IP = "192.168.11.8";

export default implement(verify, async ({ chart, release }, ctx) => {
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
