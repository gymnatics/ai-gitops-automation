<<<<<<< HEAD
=======
is_gitops_installed() {
  # Returns 0 if GitOps operator CSV is Succeeded
  oc get csv -n openshift-operators 2>/dev/null | grep -q "openshift-gitops-operator.*Succeeded" && return 0
  oc get csv -n openshift-gitops 2>/dev/null | grep -q "openshift-gitops-operator.*Succeeded" && return 0
  return 1
}

>>>>>>> 92ac872 (Apply OpenShift AI + GitOps bootstrap fixes: skip duplicate GitOps install, Argo Job Replace, DSC/Dashboard sync safeguards)
#!/bin/bash
set -e
$(dirname "$0")/scripts/bootstrap.sh  "$@"
