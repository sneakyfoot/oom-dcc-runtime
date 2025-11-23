{ pkgs }:

let
  cuda = pkgs.cudaPackages_12_8;

  # Python environment shared by CLI/Houdini/farm. Keep minimal but include ShotGrid + k8s.
  oomPythonEnv = pkgs.python311.withPackages (ps: with ps; [
    kubernetes
    rich
    pydantic
  ]);
in
{
  inherit oomPythonEnv;

  # Note: this is a FUNCTION: pkgs: [ ... ]
  commonRuntimePkgs = (pkgs': with pkgs'; [
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

    cuda.libcublas
    cuda.cudnn
    cuda.libcufft
    cuda.libcurand
    cuda.cuda_nvrtc

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
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXtst
    xorg.libxcb
    xorg.libXScrnSaver
    xorg.libXrandr
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

    # Shared Python env
    oomPythonEnv
  ]);

  vfxProfile = ''
    export LD_LIBRARY_PATH=${pkgs.ocl-icd}/lib:$LD_LIBRARY_PATH
    export PYTHONPATH=${oomPythonEnv}/${oomPythonEnv.sitePackages}:$PYTHONPATH

    export OPENCL_VENDOR_PATH=/tmp/opencl/vendors
    mkdir -p /tmp/opencl/vendors

    cp -L /run/opengl-driver/etc/OpenCL/vendors/*.icd \
      /tmp/opencl/vendors/ 2>/dev/null || true

    cp -L /etc/OpenCL/vendors/*.icd \
      /tmp/opencl/vendors/ 2>/dev/null || true
  '';
}
