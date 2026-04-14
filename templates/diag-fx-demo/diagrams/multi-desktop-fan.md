# Fan-In / Fan-Out: multi-desktop

![Fan metrics](./multi-desktop-fan.mmd.svg)

```mermaid
%%{init: {"theme":"base","themeVariables":{"activationBkgColor":"#313244","activationBorderColor":"#6c7086","actorBkg":"#313244","actorBorder":"#a6adc8","actorLineColor":"#a6adc8","actorTextColor":"#cdd6f4","background":"#1e1e2e","classText":"#cdd6f4","clusterBkg":"#313244","clusterBorder":"#6c7086","edgeLabelBackground":"#1e1e2e","labelBoxBkgColor":"#313244","labelBoxBorderColor":"#a6adc8","labelTextColor":"#cdd6f4","lineColor":"#a6adc8","loopTextColor":"#cdd6f4","mainBkg":"#313244","nodeBkg":"#313244","nodeBorder":"#a6adc8","nodeTextColor":"#cdd6f4","noteBkgColor":"#313244","noteBorderColor":"#6c7086","noteTextColor":"#cdd6f4","pie1":"#f38ba8","pie2":"#fab387","pie3":"#f9e2af","pie4":"#a6e3a1","pie5":"#94e2d5","pie6":"#89b4fa","pie7":"#cba6f7","pie8":"#f2cdcd","pieLegendTextColor":"#cdd6f4","pieOuterStrokeColor":"#6c7086","pieSectionTextColor":"#cdd6f4","pieStrokeColor":"#6c7086","pieTitleTextColor":"#cdd6f4","primaryBorderColor":"#a6adc8","primaryColor":"#313244","primaryTextColor":"#cdd6f4","secondBkg":"#313244","secondaryBorderColor":"#6c7086","secondaryColor":"#313244","secondaryTextColor":"#cdd6f4","sequenceNumberColor":"#1e1e2e","signalColor":"#a6adc8","signalTextColor":"#cdd6f4","tertiaryBorderColor":"#6c7086","tertiaryColor":"#313244","tertiaryTextColor":"#cdd6f4","textColor":"#cdd6f4","titleColor":"#cdd6f4"}}}%%
sankey-beta

"workstation","reused",7
"alice","reused",6
"demo-shell","reused",7
"gnome","reused",7
"dev-tools","reused",5
"hyprland","reused",5
"bob","reused",1
"alice/to-hosts","reused",3
"provides/define-user","reused",3
"desktop","reused",3
"provides/hostname","reused",3
"provides/mutual-provider","reused",3
"tailscale","reused",2
"virtualization","reused",3
"virtualization/podman","reused",2
"primary-user","reused",2
"provides/primary-user","reused",2
"regreet","reused",2
"networking","reused",1
"multi-desktop","reused",1
"orchestrates","workstation",6
"orchestrates","alice",6
"orchestrates","demo-shell",4
"orchestrates","gnome",4
"orchestrates","dev-tools",5
"orchestrates","hyprland",4
"orchestrates","bob",7
"orchestrates","alice/to-hosts",4
"orchestrates","provides/define-user",3
"orchestrates","desktop",3
"orchestrates","provides/hostname",3
"orchestrates","provides/mutual-provider",3
"orchestrates","tailscale",3
"orchestrates","virtualization",2
"orchestrates","virtualization/podman",2
"orchestrates","primary-user",2
"orchestrates","provides/primary-user",2
"orchestrates","regreet",2
"orchestrates","networking",2
"orchestrates","multi-desktop",1
```
