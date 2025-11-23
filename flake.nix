{
  description = "OOM VFX runtime (Houdini etc.) for local + k8s farm";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
  let
    # Target system
    system = "x86_64-linux";

    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };


    # Host + container Houdini locations
    houdiniHostRoot = "/mnt/RAID/Assets/DCCs/houdini/latest";
    houdiniContainerRoot = "/opt/houdini";


    # Shared VRP-ish runtime deps for all DCCs (Houdini, Nuke, 3DE, etc.)
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


    # Shared profile logic for ALL DCCs (OpenCL / ICD handling, etc.)
    vfxProfile = pkgs: ''
      # Shared VFX runtime profile (OpenCL, ICDs, etc.)

      export LD_LIBRARY_PATH=${pkgs.ocl-icd}/lib:$LD_LIBRARY_PATH

      export OPENCL_VENDOR_PATH=/tmp/opencl/vendors
      mkdir -p /tmp/opencl/vendors

      cp -L /run/opengl-driver/etc/OpenCL/vendors/*.icd \
        /tmp/opencl/vendors/ 2>/dev/null || true

      cp -L /etc/OpenCL/vendors/*.icd \
        /tmp/opencl/vendors/ 2>/dev/null || true
    '';


    # Generic VFX FHS env (base layer) — can be reused for Nuke / 3DE / Maya
    vfxFhsEnv =
      pkgs.buildFHSEnv {
        name = "vfx-fhs";

        targetPkgs = commonRuntimePkgs;

        profile = vfxProfile pkgs;

        runScript = "bash";
      };


    # Houdini FHS env (workstation runtime)
    houdiniFhsEnv =
      pkgs.buildFHSEnv {
        name = "houdini-fhs";

        targetPkgs = commonRuntimePkgs;

        profile = (vfxProfile pkgs) + ''
          # Houdini-specific runtime

          export HFS=${houdiniHostRoot}
          export PATH="$HFS/bin:$PATH"
          export HOUDINI_PATH="$HFS/houdini:&"

          # Prefer system/OpenCL stack, not HFS OpenCL
          export HOUDINI_USE_HFS_OCL=0
        '';

        runScript = "bash";
      };


    # Simple wrapper so artists can just run `houdini`
    houdiniWrapper =
      pkgs.writeShellScriptBin "houdini" ''
        # Run Houdini inside the FHS env
        exec ${houdiniFhsEnv}/bin/houdini-fhs houdini "$@"
      '';


    # Rootfs for container images (same deps as FHS env)
    houdiniRootfs =
      pkgs.buildEnv {
        name = "houdini-runtime-rootfs";

        paths = (commonRuntimePkgs pkgs);

        pathsToLink = [
          "/bin"
          "/lib"
          "/lib64"
          "/share"
        ];
      };


    # Houdini container runtime with profile logic similar to FHS env
    houdiniRuntimeImage =
      pkgs.dockerTools.buildImage {
        name = "oom-houdini-runtime";
        tag = "latest";

        copyToRoot = [
          houdiniRootfs
        ];

        # Inject /etc/profile + /etc/profile.d scripts so login shells
        # (bash -l) get the same runtime behavior
        extraCommands = ''
          mkdir -p etc/profile.d

          # Minimal /etc/profile that loads profile.d
          cat > etc/profile << 'EOF'
for f in /etc/profile.d/*.sh; do
  if [ -r "$f" ]; then
    . "$f"
  fi
done
EOF

          # Shared VFX profile (OpenCL, ICDs, etc.)
          cat > etc/profile.d/vfx.sh << 'EOF'
${vfxProfile pkgs}
EOF

          # Houdini-specific profile (container path)
          cat > etc/profile.d/houdini.sh << 'EOF'
export HFS=${houdiniContainerRoot}
export PATH="$HFS/bin:/bin:$PATH"
export HOUDINI_PATH="$HFS/houdini:&"
export HOUDINI_USE_HFS_OCL=0
EOF
        '';

        config = {
          WorkingDir = "/workspace";

          # These are mostly redundant with the profile but nice as defaults
          Env = [
            "HFS=${houdiniContainerRoot}"
            "PATH=${houdiniContainerRoot}/bin:/bin"
            "HOUDINI_PATH=${houdiniContainerRoot}/houdini:&"
            "HOUDINI_USE_HFS_OCL=0"
            "SESI_LMHOST=your-houdini-license-server"
            "HOUDINI_LICENSE_METHOD=sesinetd"
            "OOM_ROOT=/srv/oom"
            "PYTHONPATH=/srv/oom/python"
          ];

          # Login shell so /etc/profile runs and picks up vfx/houdini profiles.
          # In k8s, your pod spec's command/args will be appended to this.
          Entrypoint = [ "/bin/bash" "-lc" ];
        };
      };

  in
  {
    # Packages you can import from your system flake
    packages.${system} = {
      # Base VFX FHS env (for future Nuke / 3DE / Maya)
      vfx-fhs = vfxFhsEnv;

      # Houdini workstation env + convenient wrapper
      houdini-fhs = houdiniFhsEnv;
      houdini     = houdiniWrapper;

      # Container image for farm runtime
      houdini-runtime-image = houdiniRuntimeImage;
    };


    # Dev shell for you (testing / debugging)
    devShells.${system} = {
      houdini-dev =
        pkgs.mkShell {
          name = "houdini-dev-shell";

          buildInputs =
            (commonRuntimePkgs pkgs)
            ++ [
              pkgs.git
              pkgs.nixfmt-rfc-style
              houdiniWrapper
            ];

          shellHook = ''
            echo "Houdini dev shell."
            echo "  - Run 'houdini' to launch Houdini inside the FHS env."
            echo "  - Or run '${houdiniFhsEnv}/bin/houdini-fhs' directly."
          '';
        };
    };
  };
}

