{
  lib,
  stdenv,
  makeWrapper,
  python3,
}:
stdenv.mkDerivation {
  pname = "figr";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m 0755 figr.py $out/bin/figr
    patchShebangs $out/bin/figr
    wrapProgram $out/bin/figr \
      --prefix PATH : ${lib.makeBinPath [ python3 ]}
    runHook postInstall
  '';

  meta = with lib; {
    description = "Read-only Figma CLI — spec dumps, JSON, image renders, layer search, comments via the Figma REST API";
    homepage = "https://www.figma.com/developers/api";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "figr";
  };
}
