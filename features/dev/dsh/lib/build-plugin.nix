# features/dev/dsh/lib/build-plugin.nix
# Generic builder for dsh plugins (both Node host fiber and Web Client UI).
{
  lib,
  stdenv,
  nodejs_24,
  typescript,
  esbuild,
  dsh,
}:

{
  pname,
  version,
  src,
  description ? "dsh plugin",
  hasClient ? false,
  extraNativeBuildInputs ? [ ],
  ...
}:

stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    nodejs_24
    typescript
    esbuild
  ]
  ++ extraNativeBuildInputs;

  buildPhase = ''
    runHook preBuild

    # 1. Link dsh framework typing & dependencies into local node_modules
    mkdir -p node_modules/@deepseek-ai node_modules/@types
    if [ -d "${dsh}/lib/dsh/node_modules/@deepseek-ai" ]; then
      ln -s ${dsh}/lib/dsh/node_modules/@deepseek-ai/* node_modules/@deepseek-ai/
    fi
    if [ -d "${dsh}/lib/dsh/node_modules/@types" ]; then
      ln -s ${dsh}/lib/dsh/node_modules/@types/* node_modules/@types/
    fi

    # Link react & @types/react from client packages
    CLIENT_DIR="${dsh}/lib/dsh/packages/client/ui-sidebar/node_modules"
    if [ -d "$CLIENT_DIR/react" ]; then
      ln -s "$CLIENT_DIR/react" node_modules/react
    fi
    if [ -d "$CLIENT_DIR/@types/react" ]; then
      ln -s "$CLIENT_DIR/@types/react" node_modules/@types/react
    fi

    # 2. Compile TypeScript for Node.js host fiber (lib/index.js, lib/index.d.ts)
    tsc --project tsconfig.json

    ${lib.optionalString hasClient ''
      # 3. Bundle React Web Client UI (lib/client.js) matching dsh WebBoot loader protocol
      mkdir -p lib
      esbuild src/client/index.ts \
        --bundle \
        --format=cjs \
        --platform=browser \
        --target=es2022 \
        --outfile=lib/client.js \
        --external:react \
        --external:react/jsx-runtime \
        --external:react-dom \
        --external:react-dom/client \
        --external:'@deepseek-ai/*' \
        --banner:js='window.__ModuleLoader__.load({ id: ${builtins.toJSON pname}, factory: (require) => { var module = { exports: {} }; var exports = module.exports;' \
        --footer:js='return module.exports; } });'
    ''}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/node_modules/${pname}
    cp -r lib package.json cordis.patch.yml $out/lib/node_modules/${pname}/

    if [ -d "${dsh}/lib/dsh/node_modules/@deepseek-ai" ]; then
      mkdir -p $out/lib/node_modules/${pname}/node_modules
      ln -s ${dsh}/lib/dsh/node_modules/@deepseek-ai $out/lib/node_modules/${pname}/node_modules/@deepseek-ai
    fi
    runHook postInstall
  '';

  passthru.dshPluginName = pname;

  meta = {
    inherit description;
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
