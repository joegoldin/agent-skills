# Shared repository discovery. Prefer jj in colocated repos, but stop at the
# nearest repository boundary so a nested Git repo does not inherit outer jj.
sdd_repo() {
  root=$(pwd -P)
  while :; do
    if [ -e "$root/.jj" ]; then
      vcs=jj
      root=$(jj --ignore-working-copy --repository "$root" workspace root)
      return
    fi
    if [ -e "$root/.git" ]; then
      vcs=git
      root=$(git -C "$root" rev-parse --show-toplevel)
      return
    fi
    if [ "$root" = / ]; then
      echo "not in a Git or jj workspace" >&2
      return 1
    fi
    root=$(dirname "$root")
  done
}
