{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    hermit-zola = { url = "github:VersBinarii/hermit_zola"; flake = false; };
  };
  
  outputs = { self, nixpkgs, hermit-zola}:
    let
      themeName = "hermit";
    in
    {
      packages.x86_64-linux.default = with import nixpkgs { system = "x86_64-linux"; };
      stdenv.mkDerivation {
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
    };
}
