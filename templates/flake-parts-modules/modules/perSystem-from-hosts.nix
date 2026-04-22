{ den, ... }:
{

  # Read flake-parts classes from hosts and their includes
  den.relationships.flake-parts-to-host = {
    from = "flake-parts";
    to = "host";
    resolve =
      _:
      map (host: { inherit host; }) (
        builtins.concatMap builtins.attrValues (builtins.attrValues den.hosts)
      );
  };

}
