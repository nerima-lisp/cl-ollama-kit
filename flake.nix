{
  description = "Transport-independent Common Lisp client for the Ollama API";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.7.4";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.paredit-cli.follows = "paredit-cli";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v1.7.1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    # cl-boundary-kit is used by the test system and by cl-resilience-kit.
    cl-boundary-kit = {
      url = "github:nerima-lisp/cl-boundary-kit/v2.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-host-kit.follows = "cl-host-kit";
      inputs.cl-weave.follows = "cl-weave";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    cl-codec-kit = {
      url = "github:nerima-lisp/cl-codec-kit/v0.6.0";
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
      inputs.cl-date-kit.follows = "cl-date-kit";
      inputs.cl-host-kit.follows = "cl-host-kit";
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

    cl-date-kit = {
      url = "github:nerima-lisp/cl-date-kit/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-weave.follows = "cl-weave";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    cl-deflate-kit = {
      url = "github:nerima-lisp/cl-deflate-kit/main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-weave.follows = "cl-weave";
    };

    cl-crypto-kit = {
      url = "github:nerima-lisp/cl-crypto-kit/761e95926923eba809f3e5deac88e68414aef894";
      flake = false;
    };

    cl-hpack-codec-kit = {
      url = "github:nerima-lisp/cl-hpack-codec-kit/08bc4c9ff1bcedb0624ad65d567a5e2d213b7ab9";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-weave.follows = "cl-weave";
    };

    cl-host-kit = {
      url = "github:nerima-lisp/cl-host-kit/v0.3.1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-weave.follows = "cl-weave";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    cl-http-kit = {
      url = "github:nerima-lisp/cl-http-kit/v0.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-weave.follows = "cl-weave";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.paredit-cli.follows = "paredit-cli";
      inputs.cl-boundary-kit.follows = "cl-boundary-kit";
      inputs.cl-codec-kit.follows = "cl-codec-kit";
      inputs.cl-concurrent-kit.follows = "cl-concurrent-kit";
      inputs.cl-crypto-kit.follows = "cl-crypto-kit";
      inputs.cl-date-kit.follows = "cl-date-kit";
      inputs.cl-deflate-kit.follows = "cl-deflate-kit";
      inputs.cl-host-kit.follows = "cl-host-kit";
      inputs.cl-hpack-codec-kit.follows = "cl-hpack-codec-kit";
      inputs.cl-http-message-kit.follows = "cl-http-message-kit";
      inputs.cl-tls-kit.follows = "cl-tls-kit";
    };

    cl-http-message-kit = {
      url = "github:nerima-lisp/cl-http-message-kit/v2.0.1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-weave.follows = "cl-weave";
      inputs.paredit-cli.follows = "paredit-cli";
      inputs.cl-hpack-codec-kit.follows = "cl-hpack-codec-kit";
    };

    cl-resilience-kit = {
      url = "github:nerima-lisp/cl-resilience-kit/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-nix-forge.follows = "cl-nix-forge";
      inputs.cl-weave.follows = "cl-weave";
      inputs.paredit-cli.follows = "paredit-cli";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.cl-boundary-kit.follows = "cl-boundary-kit";
      inputs.cl-concurrent-kit.follows = "cl-concurrent-kit";
      inputs.cl-date-kit.follows = "cl-date-kit";
    };

    cl-tls-kit = {
      url = "github:nerima-lisp/cl-tls-kit/v0.5.2";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-weave.follows = "cl-weave";
      inputs.cl-crypto-kit.follows = "cl-crypto-kit";
    };

    # cl-sse-kit's flake publishes source only; compile the runtime system below.
    cl-sse-kit = {
      url = "github:nerima-lisp/cl-sse-kit/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-codec-kit.follows = "cl-codec-kit";
      inputs.cl-boundary-kit.follows = "cl-boundary-kit";
      inputs.cl-concurrent-kit.follows = "cl-concurrent-kit";
      inputs.cl-weave.follows = "cl-weave";
      inputs.cl-crypto-kit.follows = "cl-crypto-kit";
      inputs.cl-date-kit.follows = "cl-date-kit";
      inputs.cl-deflate-kit.follows = "cl-deflate-kit";
      inputs.cl-host-kit.follows = "cl-host-kit";
      inputs.cl-hpack-codec-kit.follows = "cl-hpack-codec-kit";
      inputs.cl-http-kit.follows = "cl-http-kit";
      inputs.cl-http-message-kit.follows = "cl-http-message-kit";
      inputs.cl-resilience-kit.follows = "cl-resilience-kit";
      inputs.cl-tls-kit.follows = "cl-tls-kit";
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
      cl-date-kit,
      cl-deflate-kit,
      cl-crypto-kit,
      cl-hpack-codec-kit,
      cl-host-kit,
      cl-http-kit,
      cl-http-message-kit,
      cl-json-kit,
      cl-resilience-kit,
      cl-sse-kit,
      cl-tls-kit,
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

      lispDependencies =
        ctx:
        let
          forge = cl-nix-forge.lib.${ctx.system};
          wrapForeign = drv: forge.fromDerivation { inherit drv; recursive = true; };
          fromNixpkgsLisp = drv: forge.fromNixpkgsLisp { inherit drv; lispImplementation = "sbcl"; };
          externalLispDependencies = map fromNixpkgsLisp [
            ctx.pkgs.sbclPackages.alexandria
            ctx.pkgs.sbclPackages.bordeaux-threads
            ctx.pkgs.sbclPackages.global-vars
            ctx.pkgs.sbclPackages.trivial-features
            ctx.pkgs.sbclPackages.trivial-garbage
          ];
          clHttpMessageKit = forge.lispDerivation {
            pname = "cl-http-message-kit";
            version = "2.0.1";
            lispSystem = "cl-http-message-kit";
            src = cl-http-message-kit.outPath;
            lispDependencies = [ clHpackCodecKit ];
          };
          clHttpTlsKit = wrapForeign cl-tls-kit.packages.${ctx.system}.default;
          clHttpDeflateKit = forge.lispDerivation {
            pname = "cl-deflate-kit";
            version = "0.4.0";
            lispSystem = "cl-deflate-kit";
            src = cl-deflate-kit.outPath;
          };
          clHpackCodecKit = forge.lispDerivation {
            pname = "cl-hpack-codec-kit";
            version = "1.1.1";
            lispSystem = "cl-hpack-codec-kit";
            src = cl-hpack-codec-kit.outPath;
          };
          clCryptoKit = wrapForeign (forge.lispDerivation {
            pname = "cl-crypto-kit";
            version = "0.1.0";
            lispSystem = "cl-crypto-kit";
            src = cl-crypto-kit.outPath;
            lispDependencies = externalLispDependencies;
          });
          clHttpKit = wrapForeign (forge.lispDerivation {
            pname = "cl-http-kit";
            version = "0.5.0";
            lispSystems = [ "cl-http-kit/client" "cl-http-kit/tls" ];
            src = cl-http-kit.outPath;
            lispDependencies = [
              clHttpMessageKit
              clHpackCodecKit
              cl-codec-kit.packages.${ctx.system}.cl-codec-kit
              clHttpDeflateKit
              clHttpTlsKit
              clCryptoKit
            ] ++ externalLispDependencies;
          });
          clSseKit = wrapForeign (forge.lispDerivation {
            pname = "cl-sse-kit";
            version = "1.1.0";
            lispSystem = "cl-sse-kit";
            src = cl-sse-kit.packages.${ctx.system}.default;
            lispAsdPath = [ "share/common-lisp/source/cl-sse-kit" ];
            lispDependencies = [
              cl-codec-kit.packages.${ctx.system}.cl-codec-kit
              clHttpMessageKit
              clHpackCodecKit
              cl-resilience-kit.packages.${ctx.system}.cl-resilience-kit
              cl-boundary-kit.packages.${ctx.system}.cl-boundary-kit
              cl-concurrent-kit.packages.${ctx.system}.cl-concurrent-kit
              cl-date-kit.packages.${ctx.system}.cl-date-kit
              cl-host-kit.packages.${ctx.system}.cl-host-kit
            ] ++ externalLispDependencies;
          });
        in
        [
          clHttpKit
          clHttpMessageKit
          clHttpTlsKit
          clSseKit
          cl-codec-kit.packages.${ctx.system}.cl-codec-kit
          cl-concurrent-kit.packages.${ctx.system}.cl-concurrent-kit
          cl-json-kit.packages.${ctx.system}.cl-json-kit
        ];

      lispCheckDependencies = ctx: [
        cl-weave.packages.${ctx.system}.cl-weave
        cl-boundary-kit.packages.${ctx.system}.cl-boundary-kit
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
