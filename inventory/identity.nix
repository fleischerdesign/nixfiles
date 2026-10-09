_: {
  my.directory = {
    users = {
      philipp.initialProfile = {
        displayName = "Philipp";
        email = "philipp@vyrx.de";
      };
      katja.initialProfile = {
        displayName = "Katja";
        email = "katja@vyrx.de";
      };
      lilly.initialProfile = {
        displayName = "Lilly";
        email = "lilly@vyrx.de";
      };
      kai.initialProfile = {
        displayName = "Kai";
        email = "kai@vyrx.de";
      };
      rieke.initialProfile = {
        displayName = "Rieke";
        email = "rieke@vyrx.de";
      };
    };
    groups = {
      infra-admins.description = "Cluster Administrators (Root & Global Access)";
      media-users.description = "Access to Media Streaming & Requests";
      family.description = "Family members with home automation & smart home access";
      # The OpenClaw gateways were removed; the group is retired explicitly rather than dropped. A
      # directory group that merely vanishes from this inventory is not deleted on the next apply
      # (contracts/directory: "Removal requires an explicit absent declaration").
      ai-users.state = "absent";
    };
  };
  # Provider-specific privilege mapping, not a universal property of a directory group.
  my.features.services.authentik.server.superuserGroups = [ "infra-admins" ];
}
