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
- **ECK (Elastic Cloud on Kubernetes) Operator** - Usually installed as `elasticsearch-eck-operator-certified` in `openshift-operators`
- **Red Hat Elasticsearch Operator** - Usually installed as `elasticsearch-operator` in `openshift-operators-redhat`

The job will check both namespaces and look for either operator pattern to ensure compatibility with different installation methods.

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
