# External-provider DNS requirements are site facts, not reconciler policy.
{ config, ... }:
{
  my.features.system.networking.cloudflare.records =
    map
      (
        record:
        record
        // {
          name = "${record.name}.${config.my.topology.domain}";
          type = "CNAME";
          proxied = false;
          comment = "Managed by VYRX GitOps: SMTP2GO sender domain";
        }
      )
      [
        {
          name = "em690000";
          content = "return.smtp2go.net";
          ttl = 3600;
        }
        {
          name = "s690000._domainkey";
          content = "dkim.smtp2go.net";
          ttl = 14400;
        }
        {
          name = "link";
          content = "track.smtp2go.net";
          ttl = 3600;
        }
      ];
}
