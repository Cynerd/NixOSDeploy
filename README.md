# NixDeploy (NixOS deployment tool)

This is yet another deployment tool for NixOS. This tries to be as easy to use
as possible while not introducing new concepts to NixOS.

This deployment tool looks to the future and thus it is mostly usable only if
you use Flakes!

The concept is that Nix Flakes allow you to manage multiple NixOS profiles in a
single repository. The only thing that is missing at that point is the
deployment solution, that is definition where and how to build and copy and
apply new NixOS version. This tries to deal with already existing systems where
you have SSH access and configured way to get root access. The NixOS module in
this repository specifies configuration for nixdeploy script.

## Usage

NixDeploy consist of NixOS configuration module and `nixdeploy` tool itself.

The configuration can be bootstrapped with:

```console
nix flake init -t gitlab:cynerd/nixdeploy
```

This will copy to your current work directory template from this repository that
is prepared to be used with NixDeploy. If you already have existing
configurations, then you can just add this repository as flake input and
`nixosModules.default` to modules your configurations import.

The important step is to activate deployment in your configuration. The simplest
is to just include option `deploy.enable = true;`.

The next step is to actually run `nixdeploy`. You have few options how to run
it, you can either run it directly from this flake with `nix run
gitlab:cynerd/nixdeploy` or you can install it as package to your system, but
the preferred way is to make it a default package of you flake:

```nix
packages.x86_64-linux.default = nixdeploy.packages.x86_64-linux.default;
```

Now you can just do `nix run .` to invoke NixDeploy. The advantage of this is
that consistency between NixOS module and the tool is ensured.

Now you can read the help of the `nixdeploy` with `nix run . -- -h`.

All available configuration can be seen in [NixOS module file](./nixos.nix) in
this repository.
