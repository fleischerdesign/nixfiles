# The same native API reconciliation runs against a headless server or a desktop's embedded server.
{
  config,
  lib,
  pkgs,
  accounts,
  uiPasswordSecret,
  serverUrl,
  opencodeDatabase,
  integrationID ? "opencode-go",
  switchProvider ? integrationID,
  after ? [ "openchamber.service" ],
  wantedBy ? [ "multi-user.target" ],
  stateFile ? "/var/lib/openchamber-nixfiles/go-accounts.json",
  userScope ? false,
  protectHome ? true,
}:
let
  seed = pkgs.writeShellApplication {
    name = "openchamber-go-accounts";
    runtimeInputs = [ pkgs.nodejs_24 ];
    text = ''
      exec ${pkgs.nodejs_24}/bin/node ${./go-accounts.mjs} "$@"
    '';
  };
  seedConfig = pkgs.writeText "openchamber-go-accounts.json" (
    builtins.toJSON {
      inherit
        serverUrl
        integrationID
        switchProvider
        opencodeDatabase
        stateFile
        ;
      slots = map (account: {
        slot = account.slot;
        secretId = account.slot;
        secret = account.apiKeySecret;
      }) accounts;
    }
  );
in
{
  description = "Seed OpenCode Go accounts into OpenCode's credential store";
  inherit after wantedBy;
  # A user unit is not restarted by the system switch; the launcher restarts it at every start.
  restartTriggers = lib.optional (!userScope) seedConfig;
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = "${seed}/bin/openchamber-go-accounts";
    Environment = [ "OPENCHAMBER_GO_CONFIG=${seedConfig}" ];
    UMask = "0077";
    LoadCredential = [
      "ui_password:${config.sops.secrets.${uiPasswordSecret}.path}"
    ]
    ++ map (account: "${account.slot}:${config.sops.secrets.${account.apiKeySecret}.path}") accounts;
  }
  // lib.optionalAttrs (!userScope) {
    # The system service runs as an isolated account, so it declares its own state directory and
    # sandbox. A user unit already runs as the owner of the home and the OpenCode store.
    StateDirectory = "openchamber-nixfiles";
    StateDirectoryMode = "0700";
    ProtectSystem = "strict";
    ProtectHome = protectHome;
    PrivateTmp = true;
    NoNewPrivileges = true;
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
    ];
  };
}
