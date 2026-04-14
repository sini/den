{ den, ... }:
{
  den.aspects.desktop-gdm = {
    includes = with den.aspects; [ workstation ];
    meta.adapter = den.lib.aspects.fx.substituteAspect den.aspects.regreet den.aspects.gdm;
  };
}
