# gitlab-runner-autoscaler-image

Custom GitLab Runner image with AWS autoscaling support via the [fleeting-plugin-aws](https://gitlab.com/gitlab-org/fleeting/plugins/aws). At startup, it fetches runner configuration and SSH keys from AWS Secrets Manager, then launches gitlab-runner with autoscaling enabled.

This image is designed to be used with [terraform-aws-mcaf-gitlab-runner-autoscaler](https://github.com/schubergphilis-ep/terraform-aws-mcaf-gitlab-runner-autoscaler), which provisions the supporting AWS infrastructure (ECS service, Secrets Manager secrets, IAM roles, and EC2 autoscaling configuration).

## Architecture

```
┌──────────────────────────────────────────────────┐
│  Container startup (entrypoint)                  │
│                                                  │
│  1. Configure Docker credential helpers (if set) │
│  2. Fetch SSH key from Secrets Manager           │
│  3. Fetch runner config from Secrets Manager     │
│  4. Inject SSH key path into config              │
│  5. Transform JSON → TOML config                 │
│  6. exec gitlab-runner                           │
└──────────────────────────────────────────────────┘
```

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `AWS_REGION` | No | `us-east-1` | AWS region for Secrets Manager calls |
| `GITLAB_CONFIG_SECRET_NAME` | No | `gitlab-runner-config` | Secrets Manager secret containing the runner config (JSON) |
| `SSH_KEY_SECRET_NAME` | No | `gitlab-runner-ssh-key` | Secrets Manager secret containing the SSH private key |
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

Store the runner configuration as a JSON string. The entrypoint transforms it to TOML at startup. The `key_path` field in `runners[].autoscaler.connector_config` is automatically set to the fetched SSH key path.

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

### SSH key (`SSH_KEY_SECRET_NAME`)

Store the SSH private key in standard OpenSSH format. The entrypoint fetches it at runtime from Secrets Manager (encrypted at rest via KMS) and writes it to disk with `chmod 600`. The fleeting-plugin-aws requires an SSH key to connect to the EC2 instances it provisions for job execution. The key must be provided inside the container because the runner AMI uses Fedora CoreOS, which does not support EC2 Instance Connect — so a pre-shared key pair is the only available authentication method.

## IAM permissions

The container requires AWS credentials (via ECS task role, instance profile, or environment variables) with the following permissions:

```json
{
  "Effect": "Allow",
  "Action": "secretsmanager:GetSecretValue",
  "Resource": [
    "arn:aws:secretsmanager:<region>:<account>:secret:<runner-config-secret>",
    "arn:aws:secretsmanager:<region>:<account>:secret:<ssh-key-secret>"
  ]
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
  -e SSH_KEY_SECRET_NAME=my-runner-ssh-key \
  -e DOCKER_CREDENTIAL_HELPERS='{"123456789.dkr.ecr.eu-west-1.amazonaws.com":"ecr-login"}' \
  gitlab-runner-autoscaler run
```

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Image definition based on `gitlab/gitlab-runner:alpine`. Installs aws-cli, jq, remarshal, docker-credential-ecr-login, and the fleeting-plugin-aws |
| `entrypoint` | Startup script that configures credentials, fetches secrets, and launches the runner |
| `config.json` | Default Docker credential helper config (empty `credHelpers`, overridden at runtime by `DOCKER_CREDENTIAL_HELPERS`) |
