#!/usr/bin/env bash
set -e

# Use /credentials as AWS credentials file if it exists
test -f /credentials && export AWS_SHARED_CREDENTIALS_FILE="/credentials"

if [[ -z "$AWS_SHARED_CREDENTIALS_FILE" ]]; then
    echo "Either AWS_SHARED_CREDENTIALS_FILE or /credentials file must be set"
    exit 1
fi

DRY_RUN=${DRY_RUN:-"True"}
ACTION=${ACTION:-"Apply"}

if [[ $DRY_RUN != "True" ]] && [[ $DRY_RUN != "False" ]]; then
    echo "Invalid DRY_RUN option: $DRY_RUN. Must be 'True' or 'False'"
    exit 1
fi

if [[ $ACTION != "Apply" ]] && [[ $ACTION != "Destroy" ]]; then
    echo "Invalid ACTION option: $ACTION. Must be 'Apply' or 'Destroy'"
    exit 1
fi

echo "Starting CDKTF: ACTION=$ACTION with DRY_RUN=$DRY_RUN"

# CDKTF output options
export CI=true
export FORCE_COLOR=${FORCE_COLOR:-"0"}
export TF_CLI_ARGS=${TF_CLI_ARGS:-"-no-color"}
export ER_OUTDIR=${ER_OUTDIR:-"/tmp/cdktf.out"}

OUTPUT_FILE=${OUTPUT_FILE:-"/work/output.json"}
CDKTF_OUT_DIR="$ER_OUTDIR/stacks/CDKTF"
TERRAFORM_CMD="terraform -chdir=$CDKTF_OUT_DIR"

# CDKTF init forces the provider re-download to calculate
# Other platform provider SHAs. USing terraform to init the configuration avoids it
# This shuold be reevaluated in the future.
# https://github.com/hashicorp/terraform-cdk/issues/3622
cdktf synth --output "$ER_OUTDIR"
$TERRAFORM_CMD init

if [[ $ACTION == "Apply" ]]; then
    if [[ $DRY_RUN == "True" ]]; then
        cdktf plan --skip-synth --output "$ER_OUTDIR"
        if [ -f "validate_plan.py" ]; then
            $TERRAFORM_CMD show -json "$CDKTF_OUT_DIR"/plan > "$CDKTF_OUT_DIR"/plan.json
            python3 validate_plan.py "$CDKTF_OUT_DIR"/plan.json
        fi
    elif [[ $DRY_RUN == "False" ]]; then
        # cdktf apply isn't reliable for now, using terraform apply instead
        $TERRAFORM_CMD apply -auto-approve
        $TERRAFORM_CMD output -json > "$OUTPUT_FILE"
    fi
elif [[ $ACTION == "Destroy" ]]; then
    if [[ $DRY_RUN == "True" ]]; then
        $TERRAFORM_CMD plan -destroy
    elif [[ $DRY_RUN == "False" ]]; then
        cdktf destroy \
            --auto-approve \
            --output "$ER_OUTDIR"
    fi
fi
