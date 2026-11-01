# ingress-envoy

Envoy Gateway — a Kubernetes-native implementation of the Gateway API, built on the Envoy proxy. Provides multi-tenancy, advanced L7 traffic management, and a standardized API that is the successor to the Ingress resource.

## Description

Envoy Gateway implements the [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/), which is the official successor to the Ingress resource. Instead of vendor-specific annotations and CRDs, Gateway API provides a standardized, role-oriented API with `GatewayClass`, `Gateway`, and `HTTPRoute` resources. Envoy Gateway uses Envoy proxy under the hood — the same proxy that powers Istio's data plane.

Key features:
- **Gateway API** — standardized, portable API replacing vendor-specific Ingress annotations
- **Multi-tenancy** — platform teams manage `GatewayClass` and `Gateway`, app teams manage `HTTPRoute`
- **Built on Envoy** — battle-tested L7 proxy with advanced traffic management
- **L7 features** — header-based routing, traffic splitting, request mirroring, URL rewrites, rate limiting
- **Extensibility** — BackendTrafficPolicy, SecurityPolicy, and EnvoyPatchPolicy CRDs for advanced config

## When to Use

- You want to adopt the **Gateway API** (the Kubernetes standard replacing Ingress)
- You are a **platform team** providing ingress infrastructure to multiple app teams (multi-tenancy)
- You need **advanced L7 routing** (header matching, traffic splitting, mirroring) without a full service mesh
- You want a **portable** ingress solution not locked to vendor-specific annotations
- You need **Envoy's performance** and feature set without the complexity of Istio

## Comparison with Alternatives

| Feature | Envoy Gateway | Nginx | Kong | Traefik | ALB Controller |
|---|---|---|---|---|---|
| **API** | Gateway API | Ingress + annotations | Ingress + CRDs | Ingress + IngressRoute | Ingress + annotations |
| **Multi-tenancy** | ✅ Role-oriented | ❌ No | ❌ No | ❌ No | ❌ No |
| **Traffic splitting** | ✅ Native | ❌ No | ❌ No | ✅ Via CRD | ❌ No |
| **Request mirroring** | ✅ Native | ❌ No | ❌ No | ✅ Via CRD | ❌ No |
| **Rate limiting** | ✅ BackendTrafficPolicy | ❌ Basic | ✅ Built-in | ✅ Middleware | ❌ No |
| **Auth** | ✅ SecurityPolicy (JWT, OIDC) | ❌ External | ✅ Plugins | ✅ Middleware | ✅ Cognito |
| **Maturity** | Growing (GA since v1.0) | Very mature | Mature | Mature | Mature |
| **Best for** | Platform teams, Gateway API | Simple routing | API management | Dynamic environments | AWS-native |

**Choose Envoy Gateway when** you want to adopt the Gateway API standard, need multi-tenancy for platform teams, or want Envoy's L7 features without a full service mesh. Choose Nginx for the simplest setup. Choose Kong for API management. Choose Traefik for auto-discovery. Choose ALB for AWS-native with zero in-cluster components.

## Prerequisites

- `kubectl` access to the cluster
- Helm 3+
- Gateway API CRDs (installed automatically by the chart)

## Install

```bash
helm dependency build
helm install envoy-gateway . -n envoy-gateway-system --create-namespace
```

## Verify

```bash
kubectl get pods -n envoy-gateway-system
kubectl get gatewayclass
```

You should see a `GatewayClass` named `eg` (Envoy Gateway).

Create a test Gateway and HTTPRoute:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
  namespace: default
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-route
  namespace: default
spec:
  parentRefs:
    - name: my-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: my-app
          port: 80
```

```bash
kubectl get gateway my-gateway
kubectl get httproute my-route
```

## Configure

### Traffic Splitting (Canary)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: canary-route
spec:
  parentRefs:
    - name: my-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: my-app-stable
          port: 80
          weight: 90
        - name: my-app-canary
          port: 80
          weight: 10
```

### Header-Based Routing

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: header-route
spec:
  parentRefs:
    - name: my-gateway
  rules:
    - matches:
        - headers:
            - name: x-env
              value: canary
      backendRefs:
        - name: my-app-canary
          port: 80
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: my-app-stable
          port: 80
```

### TLS with ACM (via NLB annotation)

Configure the Gateway's Service to use an NLB with ACM:

```yaml
# In values.yaml
gateway-helm:
  config:
    envoyGateway:
      provider:
        kubernetes:
          envoyService:
            annotations:
              service.beta.kubernetes.io/aws-load-balancer-type: external
              service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
```

## Upgrade

```bash
helm dependency update
helm upgrade envoy-gateway . -n envoy-gateway-system
```

## Uninstall

```bash
helm uninstall envoy-gateway -n envoy-gateway-system
```

> **Note:** Delete all Gateway and HTTPRoute resources before uninstalling to avoid orphaned load balancers.

## Troubleshooting

| Problem | Action |
|---|---|
| GatewayClass not created | Check controller logs: `kubectl logs -n envoy-gateway-system -l app.kubernetes.io/name=gateway-helm` |
| Gateway stuck `Pending` | Check if the GatewayClass exists: `kubectl get gatewayclass` |
| HTTPRoute not routing | Verify `parentRefs` matches the Gateway name and namespace |
| No EXTERNAL-IP | Check the Envoy proxy Service: `kubectl get svc -n envoy-gateway-system` |
| 404 on requests | Verify HTTPRoute matches and backendRefs point to existing Services |
| Traffic split not working | Ensure both backend Services have ready endpoints |

## Useful Commands

```bash
# List all Gateway API resources
kubectl get gatewayclass,gateway,httproute -A

# Check Envoy Gateway controller logs
kubectl logs -n envoy-gateway-system -l app.kubernetes.io/name=gateway-helm

# Check Envoy proxy logs (data plane)
kubectl logs -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name

# Describe a Gateway for status/conditions
kubectl describe gateway my-gateway

# Check HTTPRoute status
kubectl describe httproute my-route

# List all listeners and their status
kubectl get gateway -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.listeners[*]}{.name}:{.conditions[0].type}={.conditions[0].status}{" "}{end}{"\n"}{end}'
```
