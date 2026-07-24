#!/usr/bin/env bats
# -----------------------------------------------------------------------------
# Behavioral tests for the pre-delete unpin hook of the kubernetes-nodes chart
# (packages/apps/kubernetes-nodes/templates/pre-delete-unpin.yaml).
#
# helm-unittest (tests/pre_delete_unpin_test.yaml) pins the hook's YAML shape;
# this file tests the embedded shell script's BEHAVIOR: the rendered chart's Job
# args are extracted and executed against a fake kubectl, because the script's
# error classification cannot be asserted from the manifest. The contract under
# test: NotFound on a read means "native pool or already gone" and is a no-op,
# while a transient server error must fail the Job (set -e, retried by
# backoffLimit) -- treating it as absent would skip the unpin, report success,
# and leak the still-keep-annotated worker objects past the uninstall.
#
# Requires helm (present in the unit-tests CI toolchain; the same job installs
# the helm-unittest plugin).
#
# cozytest.sh awk parser: @test blocks only, a bare `}` at column 0 ends a test,
# no run/$status/setup/teardown. Assertions are direct shell tests.
# Run with: hack/cozytest.sh hack/kubernetes-nodes-unpin-hook.bats
# -----------------------------------------------------------------------------

FAKEBIN="$PWD/hack/testdata/kubernetes-nodes-unpin"
CHART="$PWD/packages/apps/kubernetes-nodes"

# prep renders the chart for pool md0 of cluster myk8s and extracts the unpin
# Job's script (the only `- |` block in the template) into $WORK/unpin.sh.
prep() {
  chmod +x "$FAKEBIN/kubectl"
  WORK=$(mktemp -d)
  export FAKE_CMDLOG="$WORK/cmdlog"
  : > "$FAKE_CMDLOG"
  # -s selects the output but the whole chart still renders, so the values must
  # clear nodegroup.yaml's offline hurdles the same way the snapshot suite does:
  # instanceType="" + explicit resources (lookup returns nil under `helm
  # template`), and a _cluster block (injected from cozystack-values at runtime).
  helm template kubernetes-nodes-myk8s-md0 "$CHART" --namespace tenant-test \
    --set cluster=myk8s \
    --set instanceType= --set resources.cpu=4 --set resources.memory=8Gi \
    --set _cluster.cluster-domain=cozy.local \
    -s templates/pre-delete-unpin.yaml > "$WORK/rendered.yaml" 2>"$WORK/helm-stderr"
  sed -n '/- |/,/securityContext:/p' "$WORK/rendered.yaml" |
    sed '1d;$d' | sed 's/^              //' > "$WORK/unpin.sh"
  # Extraction sanity: a template refactor that moves the script must fail here,
  # loudly, not silently test an empty file.
  grep -q 'removing helm.sh/resource-policy' "$WORK/unpin.sh"
  export PATH="$FAKEBIN:$PATH"
}

@test "unpin hook: NotFound objects are a no-op and the script succeeds (native pool preserved)" {
  prep
  export FAKE_MODE=notfound
  rc=0
  sh "$WORK/unpin.sh" >"$WORK/out" 2>&1 || rc=$?
  cat "$WORK/out"
  [ "$rc" -eq 0 ]
  ! grep -q 'annotate' "$FAKE_CMDLOG"
  rm -rf "$WORK"
}

@test "unpin hook: a transient error reading an object fails the Job, not silently skipping the unpin" {
  prep
  # kubectl exits 1 for NotFound and for a transient failure alike; if the
  # script read a timeout as "absent" it would skip the unpin, succeed, and the
  # uninstall would leave the keep-annotated MachineDeployment (and its worker
  # VMs) running unmanaged in the tenant namespace. The KMT list query succeeds
  # in this mode, so a failure proves the NAMED-get classification.
  export FAKE_MODE=error-named
  rc=0
  sh "$WORK/unpin.sh" >"$WORK/out" 2>&1 || rc=$?
  cat "$WORK/out"
  [ "$rc" -ne 0 ]
  grep -q 'ERROR: reading' "$WORK/out"
  ! grep -q 'annotate' "$FAKE_CMDLOG"
  rm -rf "$WORK"
}

@test "unpin hook: keep-annotated objects are unpinned, hash-anchored to this pool's own KMTs" {
  prep
  export FAKE_MODE=pinned
  FAKE_KMT_NAMES=$(printf '%s\n%s' kubernetes-myk8s-md0-abc123 kubernetes-myk8s-md0-large-def456)
  export FAKE_KMT_NAMES
  rc=0
  sh "$WORK/unpin.sh" >"$WORK/out" 2>&1 || rc=$?
  cat "$WORK/out"
  [ "$rc" -eq 0 ]
  # All three named objects and the pool's own KMT get the annotation removed...
  grep -q 'annotate .*machinedeployment.cluster.x-k8s.io/kubernetes-myk8s-md0 helm.sh/resource-policy-' "$FAKE_CMDLOG"
  grep -q 'annotate .*machinehealthcheck.cluster.x-k8s.io/kubernetes-myk8s-md0 helm.sh/resource-policy-' "$FAKE_CMDLOG"
  grep -q 'annotate .*workloadmonitor.cozystack.io/kubernetes-myk8s-md0 helm.sh/resource-policy-' "$FAKE_CMDLOG"
  grep -q 'annotate .*kubevirtmachinetemplate.infrastructure.cluster.x-k8s.io/kubernetes-myk8s-md0-abc123 helm.sh/resource-policy-' "$FAKE_CMDLOG"
  # ...but the sibling pool md0-large's KMT is left alone (6-hex anchor).
  ! grep -q 'md0-large-def456' "$FAKE_CMDLOG"
  rm -rf "$WORK"
}

@test "unpin hook: an existing object without the keep annotation is left untouched" {
  prep
  export FAKE_MODE=unpinned
  rc=0
  sh "$WORK/unpin.sh" >"$WORK/out" 2>&1 || rc=$?
  cat "$WORK/out"
  [ "$rc" -eq 0 ]
  ! grep -q 'annotate' "$FAKE_CMDLOG"
  rm -rf "$WORK"
}
