import { readFileSync } from "node:fs";
import { join } from "node:path";
import { implement, step, Source } from "@olivervea/pipelines";
import * as M from "../models";

const KINDS = ["Deployment", "Service", "PersistentVolumeClaim"];

export const check = implement(step({
  name: "check",
  description: "Lints and renders the chart; it must render a Deployment, Service and PVC with a pinned image tag.",
  image: "alpine/helm:3.21.3",
  input: { source: Source },
  output: M.CheckedChart,
  timeoutSeconds: 300,
}), async ({ source }, ctx) => {
  const chart = join(await ctx.files.fetch(source.tree), "helm");
  await ctx.exec(["helm", "lint", chart]);
  await ctx.exec(["helm", "lint", chart, "-f", join(chart, "values-homelab.yaml")]);
  // Rendering catches template errors lint misses (a bad range, an undefined value).
  const rendered = join(ctx.tmpDir, "rendered.yaml");
  await ctx.sh(`helm template crafty ${chart} -n apps -f ${chart}/values-homelab.yaml > ${rendered}`);
  const yaml = readFileSync(rendered, "utf8");
  for (const kind of KINDS) if (!yaml.includes(`kind: ${kind}`)) throw new Error(`the chart renders no ${kind}`);

  // A :latest image would upgrade the panel on any pod restart.
  const image = yaml.match(/^\s+image:\s*"?([^"\s]+)"?/m)?.[1];
  if (!image) throw new Error("the chart renders no image");
  if (!/:[^/]+$/.test(image) || image.endsWith(":latest")) throw new Error(`the image must have a pinned tag, got ${image}`);
  ctx.log("chart checked", { image });
  return { image };
});
