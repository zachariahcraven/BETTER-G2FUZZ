#!/bin/bash
# resolve-latest.sh [projects.tsv] > latest.tsv: each project's newest stable release tag and its commit
# (git ls-remote; tags matching the project's regex, highest by version sort; peeled commit of annotated tags).
# Tarball-only projects (no git) print "manual" and are pinned by hand with a sha256 in manifest.tsv.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
printf 'project\ttag\tcommit\n'
grep -v '^#' "${1:-$HERE/projects.tsv}" | while IFS=$'\t' read -r p bench repo re; do
  [ -n "$p" ] || continue
  case "$repo" in tarball:*) printf '%s\tmanual\t%s\n' "$p" "${repo#tarball:}"; continue;; esac
  refs=$(git ls-remote --tags "$repo" 2>/dev/null) || { printf '%s\tERROR\tls-remote failed\n' "$p"; continue; }
  tag=$(echo "$refs" | awk '{print $2}' | sed -e 's#refs/tags/##' -e 's/\^{}$//' | sort -u | grep -E "$re" | sort -V | tail -1)
  [ -n "$tag" ] || { printf '%s\tERROR\tno tag matches %s\n' "$p" "$re"; continue; }
  c=$(echo "$refs" | awk -v t="refs/tags/$tag^{}" '$2==t{print $1}')
  [ -n "$c" ] || c=$(echo "$refs" | awk -v t="refs/tags/$tag" '$2==t{print $1}')
  printf '%s\t%s\t%s\n' "$p" "$tag" "$c"
done
