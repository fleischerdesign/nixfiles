# Paid workspaces shared by OpenClaw's model provider and the coding runtimes; ordering
# expresses the initial preference. Keep the funded subscription first: worker-placed sessions
# select the first profile and do not rotate to another account when it reports a billing error.
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
