#!/usr/bin/env bash
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

stage() {
	_print '1;35' "$@"
}
verbose() {
	[[ "$verbose" != "y" ]] || _print "1;37" "${@@Q}"
}
info() {
	_print "1;32" "$@"
}
warning() {
	_print '1;33' "$@"
}
error() {
	_print '1;31' "$@"
}
fail() {
	error "$@"
	exit 1
}

usage() {
	echo "Usage: $0 [OPTION].. [SYSTEM].." >&2
}

help() {
	usage
	cat >&2 <<-EOF

		NixOS deployment tool.
		This tool manages your NixOS configuration evaluation, build, copy to
		the destination and switch to it.

		Options:
		  -e      Perform only evaluation
		  -r      Perform only evaluation and build (realize)
		  -c      Perform only evaluation, build and copy
		  -t      Do not make it boot default when switching to the new configuration
		  -b      Do not switch to the configuration immediately (make it only boot default)
		  -d      Instead of activation switch print only what would be done to activate it
		  -a ARGS Argument to be appended when invoking 'nix build'
		  -p PATH Path to the directory with flake (otherwise current directory is used)
		  -f      Fast execution by not fetching latest deployment configuration
		  -l      Force local build instead of remote (handy for testing)
		  -v      Run in verbose mode that tells you executed Nix commands
		  -x      Run in debug mode
		  -h      Print this help text and exit
	EOF
}

jqread() {
	local filter="$1"
	shift
	{
		for var in "$@"; do
			IFS= read -rd '' "$var"
		done
	} < <(jq --raw-output0 "$filter")
}

jqget() {
	jq -r "$@"
}

jqcheck() {
	jq -e "$@" >/dev/null
}

_nix() {
	local op="$1"
	shift
	verbose nix "$op" "$@"
	nix "$op" "$@"
}

nixeval() {
	local attr="$1"
	shift
	_nix eval --no-warn-dirty --json "$src#$attr" "$@"
}

nixeval_raw() {
	local attr="$1"
	shift
	_nix eval --no-warn-dirty --raw "$src#$attr" "$@"
}

config_check() {
	jqcheck "$2" <<<"${configs["$1"]}"
}
config_get() {
	jqget "$2" <<<"${configs["$1"]}"
}
config_read() {
	local config="$1"
	local query="$2"
	shift 2
	jqread "$query" "$@" <<<"${configs["$config"]}"
}

use_remote_build() {
	[[ "$local_build" != "y" ]] && config_check "$1" '.remoteBuild'
}

