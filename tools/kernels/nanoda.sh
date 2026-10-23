#!/usr/bin/env bash
# Re-check every project declaration with nanoda, an independent Lean 4 type checker written in
# Rust. It is a second kernel, so a bug in Lean's own kernel would also have to exist in nanoda to
# go unnoticed (docs/trusted-base.md §7).
#
# Axiom policy is owned by `lake exe axiomcheck`. nanoda adds a second line of defence: axioms not
# on the allowlist (the toolchain declares sorryAx, ofReduceBool, ...) are skipped, and any exported
# declaration that *uses* one is a hard error.
#
# Usage, from the repo root after `cd lean && lake build`:
#   tools/kernels/nanoda.sh
# Needs git, cargo and elan. NANODA_WORK=dir reuses a build directory between runs.
set -euo pipefail

# Pinned so the check is reproducible. Bump lean4export together with lean/lean-toolchain.
LEAN4EXPORT_REPO=https://github.com/leanprover/lean4export.git
LEAN4EXPORT_REV=5a9a355dc6c5fd82b69058d433e2ae2e8dfbf8fe  # "chore: bump toolchain to v4.35.0"
NANODA_REPO=https://github.com/ammkrn/nanoda_lib.git
NANODA_REV=8199c74c8166dc1fff1be3b4bd144cb725268628       # master, 2026-10-23 (reads lean4export NDJSON)

REPO=$(cd "$(dirname "$0")/../.." && pwd)
WORK=${NANODA_WORK:-$(mktemp -d)}
mkdir -p "$WORK"

fetch() {  # repo rev dir
  if [[ ! -d $3/.git ]]; then
    git init -q "$3"
    git -C "$3" remote add origin "$1"
  fi
  git -C "$3" fetch -q --depth 1 origin "$2"
  git -C "$3" checkout -q --force FETCH_HEAD
}

echo "== lean4export @ $LEAN4EXPORT_REV"
fetch "$LEAN4EXPORT_REPO" "$LEAN4EXPORT_REV" "$WORK/lean4export"
cp "$REPO/lean/lean-toolchain" "$WORK/lean4export/lean-toolchain"
(cd "$WORK/lean4export" && lake build)

echo "== nanoda_lib @ $NANODA_REV"
fetch "$NANODA_REPO" "$NANODA_REV" "$WORK/nanoda_lib"
(cd "$WORK/nanoda_lib" && cargo build --release --quiet)

# Every module under the checked prefixes, discovered from disk like axiomcheck does.
cd "$REPO/lean"
modules=()
for prefix in SfVerify Spec Proofs Subjects; do
  [[ -f $prefix.lean ]] && modules+=("$prefix")
  if [[ -d $prefix ]]; then
    while IFS= read -r f; do
      m=${f%.lean}
      modules+=("${m//\//.}")
    done < <(find "$prefix" -name '*.lean' | sort)
  fi
done
echo "== exporting ${#modules[@]} module(s)"
lake env "$WORK/lean4export/.lake/build/bin/lean4export" "${modules[@]}" > "$WORK/export.ndjson"
echo "export: $(wc -l < "$WORK/export.ndjson") lines"

# Allowed axioms, read from the allowlist so there is a single source of truth.
axioms=$(grep -o '``[A-Za-z_.]*' SfVerify/Axioms.lean | sed 's/^``//' \
  | awk '{printf "%s\"%s\"", (NR>1?", ":""), $0}')

cat > "$WORK/nanoda.json" <<EOF
{
  "export_file_path": "$WORK/export.ndjson",
  "use_stdin": false,
  "permitted_axioms": [$axioms],
  "unpermitted_axiom_hard_error": false,
  "nat_extension": true,
  "string_extension": true,
  "print_success_message": true
}
EOF

echo "== nanoda"
"$WORK/nanoda_lib/target/release/nanoda_bin" "$WORK/nanoda.json"
