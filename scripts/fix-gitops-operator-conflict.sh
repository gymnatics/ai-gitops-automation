#!/bin/bash
set -e

echo "🔧 Fixing GitOps Operator Installation Conflict"
echo "=============================================="

# Function to check if GitOps is already installed
check_existing_gitops() {
    echo "Checking for existing GitOps installation..."
    
    # Check for GitOps CSV
    EXISTING_CSV=$(oc get csv -n openshift-gitops-operator 2>/dev/null | grep openshift-gitops-operator | awk '{print $1}' || echo "")
    
    if [ -n "$EXISTING_CSV" ]; then
        echo "✅ Found existing GitOps operator: $EXISTING_CSV"
        CSV_STATUS=$(oc get csv $EXISTING_CSV -n openshift-gitops-operator -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo "   Status: $CSV_STATUS"
        return 0
    else
        echo "❌ No existing GitOps operator found"
        return 1
    fi
}

# Function to update bootstrap script to skip GitOps installation if already exists
update_bootstrap_behavior() {
    echo ""
    echo "Creating enhanced bootstrap wrapper..."
    
    cat > /Users/dayeo/ai-gitops-automation/scripts/bootstrap-enhanced.sh <<'EOF'
#!/bin/bash
set -e

# Enhanced bootstrap script that handles existing GitOps installations

# Source the original bootstrap script functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"
source "${SCRIPT_DIR}/util.sh"
source "${SCRIPT_DIR}/command_flags.sh" "$@"

# Override the install_gitops function
install_gitops_smart() {
    echo
    echo "Checking GitOps Operator status..."
    
    # Check if GitOps is already installed
    EXISTING_CSV=$(oc get csv -n openshift-gitops-operator 2>/dev/null | grep openshift-gitops-operator | awk '{print $1}' || echo "")
    
    if [ -n "$EXISTING_CSV" ]; then
        CSV_STATUS=$(oc get csv $EXISTING_CSV -n openshift-gitops-operator -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        
        if [ "$CSV_STATUS" == "Succeeded" ]; then
            echo "✅ GitOps operator is already installed and running (CSV: $EXISTING_CSV)"
            echo "   Skipping GitOps installation..."
            return 0
        else
            echo "⚠️  GitOps operator exists but not in Succeeded state (Status: $CSV_STATUS)"
            echo "   Proceeding with installation check..."
        fi
    fi
    
    # Call original install_gitops if not already installed
    source "${SCRIPT_DIR}/bootstrap.sh"
    install_gitops
}

# Replace the install_gitops call with our smart version
sed -i.bak 's/install_gitops$/install_gitops_smart/' "${SCRIPT_DIR}/bootstrap.sh"

# Run the modified bootstrap
"${SCRIPT_DIR}/bootstrap.sh" "$@"

# Restore original bootstrap
mv "${SCRIPT_DIR}/bootstrap.sh.bak" "${SCRIPT_DIR}/bootstrap.sh"
EOF
    
    chmod +x /Users/dayeo/ai-gitops-automation/scripts/bootstrap-enhanced.sh
    echo "✅ Enhanced bootstrap script created"
}

# Function to fix dynamic configuration to handle existing GitOps
fix_dynamic_config() {
    echo ""
    echo "Updating dynamic configuration to handle existing GitOps..."
    
    # Check if dynamic overlay exists
    DYNAMIC_PATCH="/Users/dayeo/ai-gitops-automation/clusters/overlays/dynamic/patch-operators-list.yaml"
    
    if [ -f "$DYNAMIC_PATCH" ]; then
        echo "Checking if GitOps operator is in dynamic configuration..."
        
        # Create a backup
        cp "$DYNAMIC_PATCH" "${DYNAMIC_PATCH}.backup"
        
        # Check if GitOps is already installed
        if check_existing_gitops; then
            echo "Removing GitOps operator from dynamic patch (already installed)..."
            
            # Use yq to remove the GitOps operator entry
            yq eval 'del(.spec.generators[0].elements[] | select(.values.name == "openshift-gitops-operator"))' -i "$DYNAMIC_PATCH"
            
            echo "✅ Updated dynamic configuration"
        fi
    fi
}

# Function to sync GitOps configurations
sync_gitops_config() {
    echo ""
    echo "Syncing GitOps configurations..."
    
    # Get the current GitOps instance configuration
    GITOPS_INSTANCE=$(oc get argocd openshift-gitops -n openshift-gitops -o yaml 2>/dev/null || echo "")
    
    if [ -n "$GITOPS_INSTANCE" ]; then
        echo "Found GitOps instance, ensuring proper configuration..."
        
        # Ensure resource health checks are configured
        oc patch argocd openshift-gitops -n openshift-gitops --type=merge -p '{
            "spec": {
                "resourceCustomizations": "argoproj.io/Application:\n  health.lua: |\n    hs = {}\n    hs.status = \"Progressing\"\n    hs.message = \"\"\n    if obj.status ~= nil then\n      if obj.status.health ~= nil then\n        hs.status = obj.status.health.status\n        hs.message = obj.status.health.message\n      end\n    end\n    return hs\n",
                "resourceHealthChecks": [
                    {
                        "group": "datasciencecluster.opendatahub.io",
                        "kind": "DataScienceCluster",
                        "check": "health_status = {}\nif obj.status ~= nil then\n  if obj.status.conditions ~= nil then\n    for i, condition in pairs(obj.status.conditions) do\n      if condition.type == \"Available\" and condition.status == \"True\" then\n        health_status.status = \"Healthy\"\n        health_status.message = \"DataScienceCluster is available\"\n        return health_status\n      end\n    end\n  end\nend\nhealth_status.status = \"Progressing\"\nhealth_status.message = \"DataScienceCluster is being created\"\nreturn health_status\n"
                    }
                ]
            }
        }' 2>/dev/null || echo "Could not patch ArgoCD instance"
    fi
    
    echo "✅ GitOps configuration synchronized"
}

# Main execution
main() {
    echo "Starting GitOps operator conflict resolution at $(date)"
    
    # Check if logged into OpenShift
    if ! oc whoami &>/dev/null; then
        echo "❌ Error: Not logged into OpenShift. Please run 'oc login' first."
        exit 1
    fi
    
    # Check existing GitOps installation
    check_existing_gitops
    
    # Update bootstrap behavior
    update_bootstrap_behavior
    
    # Fix dynamic configuration
    fix_dynamic_config
    
    # Sync GitOps configurations
    sync_gitops_config
    
    echo ""
    echo "🎉 GitOps operator conflict resolution complete!"
    echo ""
    echo "Recommendations:"
    echo "1. Use './scripts/bootstrap-enhanced.sh' instead of './bootstrap.sh' for future deployments"
    echo "2. This script will automatically detect existing GitOps installations"
    echo "3. If you need to force reinstall GitOps, manually delete the operator first"
    echo ""
    echo "To manually remove GitOps operator (if needed):"
    echo "  oc delete csv -n openshift-gitops-operator -l operators.coreos.com/openshift-gitops-operator.openshift-gitops-operator"
    echo "  oc delete subscription openshift-gitops-operator -n openshift-gitops-operator"
}

# Run main function
main "$@"
