# Until https://issues.redhat.com/browse/RELEASE-993 is resolved, we need to use :SHA instead of :VERSION tags
FROM quay.io/redhat-services-prod/app-sre-tenant/er-base-cdktf-aws-main/er-base-cdktf-aws-main:3ab182e AS prod

# keep in sync with pyproject.toml
LABEL konflux.additional-tags="0.2.0"

# Keep in sync with the 'cdktf-cdktf-provider-random' version in pyproject.toml
ENV TF_PROVIDER_RANDOM_VERSION="3.6.3"
ENV TF_PROVIDER_RANDOM_PATH="${TF_PLUGIN_CACHE}/registry.terraform.io/hashicorp/random/${TF_PROVIDER_RANDOM_VERSION}/linux_amd64"

RUN mkdir -p ${TF_PROVIDER_RANDOM_PATH} && \
    curl -sfL https://releases.hashicorp.com/terraform-provider-random/${TF_PROVIDER_RANDOM_VERSION}/terraform-provider-random_${TF_PROVIDER_RANDOM_VERSION}_linux_amd64.zip \
    -o /tmp/package-${TF_PROVIDER_RANDOM_VERSION}.zip && \
    unzip /tmp/package-${TF_PROVIDER_RANDOM_VERSION}.zip -d ${TF_PROVIDER_RANDOM_PATH}/ && \
    rm /tmp/package-${TF_PROVIDER_RANDOM_VERSION}.zip

# Install dependencies
COPY pyproject.toml uv.lock ./
RUN uv sync --no-install-project --no-dev

COPY README.md Makefile cdktf.json validate_plan.py ./

# the source code
COPY er_aws_msk ./er_aws_msk

# Sync the project
RUN uv sync --no-editable --no-dev

FROM prod AS test
# install test dependencies
RUN uv sync --no-editable

COPY tests ./tests
RUN make test
