{
  networking.hostName = "Ethans-MacBook-Pro-Mercury";
  networking.localHostName = "Ethans-MacBook-Pro-Mercury";
  networking.computerName = "Ethan’s MacBook Pro Mercury";

  # Mercury IT appends AWS_CA_BUNDLE to /etc/zshenv and /etc/bashrc. nix-darwin
  # replaces both files, so the variable has to come from here instead.
  environment.variables.AWS_CA_BUNDLE = "/Library/Mercury/certs/aws-ca-bundle.pem";

  # The Lix installer and Mercury IT both edited these files, so nix-darwin
  # doesn't recognize them and would refuse to switch. These are their exact
  # contents as of 2026-11-10; nix-darwin moves a matching file to
  # *.before-nix-darwin and takes over. Any later edit changes the hash and
  # brings the refusal back, which is the safe outcome.
  environment.etc."zshenv".knownSha256Hashes = [ "97e999cc8587e5c8e7019675565c8df541b0dbe3308d17833da02bf3d38125aa" ];
  environment.etc."bashrc".knownSha256Hashes = [ "2f25479269085a80c63094c733a8f24c8ab060f0ef4739d5fefdb423a461ed52" ];
}
