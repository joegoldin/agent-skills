{
  lib,
  stdenv,
  makeWrapper,
  coreutils,
  curl,
  jq,
}:
stdenv.mkDerivation {
  pname = "pxd";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m 0755 pxd.sh $out/bin/pxd
    wrapProgram $out/bin/pxd \
      --prefix PATH : ${lib.makeBinPath [ coreutils curl jq ]}
    runHook postInstall
  '';

  meta = with lib; {
    description = "Pixeldrain CLI — upload, download, list, info, delete via the pixeldrain.com API";
    homepage = "https://pixeldrain.com/api";
    license = licenses.mit;
    platforms = platforms.unix;
    mainProgram = "pxd";
  };
}
