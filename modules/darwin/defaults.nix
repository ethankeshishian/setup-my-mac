{ config, lib, ... }:
let
  user = lib.escapeShellArg config.system.primaryUser;
in
{
  system.defaults = {
    dock = {
      orientation = "right";
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.4;
      wvous-bl-corner = 4;
      show-recents = false;
      expose-group-apps = true;
    };
    NSGlobalDomain._HIHideMenuBar = true;
    trackpad = {
      Clicking = true;
      TrackpadThreeFingerDrag = true;
      Dragging = false;
      DragLock = false;
    };
    CustomUserPreferences = {
      "com.apple.dock".wvous-br-modifier = 1048576;
      NSGlobalDomain.NSWindowShouldDragOnGesture = true;
      "com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
        "64" = {
          enabled = false;
          value.parameters = [ 65535 49 1048576 ];
          type = "standard";
        };
        "65" = {
          enabled = false;
          value.parameters = [ 65535 49 1572864 ];
          type = "standard";
        };
      };
    };
  };

  # Re-read settings in the primary user's login session after defaults apply.
  system.activationScripts.postActivation.text = ''
    /bin/launchctl asuser "$(/usr/bin/id -u ${user})" \
      /usr/bin/sudo -u ${user} \
      /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';
}
