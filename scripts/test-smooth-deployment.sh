#!/bin/bash
set -e

echo "🧪 Testing Smooth AI GitOps Deployment"
echo "======================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    
    echo -n "Testing: $test_name... "
    if eval "$test_cmd" &>/dev/null; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Function to check operator status
check_operator_status() {
    local operator="$1"
    local namespace="$2"
    
    oc get csv -n "$namespace" 2>/dev/null | grep -q "$operator.*Succeeded"
}

# Function to check application sync status
check_app_sync() {
    local app_name="$1"
    
    local sync_status=$(oc get application "$app_name" -n openshift-gitops -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "NotFound")
    [[ "$sync_status" == "Synced" ]]
}

# Function to check if resource exists
check_resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="$3"
    
    if [ -n "$namespace" ]; then
        oc get "$resource_type" "$resource_name" -n "$namespace" &>/dev/null
    else
        oc get "$resource_type" "$resource_name" &>/dev/null
    fi
}

echo ""
echo "Pre-deployment Checks"
echo "--------------------"

# Check if logged in
run_test "OpenShift login" "oc whoami"

# Check if bootstrap script exists
run_test "Bootstrap script exists" "[ -f scripts/bootstrap.sh ]"

# Check if dynamic config script exists
run_test "Dynamic config script exists" "[ -f scripts/dynamic_config.sh ]"

echo ""
echo "Configuration File Checks"
echo "------------------------"

# Check DataScienceCluster configuration
run_test "DataScienceCluster has sync annotations" "grep -q 'ServerSideApply=true' components/operators/openshift-ai/instance/base/datasciencecluster.yaml"

# Check ODH Dashboard config
run_test "ODH Dashboard has sync annotations" "grep -q 'ServerSideApply=true' components/operators/openshift-ai/instance/base/odhdashboardconfig.yaml"

# Check GitOps console job
run_test "GitOps console job has Replace option" "grep -q 'Replace=true' components/operators/openshift-gitops/operator/components/enable-console-plugin/console-plugin-job.yaml"

# Check kubeadmin cluster-admin
run_test "Kubeadmin cluster-admin file exists" "[ -f components/operators/openshift-ai/instance/base/kubeadmin-cluster-admin.yaml ]"

# Check health check component
run_test "OpenShift AI health check in GitOps" "grep -q 'health-check-openshift-ai' components/operators/openshift-gitops/instance/overlays/default/kustomization.yaml"

echo ""
echo "Bootstrap Function Checks"
echo "------------------------"

# Check for health check function
run_test "Health check function exists" "grep -q 'configure_gitops_health_checks' scripts/bootstrap.sh"

# Check for existing operator detection
run_test "Existing operator check exists" "grep -q 'check_existing_operators' scripts/dynamic_config.sh"

echo ""
echo "Post-Deployment Validation (if cluster has deployments)"
echo "------------------------------------------------------"

# Check if GitOps is installed
if check_operator_status "openshift-gitops-operator" "openshift-gitops-operator"; then
    echo -e "${YELLOW}Found existing GitOps deployment, checking status...${NC}"
    
    run_test "GitOps operator healthy" "check_operator_status 'openshift-gitops-operator' 'openshift-gitops-operator'"
    run_test "GitOps instance exists" "check_resource_exists 'argocd' 'openshift-gitops' 'openshift-gitops'"
    
    # Check for console plugin job issues
    run_test "No failed console plugin jobs" "! oc get jobs -n openshift-gitops-operator 2>/dev/null | grep -q 'job-gitops-console-plugin.*0/1'"
fi

# Check if OpenShift AI is installed
if check_operator_status "rhods-operator" "redhat-ods-operator"; then
    echo -e "${YELLOW}Found existing OpenShift AI deployment, checking status...${NC}"
    
    run_test "OpenShift AI operator healthy" "check_operator_status 'rhods-operator' 'redhat-ods-operator'"
    run_test "DataScienceCluster exists" "check_resource_exists 'datasciencecluster' 'default' 'redhat-ods-applications'"
    run_test "ODH Dashboard config exists" "check_resource_exists 'odhdashboardconfig' 'odh-dashboard-config' 'redhat-ods-applications'"
    
    # Check model serving components
    run_test "KServe deployments exist" "oc get deployment -n knative-serving 2>/dev/null | grep -q controller"
    run_test "ModelMesh deployments exist" "oc get deployment -n redhat-ods-applications 2>/dev/null | grep -q modelmesh"
    
    # Check permissions
    run_test "Kubeadmin has cluster-admin" "oc get clusterrolebinding add-kubeadmin &>/dev/null"
    run_test "rhods-admins group exists" "check_resource_exists 'group' 'rhods-admins'"
fi

# Check ArgoCD applications if GitOps is installed
if oc get applications -n openshift-gitops &>/dev/null; then
    echo -e "${YELLOW}Checking ArgoCD application sync status...${NC}"
    
    # Get all applications and check their sync status
    for app in $(oc get applications -n openshift-gitops -o name 2>/dev/null | cut -d'/' -f2); do
        if check_app_sync "$app"; then
            echo -e "  $app: ${GREEN}Synced${NC}"
        else
            echo -e "  $app: ${RED}Not Synced${NC}"
            ((TESTS_FAILED++))
        fi
    done
fi

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed! The deployment should run smoothly.${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed. Please review the failures above.${NC}"
    echo ""
    echo "Common fixes:"
    echo "1. For sync issues: Wait a few minutes and re-run the test"
    echo "2. For missing resources: Check if the bootstrap has completed"
    echo "3. For operator issues: Check operator logs for errors"
    exit 1
fi
