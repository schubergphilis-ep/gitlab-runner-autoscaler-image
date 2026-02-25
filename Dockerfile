FROM gitlab/gitlab-runner:alpine

LABEL maintainer="Schuberg Philis B.V."

RUN apk add --no-cache \
    aws-cli=2.32.7-r0 \
    python3=3.12.12-r0 \
    pipx=1.8.0-r0 \
    docker-credential-ecr-login=0.11.0-r2 \
    jq=1.8.1-r0

# Install remarshal using pipx
RUN pipx install remarshal==1.3.0 && \
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