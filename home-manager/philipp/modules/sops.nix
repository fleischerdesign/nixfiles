{...}:
{
    sops = {
    age.keyFile = "/home/philipp/.config/sops/age/key.txt"; # must have no password!
    # It's also possible to use a ssh key, but only when it has no password:
    #age.sshKeyPaths = [ "/home/user/path-to-ssh-key" ];
    defaultSopsFile = ../../../secrets/main.yaml;
    secrets.openai = { };
    secrets.codestral = { };
  };
}