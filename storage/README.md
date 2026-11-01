# storage

StorageClass manifests for EBS (gp3) and EFS CSI drivers on EKS. This is a manifests-only chart — no Helm dependencies. The CSI drivers are installed separately (EBS via EKS addon, EFS via Helm).

## Description

Kubernetes needs StorageClasses to dynamically provision persistent volumes. This chart provides two StorageClass manifests:

- **gp3** (EBS) — default StorageClass for `ReadWriteOnce` workloads (databases, caches, single-pod storage). Uses the EBS CSI driver, which is installed as an **EKS managed addon via Terraform** — no Helm chart needed.
- **efs** (EFS) — StorageClass for `ReadWriteMany` workloads (shared storage across multiple pods). Uses the EFS CSI driver, which is installed via **Helm** (see below).

### When to Use Which

| Use Case | StorageClass | Access Mode |
|---|---|---|
| Databases (PostgreSQL, MySQL) | `gp3` (EBS) | ReadWriteOnce |
| Redis, single-pod caches | `gp3` (EBS) | ReadWriteOnce |
| Shared uploads, media files | `efs` (EFS) | ReadWriteMany |
| Shared config across pods | `efs` (EFS) | ReadWriteMany |
| ML model storage (multi-reader) | `efs` (EFS) | ReadWriteMany |

## Prerequisites

- `kubectl` access to the cluster
- **EBS CSI driver** — installed as EKS managed addon (via Terraform). Verify: `kubectl get csidriver ebs.csi.aws.com`
- **EFS CSI driver** — installed via Helm (see Install section). Verify: `kubectl get csidriver efs.csi.aws.com`
- **EFS filesystem** — created in AWS (same VPC as EKS, security groups allowing NFS port 2049)

## Install

### EBS CSI Driver (EKS Addon)

The EBS CSI driver is managed by EKS via Terraform — no Helm install needed. Verify it's running:

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
kubectl get csidriver ebs.csi.aws.com
```

Apply the gp3 StorageClass:

```bash
kubectl apply -f manifests/gp3-storageclass.yaml
```

### EFS CSI Driver (Helm)

```bash
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver -n kube-system
```

Update `fileSystemId` in `manifests/efs-storageclass.yaml` with your EFS filesystem ID, then apply:

```bash
kubectl apply -f manifests/efs-storageclass.yaml
```

## Verify

```bash
# Check StorageClasses
kubectl get storageclass

# Verify gp3 is the default
kubectl get storageclass gp3 -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}'

# Test EBS provisioning
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-ebs
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp3
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get pvc test-ebs  # Should become Bound after a pod uses it

# Test EFS provisioning
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-efs
spec:
  accessModes: [ReadWriteMany]
  storageClassName: efs
  resources:
    requests:
      storage: 5Gi
EOF
kubectl get pvc test-efs  # Should become Bound
```

## Uninstall

```bash
kubectl delete storageclass gp3 efs
```

> **Warning:** Deleting a StorageClass does not delete existing PVs/PVCs, but new PVCs referencing it will fail.

## Troubleshooting

| Problem | Action |
|---|---|
| PVC stuck Pending (EBS) | Check EBS CSI driver pods: `kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver` |
| PVC stuck Pending (EFS) | Check EFS CSI driver pods: `kubectl get pods -n kube-system -l app=efs-csi-controller` |
| EFS mount timeout | Verify security groups allow NFS (port 2049) from EKS nodes to EFS |
| `gp3` not default | Re-apply the manifest — check the `is-default-class` annotation |
| Volume not encrypted | Verify `encrypted: "true"` in the gp3 StorageClass parameters |
| EFS `fileSystemId` error | Update `fs-CHANGE_ME` in `manifests/efs-storageclass.yaml` with your actual EFS ID |

## Useful Commands

```bash
# List all StorageClasses
kubectl get storageclass

# List all PVCs and their StorageClass
kubectl get pvc -A -o wide

# List all PVs
kubectl get pv

# Check CSI drivers installed
kubectl get csidriver

# Describe a stuck PVC for events
kubectl describe pvc <name>

# Check EBS CSI driver logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

# Check EFS CSI driver logs
kubectl logs -n kube-system -l app=efs-csi-controller
```
