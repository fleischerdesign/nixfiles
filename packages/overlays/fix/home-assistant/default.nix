# Temporary: Home Assistant cannot be connected to ChatGPT from the release nixpkgs pins.
#
# Two upstream gaps sit in 2026.9.4 and are closed in 2026.10.0; ChatGPT's connector meets both:
#
#   7398141b4c  Support PKCE S256 in OAuth server (#181957)
#     ChatGPT refuses an instance whose /.well-known/oauth-authorization-server omits
#     "code_challenge_methods_supported": ["S256"] - the connector cannot be created at all.
#   ef31c2d9ca  Correct OAuth discovery metadata for public clients (#184254)
#     Without "token_endpoint_auth_methods_supported": ["none"] a client assumes the RFC 8414 default
#     client_secret_basic, sends its token request as a confidential client, and the token endpoint
#     answers 400 - after a successful login ChatGPT reports "We couldn't connect your account".
#   52fdc84634  Reject PKCE authorization codes in LinkUserView (#183213)
#     Hardening follow-up to the first commit, carried with it.
#
# The patch files are the production halves of those commits, re-anchored onto this release with
# context lines from its sources (tests omitted - nixpkgs disables tests/components anyway). All three
# apply with --fuzz=0, and the patched package passes the whole check phase (8165 tests).
#
# Removal condition: nixpkgs ships Home Assistant 2026.10.x. Then delete this directory and its import
# in flake.nix - the overlay warns instead of patching from that release on, so it cannot be forgotten
# silently.
_final: prev: {
  home-assistant =
    if prev.lib.versionOlder prev.home-assistant.version "2026.10" then
      prev.home-assistant.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ./pkce-s256.patch
          ./pkce-hardening.patch
          ./oauth-discovery-metadata.patch
        ];
      })
    else
      prev.lib.warn "packages/overlays/fix/home-assistant is obsolete: Home Assistant ${prev.home-assistant.version} ships the OAuth metadata; delete the directory and its import in flake.nix" prev.home-assistant;
}
