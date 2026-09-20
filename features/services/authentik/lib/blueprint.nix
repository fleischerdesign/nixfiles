# lib/blueprint.nix
# Constructors for authentik blueprints.
#
# Blueprint entries are hand-written YAML in the upstream documentation, and three things about them are
# silent when wrong. A model name is a string ("app.model"): without the dot the importer raises
# `ValueError: not enough values to unpack`. References come in two kinds that are *not*
# interchangeable - `!KeyOf` resolves only within the same blueprint, `!Find` looks the object up in the
# database - and using the wrong one produces an entry that is simply skipped. And whether a field belongs
# in `identifiers` or in `attrs` decides whether the entry is found again on the next apply: a flow stage
# binding whose `stage` sat in `attrs` was never created at all.
#
# All three were measured mistakes in one night. These constructors make them unrepresentable: model names
# exist once, references are named for what they mean, and the builders place fields where the model wants
# them. The output is byte-identical to the hand-written entries it replaces, which is checked by building
# the blueprint directory before and after and comparing the files.
{ lib }:
let
  # authentik serializes a blueprint to JSON and strips this marker in a sed pass, which is how YAML tags
  # reach the file unquoted.
  marker = value: "@@YAML_TAG@@${value}";

  # The models this repository uses, named once.
  models = {
    metaApplyBlueprint = "authentik_blueprints.metaapplyblueprint";
    role = "authentik_rbac.role";
    user = "authentik_core.user";
    token = "authentik_core.token";
    application = "authentik_core.application";
    flow = "authentik_flows.flow";
    flowStageBinding = "authentik_flows.flowstagebinding";
    passwordStage = "authentik_stages_password.passwordstage";
    identificationStage = "authentik_stages_identification.identificationstage";
    userLoginStage = "authentik_stages_user_login.userloginstage";
    consentStage = "authentik_stages_consent.consentstage";
    proxyProvider = "authentik_providers_proxy.proxyprovider";
    oauth2Provider = "authentik_providers_oauth2.oauth2provider";
    ldapProvider = "authentik_providers_ldap.ldapprovider";
    outpost = "authentik_outposts.outpost";
    policyBinding = "authentik_policies.policybinding";
  };

  refs = {
    # Points at an entry declared in the same blueprint, by its `id`.
    sameBlueprint = id: marker "!KeyOf ${id}";

    # Looks an object up in the database, which is the only reference that works across blueprints.
    byField =
      model: field: value:
      marker "!Find [${model}, [${field}, ${value}]]";

    byName = model: name: refs.byField model "name" name;
    bySlug = model: slug: refs.byField model "slug" slug;

    file = path: marker "!File ${path}";
    context = key: marker "!Context ${key}";
  };

  # A raw entry. Fields that are not needed are omitted rather than set to null: the importer hands the
  # entry to a serializer, and an absent field is not the same as an empty one.
  entry =
    {
      model,
      identifiers ? { },
      attrs ? null,
      id ? null,
      state ? null,
      permissions ? null,
    }:
    lib.filterAttrs (_: value: value != null) {
      inherit
        model
        identifiers
        attrs
        id
        state
        permissions
        ;
    };

  # Tombstone: declares that an object must not exist. A no-op when it is already gone, so it may stay in
  # the file forever, which is what makes removal declarative instead of manual.
  absent =
    { model, identifiers }:
    entry {
      inherit model identifiers;
      state = "absent";
    };

  # Dependencies between blueprints, because authentik guarantees no apply order across files.
  metaApply =
    path:
    entry {
      model = models.metaApplyBlueprint;
      attrs.identifiers.path = path;
    };

  role =
    {
      name,
      id,
      permissions ? [ ],
    }:
    entry {
      inherit id;
      model = models.role;
      identifiers.name = name;
      attrs.permissions = permissions;
    };

  # A service account, and the token it authenticates with. `intent` distinguishes an API token (for the
  # HTTP API) from an app password (for an LDAP bind); authentik rejects the wrong one at the other end.
  serviceAccount =
    {
      username,
      name,
      id,
      roles ? [ ],
    }:
    entry {
      inherit id;
      model = models.user;
      identifiers.username = username;
      attrs = {
        inherit name;
        inherit roles;
        type = "service_account";
      };
    };

  token =
    {
      identifier,
      intent,
      user,
      key,
    }:
    entry {
      model = models.token;
      identifiers.identifier = identifier;
      attrs = {
        inherit intent user key;
      };
    };

  application =
    {
      slug,
      name,
      provider,
      openInNewTab ? false,
    }:
    entry {
      model = models.application;
      identifiers.slug = slug;
      attrs = {
        inherit name provider;
        open_in_new_tab = openInNewTab;
      };
    };

  flow =
    {
      slug,
      id,
      name,
      title,
      designation,
      policyEngineMode ? "any",
      authentication ? null,
      deniedAction ? null,
      layout ? null,
    }:
    entry {
      inherit id;
      model = models.flow;
      identifiers.slug = slug;
      attrs = {
        designation = designation;
        name = name;
        policy_engine_mode = policyEngineMode;
        title = title;
      }
      // lib.optionalAttrs (authentication != null) { inherit authentication; }
      // lib.optionalAttrs (deniedAction != null) { denied_action = deniedAction; }
      // lib.optionalAttrs (layout != null) { inherit layout; };
    };

  # The password stage decides which credentials a bind accepts: `InbuiltBackend` for a real password,
  # `TokenBackend` for an app password.
  passwordStage =
    {
      name,
      id,
      backends,
    }:
    entry {
      inherit id;
      model = models.passwordStage;
      identifiers.name = name;
      attrs = { inherit backends; };
    };

  # The identification stage carries its password stage, which is why the password stage is not bound to
  # the flow directly.
  identificationStage =
    {
      name,
      id,
      passwordStage,
      userFields,
    }:
    entry {
      inherit id;
      model = models.identificationStage;
      identifiers.name = name;
      attrs = {
        password_stage = passwordStage;
        user_fields = userFields;
      };
    };

  userLoginStage =
    {
      name,
      id,
    }:
    entry {
      inherit id;
      model = models.userLoginStage;
      identifiers.name = name;
    };

  consentStage =
    {
      name,
      id,
      mode,
    }:
    entry {
      inherit id;
      model = models.consentStage;
      identifiers.name = name;
      attrs = { inherit mode; };
    };

  # Which stage runs when. All three fields identify the binding, so all three belong in `identifiers`:
  # with `stage` in `attrs` the entry was accepted by the serializer and never created.
  flowStageBinding =
    {
      target,
      stage,
      order,
      evaluateOnPlan ? null,
      reEvaluatePolicies ? null,
    }:
    entry {
      model = models.flowStageBinding;
      identifiers = {
        inherit
          order
          stage
          target
          ;
      };
      attrs =
        lib.optionalAttrs (evaluateOnPlan != null) { evaluate_on_plan = evaluateOnPlan; }
        // lib.optionalAttrs (reEvaluatePolicies != null) { re_evaluate_policies = reEvaluatePolicies; };
    };

  proxyProvider =
    {
      name,
      id,
      externalHost,
      authorizationFlow,
      invalidationFlow,
      mode ? null,
      interceptHeaderAuth ? null,
    }:
    entry {
      inherit id;
      model = models.proxyProvider;
      identifiers.name = name;
      attrs = {
        external_host = externalHost;
        authorization_flow = authorizationFlow;
        invalidation_flow = invalidationFlow;
      }
      // lib.optionalAttrs (mode != null) { inherit mode; }
      // lib.optionalAttrs (interceptHeaderAuth != null) {
        intercept_header_auth = interceptHeaderAuth;
      };
    };

  oauth2Provider =
    {
      name,
      id,
      clientId,
      clientSecret,
      authorizationFlow,
      invalidationFlow,
      redirectUris,
      subMode,
      includeClaimsInIdToken ? true,
    }:
    entry {
      inherit id;
      model = models.oauth2Provider;
      identifiers.name = name;
      attrs = {
        client_id = clientId;
        client_secret = clientSecret;
        authorization_flow = authorizationFlow;
        invalidation_flow = invalidationFlow;
        redirect_uris = redirectUris;
        sub_mode = subMode;
        include_claims_in_id_token = includeClaimsInIdToken;
      };
    };

  # The provider the LDAP outpost serves. Note which flow is which: `authorization_flow` is what the
  # outpost consumes as its *bind* flow (providers/ldap/api.py: `bind_flow_slug` is sourced from it), so it
  # must name a flow that authenticates.
  ldapProvider =
    {
      name,
      id,
      baseDn,
      authenticationFlow,
      authorizationFlow,
      invalidationFlow,
      permissions ? [ ],
    }:
    entry {
      inherit id;
      model = models.ldapProvider;
      identifiers.name = name;
      attrs = {
        authentication_flow = authenticationFlow;
        authorization_flow = authorizationFlow;
        base_dn = baseDn;
        invalidation_flow = invalidationFlow;
      };
      inherit permissions;
    };

  outpost =
    {
      name,
      id,
      type,
      providers,
      config,
      permissions ? [ ],
    }:
    entry {
      inherit id;
      model = models.outpost;
      identifiers.name = name;
      attrs = {
        config = config;
        providers = providers;
        type = type;
        service_connection = null;
      };
      inherit permissions;
    };

  # Policy bindings take exactly one of policy, group or user, and the target plus order identify the row.
  policyBinding =
    {
      target,
      order,
      policy ? null,
      group ? null,
      user ? null,
      enabled ? null,
    }:
    entry {
      model = models.policyBinding;
      identifiers = {
        inherit order target;
      };
      attrs =
        lib.optionalAttrs (enabled != null) { inherit enabled; }
        // lib.optionalAttrs (policy != null) { inherit policy; }
        // lib.optionalAttrs (group != null) { inherit group; }
        // lib.optionalAttrs (user != null) { inherit user; };
    };

  blueprint =
    {
      name,
      entries,
    }:
    {
      version = 1;
      inherit entries;
      metadata = { inherit name; };
    };
in
{
  inherit
    models
    refs
    entry
    absent
    metaApply
    role
    serviceAccount
    token
    application
    flow
    passwordStage
    identificationStage
    userLoginStage
    consentStage
    flowStageBinding
    proxyProvider
    oauth2Provider
    ldapProvider
    outpost
    policyBinding
    blueprint
    ;
}
