# cert-manager

Automatic TLS certificates from Let's Encrypt via DNS01 challenge (Route 53). Handles issuance, renewal, and revocation of X.509 certificates.

## Prerequisites

- IRSA role ARN from `terraform output cert_manager_role_arn`
- Domain managed in Route 53
- Hosted zone ID for the domain

## Install

```bash
helm dependency build
helm install cert-manager . -n cert-manager --create-namespace
```

Apply the ClusterIssuer (update email and hosted zone ID in the manifest first):

```bash
kubectl apply -f manifests/cluster-issuer.yaml
```

## Verify

```bash
kubectl get pods -n cert-manager
kubectl get clusterissuer
kubectl get certificates -A
```

The ClusterIssuer should show `Ready: True`:

```bash
kubectl describe clusterissuer letsencrypt-production
```

## Upgrade

```bash
helm dependency update
helm upgrade cert-manager . -n cert-manager
```

## Uninstall

```bash
kubectl delete clusterissuer --all
helm uninstall cert-manager -n cert-manager
```

> **Note:** CRDs are not removed by `helm uninstall`. To fully clean up:
> ```bash
> kubectl delete crd -l app.kubernetes.io/name=cert-manager
> ```

## Troubleshooting

| Problem | Action |
|---|---|
| Certificate stuck in `Pending` | `kubectl describe certificate <name>` — check the Order and Challenge |
| Challenge failed | `kubectl describe challenge -n <namespace>` — check DNS propagation |
| ClusterIssuer not ready | `kubectl describe clusterissuer letsencrypt-production` — check IRSA and hosted zone ID |
| Permission denied on Route 53 | Verify IAM policy has `route53:ChangeResourceRecordSets` and `route53:GetChange` |
| Rate limited by Let's Encrypt | Use the staging issuer for testing: `https://acme-staging-v02.api.letsencrypt.org/directory` |
| Certificate not renewing | cert-manager renews at 2/3 of lifetime; check `kubectl get certificates -A` for expiry dates |

## Useful Commands

```bash
# List all certificates
kubectl get certificates -A

# List pending challenges
kubectl get challenges -A

# Describe a certificate (shows issuance status)
kubectl describe certificate <name> -n <namespace>

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Force certificate renewal by deleting the TLS secret
kubectl delete secret <tls-secret> -n <namespace>

# Check certificate expiry
kubectl get secret <tls-secret> -n <namespace> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates
```
