#!/bin/bash
set -e

echo "🚀 OpenShift AI GitOps Fix and Test Script"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check if we're in the right directory
if [[ ! -f "bootstrap.sh" ]]; then
    print_error "Must run from ai-gitops-automation directory"
    echo "Please run: cd ~/ai-gitops-automation"
    exit 1
fi

echo "📍 Current directory: $(pwd)"
echo ""

# Step 1: Pull latest changes
echo "1️⃣ Pulling latest changes from Git..."
git pull origin main || {
    print_warning "Could not pull latest changes. You may need to commit local changes first."
}

echo ""
echo "2️⃣ Running fix script for dynamic configuration..."
if [[ -f "./fix-dynamic-config-issues.sh" ]]; then
    ./fix-dynamic-config-issues.sh
else
    print_error "fix-dynamic-config-issues.sh not found!"
fi

echo ""
echo "3️⃣ Checking cluster login status..."
if oc whoami &>/dev/null; then
    print_status "Logged in as: $(oc whoami)"
    print_status "Server: $(oc whoami --show-server)"
else
    print_error "Not logged in to OpenShift"
    echo "Please run: oc login"
    exit 1
fi

echo ""
echo "4️⃣ Checking current application statuses..."
echo ""
echo "OpenShift AI Operator:"
oc get application openshift-ai-operator -n openshift-gitops -o json 2>/dev/null | jq -r '"  Sync: " + .status.sync.status + ", Health: " + .status.health.status' || echo "  Not found"

echo ""
echo "GPU Operator:"
oc get application nvidia-gpu-operator -n openshift-gitops -o json 2>/dev/null | jq -r '"  Sync: " + .status.sync.status + ", Health: " + .status.health.status' || echo "  Not found"

echo ""
echo "5️⃣ Checking for SharedResourceWarning..."
WARNINGS=$(oc get application openshift-ai-operator -n openshift-gitops -o json 2>/dev/null | jq -r '.status.conditions[]? | select(.type == "SharedResourceWarning") | .message' || echo "")
if [[ -n "$WARNINGS" ]]; then
    print_warning "SharedResourceWarning found - will be fixed"
else
    print_status "No SharedResourceWarning"
fi

echo ""
echo "6️⃣ Checking GPU nodes..."
GPU_NODES=$(oc get nodes -l node-role.kubernetes.io/gpu --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "$GPU_NODES" -gt 0 ]]; then
    echo "  Current GPU nodes:"
    oc get nodes -l node-role.kubernetes.io/gpu -o custom-columns=NAME:.metadata.name,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type,STATUS:.status.conditions[-1].type 2>/dev/null || true
else
    print_warning "No GPU nodes found"
fi

echo ""
echo "7️⃣ Fixing GitOps console job if needed..."
if oc get job job-gitops-console-plugin -n openshift-gitops &>/dev/null 2>&1; then
    print_warning "GitOps console job exists, running fix..."
    if [[ -f "./fix-gitops-console-job.sh" ]]; then
        ./fix-gitops-console-job.sh
    fi
else
    print_status "No GitOps console job issues"
fi

echo ""
echo "8️⃣ Syncing applications..."

# Sync OpenShift AI
echo "  Syncing OpenShift AI Operator..."
oc annotate application openshift-ai-operator -n openshift-gitops argocd.argoproj.io/refresh=normal --overwrite
oc patch application openshift-ai-operator -n openshift-gitops --type=merge \
    -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD","prune":true}}}'

# Sync GPU Operator
echo "  Syncing GPU Operator..."
oc annotate application nvidia-gpu-operator -n openshift-gitops argocd.argoproj.io/refresh=normal --overwrite
oc patch application nvidia-gpu-operator -n openshift-gitops --type=merge \
    -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD","prune":true}}}'

# Refresh tenants
echo "  Refreshing tenants ApplicationSet..."
oc patch applicationset tenants -n openshift-gitops --type=merge \
    -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"normal"}}}'

echo ""
echo "9️⃣ Waiting for sync to complete..."
sleep 10

# Check sync status
for app in openshift-ai-operator nvidia-gpu-operator; do
    echo ""
    echo "  Checking $app..."
    for i in {1..6}; do
        STATUS=$(oc get application $app -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        HEALTH=$(oc get application $app -n openshift-gitops -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        echo "    Attempt $i: Sync=$STATUS, Health=$HEALTH"
        
        if [[ "$STATUS" == "Synced" ]]; then
            print_status "$app synced!"
            break
        fi
        sleep 10
    done
done

echo ""
echo "🔟 Verifying fixes..."

# Check SharedResourceWarning again
WARNINGS=$(oc get application openshift-ai-operator -n openshift-gitops -o json 2>/dev/null | jq -r '.status.conditions[]? | select(.type == "SharedResourceWarning") | .message' || echo "")
if [[ -z "$WARNINGS" ]]; then
    print_status "SharedResourceWarning resolved!"
else
    print_error "SharedResourceWarning still present"
fi

# Check if AnythingLLM application was created
echo ""
echo "Checking AnythingLLM deployment..."
if oc get application -n openshift-gitops | grep -q anythingllm; then
    print_status "AnythingLLM application found"
    oc get application anythingllm -n openshift-gitops -o json 2>/dev/null | jq -r '"  Sync: " + .status.sync.status + ", Health: " + .status.health.status' || true
else
    print_warning "AnythingLLM application not found yet"
fi

echo ""
echo "1️⃣1️⃣ Committing and pushing any local changes..."
if [[ -n $(git status --porcelain) ]]; then
    echo "  Found local changes, committing..."
    git add -A
    git commit -m "Applied fixes for GPU instance type and AnythingLLM deployment

- Fixed stable OpenShift AI overlay configuration
- Corrected GPU instance type to g5.4xlarge
- Added AnythingLLM tenant configuration
- Resolved SharedResourceWarning"
    
    git push origin main
    print_status "Changes pushed to Git"
else
    print_status "No local changes to commit"
fi

echo ""
echo "============================================"
echo "📊 Final Status Report:"
echo "============================================"
echo ""

# Final status check
echo "Applications:"
oc get applications -n openshift-gitops | grep -E "(openshift-ai|gpu|anythingllm)" || true

echo ""
echo "GPU Nodes:"
oc get nodes -l node-role.kubernetes.io/gpu -o custom-columns=NAME:.metadata.name,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type,READY:.status.conditions[-1].type 2>/dev/null || echo "No GPU nodes found"

echo ""
echo "AnythingLLM Resources:"
oc get all -n anythingllm 2>/dev/null | head -20 || echo "AnythingLLM namespace not found yet"

echo ""
echo "============================================"
print_status "Script completed!"
echo ""
echo "Next steps:"
echo "1. Monitor GPU node creation: oc get nodes -w"
echo "2. Watch AnythingLLM deployment: oc get pods -n anythingllm -w"
echo "3. Check application statuses: oc get applications -n openshift-gitops"
echo ""
echo "If you need to re-run the bootstrap with correct parameters:"
echo "./bootstrap.sh --non-interactive --dynamic \\"
echo "  --ai-version=stable \\"
echo "  --enable-gpu \\"
echo "  --gpu-instance=g5.4xlarge \\"
echo "  --enable-anythingllm \\"
echo "  --modelcar-model=llama3.1-8b"
