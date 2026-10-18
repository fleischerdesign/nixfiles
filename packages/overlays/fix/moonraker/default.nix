_final: prev: {
  home-assistant-custom-components = prev.home-assistant-custom-components // {
    moonraker = prev.home-assistant-custom-components.moonraker.overridePythonAttrs (oldAttrs: {
      disabledTests = (oldAttrs.disabledTests or [ ]) ++ [
        "test_set_custom_gcode_service"
        "test_send_gcode_list_payload_normalizes_script"
        "test_send_gcode_empty_payload_skips_send"
        "test_send_gcode_accepts_config_entry_id_and_deduplicates"
      ];

      # These four tests reach into Home Assistant's device registry with a mapping
      # API it no longer offers (upstream moonraker-home-assistant#789). nixpkgs met
      # the same failures while bumping Home Assistant and marked the package `broken`
      # for them (NixOS/nixpkgs#571402, commit 683b861faa) instead of disabling the
      # tests. Evaluation now refuses the package before `disabledTests` can help, so
      # clear the flag here: the condition it reports is already handled above.
      meta = (oldAttrs.meta or { }) // {
        broken = false;
      };
    });
  };
}
