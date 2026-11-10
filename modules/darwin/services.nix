{ config, pkgs, ... }:
{
  services.sketchybar = {
    enable = true;
    # Empty config leaves ~/.config/sketchybar/sketchybarrc in charge.
    config = "";
    extraPackages = [ pkgs.aerospace pkgs.jq ];
  };

  services.jankyborders = {
    enable = true;
    active_color = "0xff3a6aff";
    inactive_color = "0x00494d64";
    width = 12.0;
  };

  # Keep AeroSpace's hand-edited config; this module never generates it.
  services.aerospace.enable = false;
  launchd.user.agents.aerospace = {
    # The workspace-change hook calls SketchyBar from AeroSpace's environment.
    path = [ pkgs.aerospace pkgs.sketchybar pkgs.jq ] ++ [ config.environment.systemPath ];
    serviceConfig = {
      ProgramArguments = [ "/Applications/Nix Apps/AeroSpace.app/Contents/MacOS/AeroSpace" ];
      KeepAlive = true;
      RunAtLoad = true;
    };
  };
}
