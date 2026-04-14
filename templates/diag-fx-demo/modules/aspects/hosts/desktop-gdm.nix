{ den, ... }:
{
  den.aspects.desktop-gdm = {
    includes = with den.aspects; [ workstation ];
    meta.handleWith = den.lib.aspects.fx.substitute den.aspects.regreet den.aspects.gdm;
  };
}
