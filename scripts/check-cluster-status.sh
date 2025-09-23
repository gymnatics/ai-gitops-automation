#!/bin/bash

echo "🔍 OpenShift Cluster Status Check Script"
echo "========================================"
echo ""
echo "This script will check the current state of your OpenShift cluster"
echo ""

BASTION_HOST="bastion.8mdfr.sandbox647.opentlc.com"
BASTION_USER="lab-user"
BASTION_PASS="7TYn8Eh0LWGv"

# Create the cluster check script
cat > /tmp/cluster-check-commands.sh << 'EOF'
#!/bin/bash
set -e

echo "📡 Logging into OpenShift cluster..."
oc login -u admin -p redhat https://api.cluster-8mdfr.8mdfr.sandbox647.opentlc.com:6443 --insecure-skip-tls-verify=true || {
    echo "❌ Failed to login. Trying alternative credentials..."
    oc login -u kubeadmin -p $(cat ~/kubeadmin-password 2>/dev/null || echo "no-password-file") https://api.cluster-8mdfr.8mdfr.sandbox647.opentlc.com:6443 --insecure-skip-tls-verify=true || {
        echo "❌ Login failed with both admin and kubeadmin"
        exit 1
    }
}

echo ""
echo "✅ Successfully logged in as: $(oc whoami)"
echo "   Server: $(oc whoami --show-server)"
echo ""

echo "═══════════════════════════════════════════════════════════════"
echo "1️⃣  GITOPS APPLICATIONS STATUS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "All GitOps Applications:"
oc get applications -n openshift-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,MESSAGE:.status.conditions[0].message --sort-by=.metadata.name

echo ""
echo "Applications with sync issues:"
oc get applications -n openshift-gitops -o json | jq -r '.items[] | select(.status.sync.status != "Synced") | "\(.metadata.name): Sync=\(.status.sync.status), Health=\(.status.health.status)"'

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "2️⃣  GITOPS CONSOLE PLUGIN JOB STATUS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Checking for GitOps console plugin job..."
if oc get job job-gitops-console-plugin -n openshift-gitops &>/dev/null 2>&1; then
    echo "⚠️  Job exists - checking status:"
    oc get job job-gitops-console-plugin -n openshift-gitops
    echo ""
    echo "Job details:"
    oc describe job job-gitops-console-plugin -n openshift-gitops | grep -A5 "Events:" || true
else
    echo "✅ No GitOps console plugin job found (this is OK if GitOps is working)"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "3️⃣  OPENSHIFT AI OPERATOR STATUS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "OpenShift AI Operator:"
if oc get csv -n redhat-ods-operator | grep -q rhods-operator; then
    echo "✅ OpenShift AI Operator is installed"
    oc get csv -n redhat-ods-operator | grep rhods-operator
else
    echo "❌ OpenShift AI Operator NOT found"
fi

echo ""
echo "DataScienceCluster:"
if oc get datasciencecluster -n redhat-ods-operator &>/dev/null 2>&1; then
    echo "✅ DataScienceCluster exists:"
    oc get datasciencecluster -n redhat-ods-operator
    echo ""
    echo "DSC Components Status:"
    oc get datasciencecluster -n redhat-ods-operator -o json | jq -r '.items[0].status.conditions[] | "\(.type): \(.status) - \(.message)"' 2>/dev/null || echo "Could not get status"
else
    echo "❌ No DataScienceCluster found"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "4️⃣  SERVICE MESH STATUS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Service Mesh Operator:"
if oc get csv -n openshift-operators | grep -q servicemeshoperator; then
    echo "✅ Service Mesh Operator is installed"
    oc get csv -n openshift-operators | grep servicemeshoperator
else
    echo "❌ Service Mesh Operator NOT installed"
fi

echo ""
echo "Service Mesh Control Plane:"
if oc get smcp -n istio-system &>/dev/null 2>&1; then
    echo "✅ Service Mesh Control Plane exists:"
    oc get smcp -n istio-system
    echo ""
    echo "SMCP Status:"
    oc get smcp -n istio-system -o json | jq -r '.items[0].status.conditions[] | "\(.type): \(.status)"' 2>/dev/null || true
else
    echo "❌ No Service Mesh Control Plane found"
    echo "   Checking if istio-system namespace exists..."
    oc get namespace istio-system &>/dev/null && echo "   ✅ istio-system namespace exists" || echo "   ❌ istio-system namespace does not exist"
fi

