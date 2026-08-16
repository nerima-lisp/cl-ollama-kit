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
      url = "github:nerima-lisp/paredit-cli/v1.6.0";
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

    # Used as an independent finite SSE grammar oracle in the check closure.
    # The production parser remains incremental and bounded in cl-ollama-kit.
    cl-sse-kit = {
      url = "github:nerima-lisp/cl-sse-kit";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-weave.follows = "cl-weave";
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
      cl-sse-kit,
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

      lispCheckDependencies =
        ctx:
        let
          clSseKit = cl-nix-forge.lib.${ctx.system}.fromDerivation {
            drv = cl-nix-forge.lib.${ctx.system}.lispDerivation {
              pname = "cl-sse-kit";
              version = "0.1.0";
              lispSystem = "cl-sse-kit";
              src = cl-sse-kit.packages.${ctx.system}.default;
              lispAsdPath = [ "share/common-lisp/source/cl-sse-kit" ];
            };
            recursive = true;
          };
        in
        [
          cl-weave.packages.${ctx.system}.cl-weave
          clSseKit
        ];

      timeoutSeconds = 240;

      docs.root = ./docs;

      treefmt.evalModule = treefmt-nix.lib.evalModule;

      devShellPackages = ctx: [ paredit-cli.packages.${ctx.system}.default ];

      extraOutputs =
        ctx:
        let
          pareditFormatCheck = ctx.pkgs.writeShellApplication {
            name = "cl-ollama-kit-paredit-format";
            runtimeInputs = [
              paredit-cli.packages.${ctx.system}.default
              ctx.pkgs.coreutils
              ctx.pkgs.jq
              ctx.pkgs.perl
            ];
            text = ''
              set -eu

              failure=0
              temporary_directory=$(mktemp -d)
              trap 'rm -rf "$temporary_directory"' EXIT
              workspace_json="$temporary_directory/workspace.json"
              file_list="$temporary_directory/files"

              paredit inspect workspace --output json . > "$workspace_json"
              if ! jq -e \
                'all(.files[]; .dialect != "common-lisp" or .status == "parsed")' \
                "$workspace_json" > /dev/null; then
                printf '%s\n' 'paredit-format: workspace contains an unparsed Common Lisp file' >&2
                exit 1
              fi
              jq -r \
                '.files[] | select(.dialect == "common-lisp" and .status == "parsed") | .path' \
                "$workspace_json" > "$file_list"

              while IFS= read -r file; do
                [ -n "$file" ] || continue
                formatted="$temporary_directory/formatted"
                normalized="$temporary_directory/normalized"
                if ! paredit edit format --file "$file" > "$formatted"; then
                  printf 'paredit-format: unable to format %s\n' "$file" >&2
                  failure=1
                  continue
                fi
                perl -0777 -pe '
                  my $in_string = 0;
                  my $block_comment_depth = 0;
                  my @parts = split /(\n)/, $_, -1;
                  for (my $i = 0; $i < @parts; $i += 2) {
                    my $line = $parts[$i];
                    for (my $position = 0; $position < length($line); ) {
                      my $character = substr($line, $position, 1);
                      my $pair = substr($line, $position, 2);
                      if ($block_comment_depth > 0) {
                        if ($pair eq "#|") {
                          $block_comment_depth++;
                          $position += 2;
                          next;
                        }
                        if ($pair eq "|#") {
                          $block_comment_depth--;
                          $position += 2;
                          next;
                        }
                        $position++;
                        next;
                      }
                      if ($in_string) {
                        if ($character eq "\\") {
                          $position += 2;
                          next;
                        }
                        $in_string = 0 if $character eq "\"";
                        $position++;
                        next;
                      }
                      last if $character eq ";";
                      if ($pair eq "#|") {
                        $block_comment_depth = 1;
                        $position += 2;
                        next;
                      }
                      $in_string = 1 if $character eq "\"";
                      $position++;
                    }
                    $line =~ s/[ \t]+$// unless $in_string;
                    $parts[$i] = $line;
                  }
                  $_ = join "", @parts;
                ' "$formatted" > "$normalized"
                if ! cmp -s "$normalized" "$file"; then
                  printf 'paredit-format: %s is not canonically formatted\n' "$file" >&2
                  failure=1
                fi
              done < "$file_list"

              exit "$failure"
            '';
          };
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
            paredit-format = ctx.cl.mkCommandCheck {
              drv = ctx.package;
              name = "cl-ollama-kit-paredit-format";
              command = [ "${pareditFormatCheck}/bin/cl-ollama-kit-paredit-format" ];
              timeoutSeconds = 240;
              killAfterSeconds = 30;
            };
          };
        };
    };
}
