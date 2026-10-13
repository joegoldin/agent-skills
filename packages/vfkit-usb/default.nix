{
  vfkit,
  apple-sdk_27,
  src,
}:
(vfkit.override { apple-sdk_15 = apple-sdk_27; }).overrideAttrs (old: {
  pname = "vfkit-usb";
  version = "0.6.3-usb-${src.shortRev or "dirty"}";
  inherit src;
  vendorHash = "sha256-sb8xZ5Va4SLVZrKJnDaf9VrQ10N4uQPKbOVwlPDK0EA=";
  ldflags = [
    "-s"
    "-w"
    "-X github.com/crc-org/vfkit/pkg/cmdline.gitVersion=${src.rev or "dirty"}"
  ];
  postInstall = (old.postInstall or "") + ''
    mkdir -p $out/Applications/vfkit.app/Contents/MacOS $out/share/vfkit/contrib/usb
    cp $out/bin/vfkit $out/Applications/vfkit.app/Contents/MacOS/vfkit
    cp contrib/usb/Info.plist $out/Applications/vfkit.app/Contents/Info.plist
    cp contrib/usb/sign.sh contrib/usb/vf-usb.entitlements $out/share/vfkit/contrib/usb/
  '';
  # Restricted USB entitlements are applied to a writable copy at activation,
  # where the user's provisioning profile and login keychain are available.
  postFixup = ''
    codesign --entitlements vf.entitlements -f -s - $out/bin/vfkit
    codesign --entitlements vf.entitlements -f -s - $out/Applications/vfkit.app/Contents/MacOS/vfkit
  '';
  passthru = (old.passthru or { }) // {
    tests = { };
  };
})
