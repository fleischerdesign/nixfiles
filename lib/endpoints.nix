# One rule for the name of an endpoint across the fleet.
#
# The same string is the blueprint's application slug, the Prometheus `service` label and the portal
# tile id. Three consumers that must agree on it are three reasons to state it once: a rename that
# changed one of them would leave the others pointing at a series or an object that no longer exists -
# silently, because each of them still evaluates.
_: {
  endpointName =
    svcName: epName: if epName == "default" || epName == "web" then svcName else "${svcName}-${epName}";
}
