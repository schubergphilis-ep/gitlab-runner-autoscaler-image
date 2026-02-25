FROM gitlab/gitlab-runner:alpine

LABEL maintainer="Schuberg Philis B.V."

RUN apk add --no-cache \
    aws-cli \
    python3 \
    pipx \
    docker-credential-ecr-login \
    jq

# Install remarshal using pipx
RUN pipx install remarshal && \
    pipx ensurepath

# Add pipx bin to PATH
ENV PATH="/root/.local/bin:${PATH}"

COPY --chmod=755 entrypoint /sbp-entrypoint
COPY config.json /root/.docker/config.json

# Install fleeting plugin at build time to avoid runtime supply chain risk.
# A minimal config.toml is needed so fleeting install knows which plugin to fetch.
RUN mkdir -p /etc/gitlab-runner && \
    printf '[[runners]]\n[runners.autoscaler]\nplugin = "aws:latest"\n' \
      > /etc/gitlab-runner/config.toml && \
    gitlab-runner fleeting install && \
    rm /etc/gitlab-runner/config.toml

ENTRYPOINT ["/sbp-entrypoint"]