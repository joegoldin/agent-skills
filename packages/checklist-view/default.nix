{ pkgs }:
pkgs.writeShellApplication {
  name = "checklist-view";
  text = ''
    if [[ $# -eq 1 && ( $1 == --help || $1 == -h ) ]]; then
      echo 'Usage: checklist-view FILE.md'
      exit 0
    fi
    if [[ $# -ne 1 || ! -f $1 ]]; then
      echo 'Usage: checklist-view FILE.md (an existing Markdown file)' >&2
      exit 2
    fi
    export NVIM_APPNAME=checklist-view
    exec ${pkgs.lib.getExe pkgs.neovim} --clean -i NONE -u ${./init.lua} \
      --cmd 'set runtimepath^=${pkgs.vimPlugins.markview-nvim}' -- "$1"
  '';
}
