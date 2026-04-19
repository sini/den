#!/usr/bin/env bash
#
# Uses nix-eval-jobs with $(nproc) workers
# NOTE: Ignores tests with expectedError
#
# Redirect stdout to null IF you only want to see failures
set -aeuo pipefail

system="x86_64-linux"
if test -n "${1:-}"; then
  system="${1}"
  shift
fi

suite=""
preSuite=""
postSuite=""

if test -n "${1:-}"; then
  suite="$1"
  preSuite=".${suite}"
  postSuite="${suite}."
  shift
fi

args=($@)

results=$(mktemp -t den-test-XXXXX.json)

nix-eval-jobs \
  --flake ./templates/ci#tests${preSuite} \
  --override-input den . \
  --workers $(nproc) \
  --force-recurse \
  --select 'tests: let
    system="'"${system}"'";
    go = prefix: v:
      if v ? expr then
        let
          hasExpected = v ? expected && !(v.expected ? undefined);
          hasExpectedError = v ? expectedError && !(v.expectedError ? undefined);
          pass = if hasExpected then v.expr == v.expected
                 else if hasExpectedError then true # ignored
                 else true;
          name = builtins.replaceStrings ["." "'\''"] ["-" "_"] prefix;
        in derivation {
          name = if pass then "PASS-${name}" else "FAIL-${name}";
          system = "${system}"; builder = "/bin/sh";
          args = ["-c" "echo > $out"];
        }
      else if builtins.isAttrs v then
        builtins.mapAttrs (k: go (if prefix == "" then k else "${prefix}.${k}")) v
      else derivation { name = "SKIP"; system = "${system}"; builder = "/bin/sh"; args = ["-c" "echo > $out"]; };
  in builtins.mapAttrs (k: go k) tests' \
  "${args[@]}" 2>/dev/null \
  | tee "$results" \
  | jq -r 'if (.name != null and (.name | startswith("PASS-"))) then "✅ '"${postSuite}"'" + .attr else "❌ '"${postSuite}"'" + .attr end'

total=$(cat "$results" | wc -l)
pass=$(jq -r 'select(.name != null and (.name | startswith("PASS-"))) | "."' "$results" | wc -l)


if [ "$(expr "$total" - "$pass")" -eq "0" ]; then
  echo "🎉 ${pass}/${total} successful" >&2
  rm "$results" || true
else
  echo "😢 ${pass}/${total} successful" >&2
  echo >&2
  echo "💥 FAILURES ($(expr "$total" - "$pass")):" >&2
  echo "For details run with \`just ci-deep <suite>\`" >&2
  echo "where <suite> does not include \`.test-xyz\`" >&2
  echo >&2
  jq -r 'select(.error != null) | "❌ '"${postSuite}"'" + .attr' "$results" >&2
  rm "$results" || true
  exit 1
fi

