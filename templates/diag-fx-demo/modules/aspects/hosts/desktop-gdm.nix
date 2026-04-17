{ den, ... }:
{
  den.aspects.desktop-gdm = {
    includes = with den.aspects; [ workstation ];
    meta.handleWith = den.lib.aspects.fx.constraints.substitute den.aspects.regreet den.aspects.gdm;
  };
}
