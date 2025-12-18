+++
title = "Building this blog with Nix, Terraform, and GitHub Actions"
date = "2025-07-27"

[taxonomies]
tags=["nix", "linux", "terraform"]
+++

{% note(title="") %}
This is an updated version of this blog post that used a different Terraform module to deploy NixOS changes to the VM. The previous version can be found in the Git history.
{% end %}

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
It also contains a Nix flake:
```nix,name=flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    serene-zola = { url = "github:robbins/serene"; flake = false; };
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
```

I'm going to assume some familiarity with Nix, but I'll still explain what's going on here. The `inputs` attribute essentially defines dependencies for this flake:
- nixpkgs, the Nix package repository
- apollo-zola, my fork of the Apollo Zola theme

Next, it defines the outputs attribute, which are the things that this flake provides, of which there are 2:
`packages.x86_64-linux.default` defines a Nix derivation (read: package) that can be built from this flake. It takes the current directory (the website source code) as source files, requires `zola` during the build process,
and then essentially runs the commands in the `configurePhase`, `buildPhase`, and `installPhase`.

The configurePhase creates a `themes/apollo` directory and copies the contents of the apollo-zola input to that directory.
The Git repository was cloned into the Nix store, so this step is essentially equivalent to `git submodule add https://github.com/not-matthias/apollo themes/apollo`.

Next, we run `zola build` which creates the website, and finally we copy the built website into `$out`, a directory in the Nix store created based on the hash of the derivation, and is where a derivations output is stored.

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
>tree
.
├── authenticated_origin_pull_ca.pem
├── flake.lock
├── flake.nix
├── main.tf
├── provider.tf
├── README.md
├── robbins.page.pem
├── robbins-page-webserver-configuration.nix
├── secrets
│   ├── cloudflare-api-token.age
│   ├── robbins-page-key.age
│   └── secrets.nix
├── terraform.tf
└── variables.tf
```

The entrypoint here is again a Nix flake:
```nix,name=flake.nix
{
  inputs = {
    nixpkgs.url = "github:robbins/nixpkgs/nixpkgs-unstable";
    website-src = {
      url = "github:robbins/robbins.page-site";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
  let
    system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
            "terraform"
          ];
        };
      };
  in
  {
    devShells."${system}".default = pkgs.mkShell {
      buildInputs = [
        (pkgs.terraform.withPlugins (p: [ p.null p.external p.google p.random ]))
        inputs.agenix.packages."${system}".agenix
        pkgs.google-cloud-sdk
        pkgs.jq
      ];
    };
    nixosConfigurations = {
      robbins-page-webserver = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
          modules = [
            ./robbins-page-webserver-configuration.nix
            inputs.agenix.nixosModules.default
            "${nixpkgs}/nixos/modules/virtualisation/google-compute-image.nix"
          ];
      };
    };
  };
}
```

We define some inputs - nixpkgs, the repo of our website's source code, and agenix, which is for runtime secret deployment.
For outputs, we again have another devShell, giving us temporary access to `terraform` and `age`, and a NixOS configuration that defines our server.

The nixosConfiguration is what builds and configures the entire NixOS system. Taking a look at the configuration file (some lines omitted):
```nix,name=flake.nix
{ config, lib, pkgs, inputs, ... }: {
  age.secrets.cloudflare-api-token.file = ./secrets/cloudflare-api-token.age;
  age.secrets.robbins-page-key = {
    file = ./secrets/robbins-page-key.age;
    owner = "nginx";
  };

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
      sslCertificate = "/etc/ssl/certs/robbins.page.pem";
      sslCertificateKey = config.age.secrets.robbins-page-key.path;
      extraConfig = ''
        ssl_client_certificate /etc/ssl/certs/authenticated_origin_pull_ca.pem;
        ssl_verify_client on;
      '';
    };
  };
  environment.systemPackages = [ inputs.website-src.packages.x86_64-linux.default ];
  environment.etc."ssl/certs/authenticated_origin_pull_ca.pem" = {
    text = builtins.readFile ./authenticated_origin_pull_ca.pem;
    user = "nginx";
  };
  environment.etc."ssl/certs/robbins.page.pem" = {
    text = builtins.readFile ./robbins.page.pem;
    user = "nginx";
  };

  services.cloudflare-dyndns = {
    enable = true;
    domains = [ "robbins.page" "www.robbins.page" ];
    apiTokenFile = config.age.secrets.cloudflare-api-token.path;
  };
}
```

We declare some secrets, an SSH host key, the Cloudflare dynamic DNS service, and the Nginx webserver.

The root of the "robbins.page" virtual host, however, isn't a typical path to "/var/www/..." but a path to the Nix store - in fact, it's the contents of the previously-built derivation defined in the site repository.

# Secrets
We want to protect our Cloudflare API token and SSL certificate key. [Agenix](https://github.com/ryantm/agenix) allows us to commit encrypted secrets that can be decrypted by the target host, using their private SSH host key.
{% important(title="Bootstrap") %}
This means that the host needs to be initially provisioned without secrets, to generate the SSH host keys, and then the secrets can be encrypted with the corresponding public key.
{% end %}

```nix,name=secrets/secrets.nix
let
  nejrobbins_gmail_com = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHBROs/XTz22QVUf1bhruq/FgrE+GHKkS77sR7Q3GJL2 nejrobbins_gmail_com";
  users = [ nejrobbins_gmail_com ];

  robbins-page-webserver = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKhMrYwPPCs+K51se/91Mn0HAhylzJ9ry7e5U4WVSQ15";
  hosts = [ robbins-page-webserver ];
