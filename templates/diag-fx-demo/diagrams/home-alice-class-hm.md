# Class Slice: homeManager: home-alice

![homeManager slice](./home-alice-class-hm.mmd.svg)

```mermaid
%%{init: {"elk":{"mergeEdges":true,"nodePlacementStrategy":"BRANDES_KOEPF"},"layout":"elk","theme":"base","themeVariables":{"activationBkgColor":"#313244","activationBorderColor":"#6c7086","actorBkg":"#313244","actorBorder":"#a6adc8","actorLineColor":"#a6adc8","actorTextColor":"#cdd6f4","background":"#1e1e2e","classText":"#cdd6f4","clusterBkg":"#313244","clusterBorder":"#6c7086","edgeLabelBackground":"#1e1e2e","labelBoxBkgColor":"#313244","labelBoxBorderColor":"#a6adc8","labelTextColor":"#cdd6f4","lineColor":"#a6adc8","loopTextColor":"#cdd6f4","mainBkg":"#313244","nodeBkg":"#313244","nodeBorder":"#a6adc8","nodeTextColor":"#cdd6f4","noteBkgColor":"#313244","noteBorderColor":"#6c7086","noteTextColor":"#cdd6f4","pie1":"#f38ba8","pie2":"#fab387","pie3":"#f9e2af","pie4":"#a6e3a1","pie5":"#94e2d5","pie6":"#89b4fa","pie7":"#cba6f7","pie8":"#f2cdcd","pieLegendTextColor":"#cdd6f4","pieOuterStrokeColor":"#6c7086","pieSectionTextColor":"#cdd6f4","pieStrokeColor":"#6c7086","pieTitleTextColor":"#cdd6f4","primaryBorderColor":"#a6adc8","primaryColor":"#313244","primaryTextColor":"#cdd6f4","secondBkg":"#313244","secondaryBorderColor":"#6c7086","secondaryColor":"#313244","secondaryTextColor":"#cdd6f4","sequenceNumberColor":"#1e1e2e","signalColor":"#a6adc8","signalTextColor":"#cdd6f4","tertiaryBorderColor":"#6c7086","tertiaryColor":"#313244","tertiaryTextColor":"#cdd6f4","textColor":"#cdd6f4","titleColor":"#cdd6f4"}}}%%
graph LR
  alice([alice]):::root

  subgraph ctx_home["home"]
  alice_dotfiles["alice-dotfiles"]:::alice_dotfiles_c
  demo_shell["demo-shell"]:::demo_shell_c
  dev_tools["dev-tools"]:::dev_tools_c
  home["home"]:::home_c
  home_bat["home-bat"]:::home_bat_c
  home_dev["home-dev"]:::home_dev_c
  home_firefox["home-firefox"]:::home_firefox_c
  home_git["home-git"]:::home_git_c
  home_productivity["home-productivity"]:::home_productivity_c
  home_slack["home-slack"]:::home_slack_c
  hyprland["hyprland"]:::hyprland_c
  primary_user["primary-user"]:::primary_user_c
  den__provides__primary_user[/"provides/primary-user"\]:::den__provides__primary_user_c
  alice --> alice_dotfiles
  alice --> demo_shell
  alice --> dev_tools
  alice --> home_dev
  alice --> home_productivity
  alice --> hyprland
  alice --> primary_user
  alice --> den__provides__primary_user
  alice_dotfiles --> alice
  alice_dotfiles --> demo_shell
  alice_dotfiles --> dev_tools
  alice_dotfiles --> home_dev
  alice_dotfiles --> home_productivity
  alice_dotfiles --> hyprland
  demo_shell --> alice
  demo_shell --> alice_dotfiles
  demo_shell --> dev_tools
  demo_shell --> home_dev
  demo_shell --> home_productivity
  demo_shell --> hyprland
  den__provides__primary_user --> demo_shell
  dev_tools --> alice
  dev_tools --> alice_dotfiles
  dev_tools --> demo_shell
  dev_tools --> home_dev
  dev_tools --> home_productivity
  dev_tools --> hyprland
  home --> alice
  home_bat --> home_dev
  home_bat --> alice
  home_bat --> alice_dotfiles
  home_bat --> demo_shell
  home_bat --> dev_tools
  home_bat --> home_productivity
  home_bat --> hyprland
  home_dev --> home_bat
  home_dev --> home_git
  home_dev --> alice
  home_dev --> alice_dotfiles
  home_dev --> demo_shell
  home_dev --> dev_tools
  home_dev --> home_productivity
  home_dev --> hyprland
  home_firefox --> home_slack
  home_firefox --> alice
  home_firefox --> alice_dotfiles
  home_firefox --> demo_shell
  home_firefox --> dev_tools
  home_firefox --> home_dev
  home_firefox --> home_productivity
  home_firefox --> hyprland
  home_git --> home_bat
  home_git --> alice
  home_git --> alice_dotfiles
  home_git --> demo_shell
  home_git --> dev_tools
  home_git --> home_dev
  home_git --> home_productivity
  home_git --> hyprland
  home_productivity --> home_firefox
  home_productivity --> home_slack
  home_productivity --> alice
  home_productivity --> alice_dotfiles
  home_productivity --> demo_shell
  home_productivity --> dev_tools
  home_productivity --> home_dev
  home_productivity --> hyprland
  home_slack --> home_productivity
  home_slack --> alice
  home_slack --> alice_dotfiles
  home_slack --> demo_shell
  home_slack --> dev_tools
  home_slack --> home_dev
  home_slack --> hyprland
  hyprland --> alice
  hyprland --> alice_dotfiles
  hyprland --> demo_shell
  hyprland --> dev_tools
  hyprland --> home_dev
  hyprland --> home_productivity
  primary_user --> demo_shell
  end


  classDef root fill:#89b4fa,stroke:#89b4fa,color:#1e1e2e,font-weight:bold
  classDef alice_c fill:#cba6f7,stroke:#cba6f7,color:#1e1e2e,stroke-width:2px
  classDef alice_dotfiles_c fill:#f2cdcd,stroke:#f2cdcd,color:#1e1e2e,stroke-width:2px
  classDef demo_shell_c fill:#cba6f7,stroke:#cba6f7,color:#1e1e2e,stroke-width:2px
  classDef dev_tools_c fill:#f38ba8,stroke:#f38ba8,color:#1e1e2e,stroke-width:2px
  classDef home_c fill:#f38ba8,stroke:#f38ba8,color:#1e1e2e,stroke-dasharray: 3 3,stroke-width:1px
  classDef home_bat_c fill:#f2cdcd,stroke:#f2cdcd,color:#1e1e2e,stroke-width:2px
  classDef home_dev_c fill:#f38ba8,stroke:#f38ba8,color:#1e1e2e,stroke-dasharray: 3 3,stroke-width:1px
  classDef home_firefox_c fill:#f38ba8,stroke:#f38ba8,color:#1e1e2e,stroke-width:2px
  classDef home_git_c fill:#cba6f7,stroke:#cba6f7,color:#1e1e2e,stroke-width:2px
  classDef home_productivity_c fill:#cba6f7,stroke:#cba6f7,color:#1e1e2e,stroke-dasharray: 3 3,stroke-width:1px
  classDef home_slack_c fill:#f2cdcd,stroke:#f2cdcd,color:#1e1e2e,stroke-width:2px
  classDef hyprland_c fill:#cba6f7,stroke:#cba6f7,color:#1e1e2e,stroke-width:2px
  classDef primary_user_c fill:#cba6f7,stroke:#cba6f7,color:#1e1e2e,stroke-dasharray: 3 3,stroke-width:1px
  classDef den__provides__primary_user_c fill:#cba6f7,stroke:#cba6f7,color:#1e1e2e,stroke-dasharray: 3 3,stroke-width:1px
style ctx_home fill:#313244,stroke:#6c7086,stroke-width:2px
style ctx_default fill:#313244,stroke:#6c7086,stroke-width:2px
```
