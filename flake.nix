{
  description = "Nix Installer Generator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      perSystem = { pkgs, ... }: {
        
        packages.default = pkgs.stdenvNoCC.mkDerivation {
          name = "install-nix-script";
          src = ./.;

          nativeBuildInputs = [ pkgs.shellcheck ];

          buildPhase = ''
            echo "Verifying Templater Script Syntax..."
            shellcheck templater.sh

            echo "Creating Installer..."
            awk '
              BEGIN {
                while ((getline < "templater.sh") > 0) {
                  templater = templater $0 "\n"
                }
                close("templater.sh")
              }
              /<<.*__OUTREACH_CONTROL_SCRIPT__/ {
                print
                printf "%s", templater
                print "__OUTREACH_CONTROL_SCRIPT__"
                getline
                next
              }
              { print }
            ' ./nix-installer.sh > installer.sh
            
            echo "Verifying Installer Script Syntax..."
            shellcheck installer.sh
          '';

          installPhase = ''
            mkdir -p $out
            cp installer.sh $out/installer.sh
            chmod +x $out/installer.sh
          '';
        };
      };
    };
}