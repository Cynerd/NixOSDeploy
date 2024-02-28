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

progress() {
	printf "%s\e[0K\r" "$*"
}

usage() {
	cat >&2 <<-EOF
		Usage: $0 [OPTION].. [SYSTEM]..

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
	nix "$op" --no-warn-dirty "$@"
}

nixeval() {
	local attr="$1"
	shift
	_nix eval --json "$src#$attr" "$@"
}

nixeval_raw() {
	local attr="$1"
	shift
	_nix eval --raw "$src#$attr" "$@"
}

config_check() {
	jqcheck "$2" "$(f_config "$1")"
}
config_get() {
	jq -r "$2" "$(f_config "$1")"
}
config_read() {
	local config="$1"
	local query="$2"
	shift 2
	jqread "$query" "$@" <"$(f_config "$config")"
}

__ssh() (
	local arg="$1"
	local config="$2"
	shift 2
	config_read "$config" '[.ssh.host,.hostName].[]' ssh_host hostname
	if [ "$hostname" != "$(hostname)" ]; then
		ssh $arg "$ssh_host" -- "$@"
	else
		if [ $# -gt 1 ]; then
			"$@"
		else
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
	config_check "$config" '.noCopySubstityte' || args+=("--substitute-on-destination")
	nix copy "${args[@]}" --to "ssh://$(config_get "$config" '.ssh.host')" "$@"
}

_outPath() {
	local config="$1"
	nix derivation show "$(readlink -f "$(f_drv "$config")")^*" |
		jq -r '.[].outputs.out.path'
}

################################################################################

# TODO we should lock our directory when we are indexing the configuration

index_config() {
	local config="$1"
	[[ -f "$(f_config "$config")" ]] && return 0
	info "Loading deployment configuration for $config..."
	local attr="nixosConfigurations.\"${config}\".config"
	if [[ "$(nixeval "$attr" --apply 'builtins.hasAttr "deploy"')" == "true" ]]; then
		nixeval "$attr.deploy"
	else
		echo "{}"
	fi >"$(f_config "$config")"
}

# Evaluate configuration and deduce the toplevel derivation
drv() {
	for config in "$@"; do
		local drv
		drv="$(f_drv "$config")"
		[[ -L "$drv" ]] && [[ -e "$drv" ]] && continue

		stage "Evaluating configuration $config..."
		local base="nixosConfigurations.\"$config\""
		local tail=".config.system.build.toplevel.drvPath"
		local func="c: c$tail"
		if ! config_check "$config" '.nativeBuild' && [[ "$(nixeval_raw "$base.config.nixpkgs.hostPlatform.system")" != "$build_system" ]]; then
			func="c: (c.extendModules {modules = [{nixpkgs.buildPlatform.system = \"$build_system\";}];})$tail"
		fi
		# TODO cover evaluation failure
		ln -sf "$(nixeval_raw "$base" --keep-derivations --apply "$func")" "$drv"
	done
}

# Build configurations locally
build() {
	local args=()
	local configs=()
	for config in "$@"; do
		config_check "$config" '.remoteBuild' && continue
		[[ -e "$(f_drv "$config")" ]] || continue
		configs+=("$config")
		args+=("$(readlink -f "$(f_drv "$config")")^*")
	done
	[[ ${#configs[@]} -gt 0 ]] || return 0
	stage "Building: ${configs[*]}"
	# Build all configurations at once
	nix build --keep-going --no-link "${nixargs[@]}" "${args[@]}" || true
	# Create links to keep latest builds from being garbage collected
	for config in "${configs[@]}"; do
		local res dest
		res="$(f_result "$config")"
		rm -f "$res"
		dest="$(_outPath "$config")"
		[[ -e "$dest" ]] || continue
		ln -sf "$dest" "$res"
	done
}

# Build configuration on the destination
remote_build() {
	for config in "$@"; do
		config_check "$config" '.remoteBuild' || continue
		[[ -e "$(f_drv "$config")" ]] || continue

		stage "Building: $config"
		local drv
		drv="$(readlink -f "$(f_drv "$config")")"
		_copy "$config" "$drv^*" --derivation
		_ssht "$config" nix build --no-link "${nixargs[@]}" "'$drv^*'"
	done
}

copy() {
	for config in "$@"; do
		[[ "$(config_get "$config" '.hostName')" != "$(hostname)" ]] || continue
		config_check "$config" '.remoteBuild' && continue

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
		freespace_raw="$(_ssh "$config" df -B 1 --output=avail /nix)"
		freespace="$(echo "$freespace_raw" | tail -1)"
		required="$(nix path-info -S "$store" | awk '{ print $2 }')"
		info "Required out of free space on $config:" \
			"$(numfmt --to=iec "$required") / $(numfmt --to=iec "$freespace")"
		if [ "$required" -ge "$freespace" ]; then
			error "There is not enough space to copy configuration: $config"
			continue
		fi

		_copy "$config" "$store"
	done
}

activate() {
	local op="$1"
	shift
	for config in "$@"; do
		out="$(_outPath "$config")"
		[[ -e "$out" ]] || config_check "$config" '.remoteBuild' || continue
		stage "${op^} configuration $config"
		_ssht "$config" "$out/bin/nixdeploy" "$op"
	done
}

################################################################################
flake_metadata="$(nix flake metadata --json)"

# Parse options
declare -a nixargs
src="$(jq -r '.url' <<<"$flake_metadata" | sed 's#^git+file://##')"
fast="n"
do_build="y"
do_copy="y"
do_activate="y"
activate_op="switch"
while getopts "erctbda:p:fxh" opt; do
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
	x)
		set -x
		;;
	h)
		usage
		exit 0
		;;
	*)
		usage
		exit 2
		;;
	esac
done
shift $((OPTIND - 1))

# Configuration
[[ -f "$src/.nixdeploy-config.sh" ]] && ."$src/.nixdeploy-config.sh"

build_system="$(nix eval --raw --impure --expr 'builtins.currentSystem')"

# Index configurations
f_src_hash="$src/.nixdeploy/hash"
f_src_config_hash="$src/.nixdeploy/hash-config"
f_configs="$src/.nixdeploy/nixosConfigurations.json"
f_config() { echo "$src/.nixdeploy/config-$1.json"; }
f_drv() { echo "$src/.nixdeploy/config-$1.drv"; }
f_result() { echo "$src/.nixdeploy/result-$1"; }

src_hash="$(_nix flake prefetch --json "$src" | jq -r '.hash')"

mkdir -p "$src/.nixdeploy"
if [[ "$(cat "$f_src_hash" 2>/dev/null)" != "$src_hash" ]]; then
	rm -f "$src/.nixdeploy"/config-*.drv >/dev/null || true
	echo "$src_hash" >"$f_src_hash"
fi
if ! [[ -f "$f_configs" ]] || [[ "$fast" == "n" ]] && ! cmp -s "$f_src_hash" "$f_src_config_hash"; then
	stage "Indexing your flake..."
	nixeval "nixosConfigurations" --apply "builtins.attrNames" >"$f_configs"
	rm -f "$src/.nixdeploy"/config-*.json >/dev/null || true
	echo "$src_hash" >"$f_src_config_hash"
fi

if [[ $# -eq 0 ]]; then
	readarray -d '' all_configs < <(jq --raw-output0 '.[]' <"$f_configs")
	for config in "${all_configs[@]}"; do
		index_config "$config"
		config_check "$config" '.enable and .default' &&
			set "$@" "$config"
	done
else
	for config in "$@"; do
		index_config "$config"
		config_check "$config" '.enable' ||
			fail "Config '$config' doesn't have deployment configured."
	done
fi

[[ $# -gt 0 ]] || fail "No configuration to deploy."

drv "$@"
if [[ "$do_build" == "y" ]]; then
	build "$@"
	remote_build "$@"
fi
[[ "$do_copy" == "y" ]] && copy "$@"
[[ "$do_activate" == "y" ]] && activate "$activate_op" "$@"
