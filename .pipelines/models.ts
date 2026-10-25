import { model, z } from "@olivervea/pipelines";

export const DeployRequest = model("DeployRequest", z.object({
  repo: z.string().default("OliverVea/crafty-k8s"),
  sha: z.string().regex(/^[0-9a-f]{40}$/),
}));

export const CheckedChart = model("CheckedChart", z.object({
  image: z.string().describe("The image the rendered chart runs, pinned to a tag."),
}));
