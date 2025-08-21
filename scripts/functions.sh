#!/bin/bash
set -e

TMP_DIR=tmp
SEALED_SECRETS_FOLDER=components/operators/sealed-secrets-operator/overlays/default/
SEALED_SECRETS_SECRET=bootstrap/base/sealed-secrets-secret.yaml
TIMEOUT_SECONDS=60

setup_bin(){
  mkdir -p ${TMP_DIR}/bin
  echo "${PATH}" | grep -q "${TMP_DIR}/bin" || \
    PATH=$(pwd)/${TMP_DIR}/bin:${PATH}
  export PATH
}

check_bin(){
  name=$1
  echo "Validating CLI tool: ${name}"
  
  which "${name}" || download_${name}
 
  case ${name} in
    oc|openshift-install|kustomize)
      echo "auto-complete: . <(${name} completion bash)"
      . <(${name} completion bash)
      ${name} version
      ;;
    *)
      echo
      ${name} --version
      ;;
  esac
  echo
}

download_yq() {
  if ! command -v yq &> /dev/null; then
    echo "🔧 yq not found. Installing..."
    VERSION=v4.2.0
    BINARY=yq_linux_amd64

    wget -q https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY}.tar.gz -O - | \
      tar xz && sudo mv ${BINARY} /usr/local/bin/yq

    if command -v yq &> /dev/null; then
      echo "✅ yq installed successfully."
    else
      echo "❌ Failed to install yq."
    fi
  else
    echo "✅ yq already installed."
  fi
}


download_kubeseal(){
  KUBESEAL_VERSION="0.23.0"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ $(uname -p) == 'arm' ]]; then
      DOWNLOAD_URL=https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-darwin-arm64.tar.gz
    else
      DOWNLOAD_URL=https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-darwin-amd64.tar.gz
    fi
  else
    if [[ $(uname -p) == 'arm' ]]; then
      DOWNLOAD_URL=https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-arm.tar.gz
    else
      DOWNLOAD_URL=https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION:?}/kubeseal-${KUBESEAL_VERSION:?}-linux-amd64.tar.gz
    fi  
  fi
  echo "Downloading Kubeseal: ${DOWNLOAD_URL}"
  curl -OL "${DOWNLOAD_URL}"
  tar -xvzf kubeseal-${KUBESEAL_VERSION:?}-linux-amd64.tar.gz kubeseal
  sudo install -m 755 kubeseal /usr/local/bin/kubeseal
}



download_ocp-install(){
  DOWNLOAD_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OCP_VERSION}/openshift-install-linux.tar.gz
  curl "${DOWNLOAD_URL}" -L | tar vzx -C ${TMP_DIR}/bin openshift-install
}

download_oc(){
  if [[ ! "$OCP_VERSION" ]]; then
    echo "OCP version missing. Please provide OCP version when running this command!"
    exit 1
  fi
  if [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ $(uname -p) == 'arm' ]]; then
      DOWNLOAD_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OCP_VERSION}/openshift-client-mac-arm64.tar.gz
    else
      DOWNLOAD_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OCP_VERSION}/openshift-client-mac.tar.gz
    fi
  else
    DOWNLOAD_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OCP_VERSION}/openshift-client-linux.tar.gz
  fi
  echo "Downloading OpenShift CLI: ${DOWNLOAD_URL}" 
  curl "${DOWNLOAD_URL}" -L | tar vzx -C ${TMP_DIR}/bin oc
}

download_kustomize(){
  cd ${TMP_DIR}/bin
  curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
  cd ../..
}

check_oc_login(){
  oc cluster-info | head -n1
  oc whoami || exit 1
  echo
}

create_sealed_secret(){
  read -r -p "Create NEW [${SEALED_SECRETS_SECRET}]? [y/N] " input
  case $input in
    [yY][eE][sS]|[yY])
      oc apply -k ${SEALED_SECRETS_FOLDER}
      [ -e ${SEALED_SECRETS_SECRET} ] && return
      sleep 20
      oc -n sealed-secrets -o yaml \
        get secret \
        -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
        > ${SEALED_SECRETS_SECRET}
      ;;
    *) echo ;;
  esac
}

