{
  lib,
  stdenv,
  makeWrapper,
  coreutils,
}:
stdenv.mkDerivation {
  pname = "re-shell";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m 0755 re-shell.sh $out/bin/re-shell
    # nix itself is deliberately not wrapped in: the caller's nix owns the
    # daemon socket, the flake registry, and the substituter config, and a
    # second nix from this closure would fight all three.
    wrapProgram $out/bin/re-shell \
      --prefix PATH : ${lib.makeBinPath [ coreutils ]}
    runHook postInstall
  '';

  meta = with lib; {
    description = "Launcher for the agent-skills re-shell reverse-engineering devShell";
    homepage = "https://github.com/joegoldin/agent-skills";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "re-shell";
  };
}
