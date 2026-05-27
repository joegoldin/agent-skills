{
  lib,
  stdenv,
  makeWrapper,
  coreutils,
  openscad,
  python3,
  jq,
}:
stdenv.mkDerivation {
  pname = "vibecad";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/vibecad
    install -m 0755 vibecad.sh $out/bin/vibecad
    install -m 0644 views.py $out/share/vibecad/views.py
    wrapProgram $out/bin/vibecad \
      --prefix PATH : ${lib.makeBinPath [ coreutils openscad python3 jq ]} \
      --set VIBECAD_SHARE $out/share/vibecad
    runHook postInstall
  '';

  meta = with lib; {
    description = "Agentic OpenSCAD iteration CLI — scaffold designs, render STL, produce 16 turntable PNG views";
    homepage = "https://github.com/cjtrowbridge/vibe-modeling";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "vibecad";
  };
}
