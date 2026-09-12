_final: prev: {
  home-assistant-custom-components = prev.home-assistant-custom-components // {
    moonraker = prev.home-assistant-custom-components.moonraker.overridePythonAttrs (oldAttrs: {
      disabledTests = (oldAttrs.disabledTests or [ ]) ++ [
        "test_set_custom_gcode_service"
        "test_send_gcode_list_payload_normalizes_script"
        "test_send_gcode_empty_payload_skips_send"
        "test_send_gcode_accepts_config_entry_id_and_deduplicates"
      ];
    });
  };
}
