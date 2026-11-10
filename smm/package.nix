{ writeShellApplication, jq, git, gitleaks }:
(writeShellApplication {
  name = "smm";
  runtimeInputs = [ jq git gitleaks ];
  text = builtins.readFile ./bin/smm;
}).overrideAttrs (old: {
  # writeShellApplication uses a single buildCommand, rather than installPhase.
  buildCommand = old.buildCommand + ''
    mkdir -p "$out/lib" "$out/cmd"
    cp -R ${./lib}/. "$out/lib/"
    cp -R ${./cmd}/. "$out/cmd/"
  '';
})
