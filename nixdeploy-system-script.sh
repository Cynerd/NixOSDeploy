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

[[ "$(readlink -f /nix/var/nix/profiles/system)" == @out@ ]] && setenv="n"
applied="y"
[[ "$(readlink -f /run/current-system)" == @out@ ]] || applied="n"

if [[ "$applied$setenv" == "yn" ]]; then
	info "This is the current NixOS configuration, no need to deploy."
	exit 0
fi
if [[ -z "${NIXDEPLOY_REEXEC:-}" ]] && [[ "$applied" == "n" ]]; then
	nix store diff-closures "/run/current-system" @out@
fi

[[ "$(id -u)" -eq 0 ]] || exec @sucmd@ NIXDEPLOY_REEXEC="yes" "$0" "$@"

latest_id=0
for link in /nix/var/nix/profiles/system-*-link; do
	link="${link#/nix/var/nix/profiles/system-}"
	link="${link%-link}"
	[[ "$link" =~ ^[0-9]+$ ]] || continue
	[[ "$(readlink -f "$link")" == @out@ ]] && {
		latest_id=
		break
	}
	[[ $latest_id -gt $link ]] || latest_id=$link
done
[[ -z "$latest_id" ]] ||
	ln -sf @out@ "/nix/var/nix/profiles/system-$((latest_id + 1))-link"

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
