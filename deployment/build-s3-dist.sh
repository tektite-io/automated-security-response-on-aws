#!/usr/bin/env bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
[[ $DEBUG ]] && set -x
set -eu -o pipefail

header() {
    declare text=$1
    echo "------------------------------------------------------------------------------"
    echo "$text"
    echo "------------------------------------------------------------------------------"
}

usage() {
    echo "Usage: $0 -b <bucket> [-v <version>] [-t]"
    echo "Version must be provided via a parameter or ../version.txt. Others are optional."
    echo "-t indicates this is a pre-prod build and instructs the build to use a non-prod Solution ID, DEV-SOxxxx"
    echo "Production example: ./build-s3-dist.sh -b solutions -v v1.0.0"
    echo "Dev example: ./build-s3-dist.sh -b solutions -v v1.0.0 -t"
}

clean() {
    declare clean_dirs=("$@")
    for dir in ${clean_dirs[@]}; do rm -rf "$dir"; done
}

# This assumes all of the OS-level configuration has been completed and git repo has already been cloned
#
# This script should be run from the repo's deployment directory
# cd deployment
# ./build-s3-dist.sh source-bucket-base-name solution-name version-code
#
# Paramenters:
#  - source-bucket-base-name: Name for the S3 bucket location where the template will source the Lambda
#    code from. The template will append '-[region_name]' to this bucket name.
#    For example: ./build-s3-dist.sh solutions v1.0.0
#    The template will then expect the source code to be located in the solutions-[region_name] bucket
#
#  - solution-name: name of the solution for consistency
#
#  - version-code: version of the package
main() {
    local root_dir=$(dirname "$(cd -P -- "$(dirname "$0")" && pwd -P)")
    local template_dir="$root_dir"/deployment
    local template_dist_dir="$template_dir"/global-s3-assets
    local build_dist_dir="$template_dir/"regional-s3-assets
    local source_dir="$root_dir"/source
    local temp_work_dir="${template_dir}"/temp
    local devtest=""

    local clean_dirs=("$template_dist_dir" "$build_dist_dir" "$temp_work_dir")

    while getopts ":b:v:tch" opt;
    do
        case "${opt}" in
            b) local bucket=${OPTARG};;
            v) local version=${OPTARG};;
            t) devtest=1;;
            c) clean "${clean_dirs[@]}" && exit 0;;
            *) usage && exit 0;;
        esac
    done

    if [[ -z "$version" ]]; then
        usage && exit 1
    fi

    # Prepend version with "v" if it does not already start with "v"
    if [[ $version != v* ]]; then
        version=v"$version"
    fi

    clean "${clean_dirs[@]}"

    # Save in environmental variables to simplify builds (?)
    echo "export DIST_OUTPUT_BUCKET=$bucket" > "$template_dir"/setenv.sh
    echo "export DIST_VERSION=$version" >> "$template_dir"/setenv.sh

    if [[ ! -e "$template_dir"/solution_env.sh ]]; then
        echo "solution_env.sh is missing from the solution root." && exit 1
    fi

    source "$template_dir"/solution_env.sh

    if [[ -z "$SOLUTION_ID" ]] || [[ -z "$SOLUTION_NAME" ]] || [[ -z "$SOLUTION_TRADEMARKEDNAME" ]]; then
        echo "Missing one of SOLUTION_ID, SOLUTION_NAME, or SOLUTION_TRADEMARKEDNAME from solution_env.sh" && exit 1
    fi

    if [[ ! -z $devtest ]]; then
        SOLUTION_ID=DEV-$SOLUTION_ID
    fi
    export SOLUTION_ID
    export SOLUTION_NAME
    export SOLUTION_TRADEMARKEDNAME

    echo "export DIST_SOLUTION_NAME=$SOLUTION_TRADEMARKEDNAME" >> ./setenv.sh

    source "$template_dir"/setenv.sh

    header "Building $SOLUTION_NAME ($SOLUTION_ID) version $version for bucket $bucket"

    header "[Init] Create folders"
    mkdir -p "$template_dist_dir"
    mkdir -p "$build_dist_dir"
    mkdir -p "$temp_work_dir"
    mkdir -p "$build_dist_dir"/lambda
    mkdir -p "$build_dist_dir"/lambda/blueprints
    mkdir -p "$build_dist_dir"/lambda/blueprints/python
    mkdir -p "$template_dist_dir"/playbooks
    mkdir -p "$template_dist_dir"/blueprints

    header "[Pack] Lambda Layer (used by playbooks)"
    # Check if poetry is available in the shell
      if command -v poetry >/dev/null 2>&1; then
        POETRY_COMMAND="poetry"
      elif [ -n "$POETRY_HOME" ] && [ -x "$POETRY_HOME/bin/poetry" ]; then
        POETRY_COMMAND="$POETRY_HOME/bin/poetry"
      else
        echo "Poetry is not available. Aborting script." >&2
        exit 1
      fi

    "$POETRY_COMMAND" export --without dev -f requirements.txt --output requirements.txt --without-hashes
    pushd "$temp_work_dir"
    mkdir -p "$temp_work_dir"/source/solution_deploy/lambdalayer/python/layer
    mkdir -p "$temp_work_dir"/source/solution_deploy/lambdalayer/python/lib/python3.11/site-packages
    cp "$source_dir"/layer/*.py "$temp_work_dir"/source/solution_deploy/lambdalayer/python/layer
    pip install -r "$template_dir"/requirements.txt -t "$temp_work_dir"/source/solution_deploy/lambdalayer/python/lib/python3.11/site-packages
    popd

    pushd "$temp_work_dir"/source/solution_deploy/lambdalayer
    zip --recurse-paths "$build_dist_dir"/lambda/layer.zip python
    popd

    header "[Pack] Custom Action Lambda"

    pushd "$source_dir"/solution_deploy/source
    zip -q ${build_dist_dir}/lambda/action_target_provider.zip action_target_provider.py cfnresponse.py
    popd

    header "[Pack] Deployment Metrics Custom Action Lambda"

    pushd "$source_dir"/solution_deploy/source
    zip -q ${build_dist_dir}/lambda/deployment_metrics_custom_resource.zip deployment_metrics_custom_resource.py cfnresponse.py
    popd


    header "[Pack] Wait Provider Lambda"

    pushd "$source_dir"/solution_deploy/source
    zip -q ${build_dist_dir}/lambda/wait_provider.zip wait_provider.py cfnresponse.py

    header "[Pack] Orchestrator Lambdas"

    pushd "$source_dir"/Orchestrator
    ls | while read file; do
        if [ ! -d $file ]; then
            zip -q "$build_dist_dir"/lambda/"$file".zip "$file"
        fi
    done
    popd

    header "[Pack] Blueprint Lambdas"

    pushd "$source_dir"/blueprints
    "$POETRY_COMMAND" export -f requirements.txt --output requirements.txt --without-hashes
    for dir in */; do
        if [ $dir == 'cdk/' ]; then
          continue
        fi

        pushd $dir/ticket_generator
        ls | while read file; do
            if [ ! -d $file ]; then
                zip -q "$build_dist_dir"/lambda/blueprints/"$file".zip "$file"
            fi
        done
        popd
    done
    popd

    pushd "$build_dist_dir"/lambda/blueprints
    mkdir -p "$build_dist_dir"/lambda/blueprints/python
    "$POETRY_COMMAND" export --without dev -f requirements.txt --output requirements.txt --without-hashes
    pip install -r "$source_dir"/blueprints/requirements.txt -t "$build_dist_dir"/lambda/blueprints/python
    zip -qr python.zip python/*
    rm -r python
    popd

    header "[Create] Playbooks"

    for playbook in $(ls "$source_dir"/playbooks); do
        if [ $playbook == 'NEWPLAYBOOK' ] || [ $playbook == '.coverage' ] || [ $playbook == 'common' ] || [ $playbook == 'playbook-index.ts' ] || [ $playbook == 'split_member_stacks.ts' ]; then
            continue
        fi
        echo Create $playbook playbook
        pushd "$source_dir"/playbooks/"$playbook"
        npx cdk synth --asset-metadata false --path-metadata false --version-reporting false --quiet
        cd cdk.out
        for template in $(ls *.template.json); do
            cp "$template" "$template_dist_dir"/playbooks/${template%.json}
        done
        popd
    done

   header "[Create] Blueprint templates"

   pushd "$source_dir"/blueprints
       for blueprintDir in */; do
           if [ $blueprintDir == 'cdk/' ]; then
            continue
           fi

           pushd ${blueprintDir}/cdk
           echo Create $blueprintDir blueprint
           npx cdk synth --asset-metadata false --path-metadata false --version-reporting false --quiet
           cd cdk.out
           for template in $(ls *.template.json); do
               cp "$template" "$template_dist_dir"/blueprints/${template%.json}
           done
           popd
       done
   popd

  header "[Create] Deployment Templates"

  pushd "$source_dir"/solution_deploy

  npx cdk synth --asset-metadata false --path-metadata false --version-reporting false --quiet
  cd cdk.out
  for template in $(ls *.template.json); do
      cp "$template" "$template_dist_dir"/${template%.json}
  done
  popd

  [ -e "$template_dir"/*.template ] && cp "$template_dir"/*.template "$template_dist_dir"/

  mv "$template_dist_dir"/SolutionDeployStack.template "$template_dist_dir"/automated-security-response-admin.template
  mv "$template_dist_dir"/MemberStack.template "$template_dist_dir"/automated-security-response-member.template
  mv "$template_dist_dir"/MemberCloudTrail*.template "$template_dist_dir"/automated-security-response-member-cloudtrail.template
  mv "$template_dist_dir"/RunbookStack.template "$template_dist_dir"/automated-security-response-remediation-runbooks.template
  mv "$template_dist_dir"/OrchestratorLogStack.template "$template_dist_dir"/automated-security-response-orchestrator-log.template
  mv "$template_dist_dir"/MemberRolesStack.template "$template_dist_dir"/automated-security-response-member-roles.template

  rm "$template_dist_dir"/*.nested.template
}

main "$@"
