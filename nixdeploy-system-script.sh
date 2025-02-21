#!@shell@
# Simple script that switches configuration as well as sets system profile
set -eu
_print() {
	local color="\e[$1m"
	local clrcolor="\e[0m"
	shift
	if ! [[ -t 2 ]]; then
		color=""
		clrcolor=""
	fi
	printf "${color}%s${clrcolor}\n" "$*" >&2
}
info() {
	_print "1;32" "$@"
}
fail() {
	_print '1;31' "$@"
	exit 1
}
find_profile() {
	find /nix/var/nix/profiles -maxdepth 1 -type l -name 'system-[0-9]*-link' "$@"
}

setenv="y"
op="${1:-switch}"
case "$op" in
switch | boot) ;;
test | dry)
	setenv="n"
	;;
*)
	fail "Unknown operation: $1"
	;;
esac
[[ $# -eq 0 ]] || shift 1
[[ $# -eq 0 ]] || fail "Invalid arguments: $*"

current_system="$(readlink -f /run/current-system)"
booted_system="$(readlink -f /run/booted-system)"

[[ "$(readlink -f /nix/var/nix/profiles/system)" == @out@ ]] && setenv="n"
applied="y"
[[ "$current_system" == @out@ ]] || applied="n"

if [[ "$applied$setenv" == "yn" ]]; then
	info "This is the current NixOS configuration, no need to deploy."
	exit 0
fi
if [[ -z "${NIXDEPLOY_REEXEC:-}" ]] && [[ "$applied" == "n" ]]; then
	nix store diff-closures "$current_system" @out@
fi

[[ "$(id -u)" -eq 0 ]] || exec @sucmd@ NIXDEPLOY_REEXEC="yes" "$0" "$@"

readarray -t revs < <(
	find_profile -printf '%P\n' |
		sed 's/system-\([^-]*\)-link/\1/g' |
		sort -n
)

# Create profile link. It is always moved to be the latest link even if it is
# already present. This is to ensure that cleanup removes only most unused
# profiles.
latest_id="${revs[-1]:-0}"
latest_link="/nix/var/nix/profiles/system-$latest_id-link"
if [[ "$(readlink -f "$latest_link")" != "@out@" ]]; then
	[[ -L "$latest_link" ]] &&
		latest_id=$((latest_id + 1))
	find_profile -lname @out@ -delete
	ln -sf @out@ "/nix/var/nix/profiles/system-$latest_id-link"
fi

# Remove older configurations
if [[ -n "@keep_latest@" ]]; then
	toclear=$((${#revs[@]} - @keep_latest@))
	for id in "${revs[@]:0:$toclear}"; do
		link="/nix/var/nix/profiles/system-$id-link"
		system="$(readlink -f "$link")"
		if [[ "$system" != "$current_system" ]] &&
			[[ "$system" != "$booted_system" ]] &&
			[[ "$system" != '@out@' ]]; then
			rm -f "$link"
		fi
	done
fi

if [[ "$setenv" == "y" ]]; then
	rm -f /nix/var/nix/profiles/system
	ln -sf @out@ /nix/var/nix/profiles/system
fi

if [[ "$applied" == "n" ]]; then
	exec systemd-run \
		-E LOCALE_ARCHIVE -E NIXOS_INSTALL_BOOTLOADER \
		--collect \
		--no-ask-password --pty \
		--same-dir \
		--service-type=exec \
		--unit=nixos-switch-to-configuration \
		--quiet --wait \
		@out@/bin/switch-to-configuration "$op"
fi
