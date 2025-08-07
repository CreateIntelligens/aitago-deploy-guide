find /srv -type d -name ".git" | while read gitdir; do
  workdir=$(dirname "$gitdir")
  echo "📁 $workdir"
  sudo git config --system --add safe.directory "$workdir"
  git --git-dir="$gitdir" --work-tree="$workdir" rev-parse --abbrev-ref HEAD
  git --git-dir="$gitdir" --work-tree="$workdir" log -1 --pretty=format:"%h %s (%cr)"
  echo ""
done

