#!/bin/sh -l

# TODO: Change revision / branch name

# INPUTS
ENV_NAME=$1
AWS_ACCESS_KEY_ID=$2
AWS_SECRET_ACCESS_KEY=$3
DOCKER_IMAGE=$4
DOCKER_IMAGE_TAG=$5
DOCKER_IMAGE_ACCESS_TOKEN=$6
GIT_USER=$7
GIT_PUSH_TOKEN=$8
GIT_BRANCH="dockerfile"
ART_CONFIG_FILE=${ART_CONFIG_FILE:-".art/art.yaml"}

echo "$!"
echo "$@"

CLUSTER_NAME="shadow"

APP_NAME=$CI_PROJECT_NAME
ART_WORKSPACE=`pwd`/.art/

# Prep workspace
mkdir -p $ART_WORKSPACE
mkdir -p $ART_WORKSPACE/bin
cd $ART_WORKSPACE

# This export is redundant
export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY

# Setup kubectl config
# If there are multiple clusters, need to pick the right one - TODO
aws eks --region us-east-2 update-kubeconfig --name $CLUSTER_NAME

# Ensure sufficient permissions for reading image
kubectl create secret -n $ENV_NAME docker-registry image-pull-secret --docker-username=argonaut --docker-password=$DOCKER_IMAGE_ACCESS_TOKEN --docker-email=argonaut@argonaut.dev --docker-server=$CI_REGISTRY
### TODO: Create secret should move to cluster and app bootstrap with possibility to update it from here??

# TODO: Update argocd-app config - branch, env,
cd ../

# NOTE: This has to be in the tools namespace
# TODO: Install art cli
art app deploy -n tools -a $ART_WORKSPACE/argocd-app.yaml -f $ART_CONFIG_FILE -i $DOCKER_IMAGE -t $DOCKER_IMAGE_TAG
# TODO: Trigger a sync for the argocd-app

echo "Exiting script"