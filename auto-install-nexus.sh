#!/bin/sh

set -e

# Set your environment variables here
OPERATOR_NAMESPACE="nexus"
NEXUS_SERVER_NAME="nexus-server"

#############################
## Do not modify anything from this line
#############################

# Print environment variables
echo -e "\n=============="
echo -e "ENVIRONMENT VARIABLES:"
echo -e " * OPERATOR_NAMESPACE: $OPERATOR_NAMESPACE"
echo -e " * NEXUS_SERVER_NAME: $NEXUS_SERVER_NAME"
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

# Install Nexus operator
echo -e "\n[1/3]Install Nexus operator"

oc process -f templates/nexus/01-operator.yaml \
    -p OPERATOR_NAMESPACE=$OPERATOR_NAMESPACE | oc apply -f -

echo -n "Waiting for pods ready..."
while [[ $(oc get pods -l name=nxrm-operator-certified -n $OPERATOR_NAMESPACE -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

# Deploy the Nexus repository manager instance
echo -e "\n[2/3]Deploy the Nexus repository manager instance"
oc process -f templates/nexus/02-server.yaml \
    -p OPERATOR_NAMESPACE=$OPERATOR_NAMESPACE \
    -p SERVER_NAME="$NEXUS_SERVER_NAME" | oc apply -f -

# Wait for DeploymentConfig
echo -n "Waiting for pods ready..."
while [[ $(oc get pods -l app=sonatype-nexus -n $OPERATOR_NAMESPACE -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

NEXUS_ROUTE=$(oc get routes $NEXUS_SERVER_NAME -n $OPERATOR_NAMESPACE --template="https://{{.spec.host}}")

# Create Helm repository
# For full doc of the API, check the Swagger doc
echo -e "\n[3/3]Create Helm repository to host packaged Helm charts"

curl -u admin:admin123 -X 'POST' \
  "$NEXUS_ROUTE/service/rest/v1/repositories/helm/hosted" \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
  "name": "helm-charts",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "ALLOW"
  },
  "cleanup": {
    "policyNames": [
      "string"
    ]
  },
  "component": {
    "proprietaryComponents": true
  }
}'

echo -e "Nexus information:"
echo -e "\t* URL: $NEXUS_ROUTE"
echo -e "\t* Username: admin"
echo -e "\t* Password: admin123"
echo -e "\t* Repository: helm-charts"
