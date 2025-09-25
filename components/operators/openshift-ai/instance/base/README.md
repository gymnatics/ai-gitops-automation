# OpenShift AI Instance Base Configuration

This directory contains the base configuration for deploying an OpenShift AI (RHOAI/RHODS) instance.

## Components

- `datasciencecluster.yaml` - The main DataScienceCluster resource
- `dsc-init.yaml` - DSCInitialization configuration
- `odhdashboardconfig.yaml` - Dashboard configuration
- `wait-for-operators-job.yaml` - Job that waits for required operators to be ready
- `wait-for-crds-job.yaml` - Job that waits for required CRDs to be available

## Wait for Operators Job

The `wait-for-operators-job.yaml` creates a job that ensures all required operators are installed and ready before proceeding with the OpenShift AI deployment. It checks for:

- **Service Mesh Operator** - in `openshift-operators` namespace
- **Serverless Operator** - in `openshift-serverless` namespace  
- **Elasticsearch Operator** - in either `openshift-operators` OR `openshift-operators-redhat` namespace

### Elasticsearch Operator Detection

The Elasticsearch operator check supports both:
- **ECK (Elastic Cloud on Kubernetes) Operator** - Installed in `openshift-operators` namespace, but runs its pods in `elasticsearch-operator` namespace
- **Red Hat Elasticsearch Operator** - Usually installed as `elasticsearch-operator` in `openshift-operators-redhat`

The job checks for the CSV (ClusterServiceVersion) in the namespace where the operator is **installed**, not where it runs:
- For ECK: Checks `openshift-operators` namespace for any CSV with "elastic" in the name
- For Red Hat ES: Checks `openshift-operators-redhat` namespace

Note: The ECK operator shows as "Elasticsearch (ECK) Operator" in the UI and typically has its operator pods running in the `elasticsearch-operator` namespace, but the CSV is in `openshift-operators`.

## Troubleshooting

If the wait-for-operators job fails:

1. Check which operators are actually installed:
   ```bash
   oc get csv -A | grep -i elastic
   oc get csv -A | grep -i servicemesh
   oc get csv -A | grep -i serverless
   ```

2. The job logs will show which namespace it's checking and what it finds:
   ```bash
   oc logs -n redhat-ods-applications job/wait-for-operators
   ```
