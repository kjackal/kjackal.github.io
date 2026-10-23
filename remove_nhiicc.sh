#!/usr/bin/env bash
set -uo pipefail

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
  echo "Error: Root privileges required. Please run: sudo bash $0"
  echo "錯誤：需要管理者權限，請使用 sudo bash $0 執行"
  exit 1
fi

echo "Starting NHIICC cleanup..."
echo "開始清理健保卡網路服務元件 (NHIICC)..."

# Helper function to remove a file or directory if it exists
remove_entry() {
  local target="$1"
  if [[ -e "$target" || -L "$target" ]]; then
    echo "Removing: $target"
    echo "正在移除：$target"
    rm -rf "$target"
  fi
}

# 1. Unload and delete LaunchDaemon service plists
for plist in \
  /Library/LaunchDaemons/nhiicc.plist \
  /Library/LaunchDaemons/tw.gov.nhi.nhiicc.plist \
  /Library/LaunchDaemons/tw.gov.nhi.nhiicc2023.plist; do
  if [[ -f "$plist" ]]; then
    echo "Unloading LaunchDaemon: $plist"
    echo "正在卸載開機服務：$plist"
    launchctl unload -w "$plist" 2>/dev/null || true
    remove_entry "$plist"
  fi
done

# 2. Ensure running nhiicc processes are terminated
if pgrep -i nhiicc >/dev/null 2>&1; then
  echo "Terminating running nhiicc process..."
  echo "正在終止執行中的 nhiicc 程序..."
  killall -9 nhiicc 2>/dev/null || true
fi

# 3. Remove application files and startup directories
remove_entry "/usr/local/share/nhiicc"
remove_entry "/Library/StartupItems/nhiicc"

# 4. Remove certificates from System Keychain (loop to remove duplicates if any)
cert_found=false
while security find-certificate -c "NHIServerCert" /Library/Keychains/System.keychain >/dev/null 2>&1; do
  cert_found=true
  echo "Removing NHIServerCert from system keychain..."
  echo "正在從系統鑰匙圈移除 NHIServerCert 憑證..."
  security delete-certificate -c "NHIServerCert" /Library/Keychains/System.keychain 2>/dev/null || break
done

if [[ "$cert_found" = false ]]; then
  echo "NHIServerCert not found in system keychain."
  echo "系統鑰匙圈中未找到 NHIServerCert 憑證。"
fi

# 5. Remove shared files and safely verify /Users/Shared/share
remove_entry "/Users/Shared/macInstall2023.txt"
remove_entry "/Users/Shared/nhiicc"

if [[ -d "/Users/Shared/share" ]]; then
  # Safeguard: verify directory contents contain NHI-related indicators before deleting
  if grep -ri "nhi" /Users/Shared/share >/dev/null 2>&1 || [[ $(find /Users/Shared/share -iname "*nhi*" 2>/dev/null | wc -l) -gt 0 ]]; then
    echo "Removing shared directory: /Users/Shared/share"
    echo "正在移除健保元件共用目錄：/Users/Shared/share"
    rm -rf "/Users/Shared/share"
  else
    echo "Skipping /Users/Shared/share: No NHI signatures found to avoid accidental deletion."
    echo "跳過 /Users/Shared/share：未偵測到健保元件特徵，避免誤刪。"
  fi
fi

# 6. Clean up macOS package receipts if present
receipts=$(pkgutil --pkgs 2>/dev/null | grep -iE "nhi|nhiicc" || true)
if [[ -n "$receipts" ]]; then
  for pkg in $receipts; do
    echo "Forgetting package receipt: $pkg"
    echo "正在清理安裝套件收據：$pkg"
    pkgutil --forget "$pkg" 2>/dev/null || true
  done
fi

echo "Cleanup complete! A system or browser restart is recommended."
echo "清理完成！建議重新啟動系統或瀏覽器。"
