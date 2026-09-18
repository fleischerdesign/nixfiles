# features/services/esphome/devices/switches.nix
# Declarative specifications for all 8 Sonoff Basic ESP8266 switches.
# Reconciles physical hardware parameters, pin triggers, and cryptographic keys.
{ pkgs, lib, ... }:

let
  mkSonoff = import ../templates/sonoff-basic.nix { inherit pkgs lib; };
in
{
  hom-rly-01 = mkSonoff {
    name = "hom-rly-01";
    friendlyName = "Arbeitszimmer Relais";
    ipv4 = "10.10.30.11";
    buttonPin = 1;
    buttonTrigger = "on_state";
    apiEncryptionKey = "Jda8P+dCXOTFvq7uEzaW9aW4WpnflW2+RcX7AMXnwCA=";
    otaPassword = "af5e67ad6ea49216ddd88fd9a6221c8b";
    apSsid = "hom-rly-01-fallback";
    apPassword = "W2Ixde5UxFww";
  };

  hom-rly-02 = mkSonoff {
    name = "hom-rly-02";
    friendlyName = "Bad Relais";
    ipv4 = "10.10.30.12";
    buttonPin = 1;
    buttonTrigger = "on_state";
    apiEncryptionKey = "U94yTjnP3QzujJV396VRjh9pZVyF22hjeW4s13faGnw=";
    otaPassword = "5d57adb137e8e7b5b2c74940ddff4cfb";
    apSsid = "hom-rly-02-fallback";
    apPassword = "80rETehdheMY";
  };

  hom-rly-03 = mkSonoff {
    name = "hom-rly-03";
    friendlyName = "Ender 3D-Drucker Relais";
    ipv4 = "10.10.30.13";
    buttonPin = 0;
    buttonTrigger = "on_press";
    apiEncryptionKey = "2S2xeWy72R8Z+ZGl0NbjR9VnEFs4RDYqlopQkCNif5M=";
    otaPassword = "8d6fc0f825883b9e8eef43b7c47f8cc8";
    apSsid = "hom-rly-03-fallback";
    apPassword = "BSTmKplv0hUH";
  };

  hom-rly-04 = mkSonoff {
    name = "hom-rly-04";
    friendlyName = "Fernseher Relais";
    ipv4 = "10.10.30.14";
    buttonPin = 1;
    buttonTrigger = "on_state";
    apiEncryptionKey = "MYp/FuWk9tFP+REGNUvcdKxvMKbUKFZqlcjjlbnlRd4=";
    otaPassword = "471791ec0a53bc5b8ac31da5070352dd";
    apSsid = "hom-rly-04-fallback";
    apPassword = "OX7Y7i7oLwGb";
  };

  hom-rly-05 = mkSonoff {
    name = "hom-rly-05";
    friendlyName = "Flur Relais";
    ipv4 = "10.10.30.15";
    buttonPin = 1;
    buttonTrigger = "on_state";
    apiEncryptionKey = "YObOx1HjsBUzYVE4OcByRPFKtreE/MYks5SwivOSjXg=";
    otaPassword = "7dba8aba52f7f8a90ef014a9586530a8";
    apSsid = "hom-rly-05-fallback";
    apPassword = "3VWTu6q8it6i";
  };

  hom-rly-06 = mkSonoff {
    name = "hom-rly-06";
    friendlyName = "Küche Relais";
    ipv4 = "10.10.30.16";
    buttonPin = 1;
    buttonTrigger = "on_state";
    apiEncryptionKey = "gVZrmyJL3G+RZiYIpPVhiGBXiwpJz8SK5/e17QdqUmQ=";
    otaPassword = "a89341a9bb704c56f3d35786b0aed0d1";
    apSsid = "hom-rly-06-fallback";
    apPassword = "TgRnUgsqedBy";
  };

  hom-rly-07 = mkSonoff {
    name = "hom-rly-07";
    friendlyName = "Schlafzimmer Relais";
    ipv4 = "10.10.30.17";
    buttonPin = 0;
    buttonTrigger = "on_press";
    apiEncryptionKey = "idWYB7B5Yjz+ynPhGVDBy+/6EV+6SXM6jggEG3U4M6g=";
    otaPassword = "1f25a66ae661bb8f7c2fe9e731430ab2";
    apSsid = "hom-rly-07-fallback";
    apPassword = "s7wS80ODeZri";
  };

  hom-rly-08 = mkSonoff {
    name = "hom-rly-08";
    friendlyName = "Sofa Relais";
    ipv4 = "10.10.30.18";
    buttonPin = 1;
    buttonTrigger = "on_state";
    apiEncryptionKey = "U9aQAvNpNBXs1E1g5fDEw94U+p+SNRdx2jI4m9gQGYs=";
    otaPassword = "d974d5481127a31e5fc0a813caff417e";
    apSsid = "hom-rly-08-fallback";
    apPassword = "IYvhXPt0PZ93";
  };
}
