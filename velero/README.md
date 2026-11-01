# Velero

Velero — Kubernetes backup and disaster recovery. Backs up cluster resources to S3 and creates EBS snapshots for persistent volumes. Supports scheduled backups, on-demand backups, and granular restores.

See also: [Disaster Recovery Guide](../disaster-recovery.md) for full DR procedures and testing.

## Prerequisites

- IRSA role ARN from `terraform output velero_role_arn`
- S3 bucket from `terraform output velero_bucket`
- Velero CLI installed (`brew install velero` or [releases](https://github.com/vmware-tanzu/velero/releases))

## Install

Update `values.yaml` with the role ARN, bucket name, and region, then:

```bash
helm dependency build
helm install velero . -n velero --create-namespace
```

## Verify

```bash
kubectl get pods -n velero
velero backup-location get
velero schedule get
```

Backup location status should be `Available`. The `daily-backup` schedule should be listed.

Run a manual backup to confirm everything works:

```bash
velero backup create test-backup --include-namespaces default --wait
velero backup describe test-backup
```

Status should be `Completed`.

## Upgrade

```bash
helm dependency update
helm upgrade velero . -n velero
```

## Uninstall

```bash
helm uninstall velero -n velero
```

> **Note:** Backups in S3 and EBS snapshots are NOT deleted when Velero is uninstalled.

## Troubleshooting

| Problem | Action |
|---|---|
| Backup failed | `velero backup describe <name> --details` — check errors |
| Partial failure | `velero backup logs <name>` — check which resources failed |
| S3 permission denied | Verify IRSA role has `s3:PutObject`, `s3:GetObject`, `s3:ListBucket` |
| EBS snapshot failed | Verify IRSA role has `ec2:CreateSnapshot`, `ec2:DescribeSnapshots` |
| Backup location `Unavailable` | Check S3 bucket name, region, and IAM permissions |
| Restore stuck | `velero restore describe <name>` — check for resource conflicts |
| PVC not restored | Ensure the StorageClass exists in the target cluster |

## Useful Commands

```bash
# List all backups
velero backup get

# Create a backup of a specific namespace
velero backup create my-backup --include-namespaces production --wait

# Create a backup with a TTL
velero backup create my-backup --include-namespaces production --ttl 168h

# Restore from a backup
velero restore create --from-backup my-backup

# Restore a single namespace
velero restore create --from-backup my-backup --include-namespaces production

# Restore specific resource types
velero restore create --from-backup my-backup --include-resources deployments,services

# List restores
velero restore get

# View restore details
velero restore describe <name>
velero restore logs <name>

# List schedules
velero schedule get

# Delete a backup (also deletes S3 data and snapshots)
velero backup delete <name>

# Check backup storage location
velero backup-location get
```
