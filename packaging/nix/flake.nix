{
  description = "MCsQuick: interactive Minecraft server setup";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }:
    let
      forAll = f: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ] (s: f nixpkgs.legacyPackages.${s});
    in {
      packages = forAll (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "mcsquick"; version = "0.2.0";
          src = ../..;
          nativeBuildInputs = [ pkgs.makeWrapper ];
          installPhase = ''
            mkdir -p $out/share/mcsquick $out/bin
            cp mc-setup.sh mc-customize.sh README.md $out/share/mcsquick/
            makeWrapper ${pkgs.bash}/bin/bash $out/bin/mcsquick \
              --add-flags $out/share/mcsquick/mc-setup.sh \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.curl pkgs.jq pkgs.gnutar pkgs.tmux pkgs.unzip ]}
          '';
        };
      });
    };
}
