# Paid workspaces for OpenClaw's model provider; ordering is the auth failover preference.
# Keep the funded subscription first: worker-placed sessions select the first profile and do not
# rotate to another account when it reports a billing error.
[
  {
    name = "subscription-1";
    apiKeySecret = "ai/opencode_api_key";
  }
  {
    name = "subscription-2";
    apiKeySecret = "ai/opencode_api_key_2";
  }
  {
    name = "subscription-3";
    apiKeySecret = "ai/opencode_api_key_3";
  }
]
