# C4 Container (Mermaid): devbox

![C4 Container Mermaid](./devbox-c4container-mmd.mmd.svg)

```mermaid
%%{init: {"theme":"base","themeVariables":{"activationBkgColor":"#313244","activationBorderColor":"#6c7086","actorBkg":"#313244","actorBorder":"#a6adc8","actorLineColor":"#a6adc8","actorTextColor":"#cdd6f4","background":"#1e1e2e","classText":"#cdd6f4","clusterBkg":"#313244","clusterBorder":"#6c7086","edgeLabelBackground":"#1e1e2e","labelBoxBkgColor":"#313244","labelBoxBorderColor":"#a6adc8","labelTextColor":"#cdd6f4","lineColor":"#a6adc8","loopTextColor":"#cdd6f4","mainBkg":"#313244","nodeBkg":"#313244","nodeBorder":"#a6adc8","nodeTextColor":"#cdd6f4","noteBkgColor":"#313244","noteBorderColor":"#6c7086","noteTextColor":"#cdd6f4","pie1":"#f38ba8","pie2":"#fab387","pie3":"#f9e2af","pie4":"#a6e3a1","pie5":"#94e2d5","pie6":"#89b4fa","pie7":"#cba6f7","pie8":"#f2cdcd","pieLegendTextColor":"#cdd6f4","pieOuterStrokeColor":"#6c7086","pieSectionTextColor":"#cdd6f4","pieStrokeColor":"#6c7086","pieTitleTextColor":"#cdd6f4","primaryBorderColor":"#a6adc8","primaryColor":"#313244","primaryTextColor":"#cdd6f4","secondBkg":"#313244","secondaryBorderColor":"#6c7086","secondaryColor":"#313244","secondaryTextColor":"#cdd6f4","sequenceNumberColor":"#1e1e2e","signalColor":"#a6adc8","signalTextColor":"#cdd6f4","tertiaryBorderColor":"#6c7086","tertiaryColor":"#313244","tertiaryTextColor":"#cdd6f4","textColor":"#cdd6f4","titleColor":"#cdd6f4"}}}%%
C4Container
title Container view: devbox

System_Boundary(devbox, "devbox") {
  Container(ctx_host, "host { host }", "nixos", "17 aspects")
  Container(ctx_default, "default { host }", "homeManager+nixos+nixos", "10 aspects")
  Container(ctx_hm_host, "hm-host { host }", "nixos", "4 aspects")
  Container(ctx_hm_user, "hm-user { host, user }", "nixos", "4 aspects")
  Container(ctx_user, "user { host, user }", "homeManager+nixos+homeManager+nixos", "10 aspects")
}

Rel(ctx_host, ctx_default, "resolve")
Rel(ctx_host, ctx_hm_host, "resolve")
Rel(ctx_hm_host, ctx_hm_user, "resolve")
Rel(ctx_host, ctx_user, "resolve")
Rel(ctx_user, ctx_default, "resolve")
```
