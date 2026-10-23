#!/usr/bin/env bash
# Self-tests for `lake exe axiomcheck` (ADR 0002). Trusted base: docs/trusted-base.md §6.
#
# Each directory under Fixtures/ is a tiny spec/proofs pair. The checker must accept `Ok` and
# reject every other case *for the stated reason*. Every fixture directory must have an
# expectation here, so a new fixture can't be added without one.
set -euo pipefail
cd "$(dirname "$0")/../.."  # lean/

lake build Fixtures axiomcheck >/dev/null

#        case              exit  required output
cases=(
  "Ok                0     PASS: 1 proven, 0 unproven, 0 failure(s)"
  "Sorry             1     outside the allowlist: [sorryAx]"
  "NativeDecide      1     native_decide"
  "CustomAxiom       1     outside the allowlist: [Fixtures.CustomAxiom.Proofs.cheat]"
  "Missing           1     Fixtures.Missing.Spec.T: no proof"
  "WrongType         1     Fixtures.WrongType.Proofs.T does not prove it"
  "Hidden            1     Fixtures.Hidden.Spec.T: no proof"
  "OutsideNamespace  1     spec statements must live in namespace"
  "ImplementedBy     1     Fixtures.ImplementedBy.Spec.slowId has @[implemented_by]"
  "Partial           1     Fixtures.Partial.Spec.loop is opaque"
  "SkipKernel        1     kernel replay rejected a project declaration"
  "UniversePoly      1     must not be universe-polymorphic"
  "ProofInSpec       1     must be declared in a module under Fixtures.ProofInSpec.Proofs"
  "Forged            1     Fixtures.Forged.Spec.Extra is declared in Fixtures.Forged.Proofs"
  "Outsider          1     module Fixtures.OutsiderHelper is imported but is neither"
)

failures=0
covered=()

run_case() {  # name expected_exit needle [extra args...]
  local name=$1 want=$2 needle=$3
  shift 3
  local out code=0
  out=$(lake exe axiomcheck --root test/axiomcheck \
          --spec "Fixtures.$name.Spec" --proofs "Fixtures.$name.Proofs" "$@" 2>&1) || code=$?
  if [[ $code -ne $want ]]; then
    echo "FAIL $name $*: exit $code, expected $want"; echo "$out" | sed 's/^/     | /'
    failures=$((failures + 1))
  elif [[ $out != *"$needle"* ]]; then
    echo "FAIL $name $*: output lacks: $needle"; echo "$out" | sed 's/^/     | /'
    failures=$((failures + 1))
  else
    echo "ok   $name $*"
  fi
}

for line in "${cases[@]}"; do
  read -r name want needle <<<"$line"
  covered+=("$name")
  run_case "$name" "$want" "$needle"
done

# --allow-unproven downgrades a missing proof to a warning (local use only; CI never passes it).
run_case Missing 0 "WARN Fixtures.Missing.Spec.T: no proof" --allow-unproven

# Statements may only depend on reviewed code. Lib is checked (--also) but not trusted.
covered+=(UntrustedDep TrustedDep)
run_case UntrustedDep 1 "depends on 1 definition(s) from untrusted modules" \
  --also Fixtures.UntrustedDep.Lib
# A trusted definition may contain an untrusted *proof*, but must itself be trusted.
run_case TrustedDep 0 "PASS: 1 proven, 0 unproven, 0 failure(s)" \
  --also Fixtures.TrustedDep.Model --also Fixtures.TrustedDep.Lib --trusted Fixtures.TrustedDep.Model
run_case TrustedDep 1 "Fixtures.TrustedDep.Model.one (in Fixtures.TrustedDep.Model)" \
  --also Fixtures.TrustedDep.Model --also Fixtures.TrustedDep.Lib

# Every fixture directory must be covered above.
for dir in test/axiomcheck/Fixtures/*/; do
  name=$(basename "$dir")
  if [[ ! " ${covered[*]} " == *" $name "* ]]; then
    echo "FAIL fixture $name has no expectation in run.sh"
    failures=$((failures + 1))
  fi
done

if [[ $failures -ne 0 ]]; then
  echo "axiomcheck self-tests: $failures failure(s)"
  exit 1
fi
echo "axiomcheck self-tests: all ${#cases[@]} cases + 4 flag variants passed"