echo ""
echo "Service Mesh Member Roll:"
if oc get smmr -n istio-system &>/dev/null 2>&1; then
    echo "✅ Service Mesh Member Roll exists:"
    oc get smmr -n istio-system
    echo "   Members:"
    oc get smmr -n istio-system -o json | jq -r '.items[0].spec.members[]' 2>/dev/null || echo "   Could not list members"
else
    echo "❌ No Service Mesh Member Roll found"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "5️⃣  SERVERLESS/KNATIVE STATUS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Serverless Operator:"
if oc get csv -n openshift-serverless | grep -q serverless-operator; then
    echo "✅ Serverless Operator is installed"
    oc get csv -n openshift-serverless | grep serverless-operator
else
    echo "❌ Serverless Operator NOT installed"
    echo "   Checking if openshift-serverless namespace exists..."
    oc get namespace openshift-serverless &>/dev/null && echo "   ✅ openshift-serverless namespace exists" || echo "   ❌ openshift-serverless namespace does not exist"
fi

echo ""
echo "Knative Serving:"
if oc get knativeserving -n knative-serving &>/dev/null 2>&1; then
    echo "✅ Knative Serving exists:"
    oc get knativeserving -n knative-serving
    echo ""
    echo "Knative Serving Status:"
    oc get knativeserving -n knative-serving -o json | jq -r '.items[0].status.conditions[] | "\(.type): \(.status)"' 2>/dev/null || true
else
    echo "❌ No Knative Serving found"
    echo "   Checking if knative-serving namespace exists..."
    oc get namespace knative-serving &>/dev/null && echo "   ✅ knative-serving namespace exists" || echo "   ❌ knative-serving namespace does not exist"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "6️⃣  OPENSHIFT AI DASHBOARD & ROUTES"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "RHOAI Dashboard Route:"
DASHBOARD_ROUTE=$(oc get route -n redhat-ods-applications rhods-dashboard -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [[ -n "$DASHBOARD_ROUTE" ]]; then
    echo "✅ Dashboard route: https://$DASHBOARD_ROUTE"
else
    echo "❌ No dashboard route found"
fi

echo ""
echo "All routes in RHOAI namespace:"
oc get routes -n redhat-ods-applications 2>/dev/null || echo "Could not list routes"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "7️⃣  PODS STATUS IN KEY NAMESPACES"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "OpenShift GitOps pods:"
oc get pods -n openshift-gitops | grep -v "Completed" | head -10

echo ""
echo "OpenShift AI pods:"
oc get pods -n redhat-ods-operator | head -10
echo ""
oc get pods -n redhat-ods-applications | head -10

echo ""
echo "Service Mesh pods (if exists):"
oc get pods -n istio-system 2>/dev/null | head -10 || echo "No istio-system namespace"

echo ""
echo "Knative pods (if exists):"
oc get pods -n knative-serving 2>/dev/null | head -10 || echo "No knative-serving namespace"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "8️⃣  ANYTHINGLLM TENANT STATUS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
if oc get namespace anythingllm &>/dev/null 2>&1; then
    echo "✅ AnythingLLM namespace exists"
    echo "Resources in AnythingLLM namespace:"
    oc get all -n anythingllm 2>/dev/null | head -20
else
    echo "❌ AnythingLLM namespace does not exist"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "📊 SUMMARY OF ISSUES FOUND"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Collect issues
ISSUES=()

# Check GitOps sync
if oc get applications -n openshift-gitops -o json | jq -e '.items[] | select(.status.sync.status != "Synced")' &>/dev/null; then
    ISSUES+=("⚠️  Some GitOps applications are out of sync")
fi

# Check Service Mesh
if ! oc get smcp -n istio-system &>/dev/null 2>&1; then
    ISSUES+=("❌ Service Mesh Control Plane is missing")
fi

# Check Knative
if ! oc get knativeserving -n knative-serving &>/dev/null 2>&1; then
    ISSUES+=("❌ Knative Serving is missing")
fi

# Check DataScienceCluster
if ! oc get datasciencecluster -n redhat-ods-operator &>/dev/null 2>&1; then
    ISSUES+=("❌ DataScienceCluster is missing")
fi

if [ ${#ISSUES[@]} -eq 0 ]; then
    echo "✅ No major issues found!"
else
    echo "Issues found:"
    for issue in "${ISSUES[@]}"; do
        echo "  $issue"
    done
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ Cluster check completed!"
echo ""
EOF

echo "Please provide the password when prompted: $BASTION_PASS"
echo ""

# Execute the check script on bastion
ssh -t $BASTION_USER@$BASTION_HOST 'bash -s' < /tmp/cluster-check-commands.sh

# Clean up
rm -f /tmp/cluster-check-commands.sh
