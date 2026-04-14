# Fleet C4 Context (Mermaid)

![Fleet C4 Mermaid](./fleet-c4context-mmd.mmd.svg)

```mermaid
%%{init: {"theme":"base","themeVariables":{"activationBkgColor":"#313244","activationBorderColor":"#6c7086","actorBkg":"#313244","actorBorder":"#a6adc8","actorLineColor":"#a6adc8","actorTextColor":"#cdd6f4","background":"#1e1e2e","classText":"#cdd6f4","clusterBkg":"#313244","clusterBorder":"#6c7086","edgeLabelBackground":"#1e1e2e","labelBoxBkgColor":"#313244","labelBoxBorderColor":"#a6adc8","labelTextColor":"#cdd6f4","lineColor":"#a6adc8","loopTextColor":"#cdd6f4","mainBkg":"#313244","nodeBkg":"#313244","nodeBorder":"#a6adc8","nodeTextColor":"#cdd6f4","noteBkgColor":"#313244","noteBorderColor":"#6c7086","noteTextColor":"#cdd6f4","pie1":"#f38ba8","pie2":"#fab387","pie3":"#f9e2af","pie4":"#a6e3a1","pie5":"#94e2d5","pie6":"#89b4fa","pie7":"#cba6f7","pie8":"#f2cdcd","pieLegendTextColor":"#cdd6f4","pieOuterStrokeColor":"#6c7086","pieSectionTextColor":"#cdd6f4","pieStrokeColor":"#6c7086","pieTitleTextColor":"#cdd6f4","primaryBorderColor":"#a6adc8","primaryColor":"#313244","primaryTextColor":"#cdd6f4","secondBkg":"#313244","secondaryBorderColor":"#6c7086","secondaryColor":"#313244","secondaryTextColor":"#cdd6f4","sequenceNumberColor":"#1e1e2e","signalColor":"#a6adc8","signalTextColor":"#cdd6f4","tertiaryBorderColor":"#6c7086","tertiaryColor":"#313244","tertiaryTextColor":"#cdd6f4","textColor":"#cdd6f4","titleColor":"#cdd6f4"}}}%%
C4Context
title diag-fx-demo — Fleet Context

Person(alice, "alice")
Person(deploy, "deploy")
Person(bob, "bob")

System(angle_brackets, "angle-brackets", "x86_64-linux")
System(desktop_gdm, "desktop-gdm", "x86_64-linux")
System(devbox, "devbox", "x86_64-linux")
System(laptop, "laptop", "x86_64-linux")
System(mail_relay, "mail-relay", "x86_64-linux")
System(multi_desktop, "multi-desktop", "x86_64-linux")
System(provider_filter, "provider-filter", "x86_64-linux")
System(web_server, "web-server", "x86_64-linux")

Rel(alice, angle_brackets, "homeManager")
Rel(alice, desktop_gdm, "homeManager")
Rel(alice, devbox, "homeManager")
Rel(alice, laptop, "homeManager")
Rel(deploy, mail_relay, "homeManager")
Rel(alice, multi_desktop, "homeManager")
Rel(bob, multi_desktop, "homeManager")
Rel(deploy, provider_filter, "homeManager")
Rel(deploy, web_server, "homeManager")
```
