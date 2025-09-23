#!/bin/bash
set -e

echo "🔧 Fixing AI GitOps Automation Issues"
echo "======================================"

# Source required functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"
source "${SCRIPT_DIR}/util.sh"

# Function to fix GitOps console plugin job
fix_gitops_console_plugin() {
    echo ""
    echo "1️⃣ Fixing GitOps Console Plugin Job"
    echo "-----------------------------------"
    
    # Delete the existing job to allow recreation
    echo "Deleting existing job-gitops-console-plugin..."
    oc delete job job-gitops-console-plugin -n openshift-gitops-operator --ignore-not-found=true
    
    # Force sync the GitOps operator application
    echo "Force syncing GitOps operator..."
    GITOPS_APP=$(oc get applications -n openshift-gitops -o name | grep gitops-operator || echo "")
    if [ -n "$GITOPS_APP" ]; then
        oc patch $GITOPS_APP -n openshift-gitops --type=merge -p '{"operation":{"sync":{"syncStrategy":{"hook":{"force":true}}}}}'
    fi
    
    echo "✅ GitOps console plugin job fix applied"
}

# Function to fix OpenShift AI sync issues
fix_openshift_ai_sync() {
    echo ""
    echo "2️⃣ Fixing OpenShift AI Sync Issues"
    echo "-----------------------------------"
    
    # First, ensure the health check is properly configured
    echo "Ensuring OpenShift AI health check is configured..."
    GITOPS_INSTANCE_APP=$(oc get applications -n openshift-gitops -o name | grep openshift-gitops-instance || echo "")
    
    if [ -n "$GITOPS_INSTANCE_APP" ]; then
        # Check if health check component is enabled
        kubectl get application openshift-gitops-instance -n openshift-gitops -o yaml | grep -q "health-check-openshift-ai" || {
            echo "Adding health check component to GitOps instance..."
            oc patch application openshift-gitops-instance -n openshift-gitops --type=json -p='[{"op": "add", "path": "/spec/source/helm/parameters/-", "value": {"name": "server.components", "value": "health-check-openshift-ai"}}]' 2>/dev/null || true
        }
    fi
    
    # Add server-side apply to problematic resources
    echo "Adding server-side apply annotations to OpenShift AI resources..."
    
    # Patch the OpenShift AI application
    AI_APP=$(oc get applications -n openshift-gitops -o name | grep openshift-ai-operator || echo "")
    if [ -n "$AI_APP" ]; then
        oc patch $AI_APP -n openshift-gitops --type=merge -p '{
            "spec": {
                "syncPolicy": {
                    "syncOptions": ["ServerSideApply=true", "CreateNamespace=true", "PrunePropagationPolicy=background"]
                }
            }
        }'
    fi
    
    echo "✅ OpenShift AI sync configuration updated"
}

# Function to fix model serving platform
fix_model_serving_platform() {
    echo ""
    echo "3️⃣ Fixing Model Serving Platform"
    echo "---------------------------------"
    
    # Check if the DataScienceCluster exists
    echo "Checking DataScienceCluster status..."
    DSC_EXISTS=$(oc get datasciencecluster default -n redhat-ods-applications 2>/dev/null || echo "not-found")
    
    if [[ "$DSC_EXISTS" == "not-found" ]]; then
        echo "DataScienceCluster not found. Waiting for it to be created..."
        sleep 30
    fi
    
    # Ensure both KServe and ModelMesh are properly configured
    echo "Ensuring model serving components are enabled..."
    oc patch datasciencecluster default -n redhat-ods-applications --type=merge -p '{
        "spec": {
            "components": {
                "kserve": {
                    "managementState": "Managed",
                    "serving": {
                        "managementState": "Managed",
                        "name": "knative-serving",
                        "ingressGateway": {
                            "certificate": {
                                "type": "OpenshiftDefaultIngress"
                            }
                        }
                    }
                },
                "modelmeshserving": {
                    "managementState": "Managed"
                }
            }
        }
    }' 2>/dev/null || echo "DataScienceCluster not ready yet"
    
    # Ensure Service Mesh is properly configured
    echo "Checking Service Mesh configuration..."
    SMCP_EXISTS=$(oc get smcp minimal -n istio-system 2>/dev/null || echo "not-found")
    if [[ "$SMCP_EXISTS" == "not-found" ]]; then
        echo "⚠️  Service Mesh Control Plane not found. Model serving requires Service Mesh."
        echo "   Ensure openshift-servicemesh operator is properly installed and configured."
    fi
    
    echo "✅ Model serving platform configuration applied"
}

