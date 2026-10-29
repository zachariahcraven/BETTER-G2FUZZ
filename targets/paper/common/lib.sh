# targets/paper/common/lib.sh: shared steps for targets/paper/<project>/build.sh (source it).
#   paper_fetch TARGET VERSION DIR   source of TARGET's manifest row for VERSION (paper|latest) into DIR,
#                                    verified against the row's pin (git commit, or sha256 of the archive)
#   paper_finish OUT TARGET VERSION  after OUT/TARGET.{afl,cmp,asan} are built: copies OUT/TARGET.args and the
#                                    stock seeds, bundles libraries the run image lacks into OUT/lib (RPATH
#                                    $ORIGIN/lib), writes OUT/build-info/TARGET.tsv (pin + sha256 of each build)
#   paper_row TARGET VERSION FIELD   one manifest field (target bench project version source pin args seeds formats)
# Needs: PAPER_REF (the reference clones: unibench, seeds, magma, fuzzbench; default the shared g2f-targets/ref)
# and RUN_LIBS (the run image's `ldconfig -p` library names, one per line; made by build-paper.sh).
PAPER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PAPER_REF=${PAPER_REF:-/home/group/csci-591-automated-vulnerability-discovery/students/g2f-targets/ref}
paper_die() { echo "paper: $*" >&2; exit 1; }

paper_row() {
  local f; case $3 in target) f=1;; bench) f=2;; project) f=3;; version) f=4;; source) f=5;; pin) f=6;;
    args) f=7;; seeds) f=8;; formats) f=9;; *) paper_die "paper_row: unknown field $3";; esac
  local r; r=$(grep -v '^#' "$PAPER_DIR/manifest.tsv" |
    awk -F'\t' -v t="$1" -v v="$2" '$1 == t && ($4 == v || index($4, v ":") == 1)')
  [ "$(echo "$r" | grep -c .)" = 1 ] || paper_die "manifest: need exactly one row for $1 $2"
  echo "$r" | cut -f$f
}

paper_fetch() {
  local src pin dir=$3; src=$(paper_row "$1" "$2" source); pin=$(paper_row "$1" "$2" pin)
  mkdir -p "$dir"
  case "$pin" in
    sha256:*)
      local a="$dir.archive"
      case "$src" in
        unibench:*) cp "$PAPER_REF/unibench/${src#unibench:}" "$a" ;;
        *) wget -q -O "$a" "$src" || paper_die "download failed: $src" ;;
      esac
      [ "$(sha256sum < "$a" | cut -c1-64)" = "${pin#sha256:}" ] || paper_die "$1 $2: sha256 of $src is not $pin"
      case "$src" in
        *.zip|*zip/download) unzip -q "$a" -d "$dir" ;;
        *) tar xf "$a" -C "$dir" ;;
      esac
      rm -f "$a"
      # archives hold one top folder: return its path (some, e.g. mp3gain, hold the files directly)
      local tops; tops=$(ls -A "$dir")
      if [ "$(echo "$tops" | wc -l)" = 1 ] && [ -d "$dir/$tops" ]; then echo "$dir/$tops"; else echo "$dir"; fi ;;
    *)
      git clone -q --no-checkout "$src" "$dir" || paper_die "clone failed: $src"
      git -C "$dir" checkout -q "$pin" || paper_die "$1 $2: no commit $pin in $src"
      [ "$(git -C "$dir" rev-parse HEAD)" = "$pin" ] || paper_die "$1 $2: HEAD is not $pin"
      echo "$dir" ;;
  esac
}

# Stock seeds: unifuzz:<folder> (unifuzz/seeds general_evaluation), magma:<lib>/<program> (targets/<lib>/corpus/<program>),
# fuzzbench (the benchmark's own seeds: build.sh puts them in OUT/seeds/TARGET itself, before paper_finish)
paper_seeds() {
  local seeds out=$3; seeds=$(paper_row "$1" "$2" seeds); mkdir -p "$out"
  case "$seeds" in
    unifuzz:*) cp -r "$PAPER_REF/seeds/general_evaluation/${seeds#unifuzz:}"/. "$out/" ;;
    magma:*) s=${seeds#magma:}; cp -r "$PAPER_REF/magma/targets/${s%%/*}/corpus/${s#*/}"/. "$out/" ;;
    fuzzbench) ;;
    *) paper_die "unknown seed source $seeds" ;;
  esac
  find "$out" -mindepth 1 -type d -empty -delete
  [ -n "$(ls -A "$out")" ] || paper_die "$1 $2: no stock seeds in $out"
}

paper_finish() {
  local out=$1 t=$2 v=$3 b lib n
  [ -f "${RUN_LIBS:-}" ] || paper_die "RUN_LIBS (the run image's library list) is not set"
  printf '%s\n' "$(paper_row "$t" "$v" args)" > "$out/$t.args"
  paper_seeds "$t" "$v" "$out/seeds/$t"
  mkdir -p "$out/lib" "$out/build-info"
  for b in afl cmp asan; do
    [ -x "$out/$t.$b" ] || paper_die "$out/$t.$b was not built"
    # libraries the run image doesn't have: bundle them next to the binaries
    ldd "$out/$t.$b" | awk '$2 == "=>" && $3 ~ /^\// {print $1, $3}' | while read -r n lib; do
      grep -qxF "$n" "$RUN_LIBS" && continue
      cp -L "$lib" "$out/lib/$n"; chmod 644 "$out/lib/$n"
      patchelf --set-rpath '$ORIGIN' "$out/lib/$n"
    done
    if [ -n "$(ls -A "$out/lib")" ]; then patchelf --set-rpath '$ORIGIN/lib' "$out/$t.$b"; fi
  done
  {
    printf '%s\t%s\t' "$t" "$(paper_row "$t" "$v" pin)"
    for b in afl cmp asan; do printf '%s=%s ' "$b" "$(sha256sum < "$out/$t.$b" | cut -c1-64)"; done
    # recipe: 'reference' (the benchmark's own build) or what build.sh sets in PAPER_RECIPE (e.g. oss-fuzz@<commit>)
    printf '\t%s\t%s\t%s\n' "${G2F_BUILDER:-unknown builder}" "$(date '+%F %T')" "recipe=${PAPER_RECIPE:-reference}"
  } > "$out/build-info/$t.tsv"
}
