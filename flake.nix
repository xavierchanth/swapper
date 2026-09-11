{
  description = "XMT — prebuilt personal macOS utilities";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    xmt-binary = {
      # The consumer's flake.lock pins the unpacked archive's narHash.
      # Nix verifies subsequent fetches against that hash automatically.
      url = "https://github.com/xavierchanth/xmt/releases/download/v1.0.0/XMT-macos.tar.gz";
      flake = false;
    };
  };

  outputs = { nixpkgs, xmt-binary, ... }: let
    systems = [ "aarch64-darwin" "x86_64-darwin" ];
  in {
    packages = nixpkgs.lib.genAttrs systems (system: let
      pkgs = import nixpkgs { inherit system; };
      xmt = pkgs.stdenvNoCC.mkDerivation {
        pname = "xmt";
        version = "1.0.0";
        src = xmt-binary;
        dontBuild = true;
        dontFixup = true; # Preserve the bundle's ad-hoc code signature.
        installPhase = ''
          runHook preInstall
          test -x XMT.app/Contents/MacOS/XMT
          mkdir -p "$out/Applications"
          cp -R XMT.app "$out/Applications/"
          runHook postInstall
        '';
        meta = {
          description = "Caps Override, Window Mover, and menu-bar hiding";
          homepage = "https://github.com/xavierchanth/xmt";
          license = pkgs.lib.licenses.bsd3;
          platforms = systems;
        };
      };
    in { inherit xmt; default = xmt; });
  };
}
