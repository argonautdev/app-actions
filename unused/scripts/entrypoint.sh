#!/bin/sh -l

# INPUTS
NAME=$1
AWS_ACCESS_KEY_ID=$2
AWS_SECRET_ACCESS_KEY=$3
DOCKER_IMAGE=$4
DOCKER_IMAGE_DIGEST=$5
DOCKER_IMAGE_ACCESS_TOKEN=$6
GIT_USER=$7
GIT_PAT=$8

APP_NAME=`echo $GITHUB_REPOSITORY | cut -d'/' -f 2`
ARGONAUT_WORKSPACE=`pwd`/argonaut-workspace
CONFIG_PATH=`pwd`/argonaut-configs

CLUSTER_NAME="shadow"

# Prep workspace
mkdir -p $ARGONAUT_WORKSPACE
mkdir -p $ARGONAUT_WORKSPACE/bin
export PATH="$ARGONAUT_WORKSPACE/bin":$PATH

cd $ARGONAUT_WORKSPACE

apk add curl bash zlib-dev binutils jq

# SETUP kubectl
echo "Setting up kubectl"
curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl
mv kubectl ./bin

# SETUP aws configure
echo "Setting up aws-cli"
wget -q -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub
wget -q https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.32-r0/glibc-2.32-r0.apk
wget -q https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.32-r0/glibc-bin-2.32-r0.apk
apk add glibc-2.32-r0.apk glibc-bin-2.32-r0.apk

curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
aws/install --bin-dir ./bin

export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY

# Setup kubectl config
aws eks --region us-east-2 update-kubeconfig --name $CLUSTER_NAME

# Install ArgoCD CLI
echo "Installing ArgoCD CLI"

export ARGOCD_SERVER=`kubectl get svc argocd-server -n argocd -o json | jq --raw-output .status.loadBalancer.ingress[0].hostname`
export ARGO_PWD=`kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2`

curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/v1.7.8/argocd-linux-amd64
chmod a+x /usr/local/bin/argocd

echo "Sleeping for 20s to give time for argocd resources to be spun up"
sleep 20s

# Access the argocd operator
argocd login $ARGOCD_SERVER --username admin --password $ARGO_PWD --insecure
argocd cluster list
export CONTEXT_NAME=`kubectl config view -o jsonpath='{.contexts[].name}'`
argocd cluster add $CONTEXT_NAME
# If there are multiple clusters, need to pick the right one
export CLUSTER_SERVER=`argocd cluster list | sed -n 2p | cut -d' ' -f 1`



# Create namespace for the app
echo "Creating app namespace: $APP_NAME"
kubectl create namespace $APP_NAME

# Ensure sufficient permissions for reading image
kubectl create secret -n $APP_NAME docker-registry image-pull-secret --docker-username=argonautdev --docker-password=$DOCKER_IMAGE_ACCESS_TOKEN --docker-email=suryaoruganti@gmail.com --docker-server=ghcr.io
### TODO: Update pod deployment spec to have imagePullSecrets
### TODO: Create secret should move to cluster and app bootstrap with possibility to update it from here??

# Create ArgoCD app release
echo "Creating ArgoCD app release"

argocd app create "$APP_NAME-release" --repo https://github.com/$GITHUB_REPOSITORY.git --path helm-config --dest-server $CLUSTER_SERVER --dest-namespace $APP_NAME --auto-prune --sync-policy automated
argocd app sync "$APP_NAME-release"

# Update docker image with latest tag
cd $CONFIG_PATH

echo "Updating docker image tag - fetch repo"
apk add --no-cache git
git remote set-url origin https://${GIT_USER}:${GIT_PAT}@github.com/$GITHUB_REPOSITORY.git
git config --global user.email "argonaut@argonaut.dev"
git config --global user.name "[Argonaut]"

# Install yq
wget -O $ARGONAUT_WORKSPACE/bin/yq "https://github.com/mikefarah/yq/releases/download/3.4.0/yq_linux_amd64"
chmod a+x $ARGONAUT_WORKSPACE/bin/yq

yq w -i values.yaml image $DOCKER_IMAGE
yq w -i values.yaml imageTag $DOCKER_IMAGE_DIGEST
echo "Updated values file digest"
cat values.yaml

echo "Git commit of new image (excluding tmp files)"
git add values.yaml
git commit -m '[skip ci] Updated the image digest'
export BRANCH_NAME=${GITHUB_REF#refs/heads/}
git push origin $BRANCH_NAME


# # SETUP argonaut
# curl -s "https://raw.githubusercontent.com/argonautdev/argonaut-actions/master/bin/argonaut-linux-amd64" -o "argonaut"
# mv argonaut ./bin/argonaut
# chmod +x ./bin/argonaut

# # argonaut build
# # argonaut apply


cd ../
# Get the lay of the land
pwd
ls -al
env

# Reading TEST env var
echo "Reading TEST env var: $TEST"
