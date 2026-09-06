# features/dev/dsh/plugins/dsh-memory/package.nix
# dsh-memory: Bitemporal knowledge graph memory engine.
#
# `withOnnx` (default false) bundles the multilingual-e5-small ONNX model +
# tokenizer next to the plugin module so the neural embedding provider can load
# it fully offline. When false (the default, e.g. feature-hash baseline), the
# build is lightweight and performs no model download.
{
  callPackage,
  dsh,
  lib,
  fetchurl,
  withOnnx ? false,
  ...
}:

let
  buildDshPlugin = callPackage ../../lib/build-plugin.nix { inherit dsh; };
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);

  # intfloat/multilingual-e5-small (ONNX, fp32) + tokenizer. These are the
  # fixpoint artifact hashes served by Hugging Face. Only evaluated (and thus
  # downloaded) when withOnnx is true.
  baseUrl = "https://huggingface.co/intfloat/multilingual-e5-small/resolve/main";
  model = fetchurl {
    url = "${baseUrl}/onnx/model.onnx";
    hash = "sha256-ykVsBrOpUF3f2RMUCJFt15KQNoMx59drtiHxy6a8hmU=";
  };
  tokenizer = fetchurl {
    url = "${baseUrl}/tokenizer.json";
    hash = "sha256-C0Sp17UcPGJiZkDNoOLC9w/azcJbu9aAODadFOvfTDk=";
  };
  tokenizerConfig = fetchurl {
    url = "${baseUrl}/tokenizer_config.json";
    hash = "sha256-oda8hzSm9jXcFYUIvvAA+OLlp1nH2S+YSyyG5f9TQls=";
  };
  modelConfig = fetchurl {
    url = "${baseUrl}/config.json";
    hash = "sha256-aRN3Nsq4uJA6B/6K+q/dolqsVUFaEqVdG/+p9YGr+Vk=";
  };

  d = manifest.name;
  # Lazy: only interpolated (and therefore downloaded) when withOnnx is true.
  onnxInstall = lib.optionalString withOnnx ''
    mkdir -p $out/lib/node_modules/${d}/onnx
    cp -r ${model} $out/lib/node_modules/${d}/onnx/model.onnx
    cp -r ${tokenizer} $out/lib/node_modules/${d}/onnx/tokenizer.json
    cp -r ${tokenizerConfig} $out/lib/node_modules/${d}/onnx/tokenizer_config.json
    cp -r ${modelConfig} $out/lib/node_modules/${d}/onnx/config.json
  '';
in
buildDshPlugin {
  pname = manifest.name;
  inherit (manifest) version;
  src = ./.;
  description = manifest.description;
  hasClient = true;
  extraInstall = onnxInstall;
}
