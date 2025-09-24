# AI GitOps Deployment Order

This document describes the complete deployment order with sync waves to ensure all components are deployed in the correct sequence.

## Deployment Sequence

### Phase 1: Core Infrastructure Operators (Negative Waves)
- **Wave -10**: Service Mesh Operator
  - Creates CRDs for Service Mesh components
  - Required by OpenShift AI for model serving

- **Wave -9**: Elasticsearch Operator  
  - Required by Service Mesh for tracing capabilities
  - Must be ready before Service Mesh instance

- **Wave -8**: Serverless Operator
  - Required for KServe serverless model serving
  - Creates Knative components

- **Wave -5**: Service Mesh Instance (data-science-smcp)
  - Creates the control plane in istio-system namespace
  - Must be ready before DSCInitialization

### Phase 2: Application Namespaces
- **Wave -1**: redhat-ods-applications namespace
  - Namespace for OpenShift AI components
  
- **Wave 3**: redhat-ods-operator namespace
  - Namespace for OpenShift AI operator

### Phase 3: OpenShift AI Operator
- **Wave 5**: OpenShift AI Operator
  - Subscription, OperatorGroup
  - Creates CRDs for DataScienceCluster, DSCInitialization, etc.

### Phase 4: Wait Jobs
- **Wave 12**: Wait for Operators Job
  - Ensures Service Mesh, Serverless, Elasticsearch are ready

- **Wave 13**: Execute wait-for-operators job

- **Wave 15**: Wait for CRDs Resources
  - ServiceAccount, ClusterRole, ClusterRoleBinding

- **Wave 16**: Wait for CRDs Job Execution
  - Waits for OpenShift AI operator to create all CRDs
  - Verifies operator pod is running

### Phase 5: Service Mesh Readiness
- **Wave 18**: Wait for Service Mesh Resources
  - ServiceAccount, ClusterRole, ClusterRoleBinding, ConfigMap

- **Wave 19**: Wait for Service Mesh Job Execution
  - Ensures Service Mesh Control Plane is ready

### Phase 6: OpenShift AI Instances
- **Wave 20**: DSCInitialization
  - Configures the OpenShift AI deployment
  - Sets up Service Mesh integration

- **Wave 25**: DataScienceCluster
  - Creates the main AI platform components
  - Enables model serving, notebooks, pipelines

- **Wave 30**: ODH Dashboard Config
  - Configures the dashboard settings
  - Sets up admin groups and permissions

### Phase 7: Additional Components
- **Wave 35**: AcceleratorProfile (GPU)
  - Only deployed in GPU-enabled overlays
  - Configures GPU tolerations

## Sync Options

All OpenShift AI custom resources include:
- `SkipDryRunOnMissingResource=true`: Prevents errors when CRDs don't exist
- `ServerSideApply=true`: Uses server-side apply for better conflict resolution
- `Validate=false`: Skips client-side validation

## Retry Policy

The ApplicationSet for operators includes:
```yaml
retry:
  limit: 5
  backoff:
    duration: 5s
    factor: 2
    maxDuration: 20m
```

This ensures transient failures are automatically retried.

## Troubleshooting

If deployment fails:

1. Check operator readiness:
   ```bash
   oc get csv -A | grep -v Succeeded
   ```

2. Check wait job logs:
   ```bash
   oc logs -n redhat-ods-applications job/wait-for-operators
   oc logs -n redhat-ods-applications job/wait-for-crds
   oc logs -n redhat-ods-applications job/wait-for-servicemesh
   ```

3. Verify CRDs exist:
   ```bash
   oc get crd | grep -E "datasciencecluster|dscinitialization|odhdashboard"
   ```

4. Check OpenShift AI operator logs:
   ```bash
   oc logs -n redhat-ods-operator -l name=rhods-operator
   ```
