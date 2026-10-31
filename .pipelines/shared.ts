import { secret } from "@olivervea/pipelines";

export const SSH_PRIVATE_KEY = secret("SSH_PRIVATE_KEY", "SSH key for running helm and kubectl on the cluster host.");
export const HOST = "oliver@bulwark-m2";
