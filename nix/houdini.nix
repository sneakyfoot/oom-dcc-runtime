{ pkgs
, commonRuntimePkgs
, vfxProfile
, houdiniHostRoot ? "/mnt/RAID/Assets/DCCs/houdini/latest"
, nukeHostRoot ? "/mnt/RAID/Assets/DCCs/nuke/latest"
, houdiniContainerRoot ? "/opt/houdini"
}:

let
  houdiniDeps = commonRuntimePkgs pkgs;

  mkHoudiniProfile = { hfsRoot, packageDir ? null }: ''
    ${vfxProfile}

    export HFS=${hfsRoot}
    export PATH="$HFS/bin:$PATH"
    export HOUDINI_PATH="$HFS/houdini:&"
    export HOUDINI_USE_HFS_OCL=0
    export HHP="$HFS/houdini/python3.11libs"
  '' + pkgs.lib.optionalString (packageDir != null) ''
    export HOUDINI_PACKAGE_DIR=${packageDir}
  '';

  houdiniHostProfile = mkHoudiniProfile {
    hfsRoot    = houdiniHostRoot;
    packageDir = "/opt/oom-repo/OOM/dcc/oom-houdini/packages";
  };

  houdiniContainerProfile = mkHoudiniProfile {
    hfsRoot    = houdiniContainerRoot;
    packageDir = "/opt/oom-repo/OOM/dcc/oom-houdini/packages";
  };

  houdiniEnv =
    pkgs.writeShellScriptBin "houdini-env" ''
      ${houdiniContainerProfile}

      exec "$HFS/bin/houdini" "$@"
    '';

  # Simple launcher: run the provided command as-is, otherwise drop into bash.
  fhsLauncher = pkgs.writeShellScript "houdini-fhs-launch" ''
    if [ "$#" -gt 0 ]; then
      exec "$@"
    else
      exec ${pkgs.bashInteractive}/bin/bash
    fi
  '';

  vfxFhsEnv =
    pkgs.buildFHSEnv {
      name = "vfx-fhs";

      targetPkgs = commonRuntimePkgs;

      profile = vfxProfile;

      runScript = fhsLauncher;
    };


  houdiniFhsEnv =
    pkgs.buildFHSEnv {
      name = "houdini-fhs";

      targetPkgs = commonRuntimePkgs;

      profile = houdiniHostProfile;

      runScript = fhsLauncher;
    };


  houdiniWrapper =
    pkgs.writeShellScriptBin "houdini" ''
      exec ${houdiniFhsEnv}/bin/houdini-fhs ${houdiniHostRoot}/bin/houdini "$@"
    '';

  nukeWrapper =
    pkgs.writeShellScriptBin "nuke" ''
      exec ${houdiniFhsEnv}/bin/houdini-fhs ${nukeHostRoot}/Nuke16.0 "$@"
    '';

  houdiniRootfs =
    pkgs.buildEnv {
      name = "houdini-runtime-rootfs";

      paths = houdiniDeps ++ [ houdiniEnv ];

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

      config = {
        WorkingDir = "/workspace";

        Cmd = [ "/bin/houdini-env" ];
      };
    };

in
{
  inherit
    vfxFhsEnv
    houdiniFhsEnv
    houdiniWrapper
    houdiniRootfs
    houdiniRuntimeImage
    nukeWrapper;
}
