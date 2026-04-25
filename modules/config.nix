{ lib, ... }:
{
  options.den.config = {
    classModuleCollisionPolicy = lib.mkOption {
      description = ''
        How to handle collisions between den context args and module-system args
        in flat-form class modules.

        - "error": throw on collision (default)
        - "class-wins": module-system value wins, den value dropped
        - "den-wins": den value wins, module-system value shadowed
      '';
      type = lib.types.enum [
        "error"
        "class-wins"
        "den-wins"
      ];
      default = "error";
    };
  };
}
