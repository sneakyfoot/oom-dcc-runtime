{ pkgs, oomSrc, pythonEnv ? pkgs.python311 }:

let
  # Plain paths into your repo
  oomRepo = "${oomSrc}";
  oomCore = "${oomRepo}/oom-core";

  # Generic helper: wrap an existing script under oom/bin/*
  mkBinWrapper = { name, script ? name }: pkgs.writeShellApplication {
    inherit name;

    runtimeInputs = [
      pkgs.uv
      pythonEnv
      pkgs.bash
    ];

    text = ''
      #!/usr/bin/env bash

      # Core repo locations
      export OOM="${oomRepo}"
      export OOM_CORE_PATH="${oomCore}"

      # Prefer caller-provided OOM_VENV; otherwise use the Nix-built runtime Python
      OOM_VENV="''${OOM_VENV:-${pythonEnv}/bin/python}"
      export UV_PYTHON="$OOM_VENV"

      # 1) Prefer legacy bash script if it exists
      if [ -x "${oomRepo}/bin/${script}" ]; then
        exec ${pkgs.bash}/bin/bash "${oomRepo}/bin/${script}" "$@"
      fi

      # 2) Fallback: Python entrypoint via uv
      if [ -f "$OOM_CORE_PATH/${script}.py" ]; then
        exec uv run "$OOM_CORE_PATH/${script}.py" "$@"
      fi

      echo "[oom] no entrypoint found (expected ${oomRepo}/bin/${script} or ${oomCore}/${script}.py)" >&2
      exit 1
    '';
  };

  oom = mkBinWrapper {
    name   = "oom";
    script = "oom";
  };

in {
  inherit oom;
}
