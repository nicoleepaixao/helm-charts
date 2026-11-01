# ArgoCD

ArgoCD — GitOps continuous delivery. Watches Git repos and syncs Kubernetes resources automatically, ensuring the cluster state matches the desired state in Git.

## Prerequisites

- `kubectl` access to the cluster
- Helm 3+
- Git repo with Kubernetes manifests or Helm charts

## Install

```bash
helm dependency build
helm install argocd . -n argocd --create-namespace
```

## Verify

```bash
kubectl get pods -n argocd
```

All pods should be `Running`.

Get the admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Access the UI:

```bash
kubectl port-forward svc/argocd-server 8080:443 -n argocd
```

Open <https://localhost:8080> (user: `admin`).

## Upgrade

```bash
helm dependency update
helm upgrade argocd . -n argocd
```

## Uninstall

```bash
helm uninstall argocd -n argocd
```

> **Note:** CRDs are not removed by `helm uninstall`. To fully clean up:
> ```bash
> kubectl delete crd -l app.kubernetes.io/part-of=argocd
> ```

## Troubleshooting

| Problem | Action |
|---|---|
| App stuck in `OutOfSync` | `argocd app diff <app>` — check what differs |
| Sync failed | `argocd app sync <app> --force` — force a re-sync |
| Repo not accessible | `argocd repo list` — verify URL and credentials |
| App stuck in `Progressing` | Check pod events: `kubectl describe pod -n <namespace> -l app=<app>` |
| Unknown error on sync | Check argocd-server logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server` |
| CRD conflicts | Sync CRDs first with `argocd app sync <app> --resource :CustomResourceDefinition` |

## Useful Commands

```bash
# List all applications
argocd app list

# Sync an application
argocd app sync <app>

# View sync history
argocd app history <app>

# Rollback to a previous revision
argocd app rollback <app> <id>

# Delete an application (keeps resources)
argocd app delete <app> --cascade=false

# Hard refresh (clear cache)
argocd app get <app> --hard-refresh

# Add a Git repository
argocd repo add <repo-url> --username <user> --password <token>

# Check ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```
