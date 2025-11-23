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

    houdiniHostRoot = "/mnt/RAID/Assets/DCCs/houdini/latest";
    houdiniContainerRoot = "/opt/houdini";

    commonRuntimePkgs = pkgs: with pkgs; [
      stdenv.cc.cc.lib
      glibc
      zlib
      libGLU
      libGL
      alsa-lib
      fontconfig
      zlib
      libpng
      dbus
      nss
      nspr
      expat
      pciutils
      libxkbcommon
      libudev0-shim
      tbb
      xwayland
      qt5.qtwayland
      nettools
      bintools
      ocl-icd
      opencl-headers
      clinfo
      intel-ocl
      numactl
      zstd
      libdrm
      libxshmfence
      libxkbfile

      xorg.libICE
      xorg.libSM
      xorg.libXmu
      xorg.libXi
      xorg.libXt
      xorg.libXext
      xorg.libX11
      xorg.libXrender
      xorg.libXcursor
      xorg.libXfixes
      xorg.libXrender
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXtst
      xorg.libxcb
      xorg.libXScrnSaver
      xorg.libXrandr
      xorg.libxcb
      xorg.xcbutil
      xorg.xcbutilimage
      xorg.xcbutilrenderutil
      xorg.xcbutilcursor
      xorg.xcbutilkeysyms
      xorg.xcbutilwm

      coreutils
      bashInteractive
      findutils
      gawk
      gnused
      gnugrep
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
          export LD_LIBRARY_PATH=${pkgs.ocl-icd}/lib:$LD_LIBRARY_PATH
          export HOUDINI_USE_HFS_OCL=0
          export OPENCL_VENDOR_PATH=/tmp/opencl/vendors
          mkdir -p /tmp/opencl/vendors
          cp -L /run/opengl-driver/etc/OpenCL/vendors/*.icd /tmp/opencl/vendors/ 2>/dev/null || true
          cp -L /etc/OpenCL/vendors/*.icd /tmp/opencl/vendors/ 2>/dev/null || true
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