in
{
  "cloudflare-api-token.age".publicKeys = users ++ hosts;
  "robbins-page-key.age".publicKeys = users ++ hosts;
}
```

Agenix allows secrets to be decrypted with any of the listed keys, so we can decrypt and edit it locally with my OS Login private key, and the server can decrypt it too with its private SSH host key.

# Terraform-NixOS-NG
The key to this project is the [terraform-nixos-ng](https://github.com/Gabriella439/terraform-nixos-ng) repository, which is a collection of Terraform modules that deploy NixOS on a remote host, and create
I've forked it to add support for Google Cloud VMs [here](https://github.com/robbins/terraform-nixos-ng).

Google Cloud doesn't have NixOS images by default, so we create a basic NixOS configuration (some lines omitted):
```nix,name=image-configuration.nix
{ config, lib, pkgs, inputs, ... }: {
  nixpkgs.hostPlatform = "x86_64-linux";

  image.extension = lib.mkForce "raw.tar.gz";
  services.openssh.enable = true;

  # Fix sudo (NixOS/nixpkgs/issues/218813)
  services.nscd.enableNsncd = false;

  services.openssh.passwordAuthentication = false;
  security.sudo.wheelNeedsPassword = false;

  nix.settings = {
    trusted-users = [ "nejrobbins_gmail_com" ];
  };
}
```

and use the `image-build` module of [nixos-anywhere](github.com/nix-community/nixos-anywhere) to build the image, and then create a Cloud Storage bucket with an image suitable for Compute Engine (some lines omitted):
```tcl,name=main.tf
module "image-build" {
  source            = "github.com/nix-community/nixos-anywhere//terraform/nix-build"
  attribute         = "${path.module}#nixosConfigurations.gce-image.config.system.build.googleComputeImage"
}

resource "random_id" "bucket" {
  byte_length = 8
}

resource "google_storage_bucket" "nixos-images" {
 name = "nixos-images-${random_id.bucket.hex}"
 location = var.region
 storage_class = var.storage_class
}

resource "google_storage_bucket_object" "nixos-installer" {
  name = local.image_path
  source = "${local.out_path}/${local.image_path}"
  bucket = google_storage_bucket.nixos-images.id
  content_type = "application/tar+gzip"
}

resource "google_compute_image" "nixos-installer-image" {
  name     = replace(replace(trimsuffix(local.image_path, "-x86_64-linux.raw.tar.gz"), ".", "-"), "_", "-")
  family   = "nixos"

  raw_disk {
    source = "https://storage.googleapis.com/${google_storage_bucket.nixos-images.name}/${google_storage_bucket_object.nixos-installer.name}"
  }
}
```

We then define our Compute Engine VM with that image, and tell it what flake attribute (our NixOS configuration) to use for rebuilds (some lines omitted):
```tcl,name=main.tf
resource "google_compute_instance" "robbins-page-webserver" {
  name = "robbins-page-webserver"
  machine_type = var.machine_type
  zone = var.zone

  boot_disk {
    device_name = "boot_disk"
    initialize_params {
      image = module.google_compute_image.gce-image
      size = 20
      type = "pd-standard"
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

# This ensures that the instance is reachable via `ssh` before we deploy NixOS
resource "null_resource" "example" {
  provisioner "remote-exec" {
    connection {
      host = local.ipv4
      user = "nejrobbins_gmail_com"
      private_key = var.INSTANCE_SSH_KEY
    }

    inline = [ ":" ]
  }
}

module "nixos" {
  source = "git::https://github.com/robbins/terraform-nixos-ng.git//nixos"

  host = "nejrobbins_gmail_com@${local.ipv4}"

  flake = ".#robbins-page-webserver"

  ssh_options = "-o StrictHostKeyChecking=accept-new -o ControlMaster=no -t -i /home/runner/.ssh/key"

  depends_on = [ null_resource.example ]
}
```

The VM uses Google OS Login, so I don't need to define any authorized SSH keys.

# GitHub Actions & Webhooks
But how do we push changes to the site repository and have the infra repository respond by updating the Terraform configuration? Enter GitHub webhooks.

In the site repository, I have a GitHub action that triggers on every new push and sends an API request to GitHub that triggers a repository dispatch event (some lines omitted):
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

In the infra repository, we have a Github action that responds to this event (some lines ommited):
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
