# Shared account identities only. Values stay in the SOPS document of each authorized consumer.
{
  opencodeGo = [
    {
      slot = "go-1";
      apiKeySecret = "ai/opencode_api_key_3";
    }
    {
      slot = "go-2";
      apiKeySecret = "ai/opencode_api_key_2";
    }
    {
      slot = "go-3";
      apiKeySecret = "ai/opencode_api_key";
    }
  ];
}
