# ingress-nginx

> **Retired upstream.** The Kubernetes project ended ingress-nginx maintenance in March 2026: no new releases and no security fixes. Keep this chart only for clusters that still depend on it, and plan the move to [Envoy Gateway](../ingress-envoy/) or the [ALB controller](../ingress-alb/). [Announcement](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/).

NGINX Ingress Controller — routes external traffic to services inside the cluster via an AWS Network Load Balancer (NLB). Handles TLS termination, path-based routing, and rate limiting.

## Prerequisites

- `kubectl` access to the cluster
- Helm 3+
- Subnets tagged for load balancer discovery (`kubernetes.io/role/elb = 1` for public, `kubernetes.io/role/internal-elb = 1` for private)

## Install

```bash
helm dependency build
helm install ingress-nginx . -n ingress-nginx --create-namespace
```

## Verify

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

The Service should show an `EXTERNAL-IP` provisioned by the NLB. This can take 2–3 minutes.

Test connectivity:

```bash
curl -v http://<EXTERNAL-IP>
```

## Upgrade

```bash
helm dependency update
helm upgrade ingress-nginx . -n ingress-nginx
```

## Uninstall

```bash
helm uninstall ingress-nginx -n ingress-nginx
```

> **Note:** The NLB is deleted automatically when the Service is removed. If it persists, check for finalizers: `kubectl get svc -n ingress-nginx -o yaml`.

## Troubleshooting

| Problem | Action |
|---|---|
| NLB stuck in provisioning | Verify subnet tags: `kubernetes.io/role/elb = 1` (public) or `kubernetes.io/role/internal-elb = 1` (private) |
| 404 on all requests | Check Ingress resources exist: `kubectl get ingress -A` |
| 502 Bad Gateway | Backend pods are not ready — check `kubectl get pods -n <namespace>` |
| TLS not working | Verify the TLS secret exists and is referenced in the Ingress resource |
| Slow responses | Check NGINX logs for upstream timeouts: `kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx` |
| Connection refused | Verify security groups allow traffic on ports 80/443 to the NLB |

## Useful Commands

```bash
# List all Ingress resources in the cluster
kubectl get ingress -A

# Check NGINX controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Test connectivity through the NLB
curl -v http://<EXTERNAL-IP>

# Check NGINX config (rendered)
kubectl exec -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -- cat /etc/nginx/nginx.conf

# Check NLB status
kubectl get svc -n ingress-nginx -o wide

# Force config reload
kubectl exec -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -- nginx -s reload
```
