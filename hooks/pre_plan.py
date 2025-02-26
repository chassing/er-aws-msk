#!/usr/bin/env python

import logging
import subprocess  # noqa: S404
from collections.abc import Sequence

from external_resources_io.config import Action, Config
from external_resources_io.input import parse_model, read_input_from_file
from external_resources_io.log import setup_logging
from external_resources_io.terraform import terraform_run

from er_aws_msk.app_interface_input import AppInterfaceInput

logger = logging.getLogger(__name__)


def migrate_resources(resources: Sequence[str], identifier: str) -> bool:
    """Migrate terraform resources."""
    changes = False
    for resource in resources:
        resource_class, *_, resource_id = resource.split(".")
        if resource_id.startswith("this"):
            # Skip resources that are already migrated
            continue

        match resource_class:
            case (
                "aws_kms_alias"
                | "aws_kms_key"
                | "aws_msk_cluster"
                | "aws_msk_configuration"
            ):
                # single resource class
                # aws_kms_alias.example-msk-msk-scram -> aws_kms_alias.this
                new_resource = f"{resource_class}.this"
            case "aws_cloudwatch_log_group" | "aws_msk_scram_secret_association":
                # resource classe with multiple occurrences via count
                # aws_cloudwatch_log_group.example-msk-msk-broker-logs -> aws_cloudwatch_log_group.this[0]
                new_resource = f"{resource_class}.this[0]"
            case (
                "aws_secretsmanager_secret"
                | "aws_secretsmanager_secret_policy"
                | "aws_secretsmanager_secret_version"
            ):
                # resource class with multiple occurrences via for each scram_users
                # aws_secretsmanager_secret.AmazonMSK_example-msk-user1-secret -> aws_secretsmanager_secret.this["user1"]
                index = (
                    resource_id.removeprefix(f"AmazonMSK_{identifier}-")
                    .removesuffix("-secret")
                    .removesuffix("-secret-policy")
                    .removesuffix("-secret-version")
                )
                new_resource = f'{resource_class}.this["{index}"]'
            case _:
                raise ValueError(f"Unsupported resource class: {resource_class}")

        logger.info(f"Migrate resource: {resource} -> {new_resource}")
        terraform_run(["state", "mv", resource, new_resource], dry_run=False)
        changes = True
    return changes


def main() -> None:
    """Run terraform migrations."""
    if Config().action == Action.DESTROY:
        # do nothing
        return

    logger.info("Running CDKTF -> Terraform HCL migration ...")
    try:
        resources = terraform_run(["state", "list"], dry_run=False).splitlines()
    except subprocess.CalledProcessError:
        # not state file found
        logger.info("No state file found. Skipping migration.")
        return

    ai_input = parse_model(AppInterfaceInput, read_input_from_file())
    changes = migrate_resources(
        resources=resources,
        identifier=ai_input.provision.identifier,
    )
    if not changes:
        # nothing to migrate. good.
        logger.info("No resources to migrate.")
        return

    logger.info("Migration completed!")


if __name__ == "__main__":
    setup_logging()
    main()
