# traefik

Traefik Ingress Controller — auto-discovers services, supports both standard Ingress and IngressRoute CRDs, with a built-in dashboard and middleware for rate limiting, auth, and circuit breaking.

## Description

Traefik is a modern reverse proxy and ingress controller designed for dynamic environments. It automatically discovers services as they are deployed — no manual configuration needed. Traefik supports both the standard Kubernetes `Ingress` resource and its own `IngressRoute` CRD, which provides advanced routing features like weighted round-robin, traffic mirroring, and middleware chains.

Key features:
- **Auto-discovery** — detects new services and routes automatically
- **Middleware** — rate limiting, basic auth, forward auth, circuit breaker, retry, headers, IP whitelist
- **Built-in dashboard** — real-time view of routes, services, and middleware
- **IngressRoute CRD** — advanced routing beyond what standard Ingress supports
- **Let's Encrypt** — built-in ACME support for automatic TLS certificates

## When to Use

- You want **automatic service discovery** without manually creating Ingress resources for every service
- You need **middleware** (rate limiting, auth, circuit breaker) without external tools
- You want a **built-in dashboard** to visualize all routes and their health
- Your environment is **dynamic** with frequent deployments and service changes
- You want both standard Ingress and advanced CRD-based routing

## Comparison with Alternatives

| Feature | Traefik | Nginx | Kong | ALB Controller |
|---|---|---|---|---|
| **Type** | L7 Reverse Proxy | L7 Reverse Proxy | API Gateway + Ingress | AWS-native L7 |
| **Auto-discovery** | ✅ Automatic | ❌ Manual | ❌ Manual | N/A |
| **Dashboard** | ✅ Built-in | ❌ No | ✅ Enterprise only | AWS Console |
| **Middleware** | ✅ Rate limit, auth, circuit breaker | ❌ Limited | ✅ 100+ plugins | ❌ No |
| **CRD Support** | ✅ IngressRoute | ❌ No | ✅ KongPlugin/Consumer | ✅ TargetGroupBinding |
| **Let's Encrypt** | ✅ Built-in ACME | ❌ Needs cert-manager | ❌ Needs cert-manager | ✅ ACM |
| **Complexity** | Low-Medium | Low | Medium-High | Low |
| **Best for** | Dynamic environments | Simple routing | API management | AWS-native apps |

**Choose Traefik when** you want auto-discovery, a built-in dashboard, and middleware without the weight of a full API Gateway. Choose Nginx for the simplest setup. Choose Kong if you need deep API management (consumers, key-auth, transformations). Choose ALB for AWS-native with zero in-cluster components.

## Prerequisites

- `kubectl` access to the cluster
- Helm 3+

## Install

```bash
helm dependency build
helm install traefik . -n traefik --create-namespace
```

## Verify

```bash
kubectl get pods -n traefik
kubectl get svc -n traefik
```

The Service should show an `EXTERNAL-IP` provisioned by the NLB.

Access the Traefik dashboard:

```bash
kubectl port-forward svc/traefik-dashboard 9000:9000 -n traefik
```

Open http://localhost:9000/dashboard/ (trailing slash required).

## Configure

### Standard Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
spec:
  ingressClassName: traefik
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

### IngressRoute with Middleware (Rate Limiting + Auth)

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: rate-limit
spec:
  rateLimit:
    average: 100
    burst: 50
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: basic-auth
spec:
  basicAuth:
    secret: auth-secret
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-api
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`api.example.com`) && PathPrefix(`/v1`)
      kind: Rule
      services:
        - name: my-api
          port: 80
      middlewares:
        - name: rate-limit
        - name: basic-auth
```

### Circuit Breaker

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: circuit-breaker
spec:
  circuitBreaker:
    expression: LatencyAtQuantileMS(50.0) > 100
```

### Internal NLB (private traffic only)

Change the scheme annotation in `values.yaml`:

```yaml
traefik:
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-scheme: internal
```

## Upgrade

```bash
helm upgrade traefik . -n traefik
```

## Uninstall

```bash
helm uninstall traefik -n traefik
```

> **Note:** The NLB provisioned by AWS may take a few minutes to be fully deleted.

## Troubleshooting

```bash
# Traefik logs
kubectl logs -n traefik -l app.kubernetes.io/name=traefik
```

- **NLB stuck in provisioning** — verify subnet tags: `kubernetes.io/role/elb = 1` (public) or `kubernetes.io/role/internal-elb = 1` (private).
- **Routes not appearing in dashboard** — check that `ingressClassName: traefik` is set, or that IngressRoute CRDs are in the correct namespace.
- **Middleware not applying** — ensure the Middleware resource is in the same namespace as the IngressRoute, or use `namespace-middlewarename` format.
- **Dashboard not accessible** — the dashboard is only exposed via port-forward by default (not via the NLB) for security.

## Useful Commands

```bash
# List all Traefik CRDs
kubectl get ingressroutes,middlewares,traefikservices -A

# List all standard Ingress resources handled by Traefik
kubectl get ingress -A -o wide | grep traefik

# Check Traefik readiness
kubectl get endpoints -n traefik

# Port-forward to test locally
kubectl port-forward svc/traefik 8080:80 -n traefik
```
