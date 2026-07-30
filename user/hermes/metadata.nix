{
  type = "agent";
  username = "hermes";
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGy3vKexfJ90UfHvwyT22jhJLGz7iVn8ZDgK17+KRpPr hermes@rollins"
  ];
  extraGroups = [ "users" ];
}
