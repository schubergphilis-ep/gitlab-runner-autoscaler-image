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
  gitlab-runner-autoscaler run
```

There are no tests, linters, or Makefile — this is a Docker image project with a shell entrypoint.

## Architecture

**Container startup flow** (handled by `entrypoint`):

1. Merge Docker credential helpers into `/root/.docker/config.json` (if `DOCKER_CREDENTIAL_HELPERS` is set)
2. Fetch GitLab Runner config (JSON) from AWS Secrets Manager
3. Convert JSON → TOML using `json2toml` (from remarshal)
4. Exec `gitlab-runner` with the generated TOML config

SSH keys are provisioned via EC2 Instance Connect (`use_static_credentials = false`, the default).

**Key files:**
- `Dockerfile` — image definition with pinned Alpine package versions
- `entrypoint` — shell script orchestrating the startup flow
- `config.json` — default (empty) Docker credential helper config

## Conventions

- **Dockerfile versions are pinned** to exact Alpine package revisions (e.g. `aws-cli=2.32.7-r0`). When Alpine drops a revision, bump to the new `-rN` suffix.
- **Fleeting plugin is installed at build time** (`gitlab-runner fleeting install`) to avoid runtime supply chain risk.
- **Commit messages** follow conventional commits: `feat:`, `fix(docker):`, etc.
- **CI** uses GitHub Actions with `schubergphilis/mcvs-docker-action` for scanning and pushing to Docker Hub.
