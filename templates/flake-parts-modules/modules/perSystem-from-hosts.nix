{ den, ... }:
{

  # Read flake-parts classes from hosts and their includes
  den.policies.flake-parts-to-host = {
    _core = true;
    from = "flake-parts";
    to = "host";
    resolve =
      _:
      map (host: { inherit host; }) (
        builtins.concatMap builtins.attrValues (builtins.attrValues den.hosts)
      );
  };

}
