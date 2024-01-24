#!/bin/sh

set -e

# Set your environment variables here
OPERATOR_NAMESPACE="openshift-gitops-operator"
ARGOCD_NAMESPACE="gitops"
ARGOCD_CLUSTER_NAME="argocd"

#############################
## Do not modify anything from this line
#############################

# Print environment variables
echo -e "\n=============="
echo -e "ENVIRONMENT VARIABLES:"
echo -e " * OPERATOR_NAMESPACE: $OPERATOR_NAMESPACE"
echo -e " * ARGOCD_NAMESPACE: $ARGOCD_NAMESPACE"
echo -e " * ARGOCD_CLUSTER_NAME: $ARGOCD_CLUSTER_NAME"
echo -e "==============\n"

# Check if the user is logged in 
if ! oc whoami &> /dev/null; then
    echo -e "Check. You are not logged. Please log in and run the script again."
    exit 1
else
    echo -e "Check. You are correctly logged in. Continue..."
    if ! oc project &> /dev/null; then
        echo -e "Current project does not exist, moving to project Default."
        oc project default 
    fi
fi

# Install OpenShift GitOps operator
echo -e "\n[1/3]Install OpenShift GitOps operator"

oc process -f openshift/01-operator.yaml \
    -p OPERATOR_NAMESPACE=$OPERATOR_NAMESPACE | oc apply -f -

echo -n "Waiting for pods ready..."
while [[ $(oc get pods -l control-plane=gitops-operator -n $OPERATOR_NAMESPACE -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

# Deploy the ArgoCD instance
echo -e "\n[2/3]Deploy the ArgoCD instance"
oc process -f openshift/02-argocd.yaml \
    -p ARGOCD_NAMESPACE=$ARGOCD_NAMESPACE \
    -p ARGOCD_CLUSTER_NAME="$ARGOCD_CLUSTER_NAME" | oc apply -f -

# Wait for DeploymentConfig
echo -n "Waiting for pods ready..."
while [[ $(oc get pods -l app.kubernetes.io/name=${ARGOCD_CLUSTER_NAME}-server -n $ARGOCD_NAMESPACE -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

ARGOCD_ROUTE=$(oc get routes $ARGOCD_CLUSTER_NAME-server -n $ARGOCD_NAMESPACE --template="https://{{.spec.host}}")

# Create the ArgoCD ConsoleLink
echo -e "\n[3/3]Create the ArgoCD ConsoleLink"
oc process -f openshift/03-consolelink.yaml \
    -p ARGOCD_ROUTE=$ARGOCD_ROUTE \
    -p ARGOCD_NAMESPACE=$ARGOCD_NAMESPACE \
    -p ARGOCD_CLUSTER_NAME="$ARGOCD_CLUSTER_NAME" | oc apply -f -

echo ""
echo -e "OpenShift GitOps information:"
echo -e "\t* URL: $ARGOCD_ROUTE"
