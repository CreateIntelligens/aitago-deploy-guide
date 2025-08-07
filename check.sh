find /srv -type d -name ".git" | while read gitdir; do
  workdir=$(dirname "$gitdir")
  echo "📁 $workdir"

  # 加入 safe.directory
  sudo git config --system --add safe.directory "$workdir"

  # 顯示目前 branch
  git --git-dir="$gitdir" --work-tree="$workdir" rev-parse --abbrev-ref HEAD

  # 顯示最後一次 commit 訊息
  git --git-dir="$gitdir" --work-tree="$workdir" log -1 --pretty=format:"%h %s (%cr)"

  # 顯示 remote URL（若無則提示）
  remote_url=$(git --git-dir="$gitdir" --work-tree="$workdir" config --get remote.origin.url)
  if [ -n "$remote_url" ]; then
    echo "🌐 Remote: $remote_url"
  else
    echo "⚠️  No remote URL set"
  fi

  echo ""
done
