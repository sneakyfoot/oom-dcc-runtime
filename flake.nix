{
  description = "OOM DCC runtime (Houdini etc.) for local + k8s farm";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";

    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    houdiniHostRoot = "/mnt/RAID/Assets/DCCs/houdini/hfs21.0.477";
    houdiniContainerRoot = "/opt/houdini";

    commonRuntimePkgs = pkgs: with pkgs; [
      stdenv.cc.cc.lib
      glibc
      zlib

      xorg.libX11
      xorg.libXext
      xorg.libXrender
      xorg.libXrandr
      xorg.libXi

      coreutils
      bashInteractive
      findutils
      gawk
      sed
      grep
      which
      procps

      python311
    ];

    houdiniFhsEnv =
      pkgs.buildFHSEnv {
        name = "houdini-fhs";

        targetPkgs = commonRuntimePkgs;

        profile = ''
          export HFS=${houdiniHostRoot}
          export PATH="$HFS/bin:$PATH"
          export HOUDINI_PATH=${houdiniHostRoot}/houdini:&
        '';

        runScript = "bash";
      };

    houdiniRootfs =
      pkgs.buildEnv {
        name = "houdini-runtime-rootfs";

        paths = (commonRuntimePkgs pkgs);

        pathsToLink = [ "/bin" "/lib" "/lib64" "/share" ];
      };

    houdiniRuntimeImage =
      pkgs.dockerTools.buildImage {
        name = "oom-houdini-runtime";
        tag = "latest";

        copyToRoot = houdiniRootfs;

        config = {
          WorkingDir = "/workspace";

          Env = [
            "HFS=${houdiniContainerRoot}"
            "PATH=${houdiniContainerRoot}/bin:/bin"
            "HOUDINI_PATH=${houdiniContainerRoot}/houdini:&"
            "SESI_LMHOST=your-houdini-license-server"
            "HOUDINI_LICENSE_METHOD=sesinetd"
            "OOM_ROOT=/srv/oom"
            "PYTHONPATH=/srv/oom/python"
          ];

          Entrypoint = [ "/bin/bash" ];
        };
      };
  in
  {
    packages.${system} = {
      houdini-fhs = houdiniFhsEnv;
      houdini-runtime-image = houdiniRuntimeImage;
    };

    devShells.${system} = {
      houdini-dev = pkgs.mkShell {
        name = "houdini-dev-shell";

        buildInputs =
          (commonRuntimePkgs pkgs)
          ++ [
            pkgs.git
            pkgs.nixfmt-rfc-style
          ];

        shellHook = ''
          echo "Houdini dev shell. To enter FHS env, run:"
          echo "  houdini-fhs"

          houdini-fhs() {
            exec ${houdiniFhsEnv}/bin/houdini-fhs "$@"
          }
        '';
      };
    };
  };
}

