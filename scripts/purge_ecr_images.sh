#!/usr/bin/env bash
# Resets an environment's docker-image state to force a cold rebuild:
# 1. Deletes every image (runtime tags + BuildKit :buildcache manifest) from
#    the matching ECR repos.
# 2. If a terraform working directory is passed, removes each
#    `terraform_data.image_build_and_upload` from state so terraform re-creates
#    the resource on the next apply. Without the state removal, `triggers_replace`
#    on those resources compares state (captured at previous plan time) against
#    the current data source read — and once state has stored `ecr_presence
#    = "MISSING"` (from any prior apply that saw missing images), a purge
#    followed by an apply does NOT trigger a rebuild because MISSING == MISSING.
#    Removing the state entry side-steps the sticky-sentinel and forces a
#    create-from-scratch on the next apply.
#
# Cold rebuild catches drift a warm registry cache silently masks: pypi
# transitives resolved at build time, base-image content-hash shifting under
# a stable tag, external `curl … | sh` outputs frozen at first run.
#
# Idempotent on missing repos (first apply on a new stage: nothing to purge).
#
# Prefix-match trap: the ECR filter is `starts_with(name, '<env_slug>-')`, so
# two stages whose slugs share a common prefix purge each other's repos when
# either CI runs (e.g. stage `dev1` also matches `dev1-hotfix`, `dev1-foo`,
# `dev1_experiment`). Avoid branch names that share a prefix with a live
# sibling stage. See docs/troubleshooting/scaffold-ecr-prefix-collision.md.
set -euo pipefail

project_name="${1:?project_name required}"
domain_name="${2:?domain_name required}"
stage_name="${3:?stage_name required}"
terraform_dir="${4:-}"
region="${AWS_DEFAULT_REGION:-eu-west-1}"

# ECR repo naming mirrors pipeline_factory/modules/build_and_upload_image_to_ecr/ecr.tf:
#   name = "${replace(environment_name, "_", "-")}-<resources_suffix>"
# so every repo of the environment shares the `<env_slug>-` prefix below.
env_slug=$(printf '%s_%s_%s' "$project_name" "$domain_name" "$stage_name" | tr '_' '-')

echo "Purging ECR repos matching ${env_slug}-* in ${region} ..."

# Paginate manually rather than relying on the AWS CLI's auto-pagination —
# some runner setups disable it via `AWS_PAGINATOR=off`, and a truncated
# first-page response would silently miss any matching repo not in the top
# `maxResults` alphabetical slice.
all_repos=""
next_token=""
while : ; do
    response=$(aws ecr describe-repositories --region "$region" \
        ${next_token:+--starting-token "$next_token"} \
        --output json)
    all_repos+=$(echo "$response" | jq -r '.repositories[].repositoryName')$'\n'
    next_token=$(echo "$response" | jq -r '.NextToken // empty')
    [ -z "$next_token" ] && break
done
repos=$(printf '%s' "$all_repos" | grep -E "^${env_slug}-" || true)

if [ -z "$repos" ]; then
    echo "No matching ECR repos — first-time apply on this stage, nothing to purge."
    exit 0
fi

for repo in $repos; do
    image_ids=$(aws ecr list-images --region "$region" --repository-name "$repo" \
        --query 'imageIds[*]' --output json)
    count=$(echo "$image_ids" | jq 'length')
    if [ "$count" = "0" ]; then
        echo "  ${repo}: empty, skipping"
        continue
    fi
    # `batch-delete-image` caps `--image-ids` at 100 items per call. Long-lived
    # stages accumulate >100 manifests (BuildKit `mode=max` pushes many layers
    # per build plus every `runtime-*` tag until the lifecycle policy expires
    # them), so chunk the IDs client-side and loop.
    echo "$image_ids" | jq -c '_nwise(100)' | while IFS= read -r chunk; do
        aws ecr batch-delete-image --region "$region" --repository-name "$repo" \
            --image-ids "$chunk" > /dev/null
    done

    # `batch-delete-image` returns as soon as the write path acks the delete,
    # but ECR's read path (list-images / describe-images) can serve the old
    # manifests for several seconds after. If we return before that lag has
    # cleared, terraform's `data.external.ecr_image_presence` still sees the
    # tag as present, `triggers_replace` doesn't flip, the image is never
    # rebuilt, and the downstream SFN then references a runtime tag that ECS
    # can't pull once propagation eventually catches up. Poll until list-images
    # returns 0 manifests before releasing the caller.
    deadline=$(( $(date +%s) + 60 ))
    while : ; do
        remaining=$(aws ecr list-images --region "$region" --repository-name "$repo" \
            --query 'imageIds[*]' --output json | jq 'length')
        [ "$remaining" -eq 0 ] && break
        if [ "$(date +%s)" -ge "$deadline" ]; then
            echo "  ${repo}: ERROR: $remaining image(s) still visible 60s after delete — aborting" >&2
            exit 1
        fi
        sleep 2
    done
    echo "  ${repo}: deleted ${count} image(s), propagation confirmed"
done

echo "Purge complete."

if [ -n "$terraform_dir" ]; then
    if [ ! -d "$terraform_dir/.terraform" ]; then
        echo "ERROR: '$terraform_dir' is not a terraform-inited directory (no .terraform/)." >&2
        echo "Run 'terraform init' there before invoking this script with a state-rm target." >&2
        exit 1
    fi
    echo "Removing terraform_data.image_build_and_upload entries from state in ${terraform_dir} ..."
    build_addrs=$(terraform -chdir="$terraform_dir" state list \
        | grep -E 'terraform_data\.image_build_and_upload$' || true)
    if [ -z "$build_addrs" ]; then
        echo "  No matching state entries found — nothing to remove."
    else
        while IFS= read -r addr; do
            echo "  terraform state rm '${addr}'"
            terraform -chdir="$terraform_dir" state rm "$addr" > /dev/null
        done <<< "$build_addrs"
    fi
    echo "State cleanup complete."
fi
