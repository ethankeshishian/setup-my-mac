#!/usr/bin/env bash

setup_tmp() {
  TMP=$(mktemp -d "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/smm.XXXXXX")
  export TMP
  export HOME="$TMP/home"
  export SMM_STATE="$TMP/state"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_CACHE_HOME="$HOME/.cache"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  unset SMM_NIX_ROOT SMM_APPLICATIONS_DIR SMM_SKIP_PREFS SMM_TEST_DOCUMENT SMM_TEST_VAULTS
  unset SMM_TX SMM_REPO SMM_BACKUP SMM_HOST SMM_YES SMM_SKIP_AEROSPACE
  unset SMM_APPLY_CMD SMM_VALIDATE_CMD SMM_SETUP_ORIGINAL_PATH
  export SMM_APPLICATIONS_DIR="$TMP/Applications"
  mkdir -p "$HOME" "$SMM_STATE" "$TMP/bin" "$SMM_APPLICATIONS_DIR"
  export PATH="$TMP/bin:$PATH"
  : > "$TMP/calls.log"
  local tool
  for tool in nix nix-env aerospace sketchybar brew darwin-rebuild sudo op gh launchctl osascript scutil systemextensionsctl karabiner_cli ghostty nvim open defaults killall kitten curl; do
    stub "$tool" 127
  done
  stub pgrep 0
  stub sysctl 0 '{ sec = 100, usec = 0 }'
}

stub() {
  local name=$1 exit_code=${2:-0} stdout=${3:-}
  case "$name" in
    ''|*[!a-zA-Z0-9_.-]*) return 2 ;;
  esac
  case "$exit_code" in
    ''|*[!0-9]*) return 2 ;;
  esac
  {
    printf '#!/usr/bin/env bash\n'
    printf 'stub_name=%q\nstub_stdout=%q\n' "$name" "$stdout"
    cat <<'STUB'
printf '%s %s\n' "$stub_name" "$*" >> "$TMP/calls.log"
if [ -n "$stub_stdout" ]; then printf '%s\n' "$stub_stdout"; fi
STUB
    printf 'exit %s\n' "$exit_code"
  } > "$TMP/bin/$name"
  chmod +x "$TMP/bin/$name"
}

# GNU and BSD sed disagree on -i, and nix develop puts GNU sed first on PATH.
# Rewriting in place with cat keeps the file's mode (stubs stay executable).
sed_inplace() {
  local script=$1 file=$2 tmp
  tmp=$(mktemp) || return 1
  sed "$script" "$file" > "$tmp" && cat "$tmp" > "$file"
  local status=$?
  rm -f "$tmp"
  return "$status"
}

calls() {
  cat "$TMP/calls.log"
}

make_repo() {
  git init --quiet --initial-branch=smm-test "$1"
  git -C "$1" config --local user.name 'Smm Test'
  git -C "$1" config --local user.email smm-test@example.invalid
  git -C "$1" -c commit.gpgsign=false commit --quiet --allow-empty -m 'Initial test commit'
}

make_remote_pair() {
  make_repo "$TMP/seed"
  git clone --quiet --bare "$TMP/seed" "$TMP/remote.git"
  local clone
  for clone in a b; do
    git clone --quiet "$TMP/remote.git" "$TMP/$clone"
    git -C "$TMP/$clone" config --local user.name 'Smm Test'
    git -C "$TMP/$clone" config --local user.email smm-test@example.invalid
  done
}

# Run a child with a controlling terminal while its stdin can still be a pipe.
run_tty() {
  python3 - "$@" <<'PY'
import errno, fcntl, os, pty, select, subprocess, sys, termios, time
master, slave = pty.openpty()
def terminal():
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
p = subprocess.Popen(sys.argv[1:], stdin=subprocess.DEVNULL, stdout=slave, stderr=slave,
                     preexec_fn=terminal, close_fds=True)
os.close(slave)
end = time.monotonic() + 15
try:
    while time.monotonic() < end:
        if select.select([master], [], [], .1)[0]:
            try:
                data = os.read(master, 65536)
            except OSError as e:
                if e.errno == errno.EIO: break
                raise
            if not data: break
            sys.stdout.buffer.write(data); sys.stdout.buffer.flush()
            if any(prompt in data for prompt in (b'TTY prompt', b'Host name [', b'Commit message:')):
                os.write(master, (os.environ.get('SMM_TEST_TTY_INPUT', 'yes') + '\n').encode())
        elif p.poll() is not None: break
    sys.exit(p.wait(timeout=1))
finally:
    if p.poll() is None: p.kill(); p.wait()
    os.close(master)
PY
}
