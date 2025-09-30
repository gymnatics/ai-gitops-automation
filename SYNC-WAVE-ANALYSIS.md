# Sync Wave Analysis for AI GitOps Automation

## Current Sync Wave Order

Based on my analysis, here are all the sync waves in order:

### Negative Waves (Pre-deployment)
- **-10**: OpenShift Service Mesh Operator
- **-9**: Elasticsearch Operator  
- **-8**: OpenShift Serverless Operator
- **-5**: Service Mesh Control Plane
- **-2**: RHOAI validation job RBAC (in working-config overlay)
- **-1**: 
  - OpenShift AI namespace (redhat-ods-applications)
  - DSCInitialization
  - RHOAI validation job (in working-config overlay)

### Positive Waves (Main deployment)
- **0**: 
  - DataScienceCluster
  - GitOps demo namespace patches
- **2**: GitOps demo chatbot (default)
- **3**: 
  - OpenShift AI operator namespace
  - GitOps demo MinIO job patch
- **4**: OpenShift AI operator group
- **5**: 
  - OpenShift AI operator subscription
  - OpenShift AI operator (common annotation)
  - RHODS admins group
- **10**: Console plugin jobs (GitOps, Pipelines, GPU operator)
- **12**: Wait for operators job (ServiceAccount, Role, RoleBinding)
- **13**: Wait for operators job execution
- **15**: Wait for CRDs job (ServiceAccount, Role, RoleBinding)
- **16**: Wait for CRDs job execution
- **18**: Wait for Service Mesh job resources
- **19**: Wait for Service Mesh job execution
- **30**: ODH Dashboard config (commented out)
- **35**: 
  - GPU settings config
  - Notebook sizes config
  - NVIDIA GPU accelerator profile

## Issues Identified

### 1. **Dependency Order Problems**

The current order has several issues:

1. **OpenShift AI Operator (wave 5) comes after its namespace (wave 3)**
   - This is correct

2. **DataScienceCluster (wave 0) deploys before the operator (wave 5)**
   - This is INCORRECT and likely causing failures
   - DSCInitialization (wave -1) also deploys before the operator

3. **Wait jobs timing**:
   - Wait for operators (wave 13) happens after DSC creation (wave 0)
   - Should wait for operators BEFORE creating DSC

### 2. **Service Mesh Dependencies**

Service Mesh is correctly ordered:
- Operator at -10
- Control Plane at -5
- Wait for Service Mesh at 19 (but this is after DSC at 0)

### 3. **Serverless Dependencies**

Serverless operator at -8 is good, but there's no wait for it to be ready before DSC.

## Recommended Changes

### 1. **Reorder OpenShift AI Components**

```yaml
# Current (WRONG):
-1: DSCInitialization
 0: DataScienceCluster
 3: OpenShift AI namespace
 4: Operator group
 5: Operator subscription

# Recommended (CORRECT):
 3: OpenShift AI namespace
 4: Operator group
 5: Operator subscription
10: Wait for OpenShift AI operator to be ready
11: DSCInitialization
12: DataScienceCluster
```

### 2. **Fix Wait Job Timing**

Move the wait jobs to happen BEFORE resource creation:
- Wait for operators: Change from 13 to 8
- Wait for CRDs: Change from 16 to 9

### 3. **Update Base Configuration**

Update these files:

```yaml
# components/operators/openshift-ai/instance/base/dsc-init.yaml
argocd.argoproj.io/sync-wave: "11"  # was -1

# components/operators/openshift-ai/instance/base/datasciencecluster.yaml
argocd.argoproj.io/sync-wave: "12"  # was 0

# components/operators/openshift-ai/instance/base/wait-for-operators-job.yaml
argocd.argoproj.io/sync-wave: "8"   # was 12/13

# components/operators/openshift-ai/instance/base/wait-for-crds-job.yaml
argocd.argoproj.io/sync-wave: "9"   # was 15/16
```

## Proper Deployment Order

Here's the corrected order:

1. **Infrastructure Operators** (-10 to -8)
   - Service Mesh Operator
   - Elasticsearch Operator
   - Serverless Operator

2. **Service Mesh Setup** (-5)
   - Service Mesh Control Plane

3. **OpenShift AI Operator** (3-5)
   - Namespace
   - Operator Group
   - Subscription

4. **Wait for Dependencies** (8-9)
   - Wait for all operators
   - Wait for CRDs

5. **OpenShift AI Instance** (11-12)
   - DSCInitialization
   - DataScienceCluster

6. **Post-deployment** (30+)
   - Configurations
   - Accelerator profiles
   - Additional settings