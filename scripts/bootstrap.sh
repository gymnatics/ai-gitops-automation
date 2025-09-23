#!/bin/bash
set -e

# Default values
LANG=C
TIMEOUT_SECONDS=45
OPERATOR_NS="openshift-gitops-operator"
ARGO_NS="openshift-gitops"
GITOPS_OVERLAY=components/operators/openshift-gitops/operator/overlays/latest/

# shellcheck source=/dev/null
source "$(dirname "$0")/functions.sh"
source "$(dirname "$0")/util.sh"
source "$(dirname "$0")/command_flags.sh" "$@"
source "$(dirname "$0")/dynamic_config.sh"

apply_firmly(){
  if [ ! -f "${1}/kustomization.yaml" ]; then
    print_error "Please provide a dir with \"kustomization.yaml\""
    return 1
  fi

  # Debug: show real apply errors instead of suppressing them
  until oc kustomize "${1}" --enable-helm | oc apply -f-
  do
    echo -n "."
    sleep 5
  done
  echo ""
}


install_gitops(){
  echo
  echo "Checking if GitOps Operator is already installed and running"

  # Detect if the GitOps operator CSV is in 'Succeeded' state
  if oc get csv -n ${OPERATOR_NS} | grep -q "openshift-gitops-operator.*Succeeded"; then
    echo "✅ GitOps operator is already installed and running."
    
    # Ensure GitOps instance has proper health checks configured
    echo "Configuring GitOps instance health checks..."
    configure_gitops_health_checks
    
    return 0
  fi

  echo "🛠️ Installing GitOps Operator..."

  apply_firmly ${GITOPS_OVERLAY}

  echo "📦 Retrieving the InstallPlan name..."
  INSTALL_PLAN_NAME=$(oc get sub openshift-gitops-operator -n ${OPERATOR_NS} -o jsonpath='{.status.installPlanRef.name}')

  echo "📜 Retrieving the CSV name..."
  CSV_NAME=$(oc get ip "$INSTALL_PLAN_NAME" -n ${OPERATOR_NS} -o jsonpath='{.spec.clusterServiceVersionNames[0]}')

  echo "⏳ Waiting for operator installation to complete..."
  oc wait --for=jsonpath='{.status.phase}'=Succeeded csv/${CSV_NAME} -n ${OPERATOR_NS}

  echo "✅ OpenShift GitOps successfully installed."
  
  # Configure health checks after installation
  configure_gitops_health_checks
}

configure_gitops_health_checks(){
  echo "Configuring GitOps health checks for DataScienceCluster..."
  
  # Wait for GitOps instance to be ready
  until oc get argocd openshift-gitops -n ${ARGO_NS} &>/dev/null; do
    echo -n "."
    sleep 5
  done
  
  # Apply health check configuration
  oc patch argocd openshift-gitops -n ${ARGO_NS} --type=merge -p '{
    "spec": {
      "resourceHealthChecks": [
        {
          "group": "datasciencecluster.opendatahub.io",
          "kind": "DataScienceCluster",
          "check": "health_status = {}\nif obj.status ~= nil then\n  if obj.status.conditions ~= nil then\n    for i, condition in pairs(obj.status.conditions) do\n      if condition.type == \"Available\" and condition.status == \"True\" then\n        health_status.status = \"Healthy\"\n        health_status.message = \"DataScienceCluster is available\"\n        return health_status\n      elseif condition.type == \"Progressing\" and condition.status == \"True\" then\n        health_status.status = \"Progressing\"\n        health_status.message = \"DataScienceCluster is progressing\"\n        return health_status\n      end\n    end\n  end\nend\nhealth_status.status = \"Progressing\"\nhealth_status.message = \"DataScienceCluster is being created\"\nreturn health_status\n"
        }
      ]
    }
  }' 2>/dev/null || true
  
  echo "✅ Health checks configured"
}