# Function to fix permissions
fix_permissions() {
    echo ""
    echo "4️⃣ Fixing OpenShift AI Permissions"
    echo "-----------------------------------"
    
    # Apply the kubeadmin cluster-admin binding
    echo "Adding kubeadmin to cluster-admin role..."
    cat <<EOF | oc apply -f -
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: add-kubeadmin
subjects:
  - kind: User
    apiGroup: rbac.authorization.k8s.io
    name: 'kube:admin'
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
EOF
    
    # Update the ODH Dashboard config to include admin groups
    echo "Updating ODH Dashboard admin groups..."
    oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge -p '{
        "spec": {
            "groupsConfig": {
                "adminGroups": "rhods-admins,cluster-admins",
                "allowedGroups": "system:authenticated"
            }
        }
    }' 2>/dev/null || echo "ODH Dashboard config not ready yet"
    
    # Create rhods-admins group and add kubeadmin
    echo "Creating rhods-admins group..."
    cat <<EOF | oc apply -f -
apiVersion: user.openshift.io/v1
kind: Group
metadata:
  name: rhods-admins
users:
  - kube:admin
EOF
    
    echo "✅ Permissions configured"
}

# Function to restart affected components
restart_components() {
    echo ""
    echo "5️⃣ Restarting Affected Components"
    echo "----------------------------------"
    
    # Restart GitOps application controller
    echo "Restarting GitOps application controller..."
    oc delete pods -l app.kubernetes.io/name=openshift-gitops-application-controller -n openshift-gitops --ignore-not-found=true
    
    # Restart ODH Dashboard
    echo "Restarting ODH Dashboard..."
    oc delete pods -l app=rhods-dashboard -n redhat-ods-applications --ignore-not-found=true
    
    # Restart ODH operator
    echo "Restarting OpenShift AI operator..."
    oc delete pods -l name=rhods-operator -n redhat-ods-operator --ignore-not-found=true
    
    echo "✅ Components restarted"
}

# Function to verify fixes
verify_fixes() {
    echo ""
    echo "6️⃣ Verifying Fixes"
    echo "------------------"
    
    # Check GitOps sync status
    echo "Checking GitOps applications sync status..."
    oc get applications -n openshift-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
    
    # Check DataScienceCluster status
    echo ""
    echo "Checking DataScienceCluster status..."
    oc get datasciencecluster default -n redhat-ods-applications -o jsonpath='{.status.conditions[*].type}{"\n"}{.status.conditions[*].status}{"\n"}' 2>/dev/null || echo "DataScienceCluster not ready"
    
    # Check model serving platforms
    echo ""
    echo "Checking model serving platforms..."
    echo "KServe status:"
    oc get deployment -n knative-serving 2>/dev/null | grep -E "controller|webhook" || echo "KServe not deployed"
    echo ""
    echo "ModelMesh status:"
    oc get deployment -n redhat-ods-applications 2>/dev/null | grep modelmesh || echo "ModelMesh not deployed"
    
    echo ""
    echo "✅ Verification complete"
}

# Main execution
main() {
    echo "Starting fixes at $(date)"
    
    # Check if logged into OpenShift
    if ! oc whoami &>/dev/null; then
        echo "❌ Error: Not logged into OpenShift. Please run 'oc login' first."
        exit 1
    fi
    
    # Apply fixes in order
    fix_gitops_console_plugin
    fix_openshift_ai_sync
    fix_model_serving_platform
    fix_permissions
    restart_components
    
    echo ""
    echo "⏳ Waiting 30 seconds for components to stabilize..."
    sleep 30
    
    verify_fixes
    
    echo ""
    echo "🎉 All fixes applied!"
    echo ""
    echo "Next steps:"
    echo "1. Wait 2-3 minutes for all components to fully sync"
    echo "2. Check the GitOps UI for sync status"
    echo "3. Access the OpenShift AI dashboard and verify all features are visible"
    echo "4. If issues persist, run this script again or check individual component logs"
    
    # Get routes for easy access
    GITOPS_ROUTE=$(oc get route openshift-gitops-server -o jsonpath='{.spec.host}' -n openshift-gitops 2>/dev/null || echo "not-found")
    AI_ROUTE=$(oc get route rhods-dashboard -o jsonpath='{.spec.host}' -n redhat-ods-applications 2>/dev/null || echo "not-found")
    
    echo ""
    echo "📌 Useful URLs:"
    [[ "$GITOPS_ROUTE" != "not-found" ]] && echo "   GitOps UI: https://${GITOPS_ROUTE}"
    [[ "$AI_ROUTE" != "not-found" ]] && echo "   OpenShift AI: https://${AI_ROUTE}"
}

# Run main function
main "$@"
