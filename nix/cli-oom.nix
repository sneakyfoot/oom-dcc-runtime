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

      emit_env=0
      if [ "''${1:-}" = "--print-env" ]; then
        emit_env=1
        shift
      fi

      # 1) Prefer legacy bash script if it exists
      if [ -x "${oomRepo}/bin/${script}" ]; then
        if [ $emit_env -eq 1 ]; then
          rm -f /tmp/oom.env
          ${pkgs.bash}/bin/bash "${oomRepo}/bin/${script}" "$@"
          if [ -s /tmp/oom.env ]; then
            cat /tmp/oom.env
            exit 0
          else
            echo "[oom] upstream script did not populate /tmp/oom.env" >&2
            exit 1
          fi
        else
          exec ${pkgs.bash}/bin/bash "${oomRepo}/bin/${script}" "$@"
        fi
      fi

      # 2) Fallback: Python entrypoint via uv
      if [ -f "$OOM_CORE_PATH/${script}.py" ]; then
        if [ $emit_env -eq 1 ]; then
          rm -f /tmp/oom.env
          uv run "$OOM_CORE_PATH/${script}.py" "$@"
          if [ -s /tmp/oom.env ]; then
            cat /tmp/oom.env
            exit 0
          else
            echo "[oom] Python entrypoint did not populate /tmp/oom.env" >&2
            exit 1
          fi
        else
          exec uv run "$OOM_CORE_PATH/${script}.py" "$@"
        fi
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
