_final: prev: {
  paperless-ngx = prev.paperless-ngx.overrideAttrs (oldAttrs: {
    disabledTests = (oldAttrs.disabledTests or [ ]) ++ [
      "test_search_more_like"
    ];
  });
}
