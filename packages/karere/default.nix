{ lib, stdenv, fetchFromGitHub, meson, pkg-config, vala, gtk4, libadwaita, webkitgtk_6_0, json-glib, libgee, blueprint-compiler, desktop-file-utils, appstream, ninja, wrapGAppsHook, gsettings-desktop-schemas }:

stdenv.mkDerivation rec {
  pname = "karere";
  version = "0.9.4";

  src = fetchFromGitHub {
    owner = "tobagin";
    repo = "karere";
    rev = "c020b599da488202a48b937f0b00f72c25d0b1b3";
    sha256 = "sha256-qfBAA9PFXqU+hS9evsX8898ysE58IcZz3df4kVsnaa8=";
  };

  nativeBuildInputs = [
    meson
    pkg-config
    vala
    blueprint-compiler
    desktop-file-utils
    appstream
    ninja
    wrapGAppsHook
  ];

  buildInputs = [
    gtk4
    libadwaita
    webkitgtk_6_0
    json-glib
    libgee
    gsettings-desktop-schemas
  ];

  meta = with lib; {
    description = "A modern, native GTK4/LibAdwaita wrapper for WhatsApp Web";
    homepage = "https://github.com/tobagin/karere";
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [ ];
    platforms = platforms.linux;
  };
}
