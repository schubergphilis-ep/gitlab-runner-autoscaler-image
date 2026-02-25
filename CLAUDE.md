# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Custom Docker image based on `gitlab/gitlab-runner:alpine` that enables AWS autoscaling for GitLab Runners via the fleeting-plugin-aws integration. Designed to work with the `terraform-aws-mcaf-gitlab-runner-autoscaler` Terraform module.

## Build & Run

```bash
# Build the image
docker build -t gitlab-runner-autoscaler .

# Run (requires AWS credentials in environment)
docker run \
  -e AWS_REGION=eu-west-1 \
  -e GITLAB_CONFIG_SECRET_NAME=my-runner-config \
  -e SSH_KEY_SECRET_NAME=my-runner-ssh-key \
  gitlab-runner-autoscaler run
```

There are no tests, linters, or Makefile — this is a Docker image project with a shell entrypoint.

## Architecture

**Container startup flow** (handled by `entrypoint`):

1. Merge Docker credential helpers into `/root/.docker/config.json` (if `DOCKER_CREDENTIAL_HELPERS` is set)
2. Fetch SSH private key from AWS Secrets Manager → write to `/tmp/ssh-key`
3. Fetch GitLab Runner config (JSON) from AWS Secrets Manager
4. Inject SSH key path into config via `jq`
5. Convert JSON → TOML using `json2toml` (from remarshal)
6. Exec `gitlab-runner` with the generated TOML config

**Key files:**
- `Dockerfile` — image definition with pinned Alpine package versions
- `entrypoint` — shell script orchestrating the startup flow
- `config.json` — default (empty) Docker credential helper config

## Conventions

- **Dockerfile versions are pinned** to exact Alpine package revisions (e.g. `aws-cli=2.32.7-r0`). When Alpine drops a revision, bump to the new `-rN` suffix.
- **Fleeting plugin is installed at build time** (`gitlab-runner fleeting install`) to avoid runtime supply chain risk.
- **Commit messages** follow conventional commits: `feat:`, `fix(docker):`, etc.
- **CI** uses GitHub Actions with `schubergphilis/mcvs-docker-action` for scanning and pushing to Docker Hub.
- **Code ownership**: all changes require approval from `@schubergphilis-ep/VPFCloudBuildingBlocksTeam`.
