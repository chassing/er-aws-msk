# Keep in sync with the Python version in the Dockerfile
PYTHON_VERSION ?= 3.11
SITE_PACKAGES_DIR ?= $(shell python3 -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')
CONTAINER_ENGINE ?= $(shell which podman >/dev/null 2>&1 && echo podman || echo docker)

.PHONY: format
format:
	uv run ruff check
	uv run ruff format

.PHONY: image_tests
image_tests:
	# test /tmp must be empty
	[ -z "$(shell ls -A /tmp)" ]
	# validate_plan.py must exist
	[ -f "validate_plan.py" ]

.PHONY: code_tests
code_tests:
	uv run ruff check --no-fix
	uv run ruff format --check
	uv run mypy
	uv run pytest -vv --cov=er_aws_msk --cov-report=term-missing --cov-report xml

.PHONY: dependency_tests
dependency_tests:
	python -c "import cdktf_cdktf_provider_random"
	python -c "import cdktf_cdktf_provider_aws"

.PHONY: test
test: image_tests code_tests dependency_tests

.PHONY: build
build:
	$(CONTAINER_ENGINE) build --progress plain -t er-aws-msk:test .


.PHONY: dev
dev:
	uv sync --python $(PYTHON_VERSION)
	# Prepare local development environment
	$(CONTAINER_ENGINE) run --rm -it -v $(PWD)/:/home/app/src -v $(PWD)/.gen:/cdktf-providers:z quay.io/redhat-services-prod/app-sre-tenant/er-base-cdktf-main/er-base-cdktf-main:cdktf-0.20.9-tf-1.6.6-py-3.11-v0.3.0 cdktf-provider-sync /cdktf-providers
	cp sitecustomize.py $(SITE_PACKAGES_DIR)
