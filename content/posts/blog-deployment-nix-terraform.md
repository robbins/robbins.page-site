+++
title = "Deploying this blog with Nix, Terraform, and GitHub Actions"
date = "2024-08-27"

[taxonomies]
tags=["nix", "linux", "terraform"]
+++

# Architecture & Workflow
{{ note(header="Disclaimer", body="This website could easily just be a GitHub pages with orders of magnitude less complexity. But that's not as fun.") }}
This blog is hosted on a NixOS Google Cloud VM running Nginx, with Cloudflare for caching & dynamic DNS. Before I get into the specifics of the setup, I'd like to demonstrate the workflow:

To iterate and test changes locally:
1. Run `nix develop --command zsh -c "zola serve"` and visit http://127.0.0.1:1111

To deploy them:
1. Run `git commit -m "New post" && git push`

This site is split into 2 GitHub repos - [robbins.page-site](https://github.com/robbins/robbins.page-site/) and [robbins.page-infra](https://github.com/robbins/robbins.page-infra/). Let's start
with the site repo.

# robbins.page-site
I use the [Zola](https://www.getzola.org/) static site generator to generate this website from Markdown documents. This repo holds your standard Zola website files.
It also contains a `flake.nix`:
```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    apollo-zola = { url = "github:robbins/apollo-custom"; flake = false; };
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
```

I'm going to assume some familiarity with Nix, but I'll still explain what's going on here. The `inputs` attribute essentially defines dependencies for this flake:
- nixpkgs, the Nix package repository
- apollo-zola, my fork of the Apollo Zola theme

Next, it defines the outputs attribute, which are the things that this flake provides, of which there are 2:
`packages.x86_64-linux.default` defines a Nix derivation (read: package) that can be built from this flake. It takes the current directory (the website source code) as source files, requires `zola` during the build process,
and then essentially runs the commands in the `configurePhase`, `buildPhase`, and `installPhase` one after the other.

The configurePhase creates a `themes/apollo` directory and copies the contents of the apollo-zola input to that directory.
The Git repository was cloned into the Nix store, so this step is essentially equivalent to `git submodule add https://github.com/not-matthias/apollo themes/apollo`.

Next, we run `zola build` which creates the website, and finally we copy the built website into the `$out` directory, which lives in the Nix store.

We can run `nix build` to see the result of this derivation:
```shell
nix build
$ ls -l result
lrwxrwxrwx 1 59 Aug 26 18:14 result -> /nix/store/vjc1a2p9a0kdw41a9a3ahdhrmmzv6nf4-robbins-cc-zola
$ tree result
...
index.html
├── js
│   ├── main.js
├── main.css
├── posts
│   ├── android-cuttlefish-kernel-kleaf
│   │   └── index.html
│   ├── index.html
│   └── page
│       └── 1
│           └── index.html
├── projects
│   ├── index.html
│   └── project-1
│       └── index.html
...
```

Secondly, we define `devShells.x86_64.default`, which is a local development shell with `zola` on the path, and the contents of the `apollo-zola` repo symlinked from the Nix store into the current directory.
This is required for `zola serve` to be able to render the website with my chosen template. That's how we're able to test changes locally in step 1 from above.

# robbins.page-infra
This repository contains all the code needed to deploy and manage the NixOS VM on Google Cloud.
```shell
> , tree
.
├── authenticated_origin_pull_ca.pem
├── flake.lock
├── flake.nix
├── image_nixos_custom.nix
├── main.tf
├── nixos_image.tf
├── provider.tf
├── README.md
├── robbins-page-webserver-configuration.nix
├── secrets
│   ├── cloudflare-api-token.age
│   └── secrets.nix
├── variables.tf
└── web_server.tf
```

The entrypoint here is again a flake.nix:
```nix
{
  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    website-src = {
      url = "github:robbins/robbins.page-site";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { self, nixpkgs-unstable, ... }@inputs:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs-unstable { inherit system; };
  in
  {
    devShells."${system}".default = pkgs.mkShell {
      buildInputs = with pkgs; [
        terraform
        inputs.agenix.defaultPackage."${system}"
      ];
    };
    nixosConfigurations = {
      robbins-page-webserver = nixpkgs-unstable.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [ ./robbins-page-webserver-configuration.nix inputs.agenix.nixosModule ];
      };
    };
  };
}
```

We define some inputs - nixpkgs, the repo of our website's source code, and agenix, which is for runtime secret deployment (which I won't cover here).
For outputs, we again have another devShell, giving us temporary access to `terraform` and `age`, as well as a nixosConfiguration.

The nixosConfiguration is what builds and configures the entire NixOS system. Taking a look at the configuration file (some lines ommited for clarity):
```nix
{ config, lib, pkgs, inputs, ... }: {
  imports = [ "${inputs.nixpkgs-unstable}/nixos/modules/virtualisation/google-compute-image.nix" ];

  age.secrets.cloudflare-api-token.file = ./secrets/cloudflare-api-token.age;

  services.openssh.hostKeys = [
    {
      path = "/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];

  services.nginx = {
    enable = true;
    virtualHosts."robbins.page" = {
      root = "${inputs.website-src.packages.x86_64-linux.default}";
      forceSSL = true;
      sslCertificate = "/var/keys/robbins.page.pem";
      sslCertificateKey = "/var/keys/robbins.page.key";
      extraConfig = ''
        ssl_client_certificate /etc/ssh/authenticated_origin_pull_ca.pem;
        ssl_verify_client on;
      '';
    };
  };

  environment.etc."ssh/authenticated_origin_pull_ca.pem".text = builtins.readFile ./authenticated_origin_pull_ca.pem;
  users.users.nginx.extraGroups = [ "keys" ];

  services.cloudflare-dyndns = {
    enable = true;
    domains = [ "robbins.page" "www.robbins.page" ];
    apiTokenFile = config.age.secrets.cloudflare-api-token.path;
  };
}
```

you can see that we declare some secrets, an SSH host key, Cloudflare dynamic DNS, and the Nginx webserver.

The root of the "robbins.page" virtual host, however, isn't a typical path to "/var/www/..." but a path to the Nix store - in fact, it's the contents of the previously-built derivation defined in the site repository.

# Terraform-NixOS
The key to this project is the [terraform-nixos](https://github.com/nix-community/terraform-nixos) repository, which is a collection of Terraform modules used to deploy NixOS on Google Cloud.
Specifically, this module takes care of rebuilding the system, creating the new image, and deploying it onto the host. It has some bugs and I had to fork it to workaround some issues, but I don't
think I'll migrate to what is essentially [it's successor](https://github.com/Gabriella439/terraform-nixos-ng) until this one actually stops working.

```hcl
# web_server.tf
module "deploy_nixos" {
  source = "git::https://github.com/robbins/terraform-nixos.git//deploy_nixos?ref=8f00bdaf514c144e2a75b3e4e2ea536da8c813db"
  flake = true
  nixos_config = "robbins-page-webserver"
  target_host = google_compute_instance.robbins-page-webserver.network_interface[0].access_config[0].nat_ip
  target_user = "nejrobbins_gmail_com"
  build_on_target = false
  ssh_private_key = fileexists(var.INSTANCE_SSH_KEY) == true ? file(var.INSTANCE_SSH_KEY) : var.INSTANCE_SSH_KEY
  ssh_agent = false
  keys = {
    "robbins.page.pem" = fileexists(var.ROBBINS_PAGE_PEM) == true ? file(var.ROBBINS_PAGE_PEM) : var.ROBBINS_PAGE_PEM
    "robbins.page.key" = fileexists(var.ROBBINS_PAGE_KEY) == true ? file(var.ROBBINS_PAGE_KEY) : var.ROBBINS_PAGE_KEY
  }
}

# nixos_image.tf
# create a random ID for the bucket
resource "random_id" "bucket" {
  byte_length = 8
}

# create a bucket to upload the image into
resource "google_storage_bucket" "nixos-images" {
  name     = "nixos-images-${random_id.bucket.hex}"
  location = "US"
}

# create a custom nixos base image 
module "nixos_image_custom" {
  source      = "github.com/tweag/terraform-nixos//google_image_nixos_custom"
  bucket_name = google_storage_bucket.nixos-images.name
  nixos_config = "${path.module}/image_nixos_custom.nix"
}
```

The rest of the Terraform configuration is fairly straightforward:
```hcl
resource "google_compute_instance" "robbins-page-webserver" {
  name = "robbins-page-webserver"
  machine_type = var.machine_type
  zone = var.zone

  boot_disk {
    initialize_params {
      image = module.nixos_image_custom.self_link
      size = 20
    }
  }

  tags = [ "http-server", "https-server" ]

  network_interface {
    network = var.network_name
    access_config {
      network_tier = "STANDARD"
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
    enable-oslogin-2fa = "FALSE"
  }

  allow_stopping_for_update = true
}

resource "google_compute_firewall" "firewall_rules" {
  project = var.project
  name = "allow-all-http-https"
  network = var.network_name
  description = "Allows HTTP & HTTPS traffic"

  allow {
    protocol = "tcp"
    ports = [ "80", "443" ]
  }
  source_ranges = [ "0.0.0.0/0"]
}
```

# GitHub Actions & Webhooks
But how do we push changes to the site repository and have the infra repository respond by updating the Terraform configuration? Enter GitHub webhooks.

In the site repository, I have a GitHub action that triggers on every new push and sends an API request to GitHub that triggers a repository dispatch event (some lines omitted for clarity):
```yaml
on:
  # Triggers the workflow on push or pull request events but only for the "main" branch
  push:
    branches: [ "main" ]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      # Checks-out your repository under $GITHUB_WORKSPACE, so your job can access it
      - uses: actions/checkout@v3

      # Runs a single command using the runners shell
      - name: Tell web host VM to update
        run: |
          curl -X POST https://api.github.com/repos/robbins/robbins.page-infra/dispatches \
          -H 'Accept: application/vnd.github.everest-preview+json' \
          -u ${{ secrets.ACCESS_TOKEN }} \
          --data '{"event_type": "site_updated"}'
```

In the infra repository, we have a Github action that responds to this event (some lines ommited for clarity):
```yaml
on:
  # Triggers the workflow on repository_dispatch, push or pull request events
  repository_dispatch:
  push:

env:
 TF_VAR_ACCOUNT_JSON: ${{ secrets.TF_VAR_ACCOUNT_JSON }}
 TF_VAR_INSTANCE_SSH_KEY: ${{ secrets.TF_VAR_INSTANCE_SSH_KEY }}
 TF_VAR_ROBBINS_PAGE_PEM: ${{ secrets.TF_VAR_ROBBINS_PAGE_PEM }}
 TF_VAR_ROBBINS_PAGE_KEY: ${{ secrets.TF_VAR_ROBBINS_PAGE_KEY }}

jobs:
  build-deploy:
    runs-on: ubuntu-latest

    steps:
      # Checks-out your repository under $GITHUB_WORKSPACE, so your job can access it
      - uses: actions/checkout@v3
      
      - name: Install Nix
        uses: cachix/install-nix-action@v18
        with:
          nix_path: nixpkgs=https://github.com/NixOS/nixpkgs/archive/0c9aadc8eff6daaa5149d2df9e6c49baaf44161c.tar.gz
          extra_nix_config: "system-features = nixos-test benchmark big-parallel kvm"
          
      - name: Update website input
        if: github.event.action == 'site_updated'
        run: |
          git config user.name github-actions
          git config user.email github-actions@github.com
          nix flake update website-src --commit-lock-file
        
      - name: HashiCorp - Setup Terraform
        uses: hashicorp/setup-terraform@v2.0.3
        with:
          # The API token for a Terraform Cloud/Enterprise instance to place within the credentials block of the Terraform CLI configuration file.
          cli_config_credentials_token: ${{ secrets.TF_USER_API_TOKEN }}
          terraform_version: 1.3.6
        
      - name: Terraform init
        id: init
        run: terraform init
        
      - name: Terraform Apply
        run: terraform apply  -auto-approve -input=false

      - name: Push updated flake.lock
        if: github.event.action == 'site_updated'
        run: |
          git config user.name github-actions
          git config user.email github-actions@github.com
          git push
```

This workflow will update the `flake.lock` lockfile with the new site repo input, and run `terraform apply` to rebuild and deploy the NixOS system onto the VM.

# Conclusion
That's it - this rube-goldberg machine of repo-to-repo communication with Terraform and NixOS mixed in gets me my static website.
