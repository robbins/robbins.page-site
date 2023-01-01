{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };
  
  outputs = { self, nixpkgs }: {
    packages.x86_64-linux.default = with import nixpkgs { system = "x86_64-linux"; };
    stdenv.mkDerivation {
      pname = "robbins-cc-zola";
      src = ./robbins-cc-src;
      buildInputs = [ zola ];
    };
  };
}
