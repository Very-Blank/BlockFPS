{
  description = "Hip flake";

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
          fetch = name: "${pkgs.lib.getExe pkgs.zig} fetch --save ${name}";
        in "${pkgs.lib.strings.concatStringsSep "\n" [
          (fetch "git+https://github.com/tiawl/glfw.zig.git")
          (fetch "git+https://github.com/Very-Blank/ZigMath.git")
        ]}";
      };

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

        LD_LIBRARY_PATH =
          pkgs.lib.makeLibraryPath [];

        shellHook = ''
          exec ${pkgs.lib.getExe' tmux "tmux"}
        '';
      };
  };
}
