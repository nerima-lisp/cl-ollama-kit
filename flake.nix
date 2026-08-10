{
  description = "Transport-independent Common Lisp client for the Ollama API";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v1.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    # These are the runtime dependencies declared by cl-ollama-kit.asd.
    # Keep their ASDF systems in lispDependencies so the package closure and
    # the test closure describe the same dependency boundary as ASDF.
    cl-boundary-kit = {
      url = "github:nerima-lisp/cl-boundary-kit/v2.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-weave.follows = "cl-weave";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    cl-codec-kit = {
      url = "github:nerima-lisp/cl-codec-kit/v0.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-weave.follows = "cl-weave";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.paredit-cli.follows = "paredit-cli";
    };

    cl-concurrent-kit = {
      url = "github:nerima-lisp/cl-concurrent-kit/v0.6.1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-boundary-kit.follows = "cl-boundary-kit";
      inputs.cl-weave.follows = "cl-weave";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    cl-json-kit = {
      url = "github:nerima-lisp/cl-json-kit/v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-weave.follows = "cl-weave";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-nix-forge,
      cl-weave,
      treefmt-nix,
      paredit-cli,
      cl-boundary-kit,
      cl-codec-kit,
      cl-concurrent-kit,
      cl-json-kit,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
    in
    cl-nix-forge.lib.${nixpkgs.lib.head systems}.mkPackageFlake {
      inherit self systems nixpkgs;

      pname = "cl-ollama-kit";
      asd = ./cl-ollama-kit.asd;
      root = ./.;

      meta = {
        description = "Transport-independent Common Lisp client for the Ollama API";
        license = nixpkgs.lib.licenses.mit;
        platforms = nixpkgs.lib.platforms.unix;
      };

      lispDependencies = ctx: [
        cl-boundary-kit.packages.${ctx.system}.cl-boundary-kit
        cl-codec-kit.packages.${ctx.system}.cl-codec-kit
        cl-concurrent-kit.packages.${ctx.system}.cl-concurrent-kit
        cl-json-kit.packages.${ctx.system}.cl-json-kit
      ];

      lispCheckDependencies = ctx: [ cl-weave.packages.${ctx.system}.cl-weave ];

      timeoutSeconds = 240;

      docs.root = ./docs;

      treefmt.evalModule = treefmt-nix.lib.evalModule;

      devShellPackages = ctx: [ paredit-cli.packages.${ctx.system}.default ];

      extraOutputs =
        ctx:
        let
          coverageReport = ctx.cl.mkCoverageReport {
            drv = ctx.package;
            name = "cl-ollama-kit-coverage";
            systems = [ "cl-ollama-kit" ];
            entryPoint = ./run-coverage.lisp;
            timeoutSeconds = 600;
            killAfterSeconds = 30;
          };
        in
        {
          packages.coverage = coverageReport;
          checks = {
            coverage = coverageReport;
          }
          // nixpkgs.lib.optionalAttrs (paredit-cli.lib ? ${ctx.system}) {
            paredit-lint = paredit-cli.lib.${ctx.system}.mkLintCheck {
              inherit (ctx) src;
              name = "cl-ollama-kit-paredit-lint";
            };
          };
        };
    };
}
