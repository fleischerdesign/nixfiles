_: {
  my.features.dev.codex.enable = true;
  my.features.dev.opencodex = {
    enable = true;
    initialProviders = {
      opencode-go = {
        adapter = "openai-chat";
        baseUrl = "https://opencode.ai/zen/go/v1";
        authMode = "key";
        apiKey = "\${OPENCODE_API_KEY}";
      };
    };
  };
  my.features.desktop.chatgpt.enable = true;
}
