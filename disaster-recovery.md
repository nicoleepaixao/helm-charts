# Disaster Recovery Guide

This document covers backup strategy, recovery procedures, and DR testing for the EKS cluster and its workloads.

---

## Table of Contents

- [What Is Backed Up](#what-is-backed-up)
- [What Is NOT Backed Up by Velero](#what-is-not-backed-up-by-velero)
- [DR Scenarios and Response](#dr-scenarios-and-response)
- [RTO/RPO Targets](#rtorpo-targets)
- [Recovery Procedures](#recovery-procedures)
- [DR Testing Procedure](#dr-testing-procedure)
- [Best Practices Checklist](#best-practices-checklist)

---

## What Is Backed Up

| Component | Backup Method | Location | Frequency |
|---|---|---|---|
| Kubernetes resources (Deployments, Services, ConfigMaps, etc.) | Velero | S3 bucket | Daily at 02:00 UTC |
| PersistentVolumeClaims (EBS volumes) | Velero (EBS snapshots) | AWS EBS Snapshots | Daily at 02:00 UTC |
| etcd | EKS-managed (AWS handles this) | AWS-managed | Automatic |
| Secrets | AWS Secrets Manager + Velero | AWS Secrets Manager / S3 | Continuous / Daily |
| Terraform state | S3 backend with versioning | S3 + DynamoDB lock | On every `terraform apply` |
| Helm values | Git repository | Git (GitHub/GitLab) | On every commit |
| ArgoCD application definitions | Git repository (GitOps) | Git (GitHub/GitLab) | On every commit |
| Docker images | ECR / container registry | ECR | On every push |

### Velero Backup Details

Velero runs a daily scheduled backup (`daily-backup`) at 02:00 UTC with a 30-day retention (`720h` TTL). It captures:

- All namespaced resources (Deployments, StatefulSets, Services, ConfigMaps, Secrets, Ingresses, CRDs, etc.)
- EBS volume snapshots for all PVCs
- Cluster-scoped resources (Namespaces, ClusterRoles, ClusterRoleBindings, StorageClasses)

Backups are stored in the configured S3 bucket with server-side encryption.

---

## What Is NOT Backed Up by Velero

These components live outside Kubernetes and require separate backup strategies:

| Component | Why Not Covered | Backup Strategy |
|---|---|---|
| **RDS databases** | External AWS service | RDS automated snapshots + manual snapshots before changes |
| **S3 bucket data** | External AWS service | S3 versioning + cross-region replication |
| **Route 53 DNS records** | External AWS service | Terraform state (IaC) + Route 53 export |
| **IAM roles and policies** | External AWS service | Terraform state (IaC) |
| **EKS control plane** | AWS-managed | EKS is managed by AWS; recreate via Terraform |
| **VPC, subnets, security groups** | External AWS service | Terraform state (IaC) |
| **ECR images** | External AWS service | ECR replication rules or cross-region replication |
| **CloudWatch logs** | External AWS service | CloudWatch retention policies + S3 export |
| **AWS Secrets Manager secrets** | External AWS service | Secrets Manager replication + Terraform |
| **Load Balancers (NLB/ALB)** | Dynamically provisioned | Recreated by ingress controller on restore |

> **Key takeaway:** Velero backs up what is *inside* Kubernetes. Everything *outside* (AWS services) must be protected via Terraform IaC, AWS-native backups, and replication.

---

## DR Scenarios and Response

### 1. Single Pod Failure

**Impact:** Minimal — affects one replica of a service.

**Response:** Kubernetes self-heals automatically. The ReplicaSet controller creates a replacement pod within seconds.

**Action required:** None. Monitor via Prometheus alert `PodCrashLooping` if restarts are excessive.

### 2. Single Node Failure

**Impact:** Low — pods on the failed node are rescheduled.

**Response:** Karpenter (or ASG) detects the missing node and provisions a replacement in 30–60 seconds. Pods with `PodDisruptionBudgets` maintain availability during rescheduling.

**Action required:** None. Monitor via `NodeNotReady` alert.

### 3. Availability Zone Failure

**Impact:** Medium — one-third of capacity lost (in a 3-AZ setup).

**Response:** The cluster is deployed across multiple AZs. Karpenter provisions replacement nodes in healthy AZs. Services with multiple replicas spread across AZs continue serving traffic.

**Action required:** Verify pods are rescheduled. May need to temporarily scale up if capacity is tight.

```bash
kubectl get nodes -o wide    # check AZ distribution
kubectl get pods -A -o wide  # check pod placement
```

### 4. Full Cluster Failure

**Impact:** High — all workloads are down.

**Response:** Recreate the cluster from Terraform, then restore workloads from Velero backup.

**Recovery steps:**

1. Recreate EKS cluster via Terraform:
   ```bash
   cd terraform/
   terraform apply
   ```
2. Install core infrastructure charts (calico, ingress-nginx, cert-manager, external-dns).
3. Install Velero and point it to the existing S3 backup bucket.
4. Restore from the latest backup:
   ```bash
   velero backup get
   velero restore create --from-backup <latest-backup>
   ```
5. Verify all workloads are running:
   ```bash
   kubectl get pods -A
   kubectl get ingress -A
   ```
6. Verify DNS records are recreated by external-dns.
7. Verify TLS certificates are reissued by cert-manager.

### 5. Region Failure

**Impact:** Critical — all AWS resources in the region are unavailable.

**Response:** Requires a pre-configured multi-region setup (active-passive or active-active). This is NOT currently configured.

**To prepare for region failure:**

- Enable S3 cross-region replication for the Velero backup bucket
- Replicate ECR images to a secondary region
- Maintain Terraform configuration for a standby region
- Use Route 53 health checks with failover routing
- Replicate RDS to a secondary region (read replica or Aurora Global)

### 6. Accidental Deletion (Namespace, Deployment, etc.)

**Impact:** Varies — from a single resource to an entire namespace.

**Response:** Restore the specific resource from Velero backup.

```bash
# Restore a single namespace
velero restore create --from-backup <backup-name> --include-namespaces <namespace>

# Restore specific resource types
velero restore create --from-backup <backup-name> \
  --include-namespaces production \
  --include-resources deployments,services,configmaps
```

---

## RTO/RPO Targets

| Scenario | RPO (Data Loss) | RTO (Downtime) | Notes |
|---|---|---|---|
| Pod failure | 0 | < 1 min | Self-healing, no data loss |
| Node failure | 0 | 1–3 min | Karpenter replaces node in ~60s |
| AZ failure | 0 | 2–5 min | Multi-AZ, pods reschedule |
| Cluster failure | ≤ 24h (last backup) | 30–60 min | Terraform + Velero restore |
| Region failure | ≤ 24h | 2–4 hours | Requires multi-region setup |
| Accidental deletion | ≤ 24h (last backup) | 5–15 min | Velero selective restore |
| RDS failure | ≤ 5 min (automated snapshots) | 10–30 min | RDS automated recovery |

> **Note:** RPO for Velero-backed scenarios depends on backup frequency. The default daily schedule means up to 24 hours of data loss. For lower RPO, increase backup frequency or use continuous backup for critical namespaces.

---

## Recovery Procedures

### Velero Full Cluster Restore

```bash
# 1. List available backups
velero backup get

# 2. Inspect the backup
velero backup describe <backup-name> --details

# 3. Restore everything
velero restore create full-restore --from-backup <backup-name>

# 4. Monitor restore progress
velero restore describe full-restore
velero restore logs full-restore

# 5. Verify
kubectl get pods -A
kubectl get pvc -A
kubectl get ingress -A
```

### Velero Namespace Restore

```bash
velero restore create ns-restore \
  --from-backup <backup-name> \
  --include-namespaces production

velero restore describe ns-restore
```

### Velero Single Resource Restore

```bash
velero restore create resource-restore \
  --from-backup <backup-name> \
  --include-namespaces production \
  --include-resources deployments \
  --selector app=my-app
```

### RDS Recovery

```bash
# List available snapshots
aws rds describe-db-snapshots --db-instance-identifier <db-name>

# Restore from snapshot (creates a new instance)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier <new-db-name> \
  --db-snapshot-identifier <snapshot-id>
```

### Terraform State Recovery

Terraform state is stored in S3 with versioning enabled. If state is corrupted:

```bash
# List state file versions
aws s3api list-object-versions --bucket <terraform-state-bucket> --prefix terraform.tfstate

# Restore a previous version
aws s3api get-object --bucket <terraform-state-bucket> --key terraform.tfstate \
  --version-id <version-id> terraform.tfstate.restored

# Replace current state
terraform state push terraform.tfstate.restored
```

---

## DR Testing Procedure

DR should be tested **monthly** to validate backup integrity and restore procedures.

### Monthly DR Test Checklist

1. **Create an on-demand backup:**
   ```bash
   velero backup create dr-test-$(date +%Y%m%d) --include-namespaces default
   ```

2. **Wait for backup to complete:**
   ```bash
   velero backup describe dr-test-$(date +%Y%m%d)
   # Status should be "Completed"
   ```

3. **Delete the test namespace resources:**
   ```bash
   kubectl delete deployment --all -n default
   kubectl delete service --all -n default
   ```

4. **Restore from backup:**
   ```bash
   velero restore create dr-test-restore --from-backup dr-test-$(date +%Y%m%d)
   ```

5. **Verify restore:**
   ```bash
   velero restore describe dr-test-restore
   kubectl get pods -n default
   kubectl get svc -n default
   ```

6. **Validate application functionality** — check endpoints, logs, and data integrity.

7. **Document results** — record what was tested, any issues found, and time to restore.

> **Last successful DR test:** Velero backup and restore validated — full namespace backup and restore completed successfully with all resources recovered.

### Quarterly Full DR Test

Once per quarter, perform a full cluster DR simulation:

1. Provision a temporary EKS cluster via Terraform.
2. Install Velero pointing to the production backup bucket (read-only).
3. Restore the full backup to the temporary cluster.
4. Validate all workloads, ingress, and certificates.
5. Tear down the temporary cluster.

---

## Best Practices Checklist

### Backups

- [ ] Velero daily backup schedule is active (`velero schedule get`)
- [ ] Backup retention is set (default: 30 days / `720h`)
- [ ] S3 backup bucket has versioning enabled
- [ ] S3 backup bucket has server-side encryption (SSE-S3 or SSE-KMS)
- [ ] S3 backup bucket has lifecycle rules to transition old backups to Glacier
- [ ] Velero backup-location status is `Available` (`velero backup-location get`)
- [ ] EBS snapshots are being created for PVCs

### Infrastructure as Code

- [ ] All infrastructure is defined in Terraform (no manual AWS Console changes)
- [ ] Terraform state is in S3 with versioning and DynamoDB locking
- [ ] Terraform state bucket has cross-region replication (for region DR)
- [ ] All Helm values are committed to Git

### GitOps

- [ ] ArgoCD applications are defined in Git
- [ ] All Kubernetes manifests are in Git (no `kubectl apply` from local machines in production)
- [ ] Git repository has branch protection and required reviews

### Monitoring and Alerting

- [ ] `NodeNotReady` alert is configured and tested
- [ ] `PodCrashLooping` alert is configured and tested
- [ ] `PVCAlmostFull` alert is configured and tested
- [ ] Velero backup failure alert is configured
- [ ] Alert notifications reach the on-call team (Slack, PagerDuty, email)

### High Availability

- [ ] Cluster spans at least 3 Availability Zones
- [ ] Critical workloads have `replicas >= 2`
- [ ] PodDisruptionBudgets are set for critical workloads
- [ ] Pod anti-affinity spreads replicas across nodes/AZs
- [ ] Karpenter/ASG can provision nodes in multiple AZs

### Security

- [ ] IRSA roles follow least-privilege principle
- [ ] Secrets are in AWS Secrets Manager (not plain Kubernetes Secrets for sensitive data)
- [ ] Network policies restrict pod-to-pod traffic
- [ ] TLS certificates are auto-renewed by cert-manager

### Testing

- [ ] Monthly DR test completed and documented
- [ ] Quarterly full cluster restore test completed
- [ ] Runbooks are up to date for each DR scenario
- [ ] On-call team knows how to execute restore procedures