check_sealed_secret(){
  if [ -f ${SEALED_SECRETS_SECRET} ]; then
    echo "Using Existing Sealed Secret: ${SEALED_SECRETS_SECRET}"
  else
    echo "Missing: ${SEALED_SECRETS_SECRET}"
    echo "The master key is required to bootstrap sealed secrets and CANNOT be checked into git."
    create_sealed_secret
  fi
}

wait_for_openshift_gitops(){
  echo "Checking status of all openshift-gitops pods"
  GITOPS_RESOURCES=(
    deployment/cluster:condition=Available
    statefulset/openshift-gitops-application-controller:jsonpath='{.status.readyReplicas}'=1
    deployment/openshift-gitops-applicationset-controller:condition=Available
    deployment/openshift-gitops-redis:condition=Available
    deployment/openshift-gitops-repo-server:condition=Available
    deployment/openshift-gitops-server:condition=Available
  )

  for n in "${GITOPS_RESOURCES[@]}"
  do
    RESOURCE=$(echo $n | cut -d ":" -f 1)
    CONDITION=$(echo $n | cut -d ":" -f 2)

    echo "Waiting for ${RESOURCE} state to be ${CONDITION}..."

    if [[ "$RESOURCE" == "statefulset/openshift-gitops-application-controller" ]]; then
      oc wait pods --selector app.kubernetes.io/name=openshift-gitops-application-controller \
                   --for=condition=Ready -n ${ARGO_NS} --timeout=${TIMEOUT_SECONDS}s
    else
      oc wait --for=${CONDITION} ${RESOURCE} -n ${ARGO_NS} --timeout=${TIMEOUT_SECONDS}s
    fi
  done
}

check_branch(){
  APP_PATCH_FILE="./components/argocd/apps/base/cluster-config-app-of-apps.yaml"
  APP_PATCH_PATH=".spec.source.targetRevision"

  if ! command -v yq &> /dev/null; then
    echo "yq could not be found. Unable to verify the branch."
    exit 1
  fi

  GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  APP_BRANCH=$(yq eval "${APP_PATCH_PATH}" ${APP_PATCH_FILE})

  if [[ ${GIT_BRANCH} == ${APP_BRANCH} ]]; then
    echo "Your working branch ${GIT_BRANCH}, matches your cluster overlay branch ${APP_BRANCH}"
  else 
    echo "Current: ${GIT_BRANCH}, Cluster: ${APP_BRANCH}"
    if [[ ${FORCE} == "true" ]]; then
      update_branch ${APP_PATCH_FILE} ${APP_PATCH_PATH}
    else
      echo "Do you wish to update it to ${GIT_BRANCH}?"
      PS3="Select: "
      select yn in "Yes" "No"; do
        [[ $yn == "Yes" ]] && update_branch ${APP_PATCH_FILE} ${APP_PATCH_PATH}; break
      done
    fi
  fi
}

update_branch(){
  APP_PATCH_FILE=$1
  APP_PATCH_PATH=$2
  GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  yq eval --inplace "${APP_PATCH_PATH} = \"${GIT_BRANCH}\"" ${APP_PATCH_FILE}
  git add ${APP_PATCH_FILE}
  git commit -m "automatic update to branch by bootstrap script"
  git push origin ${GIT_BRANCH}
}

get_git_basename(){
  REPO_URL=$1
  QUERY='s#(git@|https://)github.com[:/]([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)\.git#\2#'
  echo $(echo ${REPO_URL} | sed -E  ${QUERY})
}

update_repo(){
  APP_PATCH_FILE=$1
  APP_PATCH_PATH=$2
  REPO_URL=$3
  GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  yq eval --inplace "${APP_PATCH_PATH} = \"${REPO_URL}\"" ${APP_PATCH_FILE}
  git add ${APP_PATCH_FILE}
  git commit -m "automatic update to repo by bootstrap script"
  git push origin ${GIT_BRANCH}
}

