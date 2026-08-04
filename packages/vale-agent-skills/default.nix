{
  lib,
  stdenvNoCC,
  runCommand,
  makeWrapper,
  bash,
  coreutils,
  vale,
}:
let
  # Our own styles, laid out the way nixpkgs' `buildStyle` lays out the
  # third-party ones, so `vale.withStyles` can symlink them all into one
  # StylesPath.
  ourStyles = runCommand "vale-styles-agent-skills" { } ''
    mkdir -p $out/share/vale/styles
    cp -R ${./styles}/. $out/share/vale/styles/
  '';

  valeWithStyles = vale.withStyles (
    s: [
      s.alex
      s.google
      s.microsoft
      s.proselint
      s.readability
      s.write-good
    ]
    ++ [ ourStyles ]
  );
in
stdenvNoCC.mkDerivation {
  pname = "vale-agent-skills";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  doCheck = true;
  nativeCheckInputs = [ valeWithStyles ];
  checkPhase = ''
    runHook preCheck
    export VALE_SKILL_CONFIGS=$PWD/configs
    export VALE_SKILL_STYLES=$PWD/styles
    ${bash}/bin/bash tests/run-tests.sh
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/vale-agent-skills
    cp -R configs $out/share/vale-agent-skills/configs
    cp -R styles $out/share/vale-agent-skills/styles

    install -m 0755 vale-skill.sh $out/bin/vale-skill
    wrapProgram $out/bin/vale-skill \
      --prefix PATH : ${
        lib.makeBinPath [
          valeWithStyles
          coreutils
        ]
      } \
      --set VALE_SKILL_CONFIGS $out/share/vale-agent-skills/configs \
      --set VALE_SKILL_STYLES $out/share/vale-agent-skills/styles

    # Plain `vale`, styles already on its StylesPath, for anyone who would
    # rather drive it directly than through a profile.
    ln -s ${valeWithStyles}/bin/vale $out/bin/vale

    runHook postInstall
  '';

  passthru = {
    vale = valeWithStyles;
    inherit ourStyles;
  };

  meta = {
    description = "Vale styles and profiles for the avoid-ai-writing, simple-english, and diataxis skills";
    homepage = "https://vale.sh/";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "vale-skill";
  };
}
