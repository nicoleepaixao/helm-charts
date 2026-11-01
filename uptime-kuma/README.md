# Uptime Kuma

Uptime Kuma — self-hosted uptime monitoring for HTTP, TCP, DNS, and ping endpoints. Provides status pages, notifications, and incident tracking.

## Prerequisites

- `kubectl` access to the cluster
- Helm 3+
- Ingress controller (for external access)
- Storage class for persistent data

## Install

```bash
helm dependency build
helm install uptime-kuma . -n uptime-kuma --create-namespace
```

## Verify

```bash
kubectl get pods -n uptime-kuma
kubectl get pvc -n uptime-kuma
```

Pod should be `Running 1/1` and PVC should be `Bound`.

Access the UI:

```bash
kubectl port-forward svc/uptime-kuma 3001:3001 -n uptime-kuma
```

Open <http://localhost:3001> (create an admin account on first access).

## Upgrade

```bash
helm dependency update
helm upgrade uptime-kuma . -n uptime-kuma
```

## Uninstall

```bash
helm uninstall uptime-kuma -n uptime-kuma
kubectl delete pvc -n uptime-kuma -l app.kubernetes.io/name=uptime-kuma
```

## Troubleshooting

| Problem | Action |
|---|---|
| Data lost after restart | Check PVC is bound: `kubectl get pvc -n uptime-kuma` |
| Can't access externally | Check ingress resource: `kubectl get ingress -n uptime-kuma` |
| Pod stuck in `Pending` | Check PVC binding and storage class: `kubectl describe pod -n uptime-kuma` |
| Notifications not sending | Check notification settings in the UI — test each channel |
| High memory usage | Reduce monitor count or increase polling interval |

## Useful Commands

```bash
# Check pod status
kubectl get pods -n uptime-kuma

# View logs
kubectl logs -n uptime-kuma -l app.kubernetes.io/name=uptime-kuma

# Check persistent storage
kubectl get pvc -n uptime-kuma

# Restart the pod (to apply config changes)
kubectl rollout restart deployment -n uptime-kuma

# Access via port-forward
kubectl port-forward svc/uptime-kuma 3001:3001 -n uptime-kuma
```
