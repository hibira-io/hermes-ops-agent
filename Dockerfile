# Hermes Ops Agent: the Hermes Agent image set up for investigating and
# adjusting infrastructure, with Hibira Approvals built in.
#
# Reads run directly. Shell commands and MCP tool calls that change something
# (scale, restart, delete, deploy, write) wait for a second person to approve
# them in a Hibira Approvals workspace. Bring your own model key and your own
# cloud credentials; modules turn on when their environment is set.

ARG HERMES_VERSION=v0.23.1
ARG ELASTIC_MCP_VERSION=0.4.6

FROM docker.elastic.co/mcp/elasticsearch:${ELASTIC_MCP_VERSION} AS elastic_mcp

FROM nousresearch/hermes-agent:${HERMES_VERSION}

ARG TARGETARCH
ARG GRAFANA_MCP_VERSION=v2.3.0
ARG PROMETHEUS_MCP_VERSION=1.6.2
ARG DBHUB_VERSION=1.6.1
# The approval gate from npm. CI can pass a local tarball instead (GATE_SPEC=/tmp/gate.tgz).
ARG GATE_SPEC=@hibira-io/mcp-approval-gate@0.4.0
ARG WRANGLER_VERSION=4.155.0
ARG GCLOUD_VERSION=590.0.0

USER root

# Local builds behind a TLS-intercepting proxy can drop its CA in build/ca.crt
# (git-ignored); CI and published images never have one.
ARG NODE_EXTRA_CA_CERTS
ARG SSL_CERT_FILE
ARG UV_NATIVE_TLS
ARG PIP_CERT
COPY build/ /tmp/hibira-build/
RUN if [ -f /tmp/hibira-build/ca.crt ]; then \
      cp /tmp/hibira-build/ca.crt /usr/local/share/ca-certificates/build-proxy.crt && update-ca-certificates >/dev/null; \
    fi

# Cloud CLIs: AWS CLI v2 and the Google Cloud CLI (Cloudflare's wrangler comes from npm below).
RUN set -eu; \
    case "${TARGETARCH:-amd64}" in amd64) aws=x86_64; gc=x86_64 ;; arm64) aws=aarch64; gc=arm ;; *) exit 1 ;; esac; \
    curl -fsSL --retry 3 -o /tmp/awscli.zip "https://awscli.amazonaws.com/awscli-exe-linux-${aws}.zip"; \
    /usr/bin/python3 -c 'import os,sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); [(z.extract(i,"/tmp"), os.chmod(os.path.join("/tmp",i.filename),(i.external_attr>>16) or 0o644)) for i in z.infolist()]' /tmp/awscli.zip; \
    /tmp/aws/install --bin-dir /usr/local/bin --install-dir /opt/aws-cli; \
    rm -rf /tmp/aws /tmp/awscli.zip; \
    curl -fsSL --retry 3 -o /tmp/gcloud.tgz \
      "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${GCLOUD_VERSION}-linux-${gc}.tar.gz"; \
    tar -xzf /tmp/gcloud.tgz -C /opt; rm /tmp/gcloud.tgz; \
    /opt/google-cloud-sdk/install.sh --quiet --usage-reporting false --path-update false --command-completion false; \
    rm -rf /opt/google-cloud-sdk/.install/.backup; \
    for b in gcloud gsutil bq; do ln -s /opt/google-cloud-sdk/bin/$b /usr/local/bin/$b; done; \
    aws --version; gcloud --version | head -1

# Grafana MCP (also covers Loki, Tempo, alerting and incidents through Grafana).
RUN set -eu; \
    case "${TARGETARCH:-amd64}" in amd64) arch=x86_64 ;; arm64) arch=arm64 ;; *) echo "unsupported arch ${TARGETARCH}"; exit 1 ;; esac; \
    curl -fsSL --retry 3 -o /tmp/mcp-grafana.tgz \
      "https://github.com/grafana/mcp-grafana/releases/download/${GRAFANA_MCP_VERSION}/mcp-grafana_Linux_${arch}.tar.gz"; \
    tar -xzf /tmp/mcp-grafana.tgz -C /usr/local/bin mcp-grafana; \
    rm /tmp/mcp-grafana.tgz; \
    /usr/local/bin/mcp-grafana --version

# Elasticsearch MCP (indices, mappings, search, ES|QL).
COPY --from=elastic_mcp /usr/local/bin/elasticsearch-core-mcp-server /usr/local/bin/elasticsearch-core-mcp-server

# Prometheus MCP in its own virtualenv, so it never touches Hermes' Python.
RUN set -eu; \
    /usr/bin/python3 -m venv /opt/hibira/venvs/prometheus; \
    /opt/hibira/venvs/prometheus/bin/pip install --quiet --no-cache-dir "prometheus-mcp-server==${PROMETHEUS_MCP_VERSION}"; \
    ln -s /opt/hibira/venvs/prometheus/bin/prometheus-mcp-server /usr/local/bin/prometheus-mcp-server

# The approval gate, DBHub (Postgres, MySQL, MariaDB, SQL Server, SQLite) and wrangler.
RUN set -eu; \
    npm install --global --prefix /usr/local --allow-scripts=workerd,esbuild --no-fund --no-audit "${GATE_SPEC}" "@bytebase/dbhub@${DBHUB_VERSION}" "wrangler@${WRANGLER_VERSION}"; \
    npm cache clean --force; \
    rm -rf /tmp/hibira-build; \
    mcp-approval-gate --version; wrangler --version; \
    if [ -f /usr/local/share/ca-certificates/build-proxy.crt ]; then \
      rm /usr/local/share/ca-certificates/build-proxy.crt && update-ca-certificates --fresh >/dev/null; \
    fi

COPY rootfs/ /
RUN chmod 0755 /etc/cont-init.d/03-hibira /opt/hibira/bin/*; \
    ln -sf /opt/hibira/bin/hibira-setup /usr/local/bin/hibira-setup

ENV GRAFANA_USAGE_STATS=disabled \
    CLOUDSDK_CORE_DISABLE_PROMPTS=1 \
    WRANGLER_SEND_METRICS=false \
    AWS_PAGER= \
    HIBIRA_APPROVALS_URL=https://approvals.hibira.io \
    HIBIRA_CONFIG_DIR=/opt/data/.config/hibira \
    HIBIRA_STATE_DIR=/opt/data/.local/state/hibira \
    CLOUDSDK_CONFIG=/opt/data/.config/gcloud \
    AWS_CONFIG_FILE=/opt/data/.aws/config \
    AWS_SHARED_CREDENTIALS_FILE=/opt/data/.aws/credentials \
    GATE_LOGIN_COMMAND="docker exec -it <container> mcp-approval-gate login --label hermes-ops-agent"

LABEL org.opencontainers.image.title="Hermes Ops Agent" \
      org.opencontainers.image.description="Hermes Agent for ops: investigates Cloudflare, AWS, GCP, Grafana and Elasticsearch; changes wait for Hibira Approvals" \
      org.opencontainers.image.source="https://github.com/hibira-io/hermes-ops-agent" \
      org.opencontainers.image.licenses="MIT"