bootstrap_cluster(){

  base_dir="bootstrap/overlays"

  # Check if bootstrap_dir is already set
  if [ -n "$BOOTSTRAP_DIR" ]; then
    bootstrap_dir=$BOOTSTRAP_DIR
    if [[ "$bootstrap_dir" == "dynamic" ]] && [[ "${USE_DYNAMIC}" == "true" ]]; then
      # Apply dynamic config when using CLI flags
      apply_dynamic_config
    fi
    test -n "$base_dir/$bootstrap_dir";
    echo "Using bootstrap folder: $bootstrap_dir"
  else
    echo
    echo "Bootstrap Options:"
    echo "1) Use existing overlay (aws-open-environment, composer-ai-lab, demo.redhat.com)"
    echo "2) Create dynamic configuration (recommended)"
    echo
    read -p "Select option (1-2): " bootstrap_option
    
    if [[ "$bootstrap_option" == "2" ]] || [[ "${USE_DYNAMIC}" == "true" ]]; then
      # Run dynamic configuration
      if [[ "$INTERACTIVE" != "false" ]] && [[ -z "${USE_DYNAMIC}" ]]; then
        prompt_operator_versions
        prompt_instance_types
      fi
      apply_dynamic_config
      bootstrap_dir="dynamic"
    else
      PS3="Please enter a number to select a bootstrap folder: "
      
      select bootstrap_dir in $(basename -a $base_dir/*/); 
      do
          test -n "$base_dir/$bootstrap_dir" && break;
          echo ">>> Invalid Selection";
      done

      echo
      echo "Selected: ${bootstrap_dir}"
      echo
    fi
  fi

  check_branch
  check_repo
  
  echo "Apply overlay to override default instance"
  kustomize build "${base_dir}/${bootstrap_dir}" | oc apply -f -


  echo "Apply ArgoCD ApplicationSets to deploy operators"
  oc apply -k components/argocd/apps/base/

  # Apply the dynamic overlay patches to the ApplicationSets
  if [[ "$bootstrap_dir" == "dynamic" ]]; then
    echo "Applying dynamic patches to ApplicationSets"
    oc patch applicationset cluster-operators -n openshift-gitops --type=merge --patch-file clusters/overlays/dynamic/patch-operators-list.yaml
    oc patch applicationset cluster-operators -n openshift-gitops --type=json -p='[{"op": "replace", "path": "/spec/template/spec/source/repoURL", "value": "https://github.com/gymnatics/ai-gitops-automation.git"}, {"op": "replace", "path": "/spec/template/spec/source/targetRevision", "value": "main"}]'
    
    # Apply AnythingLLM tenant patch if enabled
    if [[ "${ENABLE_ANYTHINGLLM}" == "true" ]] && [[ -f "clusters/overlays/dynamic/patch-tenants-list.yaml" ]]; then
      echo "Applying AnythingLLM tenant patch"
      oc patch applicationset tenants -n openshift-gitops --type=merge --patch-file clusters/overlays/dynamic/patch-tenants-list.yaml
    fi
  fi
  wait_for_openshift_gitops

  echo
  echo "Restart the application-controller to start the sync"
  # Restart is necessary to resolve a bug where apps don't start syncing after they are applied
  oc delete pods -l app.kubernetes.io/name=openshift-gitops-application-controller -n ${ARGO_NS}

  wait_for_openshift_gitops

  route=$(oc get route openshift-gitops-server -o jsonpath='{.spec.host}' -n ${ARGO_NS})
  echo
  echo "GitOps has successfully deployed!  Check the status of the sync here:"
  echo "https://${route}"
}

# Verify CLI tooling
setup_bin
download_yq
download_kustomize
download_kubeseal

KUSTOMIZE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tmp/bin"
export PATH="${KUSTOMIZE_DIR}:$PATH"

check_bin oc
check_bin kustomize
# check_bin kubeseal
check_oc_login

# Verify sealed secrets
#check_sealed_secret

# Execute bootstrap functions
install_gitops
bootstrap_cluster
