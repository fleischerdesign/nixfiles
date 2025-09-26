self: super: {
  gnomeExtensions = super.gnomeExtensions // {
    pip-on-top = super.gnomeExtensions.pip-on-top.overrideAttrs (oldAttrs: {
      postPatch = ''
        substituteInPlace extension.js \
          --replace "window.title == 'Picture-in-picture'" "window.title == 'Picture-in-picture' || window.title == 'Bild im Bild'"
      '';
    });
  };
}
