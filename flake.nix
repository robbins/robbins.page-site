{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    apollo-zola = { url = "github:robbins/apollo-custom"; flake = false; };
    #apollo-zola = { url = "git+file:///home/nate/src/github.com/robbins/apollo-custom"; flake = false; };
  };
  
  outputs = { self, nixpkgs, apollo-zola}:
    let
      themeName = "apollo";
      pkgs = import nixpkgs { system = "x86_64-linux"; };
    in
    {
      packages.x86_64-linux.default = with pkgs; stdenv.mkDerivation {
        name = "robbins-cc-zola";
        src = ./.;
        buildInputs = with pkgs; [ zola ];
        configurePhase = ''
          mkdir -p "themes/${themeName}"
          cp -r ${apollo-zola}/* "themes/${themeName}"
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
            ln -snf "${apollo-zola}" "themes/${themeName}"
          '';
        };
    };
}