__ssh() (
	local arg="$1"
	local config="$2"
	shift 2
	config_read "$config" '[.ssh.host,._dups.hostName].[]' ssh_host hostname
	if [ "$hostname" != "$(hostname)" ]; then
		verbose ssh $arg "$ssh_host" -- "$@"
		ssh $arg "$ssh_host" -- "$@"
	else
		if [ $# -gt 1 ]; then
			verbose "$@"
			"$@"
		else
			verbose "$1"
			sh -c "$1"
		fi
	fi
)
_ssh() { __ssh '' "$@"; }
_ssht() { __ssh -t "$@"; }

_copy() {
	local config="$1"
	shift
	local -a args
	config_check "$config" '.noCopySubstitute' || args+=("--substitute-on-destination")
	_nix copy "${args[@]}" --to "ssh://$(config_get "$config" '.ssh.host')" "$@"
}

_outPath() {
	local config="$1"
	nix derivation show "$(readlink -f "$(f_drv "$config")")^*" |
		jq -r '.[].outputs.out.path'
}

################################################################################

# Load deployment configuration
config() {
	local sconfigs=("$@")
	local old_hash
	if [[ $# -eq 0 ]]; then
		{
			flock 42
			old_hash="$(jq -r 'keys | .[0]' /dev/fd/42)"
			if [[ -z "$old_hash" ]] || [[ "$fast" == "n" ]] && [[ "$old_hash" != "$src_hash" ]]; then
				stage "Indexing your flake..."
				rm -f "$src/.nixdeploy"/config-*.json >/dev/null || true
				truncate --size 0 /dev/fd/42
				nixeval "nixosConfigurations" --apply "v: {\"$src_hash\" = builtins.attrNames v;}" >&42
			fi
			readarray -d '' sconfigs < <(jq --raw-output0 '.[][]' "/dev/fd/42")
		} 42<>"$f_configs"
	fi
	for config in "${sconfigs[@]}"; do
		[[ "$config" == "localhost" ]] && config="$(hostname)"
		{
			flock 42
			old_hash="$(jq -r 'keys | .[0]' /dev/fd/42)"
			if [[ -z "$old_hash" ]] || [[ "$fast" == "n" ]] && [[ "$old_hash" != "$src_hash" ]]; then
				info "Loading deployment configuration for $config..."
				local attr="nixosConfigurations.\"${config}\".config"
				truncate --size 0 /dev/fd/42
				if [[ "$(nixeval "$attr" --apply 'builtins.hasAttr "deploy"')" == "true" ]]; then
					nixeval "$attr.deploy" --apply "v: {\"$src_hash\" = v;}" >&42
				else
					echo "{\"$src_hash\":{}}" >&42
				fi
			fi
			if [[ $# -gt 0 ]] || jqcheck '.[] | .enable and .default' </dev/fd/42; then
				if jqcheck '.[].enable' </dev/fd/42; then
					configs["$config"]="$(jq -c '.[]' /dev/fd/42)"
				else
					fail "Config '$config' doesn't have deployment configured."
				fi
			fi
		} 42<>"$(f_config "$config")"
	done
}

# Evaluate configuration and deduce the toplevel derivation
drv() {
	for config in "${!configs[@]}"; do
		local drv
		drv="$(f_drv "$config")"
		[[ -L "$drv" ]] && [[ -e "$drv" ]] &&
			[[ "$(nix derivation show "$(f_drv_store "$config")" | jq -r '.[].env.nixdeploySrcHash')" == "$src_hash" ]] &&
			continue

		stage "Evaluating configuration $config..."
		local base="nixosConfigurations.\"$config\""
		local tail=".config.system.build.toplevel.overrideAttrs {nixdeploySrcHash = \"$src_hash\";}"
		local func="c: (c$tail).drvPath"
		if ! config_check "$config" '.nativeBuild' && [[ "$(nixeval_raw "$base.config.nixpkgs.hostPlatform.system")" != "$build_system" ]]; then
			func="c: ((c.extendModules {modules = [{nixpkgs.buildPlatform.system = \"$build_system\";}];})$tail).drvPath"
		fi
		# TODO cover evaluation failure
		ln -sf "$(nixeval_raw "$base" --keep-derivations --apply "$func")" "$drv"
	done
}

# Build configurations locally
build() {
	local args=()
	local confs=()
	for config in "${!configs[@]}"; do
		use_remote_build "$config" && continue
		[[ -e "$(f_drv "$config")" ]] || continue
		confs+=("$config")
		args+=("$(f_drv_store "$config")")
	done
	[[ ${#confs[@]} -gt 0 ]] || return 0
	stage "Building: ${confs[*]}"
	# Build all configurations at once
	_nix build --keep-going --no-link "${nixargs[@]}" "${args[@]}" || true
	# Create links to keep latest builds from being garbage collected
	for config in "${confs[@]}"; do
		local res dest
		res="$(f_result "$config")"
		rm -f "$res"
		dest="$(_outPath "$config")"
		if [[ -e "$dest" ]]; then
			ln -sf "$dest" "$res"
		else
			warning "Build failed for $config"
			unset "configs[\"$config\"]"
		fi
	done
}

# Build configuration on the destination
remote_build() {
	for config in "${!configs[@]}"; do
		use_remote_build "$config" || continue
		[[ -e "$(f_drv "$config")" ]] || continue

		stage "Building: $config"
		local drv
		drv="$(f_drv_store "$config")"
		_copy "$config" "$drv" --derivation
		_ssht "$config" nix build --no-link "${nixargs[@]}" "'$drv'"
	done
}

copy() {
	for config in "${!configs[@]}"; do
		[[ "$(config_get "$config" '._dups.hostName')" != "$(hostname)" ]] || continue
		use_remote_build "$config" && continue

		local res
		res="$(f_result "$config")"
		if ! [[ -L "$res" ]] || ! [[ -e "$res" ]]; then
			warning "Configuration '$config' is not build."
			continue
		fi
		local store
		store="$(readlink -f "$res")"

		stage "Copy configuration $config..."
		local freespace required
		if ! freespace_raw="$(_ssh "$config" df -B 1 --output=avail /nix)"; then
			warning "Connection to $config failed."
			unset "configs[\"$config\"]"
			continue
		fi
		freespace="$(echo "$freespace_raw" | tail -1)"
		required="$(nix path-info -S "$store" | awk '{ print $2 }')"
		info "Required out of free space on $config:" \
			"$(numfmt --to=iec "$required") / $(numfmt --to=iec "$freespace")"
		if [ "$required" -ge "$freespace" ]; then
			error "There is not enough space to copy configuration: $config"
			unset "configs[\"$config\"]"
			continue
		fi

		_copy "$config" "$store"
	done
}

activate() {
	local op="$1"
	for config in "${!configs[@]}"; do
		out="$(_outPath "$config")"
		[[ -e "$out" ]] || use_remote_build "$config" || continue
		stage "${op^} configuration $config"
		echo -e '\a'
		_ssht "$config" "$out/bin/nixdeploy" "$op"
	done
}

################################################################################
# Parse options
declare -a nixargs
fast="n"
local_build="n"
verbose="n"
do_build="y"
do_copy="y"
do_activate="y"
activate_op="switch"
while getopts "erctbda:p:flvxh" opt; do
	case "$opt" in
	e)
		do_build="n"
		do_copy="n"
		do_activate="n"
		;;
	r)
		do_copy="n"
		do_activate="n"
		;;
	c)
		do_activate="n"
		;;
	t)
		activate_op="test"
		;;
	b)
		activate_op="boot"
		;;
	d)
		activate_op="dry"
		;;
	a)
		nixargs+=("$OPTARG")
		;;
	p)
		src="${OPTARG}"
		;;
	f)
		fast="y"
		;;
	l)
		local_build="y"
		;;
	v)
		verbose="y"
		;;
	x)
		set -x
		;;
	h)
		help
		exit 0
		;;
	*)
		usage
		exit 2
		;;
	esac
