{ den, ... }:
{
  den.aspects.alice = {
    includes = [ den._.primary-user ];
    user.extraGroups = [
      "audio"
      "video"
    ];
  };
}
