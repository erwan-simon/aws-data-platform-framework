# Scaffold Lambda / ECS task fails with `ImageNotFoundException` after a sibling branch's CI run

```
An error occurred (ImageNotFoundException) when calling the ... operation:
The image with imageId {imageDigest:'null', imageTag:'runtime-<sha1>'} does
not exist within the repository with name
'poc-datalake-scaffold-<stage>-<component>'
```

Or, at `terraform apply`:

```
module.domain.module.<...>.terraform_data.image_build_and_upload:
  Error: local-exec provisioner error
  ...
  <image tag references a manifest that ECR reports as absent>
```

The scaffold ECR repos of the affected stage contain no `runtime-*` tags, and
often no `:buildcache` tag either — as if a purge had just run — even though
no CI pipeline on this stage did anything recently.

## Cause

`scripts/purge_ecr_images.sh` (called from `mise.toml`'s `integration-scaffold` task on the
`integration_tests_scaffold` job) matches ECR repos by prefix:

```
starts_with(repositoryName, '<project>-<domain>-<stage>-')
```

The prefix contains a trailing `-` but nothing prevents a **longer stage slug**
from matching. Any stage whose slug **starts with the current stage's slug plus
`-`** shares repos with it under the same prefix.

Concrete: stage `dev1` gives the prefix `poc-datalake-scaffold-dev1-`. Repos
of the sibling stage `dev1-hotfix` are named
`poc-datalake-scaffold-dev1-hotfix-*` — which start with
`poc-datalake-scaffold-dev1-`. When the `dev1` CI runs the purge, ECR reports
both stages' repos as matches and both get their images deleted.

The stage whose CI didn't run then finds its own image tags gone, and any
Lambda / ECS task referencing them fails on the next invocation with
`ImageNotFoundException`.

## Recovery

Re-run `terraform apply` on the affected stage. The build module's
`data.external.ecr_image_presence` will report `MISSING`, the
`triggers_replace` flips, and the missing images are rebuilt and pushed
before any dependent resource references them again. No state edit needed.

## Prevention

Avoid branch names that share a prefix with a live sibling stage. Concretely:

- Don't create a branch `foo-hotfix` if another dev has an active stage `foo`.
- Don't reuse a truncated form of an existing stage name as a new branch.

The runbook is currently to coordinate branch names when multiple stages are
live at once, since the purge is scoped to the scaffold's fresh-downstream
test and reworking the ECR filter to exact matching would tie the script to
the scaffold's specific repo layout (fewer generic uses possible).
