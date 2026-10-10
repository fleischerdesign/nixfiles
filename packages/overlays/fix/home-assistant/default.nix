# Temporary: Home Assistant cannot be connected to ChatGPT from the release nixpkgs pins.
#
# Upstream gaps sit in 2026.9.4 that are closed in 2026.10.0; ChatGPT's connector meets all of them:
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
#   home-assistant/frontend#54389  Forward PKCE code_challenge parameters in login flow
#     The PKCE parameters travel through the frontend: /auth/authorize carries the challenge, but the
#     login flow is created by the single-page app, and the version 2026.9.4 pins (20260826.7) drops
#     them. Measured on the wire: "GET /auth/authorize?...code_challenge=...&code_challenge_method=S256"
#     followed by "POST /auth/login_flow {client_id, handler, redirect_uri}" without either parameter,
#     so the authorization code is stored without a challenge while ChatGPT still sends its
#     code_verifier - the token endpoint then answers 400 "Code verifier provided but no code challenge
#     was present". 2026.10 pairs its core with home-assistant-frontend 20260930.2, which is the
#     version used here; it was the first frontend release after that commit (verified: the wheel
#     carries code_challenge in 21 bundles).
#
# The patch files are the production halves of the core commits, re-anchored onto this release with
# context lines from its sources (tests omitted - nixpkgs disables tests/components anyway). All three
# apply with --fuzz=0, and the patched package passes the whole check phase (8165 tests).
#
# Removal condition: nixpkgs ships Home Assistant 2026.10.x. Then delete this directory and its import
# in flake.nix - the overlay warns instead of patching from that release on, so it cannot be forgotten
# silently.
_final: prev: {
  home-assistant =
    if prev.lib.versionOlder prev.home-assistant.version "2026.10" then
      (prev.home-assistant.override {
        packageOverrides = _self: super: {
          home-assistant-frontend = super.home-assistant-frontend.overridePythonAttrs (_: {
            version = "20260930.2";
            src = prev.fetchPypi {
              pname = "home_assistant_frontend";
              version = "20260930.2";
              format = "wheel";
              dist = "py3";
              python = "py3";
              hash = "sha256-KNnXHfY+lr0xg9NCXAw7pARG+k0Amkv0OW8xicjzI34=";
            };
          });
        };
      }).overrideAttrs
        (old: {
          patches = (old.patches or [ ]) ++ [
            ./pkce-s256.patch
            ./pkce-hardening.patch
            ./oauth-discovery-metadata.patch
          ];
        })
    else
      prev.lib.warn "packages/overlays/fix/home-assistant is obsolete: Home Assistant ${prev.home-assistant.version} ships the OAuth metadata; delete the directory and its import in flake.nix" prev.home-assistant;
}
