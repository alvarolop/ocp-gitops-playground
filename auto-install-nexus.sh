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
echo -e "==============\n"

# Check if the user is logged in 
if ! oc whoami &> /dev/null; then
    echo -e "Check. You are not logged in. Please log in and run the script again."
    exit 1
else
    echo -e "Check. You are correctly logged in. Continue..."
    oc project default
fi

# Install Nexus operator
echo -e "\n[1/4]Install Nexus operator"

oc process -f templates/nexus-01-operator.yaml \
    -p OPERATOR_NAMESPACE=$OPERATOR_NAMESPACE | oc apply -f -

echo -n "\tWaiting for pods ready..."
while [[ $(oc get pods -l name=nxrm-operator-certified -n $OPERATOR_NAMESPACE -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

# Provide priviledged SCC to the pod
# Workaround for issue: https://github.com/sonatype/operator-nxrm3/issues/8
echo -e "\n[2/4]Provide priviledged SCC to the pod"
oc adm policy add-scc-to-user privileged -z default -n $OPERATOR_NAMESPACE

# Deploy the Nexus repository manager instance
echo -e "\n[3/4]Deploy the Nexus repository manager instance"
oc process -f templates/nexus-02-server.yaml \
    -p OPERATOR_NAMESPACE=$OPERATOR_NAMESPACE \
    -p SERVER_NAME="$NEXUS_SERVER_NAME" | oc apply -f -

# Wait for DeploymentConfig
echo -n "Waiting for pods ready..."
while [[ $(oc get pods -l app=sonatype-nexus -n $OPERATOR_NAMESPACE -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo -n "." && sleep 1; done; echo -n -e "  [OK]\n"

NEXUS_ROUTE=$(oc get routes $NEXUS_SERVER_NAME -n $OPERATOR_NAMESPACE --template="https://{{.spec.host}}")

# Create Helm repository
# For full doc of the API, check the Swagger doc
echo -e "\n[4/4]Create Helm repository to host packaged Helm charts"

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
