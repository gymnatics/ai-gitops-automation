# AnythingLLM Tenant

This tenant deploys AnythingLLM as a workbench on OpenShift AI with integrated model serving using models from the Red Hat AI Services Model Car catalog.

## Components

1. **AnythingLLM Workbench**: A Jupyter notebook environment configured for AnythingLLM
2. **Model Server**: KServe-based model serving using vLLM runtime
3. **Model Storage**: Persistent storage for models downloaded from the Model Car catalog

## Available Models

The following models are available from the Model Car catalog (quay.io/redhat-ai-services/modelcar-catalog):

- `qwen3-8b` - Qwen 3 8B model
- `llama3.1-8b` - Llama 3.1 8B model  
- `mistral-7b` - Mistral 7B model
- `phi-3-mini` - Microsoft Phi-3 Mini model

## Deployment Options

### Option 1: Command Line with Model Selection

```bash
./bootstrap.sh --dynamic --enable-anythingllm --modelcar-model=qwen3-8b
```

### Option 2: Interactive Mode

Run the bootstrap script and select:
- Dynamic configuration option
- Enable AnythingLLM when prompted
- Choose your desired model from the list

### Option 3: Full Command with All Options

```bash
./bootstrap.sh \
  --dynamic \
  --enable-anythingllm \
  --modelcar-model=llama3.1-8b \
  --enable-gpu \
  --gpu-instance=g4dn.4xlarge \
  --gpu-replicas=1 \
  --ai-version=eus-2.16
```

## Architecture

1. **Model Download Job**: Pre-sync job that pulls the specified model from the Model Car catalog
2. **Model Storage PVC**: 50Gi persistent volume to store the downloaded model
3. **Workbench PVC**: 20Gi persistent volume for the AnythingLLM workbench
4. **Serving Runtime**: vLLM-based runtime optimized for LLM serving
5. **Inference Service**: KServe endpoint exposing the model API

## Customization

To use a custom model not listed above:

1. Ensure the model exists in the Model Car catalog
2. Use the custom model tag: `--modelcar-model=<your-model-tag>`

## Requirements

- OpenShift AI operator must be installed
- GPU nodes available (for optimal performance)
- Sufficient storage for model and workbench PVCs

## Model Endpoint

Once deployed, the model will be available at:
- Internal: `http://llm-model.anythingllm.svc.cluster.local:8080/v1`
- External: Check the OpenShift AI dashboard for the inference endpoint route
