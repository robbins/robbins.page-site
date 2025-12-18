{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    serene-zola = { url = "github:isunjn/serene"; flake = false; };
  };
  
  outputs = { self, nixpkgs, serene-zola}:
    let
      themeName = "serene";
      pkgs = import nixpkgs { system = "x86_64-linux"; };
    in
    {
      packages.x86_64-linux.default = with pkgs; stdenv.mkDerivation {
        name = "robbins-cc-zola";
        src = ./.;
        buildInputs = with pkgs; [ zola ];
        configurePhase = ''
          mkdir -p "themes/${themeName}"
          cp -r ${serene-zola}/* "themes/${themeName}"
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
            ln -snf "${serene-zola}" "themes/${themeName}"
          '';
        };
    };
}
