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
