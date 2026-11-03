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
  protectHome ? true,
  conditionPath ? null,
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
        ;
      stateFile = "/var/lib/openchamber-nixfiles/go-accounts.json";
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
  restartTriggers = [ seedConfig ];
  unitConfig = lib.optionalAttrs (conditionPath != null) { ConditionPathExists = conditionPath; };
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = "${seed}/bin/openchamber-go-accounts";
    Environment = [ "OPENCHAMBER_GO_CONFIG=${seedConfig}" ];
    StateDirectory = "openchamber-nixfiles";
    StateDirectoryMode = "0700";
    UMask = "0077";
    LoadCredential = [
      "ui_password:${config.sops.secrets.${uiPasswordSecret}.path}"
    ]
    ++ map (account: "${account.slot}:${config.sops.secrets.${account.apiKeySecret}.path}") accounts;
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
