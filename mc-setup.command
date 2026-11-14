#!/bin/bash
# Double-click launcher for macOS. Finds (or installs) a new enough bash, then runs mc-setup.sh.
DIR="$(cd "$(dirname "$0")" && pwd)"
xattr -dr com.apple.quarantine "$DIR" 2>/dev/null   # removes the "downloaded from the internet" flag from these files
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"

find_bash() {
  local b
  for b in /opt/homebrew/bin/bash /usr/local/bin/bash /opt/local/bin/bash; do
    if [ -x "$b" ] && "$b" -c '[ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 3 ]; }' 2>/dev/null; then echo "$b"; return 0; fi
  done
  return 1
}

NEWBASH="$(find_bash)"
if [ -z "$NEWBASH" ]; then
  echo
  echo "  The setup needs a newer 'bash' than the one that comes with macOS."
  echo "  It is a one-time install of about 2 minutes using Homebrew (the standard Mac installer for tools)."
  echo
  read -r -p "  Install it now? [Y/n] " ans
  case "$ans" in n|N|no|NO) echo "  Okay. Nothing was installed."; read -r -p "Press Enter to close " _; exit 0 ;; esac
  if ! command -v brew >/dev/null 2>&1; then
    echo
    echo "  Homebrew is not installed. Installing it first (it may ask for your Mac password, and may install the Apple command line tools - that can take a few minutes)."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$b" ] && eval "$("$b" shellenv)"; done
  fi
  if command -v brew >/dev/null 2>&1; then brew install bash; fi
  NEWBASH="$(find_bash)"
  if [ -z "$NEWBASH" ]; then
    echo
    echo "  Could not install bash automatically. Please open https://brew.sh , follow the one-line install, then run:  brew install bash"
    echo "  After that, double-click this file again."
    read -r -p "Press Enter to close " _; exit 1
  fi
fi

"$NEWBASH" "$DIR/mc-setup.sh" "$@"
echo
read -r -p "Press Enter to close this window " _
