# features/services/esphome/devices/switches.nix
# Declarative specifications for all 8 Sonoff Basic ESP8266 switches.
# Reconciles physical hardware parameters, pin triggers, and cryptographic keys.
{ pkgs, lib, ... }:

let
  mkSonoff = import ../templates/sonoff-basic.nix { inherit pkgs lib; };
in
{
  hom-sw-01 = mkSonoff {
    name = "hom-sw-01";
    friendlyName = "Sonoff Basic Arbeitszimmer";
    ipv4 = "10.10.30.11";
    buttonPin = 1;
    buttonTrigger = "on_state";
    apiEncryptionKey = "Jda8P+dCXOTFvq7uEzaW9aW4WpnflW2+RcX7AMXnwCA=";
    otaPassword = "af5e67ad6ea49216ddd88fd9a6221c8b";
    apSsid = "Sonoff-Basic-Arbeitszimmer";
    apPassword = "W2Ixde5UxFww";
  };

  hom-sw-02 = mkSonoff {
    name = "hom-sw-02";
    friendlyName = "Sonoff Basic Bad";
    ipv4 = "10.10.30.12";
    buttonPin = 1;
    buttonTrigger = "on_state";
    apiEncryptionKey = "U94yTjnP3QzujJV396VRjh9pZVyF22hjeW4s13faGnw=";
    otaPassword = "5d57adb137e8e7b5b2c74940ddff4cfb";
    apSsid = "Sonoff-Basic-Bad";
    apPassword = "80rETehdheMY";
  };

  hom-sw-03 = mkSonoff {
    name = "hom-sw-03";
    friendlyName = "Sonoff Basic Ender 3D-Drucker";
    ipv4 = "10.10.30.13";
    buttonPin = 0;
    buttonTrigger = "on_press";
    apiEncryptionKey = "2S2xeWy72R8Z+ZGl0NbjR9VnEFs4RDYqlopQkCNif5M=";
    otaPassword = "8d6fc0f825883b9e8eef43b7c47f8cc8";
    apSsid = "Sonoff-Basic-Ender";
    apPassword = "BSTmKplv0hUH";
  };

  hom-sw-04 = mkSonoff {
    name = "hom-sw-04";
    friendlyName = "Sonoff Basic Fernseher";
    ipv4 = "10.10.30.14";
    buttonPin = 1;
    buttonTrigger = "on_state";
    apiEncryptionKey = "MYp/FuWk9tFP+REGNUvcdKxvMKbUKFZqlcjjlbnlRd4=";
    otaPassword = "471791ec0a53bc5b8ac31da5070352dd";
    apSsid = "Sonoff-Basic-Fernseher";
    apPassword = "OX7Y7i7oLwGb";
  };

  hom-sw-05 = mkSonoff {
    name = "hom-sw-05";
    friendlyName = "Sonoff Basic Flur";
    ipv4 = "10.10.30.15";
    buttonPin = 1;
    buttonTrigger = "on_state";
    apiEncryptionKey = "YObOx1HjsBUzYVE4OcByRPFKtreE/MYks5SwivOSjXg=";
    otaPassword = "7dba8aba52f7f8a90ef014a9586530a8";
    apSsid = "Sonoff-Basic-Flur";
    apPassword = "3VWTu6q8it6i";
  };

  hom-sw-06 = mkSonoff {
    name = "hom-sw-06";
    friendlyName = "Sonoff Basic Küche";
    ipv4 = "10.10.30.16";
    buttonPin = 1;
    buttonTrigger = "on_state";
    apiEncryptionKey = "gVZrmyJL3G+RZiYIpPVhiGBXiwpJz8SK5/e17QdqUmQ=";
    otaPassword = "a89341a9bb704c56f3d35786b0aed0d1";
    apSsid = "Sonoff-Basic-Kuche";
    apPassword = "TgRnUgsqedBy";
  };

  hom-sw-07 = mkSonoff {
    name = "hom-sw-07";
    friendlyName = "Sonoff Basic Schlafzimmer";
    ipv4 = "10.10.30.17";
    buttonPin = 0;
    buttonTrigger = "on_press";
    apiEncryptionKey = "idWYB7B5Yjz+ynPhGVDBy+/6EV+6SXM6jggEG3U4M6g=";
    otaPassword = "1f25a66ae661bb8f7c2fe9e731430ab2";
    apSsid = "Sonoff-Basic-Schlafzimmer";
    apPassword = "s7wS80ODeZri";
  };

  hom-sw-08 = mkSonoff {
    name = "hom-sw-08";
    friendlyName = "Sonoff Basic Sofa";
    ipv4 = "10.10.30.18";
    buttonPin = 1;
    buttonTrigger = "on_state";
    apiEncryptionKey = "U9aQAvNpNBXs1E1g5fDEw94U+p+SNRdx2jI4m9gQGYs=";
    otaPassword = "d974d5481127a31e5fc0a813caff417e";
    apSsid = "Sonoff-Basic-Sofa";
    apPassword = "IYvhXPt0PZ93";
  };
}
