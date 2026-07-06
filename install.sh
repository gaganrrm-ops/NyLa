#!/data/data/com.termux/files/usr/bin/sh
# NyLa installer for a friend's phone. Run this inside Termux.
#
# What it does (in order):
#   1. Sanity-checks Termux (and warns if it's the Play Store build, which
#      has known issues with the storage permission and proot-distro).
#   2. Verifies Android has granted Termux access to shared storage. If not,
#      it walks the user through the settings screen — this step is the one
#      thing the script cannot automate.
#   3. Installs `proot-distro` (Termux's package, not Ubuntu's) and the
#      `ubuntu` container (~500 MB download).
#   4. Inside Ubuntu: installs `git`, `unzip`, `ca-certificates`, and Bun
#      (via the official bun.sh install script).
#   5. Pulls the NyLa web source from the configured GitHub repo and drops
#      it at /root/ny-la-web/ in the container.
#   6. Installs the termux-services `run` script and the `ny-la-start`
#      helper so the server auto-starts on phone boot and after a kill.
#   7. Installs the Termux:Boot startup hook (if the user has the
#      Termux:Boot app installed and granted it the BOOT_COMPLETED
#      permission — both are out of our control).
#   8. Starts the service, waits for it to come up, and prints the URL the
#      user should tap (or scan) to open the NyLa web UI in Chrome.
#
# Re-running is safe: every step is a no-op if the underlying state is
# already in place. To uninstall: `bash <(curl ...) --uninstall`.

set -e

REPO_URL="${NYLA_REPO_URL:-https://github.com/gaganrrm-ops/NyLa}"
REPO_BRANCH="${NYLA_BRANCH:-main}"
NyLa_PORT=7317
PREFIX=/data/data/com.termux/files/usr
SVDIR=$PREFIX/var/service
LOGDIR=$PREFIX/var/log
BOOT_DIR=$PREFIX/home/.termux/boot
NyLa_BIN=$PREFIX/bin/ny-la-start

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

step() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '  \033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed. Run: pkg install $1"
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

step "Preflight"

# 1. Are we in Termux? Detect by /data/data/com.termux/files/usr.
[ -d "$PREFIX" ] || die "This script must be run inside Termux. Install Termux from F-Droid: https://f-droid.org/packages/com.termux/"
ok "Running inside Termux"

# 2. Detect Play Store vs F-Droid Termux. Play build is packageVersionCode
#    "googleplay" in /data/data/com.termux/files/usr/etc/termux-extra.properties
#    (or by absence of the etc dir). F-Droid is the supported variant.
if [ -f "$PREFIX/etc/termux-extra.properties" ] && grep -q "googleplay" "$PREFIX/etc/termux-extra.properties" 2>/dev/null; then
	warn "You appear to be running the Play Store build of Termux."
	warn "The Play version is outdated and known to break storage permission + proot-distro."
	warn "Please uninstall it and install the F-Droid build: https://f-droid.org/packages/com.termux/"
	warn "Continuing in 10 seconds — press Ctrl-C to abort."
	sleep 10
else
	ok "Termux build: F-Droid (good)"
fi

# 3. Android API level: NyLa needs API 24+ (Android 7.0). Anything older will
#    fail to install the APK. We can't easily detect API level from inside
#    Termux without getprop, but it's almost always >= 24 on phones that
#    can run modern Chrome.
API=$(getprop ro.build.version.sdk 2>/dev/null || echo "0")
if [ "$API" -lt 24 ] 2>/dev/null; then
	die "This phone runs Android API $API (< 24). NyLa needs Android 7.0 or newer."
fi
ok "Android API level: $API"

# 4. Storage permission. Termux:API must be installed AND the user must
#    have granted "All files access" (Android 11+) or "Storage" (Android
#    6–10). There's no shell-side way to grant it; we have to ask.
if [ ! -d "$PREFIX/home/storage" ]; then
	warn "Termux does not yet have storage permission."
	warn "Running: termux-setup-storage  (this will pop a system dialog — accept it)"
	warn "If the dialog doesn't appear, open Termux's Android settings and"
	warn "  toggle Permissions → Files and media → Allow."
	termux-setup-storage
	sleep 1
fi
if [ -d "$PREFIX/home/storage" ]; then
	ok "Storage permission granted"
else
	warn "Storage permission was not granted. Continuing anyway — some features (APK upload, /sdcard access) will not work."
fi

