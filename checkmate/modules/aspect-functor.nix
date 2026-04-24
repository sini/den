{
  lib,
  inputs,
  config,
  den,
  ...
}:
let
  inherit (den.lib) canTake;
  # Access through den.aspects so __functor comes from mergeWithAspectMeta.
  aspect-example = den.aspects.test-functor-example;

  flake.tests."test functor applied with empty attrs" = {
    expr =
      let
        result = aspect-example { };
      in
      {
        hasCtx = result ? __ctx;
        hasScopeHandlers = result ? __scopeHandlers;
        includeCount = builtins.length result.includes;
        hasFoo = result ? nixos;
      };
    expected = {
      hasCtx = true;
      hasScopeHandlers = true;
      includeCount = 8;
      hasFoo = true;
    };
  };

  flake.tests."test functor applied with host only" = {
    expr =
      let
        result = aspect-example { host = 2; };
      in
      {
        ctxHost = result.__ctx.host;
        includeCount = builtins.length result.includes;
      };
    expected = {
      ctxHost = 2;
      includeCount = 8;
    };
  };

  flake.tests."test functor applied with home only" = {
    expr =
      let
        result = aspect-example { home = 2; };
      in
      {
        ctxHome = result.__ctx.home;
      };
    expected = {
      ctxHome = 2;
    };
  };

  flake.tests."test functor applied with home and unknown" = {
    expr =
      let
        result = aspect-example {
          home = 2;
          unknown = 1;
        };
      in
      {
        ctxHome = result.__ctx.home;
        ctxUnknown = result.__ctx.unknown;
      };
    expected = {
      ctxHome = 2;
      ctxUnknown = 1;
    };
  };

  flake.tests."test functor applied with user only" = {
    expr =
      let
        result = aspect-example { user = 2; };
      in
      {
        ctxUser = result.__ctx.user;
      };
    expected = {
      ctxUser = 2;
    };
  };

  flake.tests."test functor applied with user and host" = {
    expr =
      let
        result = aspect-example {
          user = 2;
          host = 1;
        };
      in
      {
        ctxUser = result.__ctx.user;
        ctxHost = result.__ctx.host;
      };
    expected = {
      ctxUser = 2;
      ctxHost = 1;
    };
  };

  flake.tests."test functor applied with host/user/OS" = {
    expr =
      let
        result = aspect-example {
          OS = 0;
          user = 2;
          host = 1;
        };
      in
      {
        ctxOS = result.__ctx.OS;
        ctxUser = result.__ctx.user;
        ctxHost = result.__ctx.host;
      };
    expected = {
      ctxOS = 0;
      ctxUser = 2;
      ctxHost = 1;
    };
  };

in
{
  inherit flake;

  den.aspects.test-functor-example = {
    nixos.foo = 99;
    includes = [
      { nixos.static = 100; }
      (
        { host, ... }:
        {
          nixos.host = host;
        }
      )
      (
        { host, user, ... }:
        {
          nixos.host-user = [
            host
            user
          ];
        }
      )
      (
        {
          OS,
          user,
          host,
          ...
        }:
        {
          nixos.os-user-host = [
            OS
            user
            host
          ];
        }
      )
      (
        { user, ... }:
        {
          nixos.user = user;
        }
      )
      (
        { user, ... }@ctx:
        if canTake.exactly ctx ({ user }: user) then
          { nixos.user-only = user; }
        else
          { nixos.user-only = false; }
      )
      (
        { home, ... }:
        {
          nixos.home = home;
        }
      )
      (_any: { nixos.any = 10; })
    ];
  };
}
