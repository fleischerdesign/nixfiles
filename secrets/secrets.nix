let
  philipp = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB+bSErYniJev/+/UxsilaoxHGYW8oVpd3pYMQuuGStw";
  users = [ philipp ];
in
{
  "codestral.age".publicKeys = [ philipp ];
  "openai.age".publicKeys = [ philipp ];
}