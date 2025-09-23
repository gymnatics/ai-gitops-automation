# Troubleshooting AI GitOps Automation

This document provides solutions for common issues encountered when deploying AnythingLLM and models on OpenShift AI using OpenShift GitOps.

> **Note**: Most issues described below have been permanently fixed in the codebase. This document is kept for reference and understanding of the solutions implemented.

## Common Issues and Solutions

### 1. OpenShift AI Operator Sync Issues

**Problem**: OpenShift AI operator is constantly out of sync, with `ods-applications`, `datasciencecluster`, and `odh-dashboard` config showing sync errors.

**Cause**: Missing ServerSideApply configuration and health check definitions for DataScienceCluster resources.

**Solution**:
```bash
# Run the comprehensive fix script
./scripts/fix-ai-gitops-issues.sh
```

This script will:
- Add ServerSideApply annotations to OpenShift AI resources
- Configure proper health checks for DataScienceCluster
- Update sync policies for better handling of CRDs

### 2. Model Serving Platform Not Installed

**Problem**: "No model serving platform installed" error when accessing OpenShift AI platform.

**Cause**: KServe and ModelMesh components not properly enabled, or Service Mesh dependencies missing.

**Solution**:
The fix script will automatically:
- Enable both KServe and ModelMesh serving platforms
- Configure Knative Serving with proper ingress gateway
- Verify Service Mesh installation

**Manual verification**:
```bash
# Check KServe deployment
oc get deployment -n knative-serving

# Check ModelMesh deployment  
oc get deployment -n redhat-ods-applications | grep modelmesh

# Check Service Mesh
oc get smcp -n istio-system
```

### 3. Missing OpenShift AI UI Options

**Problem**: Most options not appearing in OpenShift AI UI, likely due to permissions.

**Cause**: `kubeadmin` user not in the admin groups for OpenShift AI.

**Solution**:
The fix script will:
- Add `kube:admin` user to cluster-admin role
- Create `rhods-admins` group with kubeadmin
- Update ODH Dashboard config to include proper admin groups

**Manual steps if needed**:
```bash
# Apply kubeadmin cluster-admin binding
oc apply -f components/operators/openshift-ai/instance/components/make-kubeadmin-cluster-admin/rolebinding.yaml

# Add to rhods-admins group
oc adm groups add-users rhods-admins kube:admin
```

### 4. GitOps Console Plugin Job Error

**Problem**: GitOps operator fails to sync with "Job.batch 'job-gitops-console-plugin' is invalid: spec.template: field is immutable" error.

**Cause**: Job resources are immutable in Kubernetes and cannot be updated once created.

**Solution**:
The fix script will:
- Delete the existing job to allow recreation
- Force sync the GitOps operator application
- Apply proper sync options

**Manual fix**:
```bash
# Delete the problematic job
oc delete job job-gitops-console-plugin -n openshift-gitops-operator

# Force sync
oc patch application openshift-gitops-operator -n openshift-gitops \
  --type=merge -p '{"operation":{"sync":{"syncStrategy":{"hook":{"force":true}}}}}'
```

### 5. GitOps Operator Installation Conflict

**Problem**: GitOps operator already installed before dynamic configuration, causing conflicts.

**Cause**: Bootstrap script doesn't check for existing GitOps installation.

**Solution**:
```bash
# Run the operator conflict fix
./scripts/fix-gitops-operator-conflict.sh

# Use enhanced bootstrap for future deployments
./scripts/bootstrap-enhanced.sh
```

This will:
- Create an enhanced bootstrap script that detects existing installations
- Update dynamic configuration to exclude already-installed operators
- Prevent duplicate operator installations

## Quick Fix Process

1. **Run the comprehensive fix**:
   ```bash
   ./scripts/fix-ai-gitops-issues.sh
   ```

2. **If GitOps operator conflicts persist**:
   ```bash
   ./scripts/fix-gitops-operator-conflict.sh
   ```

3. **Wait for sync** (2-3 minutes)

4. **Verify the fixes**:
   ```bash
   # Check sync status
   oc get applications -n openshift-gitops

   # Check DataScienceCluster
   oc get datasciencecluster -n redhat-ods-applications

   # Check model serving
   oc get pods -n redhat-ods-applications | grep -E "modelmesh|kserve"
   ```

## Prevention Tips

1. **Use enhanced bootstrap**: Use `bootstrap-enhanced.sh` instead of `bootstrap.sh`
2. **Check existing installations**: Always verify what's already installed before running bootstrap
3. **Monitor sync status**: Regularly check GitOps UI for sync issues
4. **Review logs**: Check operator logs for detailed error messages

## Useful Commands

```bash
# Get GitOps and AI dashboard URLs
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='https://{.spec.host}{"\n"}'
oc get route rhods-dashboard -n redhat-ods-applications -o jsonpath='https://{.spec.host}{"\n"}'

# Check operator status
oc get csv -A | grep -E "gitops|rhods|opendatahub"

# View DataScienceCluster conditions
oc describe datasciencecluster default -n redhat-ods-applications

# Check GitOps application sync status
oc get applications -n openshift-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
```

## Still Having Issues?

If problems persist after running the fix scripts:

1. Check individual component logs:
   ```bash
   # GitOps controller logs
   oc logs -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-application-controller

   # OpenShift AI operator logs
   oc logs -n redhat-ods-operator -l name=rhods-operator

   # ODH Dashboard logs
   oc logs -n redhat-ods-applications -l app=rhods-dashboard
   ```

2. Verify all required operators are installed:
   ```bash
   oc get csv -A | grep -v Succeeded
   ```

3. Check for resource conflicts:
   ```bash
   oc get events -A --sort-by='.lastTimestamp' | grep -i error
   ```

4. Consider a clean reinstall if necessary (last resort)
