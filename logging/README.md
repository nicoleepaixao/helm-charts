# Logging

Fluent Bit — lightweight log processor that collects logs from all pods and ships them to CloudWatch Logs. Runs as a DaemonSet (one pod per node).

## Prerequisites

- IRSA role ARN from `terraform output cloudwatch_role_arn`
- CloudWatch Logs permissions on the IRSA role (`logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`)

## Install

1. Update `values.yaml` with the IRSA role ARN and AWS region.
2. Deploy:

```bash
helm dependency build
helm install logging . -n logging --create-namespace
```

## Verify

```bash
kubectl get pods -n logging
kubectl get daemonset -n logging
```

Pods run as a DaemonSet — you should see one pod per node. Check CloudWatch Logs in the AWS Console for the expected log group.

Test log delivery:

```bash
kubectl logs -n logging -l app.kubernetes.io/name=aws-for-fluent-bit | tail -20
```

Logs should show successful delivery with no errors.

## Upgrade

```bash
helm dependency update
helm upgrade logging . -n logging
```

## Uninstall

```bash
helm uninstall logging -n logging
```

> **Note:** Existing logs in CloudWatch are NOT deleted when Fluent Bit is uninstalled.

## Troubleshooting

| Problem | Action |
|---|---|
| No logs in CloudWatch | Verify IRSA role ARN and `region` in `values.yaml` |
| Permission denied errors | Check IAM policy has `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` |
| Fluent Bit pods crashing | `kubectl logs -n logging -l app.kubernetes.io/name=aws-for-fluent-bit` |
| Missing logs from some nodes | Check DaemonSet status: `kubectl get daemonset -n logging` — desired vs ready count |
| High memory usage | Tune `Mem_Buf_Limit` in the Fluent Bit config |

## Useful Commands

```bash
# Check Fluent Bit pod logs
kubectl logs -n logging -l app.kubernetes.io/name=aws-for-fluent-bit

# Check DaemonSet status (should match node count)
kubectl get daemonset -n logging

# View local pod logs (without CloudWatch)
kubectl logs <pod-name> -n <namespace>

# Follow logs in real time
kubectl logs -f <pod-name> -n <namespace>

# Query logs in CloudWatch Logs Insights (AWS Console)
# Example query:
#   fields @timestamp, @message
#   | filter kubernetes.namespace_name = "production"
#   | sort @timestamp desc
#   | limit 100
```
