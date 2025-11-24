{ pkgs
, commonRuntimePkgs
, vfxProfile
, houdiniHostRoot ? "/mnt/RAID/Assets/DCCs/houdini/latest"
, houdiniContainerRoot ? "/opt/houdini"
}:

let
  vfxFhsEnv =
    pkgs.buildFHSEnv {
      name = "vfx-fhs";

      targetPkgs = commonRuntimePkgs;

      profile = vfxProfile;

      runScript = "bash";
    };


  houdiniFhsEnv =
    pkgs.buildFHSEnv {
      name = "houdini-fhs";

      targetPkgs = commonRuntimePkgs;

      profile = vfxProfile + ''
        # Houdini-specific runtime

        export HFS=${houdiniHostRoot}
        export PATH="$HFS/bin:$PATH"
        export HOUDINI_PATH="$HFS/houdini:&"
        export HOUDINI_USE_HFS_OCL=0
        export HHP="$HFS/houdini/python3.11libs"
        export HOUDINI_PACKAGE_DIR=/opt/oom-repo/OOM/dcc/oom-houdini/packages
      '';

      runScript = "bash";
    };


  houdiniWrapper =
    pkgs.writeShellScriptBin "houdini" ''
      exec ${houdiniFhsEnv}/bin/houdini-fhs ${houdiniHostRoot}/bin/houdini "$@"
    '';


  houdiniRootfs =
    pkgs.buildEnv {
      name = "houdini-runtime-rootfs";

      paths = commonRuntimePkgs;

      pathsToLink = [
        "/bin"
        "/lib"
        "/lib64"
        "/share"
      ];
    };


  houdiniRuntimeImage =
    pkgs.dockerTools.buildImage {
      name = "oom-houdini-runtime";
      tag  = "latest";

      copyToRoot = [ houdiniRootfs ];

      extraCommands = ''
        mkdir -p etc/profile.d

        cat > etc/profile << 'EOF'
for f in /etc/profile.d/*.sh; do
  if [ -r "$f" ]; then
    . "$f"
  fi
done
EOF

        cat > etc/profile.d/vfx.sh << 'EOF'
${vfxProfile}
EOF

        cat > etc/profile.d/houdini.sh << 'EOF'
export HFS=${houdiniContainerRoot}
export PATH="$HFS/bin:/bin:$PATH"
export HOUDINI_PATH="$HFS/houdini:&"
export HOUDINI_USE_HFS_OCL=0
EOF
      '';

      config = {
        WorkingDir = "/workspace";

        Env = [
          "HFS=${houdiniContainerRoot}"
          "PATH=${houdiniContainerRoot}/bin:/bin"
          "HOUDINI_PATH=${houdiniContainerRoot}/houdini:&"
          "HOUDINI_USE_HFS_OCL=0"
          "SESI_LMHOST=your-houdini-license-server"
          "HOUDINI_LICENSE_METHOD=sesinetd"
        ];

        Entrypoint = [ "/bin/bash" "-lc" ];
      };
    };

in
{
  inherit
    vfxFhsEnv
    houdiniFhsEnv
    houdiniWrapper
    houdiniRootfs
    houdiniRuntimeImage;
}

