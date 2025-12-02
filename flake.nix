{
  description = "OOM VFX runtime (Houdini etc.) for local + k8s farm";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # core pipeline code
    oom-src = {
      flake = false;
      url = "github:sneakyfoot/OOM";  # or "path:/mnt/RAID/git/oom"
    };
  };

  outputs = { self, nixpkgs, oom-src, ... }:
  let
    system = "x86_64-linux";

    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      config.cudaSupport = true;
    };
    oomSrc = oom-src;

    common = import ./nix/common.nix { inherit pkgs; };
    oomPythonEnv = common.oomPythonEnv;

    houdini = import ./nix/houdini.nix {
      inherit pkgs;
      commonRuntimePkgs = common.commonRuntimePkgs;
      vfxProfile        = common.vfxProfile;
    };

    oomCli = import ./nix/cli-oom.nix {
      inherit pkgs oomSrc;
      pythonEnv = oomPythonEnv;
    };

  in
  {
    packages.${system} = {
      # VFX / Houdini runtimes
      vfx-fhs              = houdini.vfxFhsEnv;
      houdini-fhs          = houdini.houdiniFhsEnv;
      houdini              = houdini.houdiniWrapper;
      mplay                 = houdini.mplayWrapper;
      houdini-runtime-image = houdini.houdiniRuntimeImage;
      nuke                  = houdini.nukeWrapper;

      # OOM CLI wrappers
      oom      = oomCli.oom;

      # Handy bundle
      default = pkgs.symlinkJoin {
        name  = "oom-tools";
        paths = [
          houdini.houdiniWrapper
          oomCli.oom
          oomCli."oom-shot"
        ];
      };
    };

    nixosModules.oom-cli = { config, pkgs, lib, ... }: {
      environment.systemPackages = [
        self.packages.${config.nixpkgs.system}.oom
        self.packages.${config.nixpkgs.system}."oom-shot"
      ];
    };
  };
}