check_repo(){
  APP_PATCH_FILE="./components/argocd/apps/base/cluster-config-app-of-apps.yaml"
  APP_PATCH_PATH=".spec.source.repoURL"

  if ! command -v yq &> /dev/null; then
    echo "yq not found. Cannot verify repo."
  else
    GIT_REPO=$(git config --get remote.origin.url)
    GIT_REPO_BASENAME=$(get_git_basename ${GIT_REPO})
    APP_REPO=$(yq eval "${APP_PATCH_PATH}" ${APP_PATCH_FILE})
    APP_REPO_BASENAME=$(get_git_basename ${APP_REPO})

    if [[ ${GIT_REPO_BASENAME} == ${APP_REPO_BASENAME} ]]; then
      echo "Repo matches: ${GIT_REPO}"
    else 
      GITHUB_URL="https://github.com/${GIT_REPO_BASENAME}.git"
      echo "Mismatch. Update to ${GITHUB_URL}?"
      if [[ ${FORCE} == "true" ]]; then
        update_repo ${APP_PATCH_FILE} ${APP_PATCH_PATH} ${GITHUB_URL}
      else
        PS3="Select: "
        select yn in "Yes" "No"; do
          [[ $yn == "Yes" ]] && update_repo ${APP_PATCH_FILE} ${APP_PATCH_PATH} ${GITHUB_URL}; break
        done
      fi
    fi
  fi
}

