#!/bin/bash

echo "🧹 OpenShift Cluster Cleanup Script"
echo "==================================="
echo ""
echo "⚠️  WARNING: This script will remove ALL GitOps-managed resources!"
echo "This includes operators, configurations, and applications."
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if logged in
if ! oc whoami &>/dev/null; then
    echo -e "${RED}❌ Not logged into OpenShift${NC}"
    echo "Please run: oc login"
    exit 1
fi

echo -e "${GREEN}✅ Logged in as: $(oc whoami)${NC}"
echo ""

echo "Starting cleanup process..."
echo ""

echo "1️⃣ Removing AnythingLLM tenant resources..."
oc delete namespace anythingllm --ignore-not-found=true --wait=false

echo ""
echo "2️⃣ Removing all GitOps Applications..."
# Delete all applications except the gitops operator itself
oc get applications -n openshift-gitops -o name 2>/dev/null | grep -v "openshift-gitops-operator" | while read app; do
    echo "  Deleting $app..."
    oc delete $app -n openshift-gitops --wait=false
done

echo ""
echo "3️⃣ Removing ApplicationSets..."
oc delete applicationset --all -n openshift-gitops --wait=false

echo ""
echo "4️⃣ Removing DataScienceCluster..."
oc delete datasciencecluster --all -n redhat-ods-operator --ignore-not-found=true --wait=false

echo ""
echo "5️⃣ Removing Service Mesh components..."
oc delete smmr --all -n istio-system --ignore-not-found=true --wait=false
oc delete smcp --all -n istio-system --ignore-not-found=true --wait=false
sleep 5
oc delete namespace istio-system --ignore-not-found=true --wait=false

echo ""
echo "6️⃣ Removing Knative Serving..."
oc delete knativeserving --all -n knative-serving --ignore-not-found=true --wait=false
oc delete knativeeventing --all -n knative-eventing --ignore-not-found=true --wait=false
sleep 5
oc delete namespace knative-serving knative-eventing --ignore-not-found=true --wait=false

echo ""
echo "7️⃣ Removing GPU nodes (if any)..."
# Scale down machinesets with GPU labels
for ms in $(oc get machineset -n openshift-machine-api -o name | xargs -I {} sh -c 'oc get {} -n openshift-machine-api -o json | grep -q "node-role.kubernetes.io/gpu" && echo {}'); do
    echo "  Scaling down $ms..."
    oc scale $ms -n openshift-machine-api --replicas=0
done

echo ""
echo "8️⃣ Removing Operators..."
# Order matters - remove in reverse dependency order

# Remove OpenShift AI
echo "  Removing OpenShift AI operator..."
oc delete csv -n redhat-ods-operator -l operators.coreos.com/rhods-operator.redhat-ods-operator --ignore-not-found=true
oc delete subscription rhods-operator -n redhat-ods-operator --ignore-not-found=true
sleep 10
oc delete namespace redhat-ods-operator redhat-ods-applications redhat-ods-monitoring --ignore-not-found=true --wait=false

# Remove Serverless
echo "  Removing Serverless operator..."
oc delete csv -n openshift-serverless -l operators.coreos.com/serverless-operator.openshift-serverless --ignore-not-found=true
oc delete subscription serverless-operator -n openshift-serverless --ignore-not-found=true
sleep 10
oc delete namespace openshift-serverless --ignore-not-found=true --wait=false

# Remove Service Mesh
echo "  Removing Service Mesh operator..."
oc delete csv -n openshift-operators -l operators.coreos.com/servicemeshoperator.openshift-operators --ignore-not-found=true
oc delete subscription servicemeshoperator -n openshift-operators --ignore-not-found=true

# Remove Authorino
echo "  Removing Authorino operator..."
oc delete csv -n openshift-operators -l operators.coreos.com/authorino-operator.openshift-operators --ignore-not-found=true
oc delete subscription authorino-operator -n openshift-operators --ignore-not-found=true

# Remove Pipelines
echo "  Removing Pipelines operator..."
oc delete csv -n openshift-operators -l operators.coreos.com/openshift-pipelines-operator-rh.openshift-operators --ignore-not-found=true
oc delete subscription openshift-pipelines-operator-rh -n openshift-operators --ignore-not-found=true

# Remove GPU Operator
echo "  Removing GPU operator..."
oc delete csv -n nvidia-gpu-operator -l operators.coreos.com/gpu-operator-certified.nvidia-gpu-operator --ignore-not-found=true
oc delete subscription gpu-operator-certified -n nvidia-gpu-operator --ignore-not-found=true
sleep 10
oc delete namespace nvidia-gpu-operator --ignore-not-found=true --wait=false

# Remove NFD
echo "  Removing NFD operator..."
oc delete csv -n openshift-nfd -l operators.coreos.com/nfd.openshift-nfd --ignore-not-found=true
oc delete subscription nfd -n openshift-nfd --ignore-not-found=true
sleep 10
oc delete namespace openshift-nfd --ignore-not-found=true --wait=false

# Remove Elasticsearch
echo "  Removing Elasticsearch operator..."
# ECK operator can be in either namespace
oc delete csv -n openshift-operators-redhat -l operators.coreos.com/elasticsearch-operator.openshift-operators-redhat --ignore-not-found=true
oc delete csv -n openshift-operators -l operators.coreos.com/elasticsearch-eck-operator-certified.openshift-operators --ignore-not-found=true
oc delete subscription elasticsearch-operator -n openshift-operators-redhat --ignore-not-found=true
oc delete subscription elasticsearch-eck-operator-certified -n openshift-operators --ignore-not-found=true

echo ""
echo "9️⃣ Cleaning up remaining resources..."

# Clean up any remaining CRDs from removed operators
echo "  Removing operator CRDs..."
for crd in $(oc get crd -o name | grep -E "(servicemesh|maistra|kiali|jaeger|elastic|knative|serving|eventing|datasciencecluster|notebook|nfd|nvidia)"); do
    echo "    Removing $crd..."
    oc delete $crd --wait=false
done

# Remove MinIO if it exists
echo "  Removing MinIO..."
oc delete namespace minio --ignore-not-found=true --wait=false

echo ""
echo "🔟 Removing GitOps itself..."
read -p "Do you also want to remove OpenShift GitOps? (yes/no): " remove_gitops
if [[ "$remove_gitops" == "yes" ]]; then
    oc delete csv -n openshift-gitops-operator -l operators.coreos.com/openshift-gitops-operator.openshift-gitops-operator --ignore-not-found=true
    oc delete subscription openshift-gitops-operator -n openshift-gitops-operator --ignore-not-found=true
    sleep 10
    oc delete namespace openshift-gitops openshift-gitops-operator --ignore-not-found=true --wait=false
    echo -e "${GREEN}✅ GitOps removed${NC}"
else
    echo "GitOps operator retained."
fi

echo ""
echo "1️⃣1️⃣ Final cleanup..."
# Remove any lingering namespaces
for ns in $(oc get namespace -o name | grep -E "(redhat-ods|istio|knative|nvidia|anythingllm|minio)"); do
    echo "  Removing $ns..."
    oc delete $ns --wait=false
done

echo ""
echo "Waiting for resources to be removed..."
sleep 30

echo ""
echo "==================================="
echo "✅ Cleanup completed!"
echo ""
echo "Your cluster should now be in a bare state."
echo "You can verify by checking:"
echo "  oc get operators"
echo "  oc get applications -A"
echo "  oc get namespace"
echo ""
echo "To reinstall, run:"
echo "  ./bootstrap.sh"
