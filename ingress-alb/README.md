# ingress-alb

AWS Load Balancer Controller — provisions an Application Load Balancer (ALB) per Ingress resource. SSL termination happens at the ALB level via ACM certificates, with native WAF integration and no in-cluster proxy required.

## Description

Unlike traditional ingress controllers (Nginx, Traefik, Kong) that run a reverse proxy inside the cluster, the AWS Load Balancer Controller creates AWS-native ALBs directly. Each Ingress resource results in an ALB managed entirely by AWS — there is no proxy pod handling traffic inside the cluster. The controller watches for Ingress resources and translates them into ALB configurations via the AWS API.

Key features:
- **One ALB per Ingress** (or shared via IngressGroup) — AWS manages the load balancer lifecycle
- **SSL at ALB level** — attach ACM certificates directly, no cert-manager needed
- **WAF integration** — attach AWS WAF WebACLs to ALBs via annotations
- **Target types** — route to pods directly (IP mode) or through NodePort
- **No in-cluster proxy** — traffic goes from ALB straight to pods, reducing latency and resource usage

## When to Use

- You want **AWS-native load balancing** without running proxy pods inside the cluster
- You need **WAF integration** (AWS WAF WebACLs attached to the ALB)
- You need **ACM certificates** for SSL without managing cert-manager
- Your routing is **simple** (host/path-based) and you don't need in-cluster middleware
- You want AWS to manage the load balancer lifecycle (scaling, health checks, access logs to S3)

## Comparison with Alternatives

| Feature | ALB Controller | Nginx | Kong | Traefik |
|---|---|---|---|---|
| **Type** | AWS-native L7 | In-cluster L7 proxy | API Gateway + Ingress | In-cluster L7 proxy |
| **Proxy in cluster** | ❌ No (AWS-managed) | ✅ Yes | ✅ Yes | ✅ Yes |
| **SSL** | ✅ ACM at ALB | ✅ cert-manager/secrets | ✅ cert-manager/secrets | ✅ Built-in ACME |
| **WAF** | ✅ Native AWS WAF | ❌ No | ❌ No | ❌ No |
| **Rate Limiting** | ❌ No | ❌ Basic only | ✅ Built-in | ✅ Middleware |
| **Auth** | ✅ Cognito/OIDC only | ❌ External | ✅ JWT, Key-Auth, OAuth2 | ✅ BasicAuth, ForwardAuth |
| **Middleware/Plugins** | ❌ No | ❌ Limited | ✅ 100+ plugins | ✅ Middleware chain |
| **Complexity** | Low | Low | Medium-High | Low-Medium |
| **Best for** | AWS-native, WAF, simple routing | Simple routing | API management | Dynamic environments |

**Choose ALB Controller when** you want AWS-native load balancing with WAF and ACM, and your routing needs are simple (host/path-based). Choose Nginx for simple in-cluster routing. Choose Kong if you need API Gateway features. Choose Traefik for auto-discovery and middleware.

## Prerequisites

- `kubectl` access to the cluster
- Helm 3+
- AWS Load Balancer Controller IAM role (IRSA) with the required policy — see [AWS docs](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html)
- Subnets tagged for load balancer discovery (`kubernetes.io/role/elb = 1` for public, `kubernetes.io/role/internal-elb = 1` for private)
- VPC ID configured in `values.yaml`

## Install

```bash
helm dependency build
helm install ingress-alb . -n kube-system
```

> **Note:** The controller is typically installed in `kube-system` since it manages AWS resources cluster-wide.

## Verify

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl get deployment -n kube-system aws-load-balancer-controller
```

Create a test Ingress to verify ALB provisioning:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
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

```bash
kubectl get ingress test-alb
# ADDRESS column should show the ALB DNS name after 2-3 minutes
```

## Configure

### SSL with ACM Certificate

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:123456789:certificate/abc-123
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
spec:
  ingressClassName: alb
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

### WAF Integration

```yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/wafv2-acl-arn: arn:aws:wafv2:us-east-1:123456789:regional/webacl/my-acl/abc-123
```

### Shared ALB (IngressGroup)

Multiple Ingress resources can share a single ALB:

```yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/group.name: shared-alb
    alb.ingress.kubernetes.io/group.order: "10"
```

### Internal ALB (private traffic only)

```yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
```

## Upgrade

```bash
helm dependency update
helm upgrade ingress-alb . -n kube-system
```

## Uninstall

```bash
helm uninstall ingress-alb -n kube-system
```

> **Warning:** Delete all Ingress resources with `ingressClassName: alb` before uninstalling the controller, otherwise the ALBs will be orphaned in AWS and you'll need to delete them manually.

## Troubleshooting

| Problem | Action |
|---|---|
| ALB not created | Check controller logs: `kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller` |
| `failed to build model` error | Verify subnet tags and VPC ID in values.yaml |
| ALB stuck provisioning | Check IAM role has the required permissions (IRSA) |
| 502 Bad Gateway | Backend pods not ready or security groups blocking traffic from ALB to pods |
| SSL not working | Verify the ACM certificate ARN is correct and in the same region |
| WAF not attached | Verify the WAFv2 WebACL ARN is correct and regional (not global) |
| Target group unhealthy | Check pod health check path matches `alb.ingress.kubernetes.io/healthcheck-path` |

## Useful Commands

```bash
# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# List all ALB Ingress resources
kubectl get ingress -A -o wide | grep alb

# Check target group health via AWS CLI
aws elbv2 describe-target-health --target-group-arn <arn>

# List ALBs created by the controller
aws elbv2 describe-load-balancers --query 'LoadBalancers[?starts_with(LoadBalancerName, `k8s-`)]'

# Check IngressGroup members
kubectl get ingress -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.alb\.ingress\.kubernetes\.io/group\.name}{"\n"}{end}'

# Force reconciliation
kubectl annotate ingress <name> alb.ingress.kubernetes.io/last-updated=$(date +%s) --overwrite
```