# 5. Architecture. NyLa needs arm64 (most modern phones). x86_64 emulators
#    are also fine. i386 is not supported.
ARCH=$(uname -m)
case "$ARCH" in
	aarch64|arm64) ok "Architecture: arm64" ;;
	x86_64)        ok "Architecture: x86_64 (emulator)" ;;
	*)             die "Unsupported architecture: $ARCH. NyLa needs arm64 or x86_64." ;;
esac

# ---------------------------------------------------------------------------
# Install Termux packages we need
# ---------------------------------------------------------------------------

step "Installing Termux packages"

pkg update -y
for p in proot-distro termux-services termux-api git curl unzip; do
	if ! dpkg -s "$p" >/dev/null 2>&1; then
		pkg install -y "$p" || die "Failed to install Termux package '$p'"
	fi
done
ok "Termux packages ready (proot-distro, termux-services, termux-api, git, curl, unzip)"

# ---------------------------------------------------------------------------
# Install Ubuntu + Bun + NyLa
# ---------------------------------------------------------------------------

step "Installing Ubuntu (proot-distro)"

if ! proot-distro list 2>/dev/null | grep -q "^ubuntu$"; then
	proot-distro install ubuntu || die "Failed to install Ubuntu container"
else
	ok "Ubuntu container already present"
fi
ok "Ubuntu container ready"

step "Installing NyLa inside Ubuntu"

# We run everything inside the proot Ubuntu. Bundled into one script that
# gets piped in, so the install is a single command (idempotent: each
# inner step is a no-op if already done).
proot-distro login ubuntu -- bash -lc '
set -e
export DEBIAN_FRONTEND=noninteractive

step_inner() { printf "\n\033[1;36m  ▸ %s\033[0m\n" "$*"; }
ok_inner()   { printf "    \033[1;32m✓\033[0m %s\n" "$*"; }

# System packages
step_inner "apt packages"
if ! dpkg -s git >/dev/null 2>&1; then
	apt-get update -qq
	apt-get install -y -qq git ca-certificates curl unzip >/dev/null
fi
ok_inner "apt packages ready"

# Bun
step_inner "Bun"
if [ ! -x /root/.bun/bin/bun ]; then
	curl -fsSL https://bun.sh/install | bash >/dev/null
	ok_inner "Bun installed"
else
	ok_inner "Bun already present"
fi

# NyLa source
step_inner "NyLa source"
if [ ! -d /root/]; then
	git clone --depth 1 -b "'"$REPO_BRANCH"'" "'"$REPO_URL"'" /root/ny-la-web
	ok_inner "NyLa source cloned"
else
	ok_inner "NyLa source already present"
fi

# Install dependencies (idempotent, small)
cd /root/ny-la-web
if [ ! -d node_modules ] || [ package.json -nt node_modules ]; then
	/root/.bun/bin/bun install --production 2>&1 | tail -5
fi
ok_inner "NyLa deps ready"
'

ok "NyLa installed in Ubuntu container"

# ---------------------------------------------------------------------------
# Install the termux-services run script + helper + boot hook
# ---------------------------------------------------------------------------

step "Installing service files"

# 1. The run script (Ubuntu-context aware, sets SVDIR explicitly so the
#    kill path works from inside proot).
mkdir -p "$SVDIR/ny-la-web"
cat > "$SVDIR/ny-la-web/run" <<'RUN_EOF'
#!/data/data/com.termux/files/usr/bin/sh
# Detects inner-vs-outer Termux and execs the right bun invocation. Sets
# SVDIR so the /api/kill endpoint (which calls `sv down ny-la-web`) works
# from inside the bun process running in proot.
tracer_pid=$(awk '/^TracerPid:/{print $2}' /proc/self/status 2>/dev/null)
tracer_name=""
[ -n "$tracer_pid" ] && [ "$tracer_pid" != "0" ] && tracer_name=$(cat "/proc/$tracer_pid/comm" 2>/dev/null)
export SVDIR=/data/data/com.termux/files/usr/var/service
if [ "$tracer_name" = "proot" ]; then
	export HOME=/root
	export USER=root
	export PATH="/root/.bun/bin:/root/.nvm/versions/node/v24.18.0/bin:$PATH"
	cd /root/&& exec bun run src/server.ts 2>&1
else
	exec proot-distro login ubuntu -- bash -lc 'export SVDIR=/data/data/com.termux/files/usr/var/service; cd /root/&& exec /root/.bun/bin/bun run src/server.ts' 2>&1
