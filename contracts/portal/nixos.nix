# Portal declarations and validation; no network or identity implementation is imported here.
{ config, lib, ... }:
let
  # --- what the portal reads, and what it may do ----------------------------------------------------
  # A readout is not a tile: `presentation.tiles` says how an entry looks, these say what the portal
  # may read and do. They live beside `tiles`, not inside one, because a service has one readout
  # however many tiles it exposes, and because the ingress, the tile and the portal must not
  # each grow their own copy of the same fact.
  #
  # The shape is the app's own interface (`vyrx.de/src/lib/adapters.ts`): the generic `http-json`
  # driver reads one path and picks declared fields out of the JSON by pointer. There is no product
  # knowledge here - a driver that is not `http-json` is an honest "unsupported", not an error.
  readoutFieldSubmodule = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.str;
        description = "Field identifier, a lowercase slug";
      };

      label = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        description = ''
          Copy per locale tag, e.g. `{ de = "Version"; en = "Version"; }`. The tag set is
          `my.portal.locales`, and the assertion below fails when one is missing.
        '';
      };

      type = lib.mkOption {
        type = lib.types.enum [
          "text"
          "number"
          "duration"
          "status"
          "bytes"
          "date"
        ];
        description = "How the value is rendered; the type, not the driver, decides.";
      };

      pointer = lib.mkOption {
        type = lib.types.str;
        description = "RFC 6901 pointer into the response, starting with '/'.";
      };
    };
  };

  readoutListSubmodule = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.str;
        description = "List identifier, a lowercase slug";
      };

      label = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        description = "Copy per locale tag, as for a field.";
      };

      pointer = lib.mkOption {
        type = lib.types.str;
        description = "RFC 6901 pointer to the array in the response, starting with '/'.";
      };

      max = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = ''
          Most rows the portal reads. Bounded by the assertion below: a declaration may not ask for
          "all rows", because the portal must not become a mirror of another service's data.
        '';
      };

      items = lib.mkOption {
        type = lib.types.nonEmptyListOf readoutFieldSubmodule;
        description = "The fields of one row; a list without fields carries nothing.";
      };
    };
  };

  readoutSubmodule = lib.types.submodule {
    options = {
      driver = lib.mkOption {
        type = lib.types.str;
        default = "http-json";
        description = "The driver that performs the read; `http-json` is the generic one.";
      };

      auth = lib.mkOption {
        type = lib.types.enum [
          "none"
          "bearer"
          "header"
          "basic"
        ];
        default = "none";
        description = ''
          How the request authenticates. The credential itself comes from the environment, never from
          the declaration and never into the browser.
        '';
      };

      read = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.submodule {
            options.path = lib.mkOption {
              type = lib.types.str;
              description = "Path of the read request, starting with '/'; the method is always GET.";
            };
          }
        );
        default = null;
        description = ''
          The request whose response the fields and lists point into. Null is allowed for a service
          that only declares actions; a declaration with fields or lists must name it (asserted below).
        '';
      };

      fields = lib.mkOption {
        type = lib.types.listOf readoutFieldSubmodule;
        default = [ ];
        description = "Scalar values read from the response.";
      };

      lists = lib.mkOption {
        type = lib.types.listOf readoutListSubmodule;
        default = [ ];
        description = "Row collections read from the response.";
      };
    };
  };

  actionSubmodule = lib.types.submodule {
    options = {
      label = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        description = "Copy per locale tag, as for a field.";
      };

      confirm = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        description = "Sentence shown before the action runs; it must name both locales (asserted below).";
      };

      method = lib.mkOption {
        type = lib.types.enum [
          "POST"
          "PUT"
          "DELETE"
        ];
        description = "HTTP method the action calls.";
      };

      path = lib.mkOption {
        type = lib.types.str;
        description = "Path the action calls, starting with '/'.";
      };

      permission = lib.mkOption {
        type = lib.types.enum [ "admin" ];
        default = "admin";
        description = "Who may trigger the action; only administrators, for now.";
      };
    };
  };

  # --- the portal's declaration is checked at evaluation --------------------------------------------
  # The typed options already reject a wrong type. These assertions catch the value a type cannot see
  # and name the offender, so a bad contract fails `nix flake check` instead of a deploy - the message
  # says which service, field or action to fix.
  portalViolations =
    let
      isSlug = value: builtins.match "[a-z0-9][a-z0-9-]*" value != null;
      startsWithSlash = value: builtins.substring 0 1 value == "/";

      labelViolations =
        where: label:
        lib.optional (!(builtins.hasAttr "de" label)) "${where}: label needs German copy"
        ++ lib.optional (!(builtins.hasAttr "en" label)) "${where}: label needs English copy";

      fieldViolations =
        where: field:
        lib.optional (!isSlug field.id) "${where}: id must be a lowercase slug"
        ++ lib.optional (!startsWithSlash field.pointer) "${where}: pointer must start with '/'"
        ++ labelViolations where field.label;

      listViolations =
        where: list:
        lib.optional (!isSlug list.id) "${where}: id must be a lowercase slug"
        ++ lib.optional (!startsWithSlash list.pointer) "${where}: pointer must start with '/'"
        ++ lib.optional (list.max < 1 || list.max > 10) "${where}: max must be between 1 and 10"
        ++ lib.optional (list.items == [ ]) "${where}: a list needs at least one item field"
        ++ labelViolations where list.label
        ++ lib.concatMap (item: fieldViolations "${where}.items.${item.id}" item) list.items;

      readoutViolations =
        svcName: svc:
        let
          readout = svc.presentation.readouts;
          where = "${svcName}.presentation.readouts";
        in
        if readout == null then
          [ ]
        else
          lib.optional (readout.read == null && (readout.fields != [ ] || readout.lists != [ ])) (
            "${where}: fields or lists need a read path"
          )
          ++ lib.concatMap (field: fieldViolations "${where}.fields.${field.id}" field) readout.fields
          ++ lib.concatMap (list: listViolations "${where}.lists.${list.id}" list) readout.lists;

      actionViolations =
        svcName: svc:
        lib.concatMap (
          actionId:
          let
            action = svc.presentation.actions.${actionId};
            where = "${svcName}.presentation.actions.${actionId}";
          in
          lib.optional (!isSlug actionId) "${where}: id must be a lowercase slug"
          ++ lib.optional (!startsWithSlash action.path) "${where}: path must start with '/'"
          ++ lib.optional (
            !(builtins.hasAttr "de" action.confirm)
          ) "${where}: confirm needs a German sentence"
          ++ lib.optional (
            !(builtins.hasAttr "en" action.confirm)
          ) "${where}: confirm needs an English sentence"
          ++ labelViolations where action.label
        ) (builtins.attrNames svc.presentation.actions);

      tileViolations =
        service: svc:
        lib.concatLists (
          lib.mapAttrsToList (
            name: tile:
            let
              where = "${service}.presentation.tiles.${name}";
            in
            lib.optional (
              !(builtins.hasAttr tile.endpoint svc.endpoints)
            ) "${where}: unknown endpoint '${tile.endpoint}'"
            ++ lib.optional (
              tile.description != { }
              && !lib.all (locale: builtins.hasAttr locale tile.description) config.my.portal.locales
            ) "${where}: description must name every portal locale"
          ) svc.presentation.tiles
        );

    in
    lib.concatLists (
      lib.mapAttrsToList (
        svcName: svc:
        readoutViolations svcName svc ++ actionViolations svcName svc ++ tileViolations svcName svc
      ) config.my.contracts.provides
    );
in
{
  options.my.portal.locales = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [
      "de"
      "en"
    ];
    description = ''
      Locale tags the portal renders. A tile's `description` must carry
      every one of them; the assertion below enforces it, so a locale is never silently missing.
    '';
  };

  options.my.contracts.provides = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.presentation = {
          tiles = lib.mkOption {
            type = lib.types.attrsOf (import ./tile.nix { inherit lib; });
            default = { };
            description = "Presentation of named service endpoints in the portal and SSO UI.";
          };
          # Capabilities belong to the service, not a particular endpoint or tile.
          readouts = lib.mkOption {
            type = lib.types.nullOr readoutSubmodule;
            default = null;
            description = "What the portal reads from this service at runtime";
          };

          actions = lib.mkOption {
            type = lib.types.attrsOf actionSubmodule;
            default = { };
            description = "Actions the portal may trigger, keyed by their slug";
          };

        };
      }
    );
  };
  config.assertions = [
    {
      assertion = portalViolations == [ ];
      message = ''
        the portal's readouts or actions are invalid:
        ${lib.concatStringsSep "\n" portalViolations}
      '';
    }
  ];
}
