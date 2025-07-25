{
  ...
}:

{
  boot.extraModprobeConfig = ''
    options uvcvideo quirks=0x80 # This is the first one to try
  '';
}
