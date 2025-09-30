# Working Configuration Overlay

This overlay implements a simplified OpenShift AI deployment configuration based on the working approach from `genai-rhoai-poc-template`.

## Key Changes from Base Configuration

1. **Configuration Changes**:
   - Kept all serving components as "Managed" (modelmeshserving, modelregistry)
   - Kept `nim` configuration for NVIDIA GPU support
   - Disabled `enableComponentMonitoring` to avoid potential issues

2. **Simplified Deployment**:
   - Changed sync-wave from "25" to "0" for DataScienceCluster
   - Keep DSCInitialization but with simplified sync-wave
   - Removed complex wait-for-operators and wait-for-crds jobs
   - Added simple validation job that only checks if operator pod is running

3. **Operator Channel**:
   - Uses stable-2.16 channel explicitly

## Why These Changes?

The original configuration was trying to manage too many components and had complex dependency chains that were causing sync issues. This simplified approach:

- Keeps DSCInitialization for proper Service Mesh and monitoring setup
- Reduces the number of managed components to only what's needed
- Uses simpler validation that doesn't depend on specific CRDs
- Removes experimental features like NIM that might cause issues

## Usage

To use this overlay in your cluster configuration:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: openshift-ai-instance
  namespace: openshift-gitops
spec:
  source:
    path: components/operators/openshift-ai/instance/overlays/working-config
    # ... rest of configuration
```

## Verification

After deployment, verify the DataScienceCluster is ready:

```bash
# Check DataScienceCluster status
oc get datasciencecluster -n redhat-ods-applications

# Check if DSCInitialization was created automatically
oc get dscinitialization -A

# Verify OpenShift AI dashboard is accessible
oc get route rhods-dashboard -n redhat-ods-applications
```