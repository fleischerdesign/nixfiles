# Outbound mail transport is a site assignment; consumers remain provider-independent.
{ config, ... }:
{
  my.features.system.smtp = {
    host = "mail-eu.smtp2go.com";
    port = 2525;
    tls = "starttls";
    fromAddress = "noreply@${config.my.topology.domain}";
  };
}
