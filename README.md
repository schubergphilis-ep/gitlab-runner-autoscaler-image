# gitlab-runner-autoscaler-image

Custom GitLab Runner image with AWS autoscaling support via the [fleeting-plugin-aws](https://gitlab.com/gitlab-org/fleeting/plugins/aws). At startup, it fetches runner configuration from AWS Secrets Manager, then launches gitlab-runner with autoscaling enabled. SSH keys for connecting to EC2 instances (via private IP) are provisioned through EC2 Instance Connect.

This image is designed to be used with [terraform-aws-mcaf-gitlab-runner-autoscaler](https://github.com/schubergphilis-ep/terraform-aws-mcaf-gitlab-runner-autoscaler), which provisions the supporting AWS infrastructure (ECS service, Secrets Manager secrets, IAM roles, and EC2 autoscaling configuration).

## Architecture

```
┌──────────────────────────────────────────────────┐
│  Container startup (entrypoint)                  │
│                                                  │
│  1. Configure Docker credential helpers (if set) │
│  2. Fetch runner config from Secrets Manager     │
│  3. Transform JSON → TOML config                 │
│  4. exec gitlab-runner                           │
└──────────────────────────────────────────────────┘
```

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `AWS_REGION` | No | `us-east-1` | AWS region for Secrets Manager calls |
| `GITLAB_CONFIG_SECRET_NAME` | No | `gitlab-runner-config` | Secrets Manager secret containing the runner config (JSON) |
| `DOCKER_CREDENTIAL_HELPERS` | No | — | JSON object of Docker credential helpers. When set, writes to `/root/.docker/config.json` at startup |

### Docker credential helpers

Set `DOCKER_CREDENTIAL_HELPERS` to a JSON object mapping registries to credential helpers:

```sh
# Single ECR registry
DOCKER_CREDENTIAL_HELPERS='{"123456789.dkr.ecr.eu-west-1.amazonaws.com":"ecr-login"}'

# Multiple registries
DOCKER_CREDENTIAL_HELPERS='{"123456789.dkr.ecr.eu-west-1.amazonaws.com":"ecr-login","987654321.dkr.ecr.us-east-1.amazonaws.com":"ecr-login"}'
```

When unset, the image ships with an empty `credHelpers` config.

## Secrets Manager format

### Runner configuration (`GITLAB_CONFIG_SECRET_NAME`)

Store the runner configuration as a JSON string. The entrypoint transforms it to TOML at startup.

Example:

```json
{
  "runners": [
    {
      "name": "autoscaler",
      "url": "https://gitlab.example.com",
      "token": "glrt-...",
      "executor": "docker-autoscaler",
      "autoscaler": {
        "plugin": "aws:latest",
        "connector_config": {
          "username": "ec2-user"
        },
        "plugin_config": {
          "region": "eu-west-1"
        }
      }
    }
  ]
}
```

### SSH connectivity

SSH keys are provisioned via [EC2 Instance Connect](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-connect-methods.html). The fleeting-plugin-aws uses `use_static_credentials = false` (the default), which dynamically pushes temporary SSH keys via the `SendSSHPublicKey` API. The runner connects to EC2 instances over their private IP. This requires the `ec2-instance-connect:SendSSHPublicKey` IAM permission.

## IAM permissions

The container requires AWS credentials (via ECS task role, instance profile, or environment variables) with the following permissions:

```json
{
  "Effect": "Allow",
  "Action": "secretsmanager:GetSecretValue",
  "Resource": [
    "arn:aws:secretsmanager:<region>:<account>:secret:<runner-config-secret>"
  ]
}
```

Additionally, the fleeting-plugin-aws needs permission to push SSH keys via EC2 Instance Connect:

```json
{
  "Effect": "Allow",
  "Action": "ec2-instance-connect:SendSSHPublicKey",
  "Resource": "arn:aws:ec2:<region>:<account>:instance/*"
}
```

## Building

```sh
docker build -t gitlab-runner-autoscaler .
```

## Running

```sh
docker run \
  -e AWS_REGION=eu-west-1 \
  -e GITLAB_CONFIG_SECRET_NAME=my-runner-config \
  -e DOCKER_CREDENTIAL_HELPERS='{"123456789.dkr.ecr.eu-west-1.amazonaws.com":"ecr-login"}' \
  gitlab-runner-autoscaler run
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Image definition based on `gitlab/gitlab-runner:alpine`. Installs aws-cli, jq, remarshal, docker-credential-ecr-login, and the fleeting-plugin-aws |
| `entrypoint` | Startup script that configures credentials, fetches secrets, and launches the runner |
| `config.json` | Default Docker credential helper config (empty `credHelpers`, overridden at runtime by `DOCKER_CREDENTIAL_HELPERS`) |
