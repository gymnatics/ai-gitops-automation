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
}




bootstrap_cluster(){

  base_dir="bootstrap/overlays"

  # Check if bootstrap_dir is already set
  if [ -n "$BOOTSTRAP_DIR" ]; then
    bootstrap_dir=$BOOTSTRAP_DIR
    test -n "$base_dir/$bootstrap_dir";
    echo "Using bootstrap folder: $bootstrap_dir"
  else
    echo
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

  check_branch
  check_repo
  
  echo "Apply overlay to override default instance"
  kustomize build "${base_dir}/${bootstrap_dir}" | oc apply -f -

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
check_bin oc
check_bin kustomize
# check_bin kubeseal
check_oc_login

# Verify sealed secrets
#check_sealed_secret

# Execute bootstrap functions
install_gitops
bootstrap_cluster
