# fx-instantiate-edges suite — the per-host re-walk's surfaced edge set
# (nix/lib/aspects/fx/edges/instantiate-edges.nix mkInstantiateEdges). A pure
# projection of the inputs resolve.nix mkInstantiateArgs already derives:
# default-fold merge @ hostScopeId + provides over subtreeProvides + routes over
# subtreeRoutes. Task 16 builds + tests the function; a later task (16.3)
# collects its output into a unified edge set.
#
# `just ci fx-instantiate-edges` runs this suite.
{ denTest, lib, ... }:
{
  flake.tests.fx-instantiate-edges = {

    # A host(scope "host=igloo") + user(scope "host=igloo/user=tux") topology.
    # The host carries a nixos bucket (perScope), and a user→host route nests the
    # user's homeManager content into the host's nixos at a path. The surfaced
    # edge set must contain BOTH the host nixos default-fold merge edge (target
    # root = host, mode "merge", path []) AND the user→host route edge (target
    # class "nixos", mode "nest").
    test-host-user-edge-set = denTest (
      { den, ... }:
      let
        edges = den.lib.aspects.fx.edges.instantiateSubtree;

        hostSid = "host=igloo";
        userSid = "host=igloo/user=tux";

        # id_hash-bearing entity records so scopeName renders "<kind>:<id_hash>"
        # (the unified normalization the real per-host walk uses).
        scopeContexts = {
          ${hostSid} = {
            host = {
              name = "igloo";
              id_hash = "hh";
            };
          };
          ${userSid} = {
            host = {
              name = "igloo";
              id_hash = "hh";
            };
            user = {
              name = "tux";
              id_hash = "uu";
            };
          };
        };
        scopeEntityKind = {
          ${hostSid} = "host";
          ${userSid} = "user";
        };
        scopeName = (import ../../../../nix/lib/aspects/fx/edges/edge.nix { inherit lib; }).scopeName {
          inherit scopeEntityKind scopeContexts;
        };

        result = edges.mkInstantiateEdges {
          name = scopeName;
          scopeParent = {
            ${userSid} = hostSid;
          };
          scopeIsolated = { };
          hostScopeId = hostSid;
          subtreeScopeIds = [
            hostSid
            userSid
          ];
          # The host carries a nixos bucket → a nixos default-fold merge edge.
          perScope = {
            ${hostSid} = {
              nixos = [ { config = { }; } ];
            };
          };
          subtreeProvides = { };
          # A user→host route: homeManager source nested into nixos at a path.
          subtreeRoutes = {
            ${userSid} = [
              {
                fromClass = "homeManager";
                intoClass = "nixos";
                sourceScopeId = userSid;
                path = [
                  "home-manager"
                  "users"
                  "tux"
                ];
              }
            ];
          };
        };

        hostFold = lib.filter (
          e:
          e.mode == "merge"
          && e.path == [ ]
          && e.source ? collected
          && e.source.collected.scope == scopeName hostSid
          && e.source.collected.class == "nixos"
          && e.target ? root
          && e.target.root == scopeName hostSid
          && e.target.class == "nixos"
        ) result;

        userRoute = lib.filter (
          e:
          e.mode == "nest"
          && e.target.class == "nixos"
          &&
            e.path == [
              "home-manager"
              "users"
              "tux"
            ]
        ) result;
      in
      {
        expr = {
          hostFoldCount = builtins.length hostFold;
          userRouteCount = builtins.length userRoute;
        };
        expected = {
          hostFoldCount = 1;
          userRouteCount = 1;
        };
      }
    );

  };
}