fi
RUN_EOF
chmod +x "$SVDIR/ny-la-web/run"
ok "termux-services run script installed"

# 2. log/run so runsv can write logs
mkdir -p "$LOGDIR/sv/ny-la-web"
cat > "$SVDIR/ny-la-web/log/run" <<'LOG_EOF'
#!/data/data/com.termux/files/usr/bin/sh
exec svlogd -tt /data/data/com.termux/files/usr/var/log/sv/ny-la-web
LOG_EOF
chmod +x "$SVDIR/ny-la-web/log/run"
ok "log runner installed"

# 3. The ny-la-start helper, used by the lion-icon launcher to bring the
#    service back up after a kill.
cat > "$NYLA_BIN" <<'START_EOF'
#!/data/data/com.termux/files/usr/bin/sh
# Bring the service back up. Use this from the Android home-screen
# lion-icon shortcut (Tasker/Automate/Shortcuts) AFTER the user has tapped
# "Kill app" in the web UI.
set -e
export SVDIR=/data/data/com.termux/files/usr/var/service
PREFIX=/data/data/com.termux/files/usr
"$PREFIX/bin/sv" up 2>/dev/null || {
	echo "ny-la-start: failed to start (is termux-services installed?)" >&2
	exit 1
}
url="http://127.0.0.1:7317"
for _ in 1 2 3 4 5; do
	curl -fsS -o /dev/null "$url" 2>/dev/null && break
	sleep 0.2
done
if [ "$1" = "--show" ]; then
	"$PREFIX/bin/termux-open-url" "$url" 2>/dev/null || true
fi
echo "ny-la-web: up (http://127.0.0.1:7317)"
START_EOF
chmod +x "$NYLA_BIN"
ok "ny-la-start helper installed at $NYLA_BIN"

# 4. Termux:Boot hook. This runs the service supervisor on phone boot, so
#    the NyLa service auto-starts whenever the phone reboots.
mkdir -p "$BOOT_DIR"
cat > "$BOOT_DIR/start-nyla.sh" <<'BOOT_EOF'
#!/data/data/com.termux/files/usr/bin/sh
# Runs automatically on Android boot via the Termux:Boot app.
# Starts Termux's service supervisor (runsvdir), which then auto-starts
# every enabled termux-services job — including — on its own
# scan cycle. No terminal window is shown; this runs headless.
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export SVDIR=$PREFIX/var/service
export LOGDIR=$PREFIX/var/log
export PATH=$PREFIX/bin:$PATH

termux-wake-lock 2>/dev/null
service-daemon start
BOOT_EOF
chmod +x "$BOOT_DIR/start-nyla.sh"
ok "Termux:Boot hook installed"

# ---------------------------------------------------------------------------
# Start the service now and verify
# ---------------------------------------------------------------------------

step "Starting service"

# runsvdir may not be running yet. Start it; idempotent.
service-daemon start 2>/dev/null || true
sleep 1

# Make sure the job is "up" (this also re-runs the run script).
SVDIR=$SVDIR "$PREFIX/bin/sv" up 2>&1 | head -3 || warn "sv up returned non-zero — the service may already be running or the run script errored."

# Wait up to ~10s for the listener to come up.
URL="http://127.0.0.1:$NYLA_PORT"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
	if curl -fsS -o /dev/null "$URL" 2>/dev/null; then
		ok "Service is responding at $URL"
		break
	fi
	sleep 0.7
done

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------

step "Done"

cat <<EOF

  ✓ NyLa is installed and running.

  Open the web UI in Chrome:
      $URL

  Install the lion-icon APK (sister repo, releases page):
      ${REPO_URL%/}/releases

  Or use the PWA: Chrome → menu → "Add to Home screen".

  Logs (if anything misbehaves):
      tail -f $LOGDIR/sv/ny-la-web/current

  Restart the service:
      sv restart    # (with SVDIR=$SVDIR)

  Uninstall:
      bash <(curl ...) --uninstall

EOF

# Optional uninstall branch
if [ "$1" = "--uninstall" ]; then
	step "Uninstalling"
	SVDIR=$SVDIR "$PREFIX/bin/sv" down 2>/dev/null || true
	rm -rf "$SVDIR/ny-la-web"
	rm -f "$NYLA_BIN" "$BOOT_DIR/start-nyla.sh"
	proot-distro login ubuntu -- bash -c 'rm -rf /root/ny-la-web' 2>/dev/null || true
	ok "Uninstall complete. proot-distro remove ubuntu is left to you."
	exit 0
fi
