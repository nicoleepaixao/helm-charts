# external-dns

Automatically creates and updates Route 53 DNS records from Ingress and Service resources. Keeps DNS in sync with your cluster without manual record management.

## Prerequisites

- IRSA role ARN from `terraform output external_dns_role_arn`
- Hosted zone in Route 53
- Domain configured in `values.yaml` (`domainFilters`)

## Install

1. Update `values.yaml` with the IRSA role ARN and your domain.
2. Deploy:

```bash
helm dependency build
helm install external-dns . -n external-dns --create-namespace
```

## Verify

```bash
kubectl get pods -n external-dns
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
```

Logs should show `All records are already up to date`. Create an Ingress with a hostname and verify the DNS record appears in Route 53.

## Upgrade

```bash
helm dependency update
helm upgrade external-dns . -n external-dns
```

## Uninstall

> **WARNING:** Uninstalling does NOT delete DNS records from Route 53. Records created by external-dns will remain.

```bash
helm uninstall external-dns -n external-dns
```

To clean up orphaned TXT ownership records, delete them manually in Route 53.

## Troubleshooting

| Problem | Action |
|---|---|
| Records not created | Check `domainFilters` and `txtOwnerId` in `values.yaml` |
| Permission denied | Verify IRSA role has `route53:ChangeResourceRecordSets`, `route53:ListHostedZones`, `route53:ListResourceRecordSets` |
| Stale records | Check the `policy` setting — `sync` deletes orphaned records, `upsert-only` does not |
| Wrong hosted zone | Verify `zoneIdFilters` or `domainFilters` match your hosted zone |
| Records created but not resolving | DNS propagation can take 60–300s; check with `dig <hostname>` |

## Useful Commands

```bash
# Follow logs in real time
kubectl logs -f -n external-dns deployment/external-dns

# Check the ServiceAccount IRSA annotation
kubectl get sa -n external-dns -o yaml

# Verify DNS resolution
dig <hostname> +short

# List Route 53 records (AWS CLI)
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
```
