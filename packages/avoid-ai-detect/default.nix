{
  lib,
  stdenv,
  makeWrapper,
  coreutils,
  nodejs,
}:
stdenv.mkDerivation {
  pname = "avoid-ai-detect";
  version = "3.10.0";

  src = ./.;

  nativeBuildInputs = [
    makeWrapper
    nodejs
  ];

  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    node patterns.test.js
    node categories.test.js
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/avoid-ai-detect
    install -m 0755 avoid-ai-detect.sh $out/bin/avoid-ai-detect
    install -m 0644 cli.js $out/share/avoid-ai-detect/cli.js
    install -m 0644 patterns.js $out/share/avoid-ai-detect/patterns.js
    install -m 0644 CATEGORIES.md $out/share/avoid-ai-detect/CATEGORIES.md
    wrapProgram $out/bin/avoid-ai-detect \
      --prefix PATH : ${lib.makeBinPath [ coreutils nodejs ]} \
      --set AVOID_AI_DETECT_SHARE $out/share/avoid-ai-detect
    runHook postInstall
  '';

  meta = with lib; {
    description = "Deterministic AI-writing detector — scores text 0-100 across 44 pattern and stylometric categories";
    homepage = "https://github.com/conorbronsdon/avoid-ai-writing";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "avoid-ai-detect";
  };
}
