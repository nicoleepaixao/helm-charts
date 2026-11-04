#!/usr/bin/env bash
# Lint and render every chart in this repo (wrapper charts and sub-charts).
# Charts with a ci/*-values.yaml get those values on top of values.yaml.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0; count=0
for dir in $(find . -name Chart.yaml -not -path '*/charts/*' -printf '%h\n' | sort); do
  count=$((count + 1))
  args=()
  [ -f "$dir/values.yaml" ] && args+=(-f "$dir/values.yaml")
  for v in "$dir"/ci/*-values.yaml; do [ -f "$v" ] && args+=(-f "$v"); done
  if helm lint "$dir" "${args[@]}" >$tmp/lint.log 2>&1 \
     && helm template ci "$dir" "${args[@]}" >$tmp/render.yaml 2>$tmp/render.err; then
    printf 'ok    %-34s %4s resources\n' "${dir#./}" "$(grep -c '^kind:' $tmp/render.yaml || true)"
    # Schema validation when kubeconform is installed (always in CI)
    if command -v kubeconform >/dev/null; then
      kubeconform -summary -ignore-missing-schemas \
        -schema-location default \
        -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
        $tmp/render.yaml || { echo "FAIL  ${dir#./} schema"; fail=1; }
    fi
  else
    printf 'FAIL  %s\n' "${dir#./}"; cat $tmp/lint.log $tmp/render.err 2>/dev/null | grep -E 'ERROR|Error' | head -3
    fail=1
  fi
done
echo "$count charts checked"

# Plain manifests applied with kubectl after the charts (NodePool, ClusterIssuer...)
for m in */manifests/*.yaml; do
  python3 -c 'import sys, yaml; list(yaml.safe_load_all(open(sys.argv[1])))' "$m" \
    || { echo "FAIL  $m is not valid YAML"; fail=1; }
done
echo "$(ls */manifests/*.yaml | wc -l) manifests parsed"
exit $fail
