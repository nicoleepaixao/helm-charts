# kong

Kong Ingress Controller — an API Gateway that doubles as a Kubernetes Ingress Controller, providing rate limiting, authentication, request/response transformations, and 100+ plugins at the ingress level.

## Description

Kong is not just a reverse proxy — it is a full API Gateway. While traditional ingress controllers (like Nginx) only route traffic, Kong can enforce policies on every request: rate limiting per consumer, key-auth / JWT / OAuth2 authentication, request transformations, IP restriction, bot detection, and more. All configured via Kubernetes CRDs (`KongPlugin`, `KongConsumer`, `KongIngress`).

Kong runs in **DB-less mode** by default on Kubernetes, meaning all configuration is declarative via CRDs — no database required.

## When to Use

- Your architecture is **API-heavy** and you need plugins at the ingress level (rate limiting, auth, transformations)
- You want a single component handling both ingress routing and API management
- You need per-consumer rate limiting or authentication without building it into each service
- You're exposing APIs to external consumers and need a proper API Gateway

## Comparison with Alternatives

| Feature | Kong | Nginx | Traefik | ALB Controller |
|---|---|---|---|---|
| **Type** | API Gateway + Ingress | L7 Reverse Proxy | L7 Reverse Proxy | AWS-native L7 |
| **Rate Limiting** | ✅ Built-in (per consumer/route) | ❌ Basic only | ✅ Via middleware | ❌ No |
| **Auth Plugins** | ✅ JWT, OAuth2, Key-Auth, LDAP | ❌ External only | ✅ BasicAuth, ForwardAuth | ✅ Cognito only |
| **Request Transform** | ✅ Native plugins | ❌ No | ❌ No | ❌ No |
| **Auto-discovery** | ❌ Manual config | ❌ Manual config | ✅ Automatic | N/A |
| **Dashboard** | ✅ Kong Manager (Enterprise) | ❌ No | ✅ Built-in | AWS Console |
| **Complexity** | Medium-High | Low | Low-Medium | Low |
| **Best for** | API management | Simple routing | Dynamic environments | AWS-native apps |

**Choose Kong when** you need API Gateway features (plugins, consumers, rate limiting) at the ingress level. Choose Nginx if you just need simple routing. Choose Traefik if you want auto-discovery and a built-in dashboard. Choose ALB if you want AWS-native with zero in-cluster components.

## Prerequisites

- `kubectl` access to the cluster
- Helm 3+
- Prometheus stack installed (for ServiceMonitor)

## Install

```bash
helm dependency build
helm install kong . -n kong --create-namespace
```

## Verify

```bash
kubectl get pods -n kong
kubectl get svc -n kong
```

The proxy Service should show an `EXTERNAL-IP` provisioned by the NLB.

```bash
# Test the proxy is responding
curl -i http://<EXTERNAL-IP>
```

Expected: `HTTP 404` from Kong (no routes configured yet) — this confirms Kong is running.

## Configure

### Create an Ingress with Kong

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-api
  annotations:
    konghq.com/strip-path: "true"
spec:
  ingressClassName: kong
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /users
            pathType: Prefix
            backend:
              service:
                name: users-svc
                port:
                  number: 80
```

### Add Rate Limiting

```yaml
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: rate-limit-5rpm
config:
  minute: 5
  policy: local
plugin: rate-limiting
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-api
  annotations:
    konghq.com/plugins: rate-limit-5rpm
spec:
  ingressClassName: kong
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-api
                port:
                  number: 80
```

### Add Key Authentication

```yaml
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: key-auth
plugin: key-auth
---
apiVersion: configuration.konghq.com/v1
kind: KongConsumer
metadata:
  name: my-consumer
  annotations:
    kubernetes.io/ingress.class: kong
username: my-consumer
credentials:
  - my-consumer-key
---
apiVersion: v1
kind: Secret
metadata:
  name: my-consumer-key
  labels:
    konghq.com/credential: key-auth
stringData:
  key: my-secret-api-key
```

### Internal NLB (private traffic only)

Change the scheme annotation in `values.yaml`:

```yaml
kong:
  proxy:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-scheme: internal
```

## Upgrade

```bash
helm upgrade kong . -n kong
```

## Uninstall

```bash
helm uninstall kong -n kong
```

> **Note:** The NLB provisioned by AWS may take a few minutes to be fully deleted.

## Troubleshooting

```bash
# Kong proxy logs
kubectl logs -n kong -l app.kubernetes.io/component=app

# Kong Ingress Controller logs
kubectl logs -n kong -l app.kubernetes.io/component=controller
```

- **NLB stuck in provisioning** — verify subnet tags: `kubernetes.io/role/elb = 1` (public) or `kubernetes.io/role/internal-elb = 1` (private).
- **503 errors** — check that the backend Service and Endpoints exist: `kubectl get endpoints <service-name>`.
- **Plugins not applying** — verify the `konghq.com/plugins` annotation matches the KongPlugin metadata name.
- **Admin API disabled** — this is intentional for security. Use `KongPlugin` / `KongConsumer` CRDs or `deck` CLI for configuration.

## Useful Commands

```bash
# List all Kong CRDs
kubectl get kongplugins,kongconsumers,kongingresses -A

# Check Kong configuration status
kubectl get ingress -A -o wide | grep kong

# View all routes Kong is serving
kubectl exec -n kong deploy/kong-kong -- kong config dump 2>/dev/null | head -50

# Port-forward to test locally
kubectl port-forward svc/kong-kong-proxy 8080:80 -n kong
```
