{
  description = "Hagia: pinned development shell and sandboxed measurement build (niltempus n002)";

  # The nixpkgs revision used for kleis: Nim 2.2.12 (the reviewed version),
  # nimble 0.24.1, nph 0.7.0 and gcc 14.4.0.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/c59305bab2065cfecc4944690d9eedbb56f3a9fa";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      # The reviewed dependency manifest (niltempus, sha256 285792c1...) and the
      # upstream revisions it records. Each package is rebuilt from that
      # source and must match the manifest file for file.
      manifest = ./nix/hagia.nim-deps;
      reviewed = {
        bigints = {
          dir = "bigints-1.0.0-d7aee76dba84419721566fd5413a02cca231a806";
          src = pkgs.fetchFromGitHub {
            owner = "nim-lang";
            repo = "bigints";
            rev = "d843ecfe1e2a62c3b0e29d211df09763da408cac";
            hash = "sha256-dwA2T/PLtmihZun1l39RYIMt5/EpHf2ia6GM3ghJtnY=";
          };
        };
        chronicles = {
          dir = "chronicles-0.12.2-02febb20d088120b2836d3306cfa21f434f88f65";
          src = pkgs.fetchFromGitHub {
            owner = "status-im";
            repo = "nim-chronicles";
            rev = "27ec507429a4eb81edc20f28292ee8ec420be05b";
            hash = "sha256-6ZvEFnMpUOYTRUNtJEseRXzK6gB6xKMH/lGxxx1zqfc=";
          };
        };
        faststreams = {
          dir = "faststreams-0.5.1-969ceb3666e807db8fe5c8df63466749822367a9";
          src = pkgs.fetchFromGitHub {
            owner = "status-im";
            repo = "nim-faststreams";
            rev = "50889cd16ec8771106cdd0eeea460039e8571e06";
            hash = "sha256-fH/BYZParZa3bGhgeqNXAAYTa3GxoUhEevzTwjdcpME=";
          };
        };
        graphemes = {
          dir = "graphemes-0.12.0-5a12349aea7c9682c87a086989a8afe7c8ade36b";
          src = pkgs.fetchFromGitHub {
            owner = "nitely";
            repo = "nim-graphemes";
            rev = "cc868c314ced482ed88dca2b470aa019480ce4c9";
            hash = "sha256-g8P5wkSZglyNZHax+F6ZqLre02fxunAaMK48CtRVofY=";
          };
        };
        json_serialization = {
          dir = "json_serialization-0.4.4-8b3115354104858a0ac9019356fb29720529c2bd";
          src = pkgs.fetchFromGitHub {
            owner = "status-im";
            repo = "nim-json-serialization";
            rev = "c343b0e243d9e17e2c40f3a8a24340f7c4a71d44";
            hash = "sha256-IVW1sYaT7N36hGzgvTRUAOuj0lc9umUc1BRJbEPBGkU=";
          };
        };
        nimcrypto = {
          dir = "nimcrypto-0.7.3-f72b90fe3f4da09efa482de4f8729e7ee4abea2f";
          src = pkgs.fetchFromGitHub {
            owner = "cheatfate";
            repo = "nimcrypto";
            rev = "b3dbc9c4d08e58c5b7bfad6dc7ef2ee52f2f4c08";
            hash = "sha256-hII3bCsIRdKZx7S+CWAlKOs4qZd1jqij0V8xTgX5mew=";
          };
        };
        nimkdl = {
          dir = "nimkdl-2.1.0-7d7e1e14205fb29c301af77414d2a617e6c755bb";
          src = pkgs.fetchFromGitHub {
            owner = "greenm01";
            repo = "nimkdl";
            rev = "4755e537a848e5f91465ccb314013fc0a7ce7c2f";
            hash = "sha256-6ug30C2GpOef486Lin3lAS9TCXxkXrYBYOYLNGEWLwI=";
          };
        };
        results = {
          dir = "results-0.5.1-a9c011f74bc9ed5c91103917b9f382b12e82a9e7";
          src = pkgs.fetchFromGitHub {
            owner = "arnetheduck";
            repo = "nim-results";
            rev = "df8113dda4c2d74d460a8fa98252b0b771bf1f27";
            hash = "sha256-KbNqt0FMuzDF4X+XM6JEaZJBypLDnvVPpnBpE7Sq6sA=";
          };
        };
        serialization = {
          dir = "serialization-0.5.3-c087d26c50da40436599163888532660d6f9e631";
          src = pkgs.fetchFromGitHub {
            owner = "status-im";
            repo = "nim-serialization";
            rev = "4092500cea76154576539371709ae801afbd2a9d";
            hash = "sha256-jDOqIMbLAPydU7GY3ReZUlzTmDvGrAWn8KHZcU0z/xI=";
          };
        };
        stew = {
          dir = "stew-0.5.0-db22942939773ab7d5a0f2b2668c237240c67dd6";
          src = pkgs.fetchFromGitHub {
            owner = "status-im";
            repo = "nim-stew";
            rev = "4382b18f04b3c43c8409bfcd6b62063773b2bbaa";
            hash = "sha256-Yvqe4YBxzCHYG/3HkDo9Lq9QJvWXUXrL1AOaYWp5qVc=";
          };
        };
        testutils = {
          dir = "testutils-0.8.2-c4a67c4ca30e1b0c7198b2912409e064e011d400";
          src = pkgs.fetchFromGitHub {
            owner = "status-im";
            repo = "nim-testutils";
            rev = "74588b8b55d116ca057431ae3a0ca359e0825fcd";
            hash = "sha256-Vh9uJWreWcKzQ9WYGtuk1tTpQP502wYj1Xbei5zYxK4=";
          };
        };
        unicodedb = {
          dir = "unicodedb-0.13.0-5c5fc0c8a83d270aca74fe41d33158e9042bb91a";
          src = pkgs.fetchFromGitHub {
            owner = "nitely";
            repo = "nim-unicodedb";
            rev = "15c5e25e2a49a924bc97647481ff50125bba2c76";
            hash = "sha256-0khAhu84SI+/noc0SzQggH2NGgZ9FMqu1ASq4nWtRo8=";
          };
        };
        unittest2 = {
          dir = "unittest2-0.2.5-02bb3751ba9ddc3c17bfd89f2e41cb6bfb8fc0c9";
          src = pkgs.fetchFromGitHub {
            owner = "status-im";
            repo = "nim-unittest2";
            rev = "26f2ef3ae0ec72a2a75bfe557e02e88f6a31c189";
            hash = "sha256-XCPV7j9bvDEvXuDC7tzXx6Zv5//reGLWSRWUpqYZFtk=";
          };
        };
      };

      # Nimble reads its package registry before any task, even offline; one
      # pinned registry commit keeps that lookup offline and deterministic.
      registry = pkgs.fetchFromGitHub {
        owner = "nim-lang";
        repo = "packages";
        rev = "09f05a91e9fc09b3e4626aa4d8f9a067716552ed";
        hash = "sha256-dB/ntRX4nIhAXSlW5DAzdPiNLdO+T1020HVZ4JH0eC4=";
      };

      # Files Nimble compiled at install time: testutils' ntu command-line tool.
      # Hagia never uses it; it is reported and left out, not rebuilt.
      installTime = { testutils = "ntu"; };

      nimPackage = name: p:
        pkgs.runCommand p.dir { } ''
          ${pkgs.bash}/bin/bash ${./nix/install-reviewed-package.sh} \
            ${manifest} ${name} ${p.src} ${./nix/nimblemeta}/${name}.json $out \
            "${installTime.${name} or ""}"
        '';
      packageDirs = lib.mapAttrs nimPackage reviewed;

      # The Nimble package store the reviewed build used, as ~/.nimble/pkgs2.
      nimPackages = pkgs.linkFarm "hagia-nim-packages"
        (lib.mapAttrsToList (name: p: { name = p.dir; path = packageDirs.${name}; }) reviewed);

      # A private Nimble home with a fixed path: Nim keeps its cache beneath
      # HOME, and a random path changes the type-info hashes in the binary.
      nimbleHome = ''
        export HOME="''${TMPDIR:-/tmp}/hagia-nix-home"
        rm -rf "$HOME"
        mkdir -p "$HOME/.nimble/pkgs2"
        cp -rL ${nimPackages}/. "$HOME/.nimble/pkgs2/"
        cp ${registry}/packages.json "$HOME/.nimble/packages_official.json"
        chmod -R u+w "$HOME/.nimble"
      '';
      tools = [ pkgs.nim pkgs.nimble pkgs.nph ];
      gcc = "${pkgs.gcc14Stdenv.cc}/bin/gcc";

      # Measurement: Hagia built with the niltempus release builder's exact
      # Nim command (product_artifact.rs nim_command/nim_flags): no nimble
      # path, no user, parent or project configuration, an explicit stdlib,
      # gcc and dependency paths. The one deliberate change is a fixed
      # --nimcache path (n001). The bwrap-isolated release build remains the
      # deliverable; this binary links /nix/store.
      hagia = pkgs.gcc14Stdenv.mkDerivation {
        pname = "hagia";
        version = "0.0.0-nix-measurement";
        src = self;
        dontConfigure = true;
        buildPhase = ''
          runHook preBuild
          ${pkgs.nim-unwrapped}/bin/nim c -d:release --hints:off \
            --noNimblePath --clearNimblePath \
            --skipUserCfg:on --skipParentCfg:on --skipProjCfg:on \
            --lib:${pkgs.nim-unwrapped}/nim/lib \
            --cc:gcc --gcc.exe:${gcc} --gcc.linkerexe:${gcc} \
            ${lib.concatMapStringsSep " " (d: "--path:${d}") (lib.attrValues packageDirs)} \
            --path:src --parallelBuild:$NIX_BUILD_CORES \
            --nimcache:$TMPDIR/hagia-nimcache \
            -o:hagia src/hagia.nim
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          install -Dm755 hagia $out/bin/hagia
          runHook postInstall
        '';
      };
    in
    {
      packages.${system} = {
        inherit hagia;
        nim-packages = nimPackages;
        default = hagia;
      };

      # Hagia's own test task (layout and Sophia policy checks) and format
      # check, run in Nix's sandbox from the pinned closure.
      checks.${system} = {
        inherit hagia;
        tests = pkgs.gcc14Stdenv.mkDerivation {
          name = "hagia-tests";
          src = self;
          nativeBuildInputs = tools;
          dontConfigure = true;
          buildPhase = ''
            ${nimbleHome}
            nimble --offline --useSystemNim test
          '';
          installPhase = "touch $out";
        };
        format = pkgs.runCommand "hagia-format-check" { nativeBuildInputs = tools; } ''
          cd ${self}
          nph --check src tests hagia.nimble
          touch $out
        '';
      };

      # Tools and environment only: no filesystem, device or network isolation.
      devShells.${system}.default = pkgs.mkShell.override { stdenv = pkgs.gcc14Stdenv; } {
        packages = tools ++ [ pkgs.git ];
        shellHook = nimbleHome;
      };
    };
}
