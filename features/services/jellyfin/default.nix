{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.jellyfin;

  # Everything below is read, never restated: this endpoint's contract carries the service's own access
  # policy, the directory contract carries the DN structure, and the LDAP provider publishes the ports
  # and the naming prefix of consumer accounts.
  # The consumes projection resolves what the endpoint left open: it is the compiled form of this
  # service as a directory consumer, so the module reads the effective values, not the raw options.
  consumer = config.my.contracts.consumes.jellyfin.ldap;
  directory = config.my.directory.ldap;
  ldapService = config.my.contracts.provides.authentik-ldap.endpoints;

  # The LDAP Authentication plugin matches on memberOf, so a group name becomes a filter term.
  memberOf = group: "(memberOf=cn=${group},${directory.groupsDn})";
  orFilter = groups: "(|" + lib.concatMapStrings memberOf groups + ")";

  ldapConfigPath = "/var/lib/jellyfin/plugins/configurations/LDAP-Auth.xml";
in
{
  options.my.features.services.jellyfin = {
    enable = lib.mkEnableOption "Jellyfin Media Server";
  };

  config = lib.mkIf cfg.enable {
    services.jellyfin = {
      enable = true;

      # Native Hardware Acceleration (New in NixOS 24.11/25.05+)
      hardwareAcceleration = {
        enable = true;
        type = "vaapi"; # Use VAAPI directly instead of QSV to avoid MFX session errors
        device = "/dev/dri/renderD128";
      };

      # Transcoding optimizations
      transcoding = {
        enableHardwareEncoding = true;
        enableIntelLowPowerEncoding = false; # Skylake/Gen9 does not support Low Power encoding
        enableToneMapping = true; # Essential for watching HDR content on non-HDR screens
      };
    };

    # System-level graphics support
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver # Modern Intel driver (Broadwell and newer)
        intel-vaapi-driver # Older Intel driver
        intel-compute-runtime # OpenCL support for Tone Mapping
        libvdpau-va-gl
      ];
    };

    # Permissions
    users.groups.media = { };
    users.users.jellyfin.extraGroups = [
      "media"
      "video"
      "render"
    ];

    systemd.services.jellyfin.serviceConfig = {
      UMask = lib.mkForce "0002";
    };

    # The plugin reads its configuration when it loads, and the file is rendered outside the unit, so
    # nothing else would notice a changed render: restartTriggers ties the two together. Measured
    # before this existed: restartTriggers was empty ([]), a deploy left the service running with the
    # previous configuration, and only a manual restart made the new file take effect.
    systemd.services.jellyfin.restartTriggers = [
      config.sops.templates."jellyfin-ldap-auth.xml".path
    ];

    my.contracts.provides.jellyfin = {
      endpoints.web = {
        port = 8096;
        protocol = "tcp";
        scope = "public";
        auth = "none";
        subdomain = "jellyfin";

        # Users live in Authentik; Jellyfin keeps its own sessions, users and library permissions.
        # Who may sign in, and who administers, is a Jellyfin decision and is declared here - the
        # directory exposes identities and encodes no consumer's policy.
        ldap = {
          enable = true;
          accessGroups = [
            "media-users"
            "infra-admins"
          ];
          adminGroups = [ "infra-admins" ];
        };
        publicExempt = "enforces its own user authentication; Jellyfin clients cannot perform a browser SSO redirect";
        # Ingress reaches this over the WireGuard mesh (invariant I10).
        directAccess = {
          enable = true;
          protocol = "tcp";
          interface = "wireguard";
        };
        dashboard = {
          show = true;
          displayName = "Jellyfin";
          category = "Media";
          icon = "jellyfin";
        };
      };
      storage = {
        stateDirs = [ "/var/lib/jellyfin" ];
        cacheDirs = [ "/var/cache/jellyfin" ];
      };
    };

    # LDAP authentication.
    #
    # The LDAP Authentication plugin reads its settings from one file inside Jellyfin's state directory,
    # and that file carries the bind password. It is therefore rendered from SOPS onto tmpfs and
    # symlinked into place, so the password never enters the store and the rendered file is not part of
    # Jellyfin's writable state.
    #
    # Field names and semantics come from the installed plugin build (LDAP Authentication 24.0.0.0) and
    # from the running directory, not from the plugin's upstream example, which still points at
    # dc=ldap,dc=goauthentik,dc=io and port 3389. The DNs, the accounts and the filters are all derived;
    # the only literal in this file is the plugin's own field vocabulary.
    sops.secrets.${consumer.secretPath} = { };

    sops.templates."jellyfin-ldap-auth.xml" = {
      content = ''
        <?xml version="1.0" encoding="utf-8"?>
        <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
          <LdapServer>127.0.0.1</LdapServer>
          <LdapPort>${toString ldapService.ldap.port}</LdapPort>
          <UseSsl>false</UseSsl>
          <UseStartTls>false</UseStartTls>
          <SkipSslVerify>false</SkipSslVerify>
          <LdapBindUser>${consumer.bindDn}</LdapBindUser>
          <LdapBindPassword>${config.sops.placeholder.${consumer.secretPath}}</LdapBindPassword>
          <LdapBaseDn>${directory.usersDn}</LdapBaseDn>
          <LdapSearchFilter>${orFilter consumer.accessGroups}</LdapSearchFilter>
          <LdapAdminFilter>${orFilter consumer.adminGroups}</LdapAdminFilter>
          <EnableLdapAdminFilterMemberUid>false</EnableLdapAdminFilterMemberUid>
          <LdapSearchAttributes>uid, cn, mail, displayName</LdapSearchAttributes>
          <CreateUsersFromLdap>true</CreateUsersFromLdap>
          <AllowPassChange>false</AllowPassChange>
          <LdapUidAttribute>uid</LdapUidAttribute>
          <LdapUsernameAttribute>cn</LdapUsernameAttribute>
          <EnableLdapProfileImageSync>false</EnableLdapProfileImageSync>
          <RemoveImagesNotInLdap>false</RemoveImagesNotInLdap>
          <EnableAllFolders>true</EnableAllFolders>
        </PluginConfiguration>
      '';
      owner = "jellyfin";
      mode = "0400";
    };

    systemd.tmpfiles.rules = [
      # The plugin directory exists only after Jellyfin's first start.
      "d /var/lib/jellyfin/plugins/configurations 0755 jellyfin jellyfin - -"
      "L+ ${ldapConfigPath} - - - - ${config.sops.templates."jellyfin-ldap-auth.xml".path}"
    ];
  };
}
