{ den, lib, ... }:
let
  ctx.host.description = ''
    ## Context: den.ctx.host{host}

    Host context stage configures an OS

    A {host} context fan-outs into many {host,user} contexts.

    A `den.ctx.host{host}` transitions unconditionally into `den.ctx.default{host}`

    A `den.ctx.host{host}` obtains OS configuration nixos/darwin by using `fixedTo{host} host-aspect`.
    fixedTo takes:
      -  host-aspect's owned attrs
      -  static includes like { nixos.foo = ... } or ({ class, aspect-chain }: { nixos.foo = ...; })
      -  atLeast{host} parametric includes like ({ host }: { nixos.foo = ...; })
  '';

  # includes triggers ctxTreeType leaf detection so the node remains
  # a ctxSubmodule (callable via __functor) during transition.
  ctx.host.includes = [ ];
in
{
  den.ctx = ctx;
  den.stages.host.provides.host = { host }: host.aspect;
}