on_prem_wizard() {
    print_heading "On-Premise Configuration Wizard"

    # Operator Selection
    local operators_dir="components/operators"
    local kustomization_file="kustomization.yaml"
    local patch_file="patch-operator-list.yaml"
    local selected_operators=()

    # Get a list of available operators
    local operators=()
    while IFS= read -r -d 

select_operators() {
    local operators_dir="components/operators"
    local kustomization_file="kustomization.yaml"
    local patch_file="patch-operator-list.yaml"

    # Get a list of available operators
    local operators=()
    while IFS= read -r -d 


 '; do
        operators+=("$(basename "$REPLY")")
    done < <(find "$operators_dir" -mindepth 1 -maxdepth 1 -type d -print0)

    # Create a menu of available operators
    echo "Please select the operators you want to install:"
    local ps3="Select an operator to add (or 'done' to finish): "
    local selected_operators=()
    while true; do
        select operator in "${operators[@]}" "done"; do
            case "$operator" in
                "done")
                    break 2
                    ;;
                "")
                    echo "Invalid selection. Please try again."
                    break
                    ;;
                *)
                    if [[ ! " ${selected_operators[*]} " =~ " ${operator} " ]]; then
                        selected_operators+=("$operator")
                        echo "Added $operator."
                    else
                        echo "$operator is already selected."
                    fi
                    break
                    ;;
            esac
        done
    done

    # Generate the kustomization patch file
    if [ ${#selected_operators[@]} -gt 0 ]; then
        echo "resources:" > "$bootstrap_dir/$patch_file"
        for operator in "${selected_operators[@]}"; do
            echo "  - ../../../components/operators/$operator/operator/overlays/default" >> "$bootstrap_dir/$patch_file"
        done
        echo "Generated $patch_file with selected operators."

        # Add the patch to the main kustomization.yaml
        if ! grep -q "$patch_file" "$bootstrap_dir/$kustomization_file"; then
            echo "Applying patch to $bootstrap_dir/$kustomization_file"
            echo -e "
resources:
  - $patch_file" >> "$bootstrap_dir/$kustomization_file"
        fi
    else
        echo "No operators selected. Skipping patch generation."
    fi
}


 '; do
        operators+=("$(basename "$REPLY")")
    done < <(find "$operators_dir" -mindepth 1 -maxdepth 1 -type d -print0)

    echo "Please select the operators you want to install:"
    local ps3="Select an operator to add (or 'done' to finish): "
    while true; do
        select operator in "${operators[@]}" "done"; do
            case "$operator" in
                "done")
                    break 2
                    ;;
                "")
                    echo "Invalid selection. Please try again."
                    break;
                    ;;
                *)
                    if [[ ! " ${selected_operators[*]} " =~ " ${operator} " ]]; then
                        selected_operators+=("$operator")
                        echo "Added $operator."
                    else
                        echo "$operator is already selected."
                    fi
                    break;
                    ;;
            esac
        done
    done

    # GPU Configuration
    read -r -p "Are you using GPUs in your on-premise environment? (y/N) " use_gpus
    if [[ "$use_gpus" =~ ^[yY](es)?$ ]]; then
        print_warning "Please ensure you have created a custom overlay for the nvidia-gpu-operator that matches your specific hardware."
        print_warning "You will need to update the path in patch-operators-list.yaml manually after this wizard is complete."
    fi

    # Storage Configuration
    read -r -p "Do you need a storage operator for your on-premise storage? (e.g., for NFS, Ceph, or local storage) (y/N) " use_storage_operator
    if [[ "$use_storage_operator" =~ ^[yY](es)?$ ]]; then
        print_info "Please add the name of your storage operator to the list of selected operators."
        read -r -p "Enter the name of the storage operator component: " storage_operator_name
        if [[ -n "$storage_operator_name" ]]; then
            selected_operators+=("$storage_operator_name")
        fi
    fi

    # Networking/Load Balancer
    read -r -p "Do you need a bare-metal load balancer like MetalLB? (y/N) " use_metallb
    if [[ "$use_metallb" =~ ^[yY](es)?$ ]]; then
        if [[ ! " ${selected_operators[*]} " =~ " metallb-operator " ]]; then
            selected_operators+=("metallb-operator")
            echo "Added metallb-operator."
        fi
    fi

    # Generate the kustomization patch file
    if [ ${#selected_operators[@]} -gt 0 ]; then
        echo "resources:" > "$bootstrap_dir/$patch_file"
        for operator in "${selected_operators[@]}"; do
            echo "  - ../../../components/operators/$operator/operator/overlays/default" >> "$bootstrap_dir/$patch_file"
        done
        echo "Generated $patch_file with selected operators."

        # Add the patch to the main kustomization.yaml
        if ! grep -q "$patch_file" "$bootstrap_dir/$kustomization_file"; then
            echo "Applying patch to $bootstrap_dir/$kustomization_file"
            echo -e "
resources:
  - $patch_file" >> "$bootstrap_dir/$kustomization_file"
        fi
    else
        echo "No operators selected. Skipping patch generation."
    fi
}

patch_file(){
  APP_PATCH_FILE=$1
  NEW_VALUE=$2
  YQ_PATH=$3
  CURRENT_VALUE=$(yq eval "${YQ_PATH}" ${APP_PATCH_FILE})
  if [[ ${CURRENT_VALUE} == ${NEW_VALUE} ]]; then
    echo "${APP_PATCH_FILE} already has value ${NEW_VALUE}"
    return
  fi
  yq eval --inplace "${YQ_PATH} = \"${NEW_VALUE}\"" ${APP_PATCH_FILE}
}

select_operators() {
    local operators_dir="components/operators"
    local kustomization_file="kustomization.yaml"
    local patch_file="patch-operator-list.yaml"

    # Get a list of available operators
    local operators=()
    while IFS= read -r -d 


 '; do
        operators+=("$(basename "$REPLY")")
    done < <(find "$operators_dir" -mindepth 1 -maxdepth 1 -type d -print0)

    # Create a menu of available operators
    echo "Please select the operators you want to install:"
    local ps3="Select an operator to add (or 'done' to finish): "
    local selected_operators=()
    while true; do
        select operator in "${operators[@]}" "done"; do
            case "$operator" in
                "done")
                    break 2
                    ;;
                "")
                    echo "Invalid selection. Please try again."
                    break
                    ;;
                *)
                    if [[ ! " ${selected_operators[*]} " =~ " ${operator} " ]]; then
                        selected_operators+=("$operator")
                        echo "Added $operator."
                    else
                        echo "$operator is already selected."
                    fi
                    break
                    ;;
            esac
        done
    done

    # Generate the kustomization patch file
    if [ ${#selected_operators[@]} -gt 0 ]; then
        echo "resources:" > "$bootstrap_dir/$patch_file"
        for operator in "${selected_operators[@]}"; do
            echo "  - ../../../components/operators/$operator/operator/overlays/default" >> "$bootstrap_dir/$patch_file"
        done
        echo "Generated $patch_file with selected operators."

        # Add the patch to the main kustomization.yaml
        if ! grep -q "$patch_file" "$bootstrap_dir/$kustomization_file"; then
            echo "Applying patch to $bootstrap_dir/$kustomization_file"
            echo -e "
resources:
  - $patch_file" >> "$bootstrap_dir/$kustomization_file"
        fi
    else
        echo "No operators selected. Skipping patch generation."
    fi
}


