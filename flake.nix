{
  description = "Dev flake";

  # Info on development environments: https://nixos-and-flakes.thiscute.world/development/intro

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixnvim = {
      url = "github:Very-Blank/NixNvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nmux = {
      url = "github:Very-Blank/Nmux";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zigscient = {
      url = "github:llogick/zigscient";
      flake = false;
    };

    zig2nix = {
      url = "github:Cloudef/zig2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {nixpkgs, ...} @ inputs: let
    system = "x86_64-linux";
  in {
    devShells."${system}".default = let
      pkgs = import nixpkgs {inherit system;};

      fetchScript = pkgs.writeShellApplication {
        name = "fetch";
        runtimeInputs = [pkgs.binutils];
        text = let
          fetch = name: "${pkgs.lib.getExe pkgs.zig} fetch --save ${name}\n";
        in (pkgs.lib.strings.concatMapStrings fetch
          [
            "git+https://github.com/tiawl/glfw.zig.git"
            "git+https://github.com/Very-Blank/ZigMath.git"
            "git+https://github.com/Very-Blank/Ecs.git"
            "git+https://github.com/Very-Blank/cimgui.zig.git"
          ]);
      };

      zig-env = inputs.zig2nix.outputs.zig-env.${system} {};

      zigscientLock = pkgs.writeText "build.zig.zon2json-lock" ''
        {
          "known_folders-0.0.0-Fy-PJjrKAAAY9ALC7ALIxFsmKFP314HJw6v3NLSS3NDB": {
            "name": "known_folders",
            "url": "https://github.com/LamplightWorks/known-folders/archive/71f0a3d660401ee461cc42ae1f2360f4b83084d3.tar.gz",
            "hash": "sha256-eINWBl1JHa1KH1n/DUsTkpTrmLul2fjU/lGIiue2ep4="
          },
          "diffz-0.0.1-G2tlIYrNAQAQx3cuIp7EVs0xvxbv9DCPf4YuHmvubsrZ": {
            "name": "diffz",
            "url": "https://github.com/LamplightWorks/diffz/archive/aa11caef328a3f20f2493f8fd676a1dfa7819246.tar.gz",
            "hash": "sha256-DGet3uhgqAlpcG79bOpg3C47lWlC52CgcWRNpquWEYQ="
          },
          "lsp_kit-0.1.0-bi_PLwozDAApVpvVJHz80NPklig5biWlZCkyxjFbOtiD": {
            "name": "lsp_kit",
            "url": "https://github.com/LamplightWorks/lsp-kit/archive/98d6bed6e42a0866e1e2ba0867673d9f57ca6687.tar.gz",
            "hash": "sha256-B7V8ScSWTH87xPOpflDP+Ep1WlW/CX7SzbGDFRJngGg="
          },
          "extended_zccs-0.16.0-dev-zEaUNiafDgBP9Rxs7UD513yHtJITYpq5XSnb01UDYNeI": {
            "name": "extended_zccs",
            "url": "https://github.com/llogick/extended-zccs/archive/e2c8a0a65e63254e55218fd80aa7a8715fb53ce8.tar.gz",
            "hash": "sha256-CV7WVZjRqS61nXVbrNmPEM7k6ouVQpZgM3BSgGJ+TdE="
          },
          "N-V-__8AAOncKwEm1F9c5LrT7HMNmRMYX8-fAoqpc6YyTu9X": {
            "name": "tracy",
            "url": "https://github.com/wolfpld/tracy/archive/refs/tags/v0.13.1.tar.gz",
            "hash": "sha256-fu8Rlnh1VxHuigrfyGy7t7f+9co6oyKRu/IQV/FiJ08="
          }
        }
      '';

      zigscientpkgs = zig-env.package {
        name = "zigscient";
        src = inputs.zigscient;

        zigBuildZonLock = zigscientLock;
        zigBuildFlags = ["-Doptimize=ReleaseFast"];

        meta = {
          description = "Zig language server";
          mainProgram = "zigscient";
        };
      };

      # zigscientpkgs = pkgs.buildZigPackage {
      #   src = inputs.zigscient;
      # };

      tmux = inputs.nmux.mkPackage {
        system = system;

        extraModule = {...}: {
          config.nmux = {
            shell = pkgs.lib.getExe pkgs.zsh;

            extraConfig = ''
              set-hook -g session-created 'send-keys "nvim" enter ; new-window ; select-window -t 0'
            '';
          };
        };
      };
    in
      pkgs.mkShell {
        packages = [
          pkgs.zig

          fetchScript

          (
            inputs.nixnvim.mkPackage {
              system = system;
              extraModule = {...}: {
                config = {
                  vim = {
                    languages = {
                      zig = {
                        enable = true;
                        lsp.enable = true;
                        treesitter.enable = true;
                      };
                    };

                    lsp.servers.zls = {
                      filetypes = ["zig"];
                      cmd = pkgs.lib.mkForce [
                        "${zigscientpkgs}/bin/zigscient"
                      ];
                    };

                    # local.indenting = [
                    #   {
                    #     tabstop = 2;
                    #     shiftwidth = 2;
                    #     expandtab = true;
                    #     pattern = ["cpp" "c" "h"];
                    #   }
                    # ];
                  };
                };
              };
            }
          )
        ];

        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath ["${pkgs.wayland}" "${pkgs.libxkbcommon}" "${pkgs.libGL}"];

        # export LD_LIBRARY_PATH=${pkgs.wayland}/lib:$LD_LIBRARY_PATH
        shellHook = ''

          exec ${pkgs.lib.getExe' tmux "tmux"}
        '';
      };
  };
}
