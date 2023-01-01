{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    hermit-zola = { url = "github:VersBinarii/hermit_zola"; flake = false; };
  };
  
  outputs = { self, nixpkgs, hermit-zola}:
    let
      themeName = "hermit_zola";
      pkgs = import nixpkgs { system = "x86_64-linux"; };
    in
    {
      packages.x86_64-linux.default = with pkgs; stdenv.mkDerivation {
        name = "robbins-cc-zola";
        src = ./.;
        buildInputs = with pkgs; [ zola ];
        configurePhase = ''
          mkdir -p "themes/${themeName}"
          cp -r ${hermit-zola}/* "themes/${themeName}"
        '';
        buildPhase = ''
          zola build
        '';
        installPhase = ''
          cp -r public $out
        '';
      };
      devShells."x86_64-linux".default = pkgs.mkShell {
          packages = [ pkgs.zola ];
          shellHook = ''
            mkdir -p themes
            ln -sn "${hermit-zola}" "themes/${themeName}"
          '';
        };
    };
}
