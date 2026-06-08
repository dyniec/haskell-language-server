{
  description = "haskell-language-server development flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # For default.nix
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachSystem
      [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ]
    (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = { allowBroken = true; };
        };

        pythonWithPackages = pkgs.python3.withPackages (ps:
          [ ps.docutils
            ps.myst-parser
            ps.pip
            ps.sphinx
            ps.sphinx-rtd-theme
          ]);

        docs = pkgs.stdenv.mkDerivation {
          name = "hls-docs";
          src = pkgs.lib.sourceFilesBySuffices ./.
            [ ".py" ".rst" ".md" ".png" ".gif" ".svg" ".cabal" ];
          buildInputs = [ pythonWithPackages ];
          buildPhase = ''
            cd docs
            make --makefile=${./docs/Makefile} html BUILDDIR=$out
            '';
          dontInstall = true;
        };

        # Support of GenChangelogs.hs
        gen-hls-changelogs = hpkgs: with pkgs;
          let myGHC = hpkgs.ghcWithPackages (p: with p; [ github ]);
          in pkgs.runCommand "gen-hls-changelogs" {
            passAsFile = [ "text" ];
            preferLocalBuild = true;
            allowSubstitutes = false;
            buildInputs = [ git myGHC ];
          } ''
            dest=$out/bin/gen-hls-changelogs
            mkdir -p $out/bin
            echo "#!${runtimeShell}" >> $dest
            echo "${myGHC}/bin/runghc ${./GenChangelogs.hs}" >> $dest
            chmod +x $dest
          '';

        mkDevShell = hpkgs: with pkgs; mkShell {
          name = "haskell-language-server-dev-ghc${hpkgs.ghc.version}";
          # For binary Haskell tools, we use the default Nixpkgs GHC version.
          # This removes a rebuild with a different GHC version. The drawback of
          # this approach is that our shell may pull two GHC versions in scope.
          buildInputs = [
            # Compiler toolchain
            hpkgs.ghc
            hpkgs.haskell-language-server
            pkgs.haskellPackages.cabal-install
            # Dependencies needed to build some parts of Hackage
            gmp zlib ncurses
            # for compatibility of curl with provided gcc
            curl
            # Changelog tooling
            (gen-hls-changelogs hpkgs)
            # For the documentation
            pythonWithPackages
            (pkgs.haskell.lib.justStaticExecutables (pkgs.haskell.lib.dontCheck pkgs.haskellPackages.opentelemetry-extra))
            capstone
            stylish-haskell
            pre-commit
            ] ++ lib.optionals (!stdenv.isDarwin)
                   [ # tracy has a build problem on macos.
                     tracy
                   ];

          shellHook = ''
            # @guibou: I'm not sure theses lines are needed
            export LD_LIBRARY_PATH=${gmp}/lib:${zlib}/lib:${ncurses}/lib:${capstone}/lib
            export DYLD_LIBRARY_PATH=${gmp}/lib:${zlib}/lib:${ncurses}/lib:${capstone}/lib
            export PATH=$PATH:$HOME/.local/bin

            # Install pre-commit hook
            pre-commit install
          '';
        };

      in {
        # Developement shell with only dev tools
        devShells = {
          default = mkDevShell pkgs.haskellPackages;
          shell-ghc96 = mkDevShell pkgs.haskell.packages.ghc96;
          shell-ghc98 = mkDevShell pkgs.haskell.packages.ghc98;
          shell-ghc910 = mkDevShell pkgs.haskell.packages.ghc910;
          shell-ghc912 = mkDevShell pkgs.haskell.packages.ghc912;
          shell-ghc914 = mkDevShell (pkgs.haskell.packages.ghc914.override {
            overrides = self: super: {
              clay = pkgs.haskell.lib.doJailbreak super.clay;
              #Cabal-syntax_3_14_2_0 = pkgs.haskell.lib.doJailbreak super.Cabal-syntax_3_14_2_0;
              Cabal-syntax_3_14_2_0 = pkgs.haskell.lib.overrideCabal
              super.Cabal-syntax_3_14_2_0 (old: {
              postPatch = (old.postPatch or "") + ''
                sed -i 's/time\s*>= 1\.4\.0\.1\s*&& < 1\.15/time >=1.4.0.1/' Cabal-syntax.cabal
                sed -i 's/containers\s*>= 0\.5\.0\.0\s*&& < 0\.8/containers >=0.5.8.0/' Cabal-syntax.cabal
              '';
            });
              Cabal_3_14_2_0 = pkgs.haskell.lib.overrideCabal
              super.Cabal_3_14_2_0 (old: {
              postPatch = (old.postPatch or "") + ''
                sed -i 's/time\s*>= 1\.4\.0\.1\s*&& < 1\.15/time >=1.4.0.1/' Cabal.cabal
                sed -i 's/containers\s*>= 0\.5\.8\.0\s*&& < 0\.8/containers >=0.5.8.0/' Cabal.cabal
              '';
            });

              dec = pkgs.haskell.lib.doJailbreak super.dec;
              ghc-lib-parser = pkgs.haskell.lib.doJailbreak super.ghc-lib-parser;
              ghc-trace-events = pkgs.haskell.lib.doJailbreak super.ghc-trace-events;
              hie-compat = pkgs.haskell.lib.doJailbreak super.hie-compat;
              lucid = pkgs.haskell.lib.doJailbreak super.lucid;
              singleton-bool = pkgs.haskell.lib.doJailbreak super.singleton-bool;
            };
          });
        };


        packages = { inherit docs; };
      });

  nixConfig = {
    extra-substituters = [
      "https://haskell-language-server.cachix.org"
    ];
    extra-trusted-public-keys = [
      "haskell-language-server.cachix.org-1:juFfHrwkOxqIOZShtC4YC1uT1bBcq2RSvC7OMKx0Nz8="
    ];
  };
}
