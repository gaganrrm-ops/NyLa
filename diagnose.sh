#!/data/data/com.termux/files/usr/bin/sh
# Diagnose why termux-setup-storage isn't working on this phone.
# Outputs: where you are, what's installed, what permissions are set.
# Run:  bash <(curl -fsSL https://raw.githubusercontent.com/gaganrrm-ops/NyLa/main/diagnose.sh)
# Or copy-paste each line below if the curl one-liner also fails.

set +e

printf '\n\033[1;36m=== NyLa installer diagnostic ===\033[0m\n\n'

printf 'Where you are right now:\n  pwd:    %s\n  HOME:   %s\n  user:   %s\n' \
	"$(pwd)" "${HOME:-<unset>}" "$(whoami 2>/dev/null || echo unknown)"

printf '\nTermux is detected:\n'
if [ -d /data/data/com.termux/files/usr ]; then
	echo '  yes, /data/data/com.termux/files/usr exists'
else
	echo '  NO -- this script must be run inside Termux'
	printf '  Install: https://f-droid.org/packages/com.termux/\n'
	exit 0
fi

printf '\nTermux build (F-Droid vs Play):\n'
if [ -f /data/data/com.termux/files/usr/etc/termux-extra.properties ] && \
   grep -q googleplay /data/data/com.termux/files/usr/etc/termux-extra.properties 2>/dev/null; then
	echo '  Play Store build (UNSUPPORTED). Please install Termux from F-Droid instead.'
else
	echo '  F-Droid build (good)'
fi

printf '\nIs termux-setup-storage available?\n'
if command -v termux-setup-storage >/dev/null 2>&1; then
	echo "  yes -> $(command -v termux-setup-storage)"
else
	printf '  NO -> this command comes from the \033[1mTermux:API\033[0m app.\n'
	printf '  Fix: open F-Droid, search "Termux:API", install it.\n'
	printf '  Then re-open Termux once and re-run this script.\n'
fi

printf '\nHas storage permission been granted?\n'
if [ -d /data/data/com.termux/files/home/storage ]; then
	printf '  yes -> /data/data/com.termux/files/home/storage exists\n'
	printf '  contents: %s\n' "$(ls /data/data/com.termux/files/home/storage 2>/dev/null | tr '\n' ' ')"
else
	printf '  NO -> /data/data/com.termux/files/home/storage does not exist\n'
	printf '  Fix: install Termux:API, then run: termux-setup-storage\n'
	printf '  Or: Android Settings -> Apps -> Termux -> Permissions -> Files and media -> Allow\n'
fi

printf '\nAndroid version:\n'
printf '  SDK: %s\n' "$(getprop ro.build.version.sdk 2>/dev/null || echo 'unknown')"
printf '  release: %s\n' "$(getprop ro.build.version.release 2>/dev/null || echo 'unknown')"

printf '\nRequired Termux packages:\n'
for p in proot-distro termux-services termux-api; do
	if dpkg -s "$p" >/dev/null 2>&1; then
		echo "  $p: installed"
	else
		echo "  $p: MISSING (will be installed by the main script)"
	fi
done

printf '\n\033[1;36m=== end of diagnostic ===\033[0m\n'
printf 'If the main install script still fails after fixing the items above,\n'
printf 'copy the entire output above and send it back for diagnosis.\n\n'
