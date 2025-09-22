# Testing AnythingLLM on Existing OpenShift AI Cluster

This guide provides step-by-step instructions for testing the AnythingLLM deployment on a cluster that already has OpenShift AI installed.

## Prerequisites

1. OpenShift cluster with OpenShift AI already installed
2. `oc` CLI tool configured and logged into your cluster
3. Sufficient resources for GPU workloads (if using GPU-accelerated models)
4. Access to create new namespaces and deploy workloads

## Testing Approaches

### Approach 1: Manual Deployment (Recommended for Testing)

This approach deploys AnythingLLM independently without modifying your existing GitOps configuration.

#### Step 1: Verify Current Cluster State

```bash
cd /Users/dayeo/ai-gitops-automation
./scripts/verify-cluster-state.sh
```

This will show you:
- OpenShift login status
- GitOps operator status
- OpenShift AI installation
- GPU support availability
- Existing tenant namespaces

#### Step 2: Dry Run Test

First, test what would be deployed without actually applying it:

```bash
./scripts/deploy-anythingllm.sh --dry-run --model=qwen3-8b
```

Review the output to ensure the resources look correct.

#### Step 3: Deploy AnythingLLM

Deploy with your chosen model:

```bash
# Deploy with default model (qwen3-8b)
./scripts/deploy-anythingllm.sh

# Or deploy with a specific model
./scripts/deploy-anythingllm.sh --model=llama3.1-8b

# Deploy to a custom namespace
./scripts/deploy-anythingllm.sh --namespace=anythingllm-test --model=mistral-7b
```

#### Step 4: Monitor Deployment

Watch the deployment progress:

```bash
# Watch pods
oc get pods -n anythingllm -w

# Check events
oc get events -n anythingllm --sort-by='.lastTimestamp'

# Check model download job
oc logs -n anythingllm -l job-name=model-download -f
```

#### Step 5: Verify Components

Once deployed, verify all components are running:

```bash
# Check notebook status
oc get notebook -n anythingllm

# Check model serving
oc get inferenceservice -n anythingllm

# Check serving runtime
oc get servingruntime -n anythingllm

# Get routes/endpoints
oc get routes -n anythingllm
```

### Approach 2: GitOps Integration (For Production)

If testing is successful and you want to integrate with GitOps:

#### Step 1: Update Your Fork

First, ensure your fork includes the new AnythingLLM changes:

```bash
# Add upstream if not already added
git remote add upstream https://github.com/redhat-ai-services/ai-gitops-automation.git

# Fetch and merge changes
git fetch upstream
git checkout main
git merge upstream/main
git push origin main
```

#### Step 2: Run Dynamic Configuration

Use the bootstrap script with dynamic configuration:

```bash
./bootstrap.sh --dynamic \
  --enable-anythingllm \
  --modelcar-model=qwen3-8b \
  --non-interactive
```

This will:
- Create dynamic overlays
- Update ApplicationSets
- Apply the configuration through GitOps

### Approach 3: GitOps Manual Patch

For existing GitOps deployments, you can manually add AnythingLLM:

```bash
# Create the patch file
cat > anythingllm-patch.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: anythingllm
  namespace: openshift-gitops
spec:
  destination:
    namespace: anythingllm
    server: https://kubernetes.default.svc
  project: tenants
  source:
    path: tenants/anythingllm/overlays/default
    repoURL: https://github.com/YOUR-ORG/ai-gitops-automation.git
    targetRevision: main
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
EOF

# Apply the application
oc apply -f anythingllm-patch.yaml
```

## Troubleshooting

### Common Issues

1. **Model Download Fails**
   ```bash
   # Check job logs
   oc logs -n anythingllm job/model-download
   
   # Check if image pull is working
   oc run test-pull --image=quay.io/redhat-ai-services/modelcar-catalog:qwen3-8b --rm -it --command -- ls /model
   ```

2. **Insufficient Resources**
   ```bash
   # Check node resources
   oc describe nodes | grep -A 5 "Allocated resources"
   
   # Check if GPU is available
   oc get nodes -l nvidia.com/gpu.present=true
   ```

3. **Workbench Not Starting**
   ```bash
   # Check notebook events
   oc describe notebook anythingllm-workbench -n anythingllm
   
   # Check pod logs
   oc logs -n anythingllm -l notebook-name=anythingllm-workbench
   ```

4. **Model Server Issues**
   ```bash
   # Check InferenceService status
   oc describe inferenceservice llm-model -n anythingllm
   
   # Check predictor pod
   oc logs -n anythingllm -l serving.kserve.io/inferenceservice=llm-model
   ```

## Accessing AnythingLLM

Once deployed successfully:

1. **Access the Workbench**:
   - Go to OpenShift AI Dashboard
   - Navigate to Data Science Projects
   - Find the AnythingLLM project
   - Click on the workbench to open it

2. **Access the Model Endpoint**:
   ```bash
   # Get the inference service URL
   oc get inferenceservice llm-model -n anythingllm -o jsonpath='{.status.url}'
   
   # For internal access
   ENDPOINT="http://llm-model.anythingllm.svc.cluster.local:8080/v1"
   ```

3. **Test the Model**:
   ```bash
   # Port-forward for local testing
   oc port-forward -n anythingllm svc/llm-model 8080:8080
   
   # Test with curl
   curl http://localhost:8080/v1/models
   ```

## Cleanup

To remove the AnythingLLM deployment:

```bash
# Remove with confirmation
./scripts/cleanup-anythingllm.sh

# Remove without confirmation
./scripts/cleanup-anythingllm.sh --force

# Remove from custom namespace
./scripts/cleanup-anythingllm.sh --namespace=anythingllm-test --force
```

## Performance Considerations

1. **Model Storage**: Each model requires 20-50GB of storage
2. **Memory Requirements**: 
   - Workbench: 8-16GB RAM
   - Model Server: 16-24GB RAM minimum
3. **GPU Requirements**: 
   - Most models benefit from GPU acceleration
   - Ensure GPU nodes have sufficient VRAM for your model

## Security Notes

1. The default configuration uses placeholder credentials for S3 storage
2. Update the `storage-config` secret with real credentials if using S3
3. Consider network policies to restrict access to the model endpoint
4. Review and update RBAC permissions as needed

## Next Steps

After successful testing:

1. Customize the workbench image if needed
2. Add authentication to the model endpoint
3. Configure monitoring and alerting
4. Set up model versioning and updates
5. Integrate with your applications
