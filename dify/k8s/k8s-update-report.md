# Kubernetes Configuration Update Report

**Date**: 2025-08-11
**Purpose**: Update k8s configuration files to match the current live state in the dify namespace

## Summary of Changes

### 1. Storage Configuration Updates

#### PersistentVolumeClaims (PVCs)
- **File**: `03-pvc.yaml`
  - Changed PVC name from `dify-storage-pvc` to `dify-storage-pvc-longhorn-rwx`
  - Changed storage class from `local-path` to `longhorn`
  - Changed access mode from `ReadWriteOnce` to `ReadWriteMany`

- **File**: `05-plugin-pvc.yaml`
  - Changed PVC name from `dify-plugin-storage-pvc` to `dify-plugin-storage-pvc-longhorn`
  - Changed storage class from `local-path` to `longhorn`

#### Deployment Volume References
- **Files Updated**: 
  - `10-api-deployment.yaml`
  - `20-worker-deployment.yaml`
  - `13-plugin-daemon-deployment.yaml`
- **Change**: Updated PVC references to match the new PVC names

### 2. ConfigMap Updates

- **File**: `01-configmap.yaml`
  - Removed `CODE_EXECUTION_API_KEY` from ConfigMap (this should only be in Secrets)

### 3. Unchanged Components

The following components match the live state and required no updates:
- Services (all service definitions are correct)
- Ingresses (both web and API ingresses are correctly configured)
- Secrets structure (keys match, values not compared for security)
- SSRF Proxy ConfigMap
- Deployment configurations (replicas, images, environment variables)

## Key Observations

1. **Storage Migration**: The cluster has migrated from local-path storage to Longhorn storage, which provides better resilience and features.

2. **Security Improvement**: The `CODE_EXECUTION_API_KEY` has been properly moved to Secrets only, removing it from the ConfigMap.

3. **TLS Certificates**: The cluster has TLS certificates configured for both domains (dify.maywzh.com and dify-api.maywzh.com).

4. **High Availability**: The API and Web services are running with 2 replicas each for high availability.

## Recommendations

1. **Remove Old Files**: The `03-pv.yaml.old` file can be removed as the cluster is now using dynamic provisioning with Longhorn.

2. **Update Documentation**: Update the README.md to reflect the new storage requirements (Longhorn storage class).

3. **Deployment Script**: The `deploy.sh` script should be tested to ensure it works with the updated configurations.

## Validation

To validate these changes, you can:
1. Apply the updated YAML files to a test namespace
2. Compare with the live state using `kubectl diff`
3. Run `kubectl apply --dry-run=client` to check for any issues

## Files Modified

1. `k8s/03-pvc.yaml`
2. `k8s/05-plugin-pvc.yaml`
3. `k8s/10-api-deployment.yaml`
4. `k8s/20-worker-deployment.yaml`
5. `k8s/13-plugin-daemon-deployment.yaml`
6. `k8s/01-configmap.yaml`
7. `k8s/k8s-update-report.md` (this file)
