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
      ai-users = {
        description = "Personal AI gateway owners";
        members = [ "philipp" ];
      };
    };
  };
  # Provider-specific privilege mapping, not a universal property of a directory group.
  my.features.services.authentik.server.superuserGroups = [ "infra-admins" ];
}
