# Secrets Store CSI Driver

Secrets Store CSI Driver — mounts AWS Secrets Manager (and SSM Parameter Store) secrets as volumes in pods. Secrets are fetched at pod startup and optionally synced to Kubernetes Secrets.

## Prerequisites

- IRSA role ARN from `terraform output secrets_csi_role_arn`
- Secrets created in AWS Secrets Manager
- Helm 3+

## Install

```bash
helm dependency build
helm install secrets-csi . -n kube-system
```

Install the AWS provider:

```bash
helm repo add aws-provider https://aws.github.io/secrets-store-csi-driver-provider-aws
helm install secrets-provider aws-provider/secrets-store-csi-driver-provider-aws -n kube-system
```

Apply an example SecretProviderClass:

```bash
kubectl apply -f manifests/example-spc.yaml
```

## Verify

```bash
kubectl get pods -n kube-system -l app=secrets-store-csi-driver
kubectl get pods -n kube-system -l app=secrets-store-csi-driver-provider-aws
kubectl get csidriver
```

The CSI driver runs as a DaemonSet (one pod per node). The AWS provider also runs as a DaemonSet.

## Upgrade

```bash
helm dependency update
helm upgrade secrets-csi . -n kube-system
helm upgrade secrets-provider aws-provider/secrets-store-csi-driver-provider-aws -n kube-system
```

## Uninstall

Remove the provider first, then the driver:

```bash
helm uninstall secrets-provider -n kube-system
helm uninstall secrets-csi -n kube-system
```

> **Warning:** Pods that reference a SecretProviderClass will fail to start after uninstalling.

## Troubleshooting

| Problem | Action |
|---|---|
| Secret not mounted | `kubectl describe pod <pod>` — check SecretProviderClass name and IRSA role |
| Permission denied | Verify IAM policy allows `secretsmanager:GetSecretValue` for the secret ARN |
| Pod stuck in `ContainerCreating` | Check CSI driver pod logs: `kubectl logs -n kube-system -l app=secrets-store-csi-driver` |
| Secret value stale | Secrets are fetched at pod startup; restart the pod to refresh |
| Provider pod not running | `kubectl get pods -n kube-system -l app=secrets-store-csi-driver-provider-aws` |

## Useful Commands

```bash
# List all SecretProviderClasses
kubectl get secretproviderclass -A

# Check mount status
kubectl get secretproviderclasspodstatus -A

# View CSI driver logs
kubectl logs -n kube-system -l app=secrets-store-csi-driver

# View AWS provider logs
kubectl logs -n kube-system -l app=secrets-store-csi-driver-provider-aws

# Test a secret mount by exec-ing into a pod
kubectl exec -it <pod> -- cat /mnt/secrets-store/<secret-key>
```
