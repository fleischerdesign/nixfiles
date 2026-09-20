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

  # Ownership marker. Every blueprint this repository owns carries it; the apply reads it to separate our
  # declarations from authentik's own defaults, whose objects an administrator may edit in the interface
  # without a deploy reverting the edit. The name and value live here once so the apply cannot disagree
  # with the files it selects.
  ownerLabelName = "vyrx";
  ownerLabelValue = "owned";

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
    # Retained only for the "Authorize LDAP consumer" tombstone in the consumers blueprint; there is no
    # builder for it any more (the authorization-flow experiment that used one was removed).
    consentStage = "authentik_stages_consent.consentstage";
    proxyProvider = "authentik_providers_proxy.proxyprovider";
    oauth2Provider = "authentik_providers_oauth2.oauth2provider";
    ldapProvider = "authentik_providers_ldap.ldapprovider";
    outpost = "authentik_outposts.outpost";
    policyBinding = "authentik_policies.policybinding";
    # The base the binding points at. A Flow has two identities - its own `flow_uuid` and the
    # `PolicyBindingModel.pbm_uuid` a PolicyBinding's `target` is keyed on - so a tombstone has to
    # reference the base model, never the flow itself.
    policyBindingModel = "authentik_policies.policybindingmodel";
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

    # A `PolicyBinding.target` is keyed on the PolicyBindingModel's `pbm_uuid`, never on the concrete
    # object's own pk: a Flow carries both `flow_uuid` and `pbm_uuid`, and `bySlug` on the flow returns
    # the former, so a binding wrote a target that matched nothing and was neither created nor removed.
    # Resolve through the base model instead; `child` is the reverse accessor (`flow`, `application`, ...).
    policyTargetBySlug = child: slug: refs.byField models.policyBindingModel "${child}__slug" slug;

    file = path: marker "!File ${path}";
    env = name: marker "!Env ${name}";
    context = key: marker "!Context ${key}";
  };

  # A raw entry. Fields that are not needed are omitted rather than set to null: the importer hands the
  # entry to a serializer, and an absent field is not the same as an empty one. `identifiers` is dropped
  # when empty because no model takes an empty identifier set, while `attrs = { }` is meaningful - a stage
  # binding with no extra fields is exactly that.
  entry =
    {
      model,
      identifiers ? { },
      attrs ? null,
      id ? null,
      state ? null,
      permissions ? null,
    }:
    lib.filterAttrs (name: value: value != null && !(name == "identifiers" && value == { })) {
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

  # Dependencies between blueprints, because authentik guarantees no apply order across files and documents
  # the meta model for exactly this: "If you have dependencies between blueprints, you should use meta
  # models to make sure that objects are created in the correct order."
  #
  # The identifiers of that meta model are "key-value attributes used to match the blueprint instance", so
  # there are two ways to name the dependency: the path of a file-based blueprint (the upstream ones) and the
  # instance name of a generated one. Both exist here, and mixing them up would be silent - the entry would
  # match nothing, and `required` defaults to true, so it would fail the whole blueprint rather than the
  # dependency alone.
  metaApply =
    path:
    entry {
      model = models.metaApplyBlueprint;
      attrs.identifiers.path = path;
    };

  metaApplyInstance =
    name:
    entry {
      model = models.metaApplyBlueprint;
      attrs.identifiers.name = name;
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
        # Two measured facts keep a SOPS-backed token in step with the outpost that reads it once at
        # start. `expiring = false` is the one that stops the loss: `Token.expire_action` rotates
        # **every** api-intent token whose `expires` has passed, regardless of `managed`, which rotated
        # these keys every 30 minutes (measured: `secret_rotate` events for both outpost tokens; an
        # app_password expires instead, which would have broken the Jellyfin bind at the same interval).
        # `managed = null` keeps authentik from claiming ownership; the serializer accepts only a
        # non-empty string or SQL NULL for it (a boolean is rejected as "not a valid string", the
        # 2026-09-20 failure; `""` is rejected as blank).
        managed = null;
        expiring = false;
      };
    };

  application =
    {
      slug,
      name,
      provider,
      openInNewTab ? false,
      group ? null,
      metaLaunchUrl ? null,
    }:
    entry {
      model = models.application;
      identifiers.slug = slug;
      attrs = {
        inherit name provider;
        open_in_new_tab = openInNewTab;
      }
      // lib.optionalAttrs (group != null) { inherit group; }
      // lib.optionalAttrs (metaLaunchUrl != null) { meta_launch_url = metaLaunchUrl; };
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
        # Declared, not inherited. `mfa_support` defaults to true in the model and the database carried
        # true while nothing in the repository named it - an undeclared dependency (identity.md §11.4).
        # Code-based MFA is meaningless for a bind account, and declaring the value keeps a fresh
        # install from silently depending on the model default.
        mfa_support = false;
        # Both default to `direct`; declared so their origin is the repository, not a model default
        # an upgrade may change.
        bind_mode = "direct";
        search_mode = "direct";
      };
      inherit permissions;
    };

  outpost =
    {
      name,
      id,
      type ? null,
      providers,
      config,
      permissions ? [ ],
    }:
    entry {
      inherit id;
      model = models.outpost;
      identifiers.name = name;
      attrs = {
        inherit config providers;
      }
      // lib.optionalAttrs (type != null) { inherit type; }
      # Only a non-embedded outpost carries a service connection field; authentik's own embedded
      # outpost has neither a type nor a connection.
      // lib.optionalAttrs (type != null) { service_connection = null; };
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
      metadata = {
        inherit name;
        labels.${ownerLabelName} = ownerLabelValue;
      };
    };
in
{
  inherit
    ownerLabelName
    ownerLabelValue
    models
    refs
    entry
    absent
    metaApply
    metaApplyInstance
    role
    serviceAccount
    token
    application
    flow
    passwordStage
    identificationStage
    userLoginStage
    flowStageBinding
    proxyProvider
    oauth2Provider
    ldapProvider
    outpost
    policyBinding
    blueprint
    ;
}
