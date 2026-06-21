# Docker build aborts mid-`COPY` with a BuildKit `graceful_stop`

```
module.domain.module.<sandbox>.module.image_build_and_upload.terraform_data.image_build_and_upload (local-exec):
  #14 [ N/M] COPY ./payload/datalake_sdk/. .
  ERROR: failed to receive status: rpc error: code = Unavailable
         desc = closing transport due to: connection error:
         desc = "error reading from server: EOF",
         received prior goaway: code: NO_ERROR,
         debug data: "graceful_stop"

Cannot build and push docker image

Error: local-exec provisioner error
  with module.domain.module.<...>.terraform_data.image_build_and_upload,
  on .../build_and_upload_image_to_ecr.tf line 48, in resource "terraform_data" "image_build_and_upload":
  Error running command '/bin/bash build_and_upload_image_to_ecr.sh ...': exit status 1.
```

A sandbox image build (ECS or EMR Serverless) failed because the BuildKit
daemon driving `docker build` shut its gRPC stream down mid-layer
(`received prior goaway: ... "graceful_stop"`). The `terraform apply` reports a
`local-exec provisioner error` since the wrapped `build_and_upload_image_to_ecr.sh`
script exited non-zero, but the root cause is the BuildKit transport drop, not
the Terraform code or the Dockerfile.

## Cause

The build host's BuildKit instance was restarted, evicted, or lost its
connection with the `docker buildx` client while a layer was streaming. Common
triggers:

- the build host was recycled or reaped while the build was in flight
  (ephemeral CI runner ending its lease, host autoscaling, OS-level OOM killer
  on a memory-pressured machine);
- the BuildKit daemon was restarted by another process sharing the host
  (parallel build, daemon upgrade, `systemctl restart docker`);
- a transient network blip between the `docker buildx` client and the BuildKit
  endpoint (relevant when BuildKit runs in a separate container or remote
  pool).

This is **not deterministic** — the same commit on the same Dockerfile will
typically succeed on the next attempt. There's nothing to fix in the
framework code.

## Fix

Re-run the deployment. The next attempt starts a fresh BuildKit session and
the layers that had already been pushed are reused from the cache, so the
retry is usually fast.

- In a CI pipeline: re-trigger the failed job.
- Locally: re-run `terraform apply` (or whatever wrapper drives the
  deployment).

If you see this happening repeatedly on the same host within a short window,
that's the signal something is genuinely wrong with the build host (memory
pressure, disk-full, daemon crash loop) rather than a one-off transport drop
— investigate the host before retrying further.