done
shift $((OPTIND - 1))

if ! [[ -v src ]]; then
	flake_metadata="$(nix flake metadata --json)"
	src="$(jq -r '.url' <<<"$flake_metadata" | sed 's#^git+file://##')"
fi
build_system="$(nix eval --raw --impure --expr 'builtins.currentSystem')"

# Configuration
[[ -f "$src/.nixdeploy-config.sh" ]] && ."$src/.nixdeploy-config.sh"

# Index files
f_configs="$src/.nixdeploy/nixosConfigurations.json"
f_config() { echo "$src/.nixdeploy/config-$1.json"; }
f_drv() { echo "$src/.nixdeploy/config-$1.drv"; }
f_drv_store() { echo "$(readlink -f "$(f_drv "$1")")^*"; }
f_result() { echo "$src/.nixdeploy/result-$1"; }

src_hash="$(_nix flake prefetch --json "$src" | jq -r '.hash')"

declare -A configs=()
mkdir -p "$src/.nixdeploy"
config "$@"

((${#configs[@]})) || fail "No configuration to deploy."

drv
if [[ "$do_build" == "y" ]]; then
	build
	remote_build
fi
[[ "$do_copy" == "y" ]] && copy
[[ "$do_activate" == "y" ]] && activate "$activate_op"
exit 0
