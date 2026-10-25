import { readFileSync } from "node:fs";
import { join } from "node:path";
import { implement } from "@olivervea/pipelines";
import { check } from "../pipeline";

const KINDS = ["Deployment", "Service", "PersistentVolumeClaim"];

export default implement(check, async ({ source }, ctx) => {
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
