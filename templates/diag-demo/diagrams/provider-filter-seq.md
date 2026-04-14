# Resolution Sequence: provider-filter

![Sequence](./provider-filter-seq.mmd.svg)

```mermaid
%%{init: {"theme":"base","themeVariables":{"activationBkgColor":"#313244","activationBorderColor":"#6c7086","actorBkg":"#313244","actorBorder":"#a6adc8","actorLineColor":"#a6adc8","actorTextColor":"#cdd6f4","background":"#1e1e2e","classText":"#cdd6f4","clusterBkg":"#313244","clusterBorder":"#6c7086","edgeLabelBackground":"#1e1e2e","labelBoxBkgColor":"#313244","labelBoxBorderColor":"#a6adc8","labelTextColor":"#cdd6f4","lineColor":"#a6adc8","loopTextColor":"#cdd6f4","mainBkg":"#313244","nodeBkg":"#313244","nodeBorder":"#a6adc8","nodeTextColor":"#cdd6f4","noteBkgColor":"#313244","noteBorderColor":"#6c7086","noteTextColor":"#cdd6f4","pie1":"#f38ba8","pie2":"#fab387","pie3":"#f9e2af","pie4":"#a6e3a1","pie5":"#94e2d5","pie6":"#89b4fa","pie7":"#cba6f7","pie8":"#f2cdcd","pieLegendTextColor":"#cdd6f4","pieOuterStrokeColor":"#6c7086","pieSectionTextColor":"#cdd6f4","pieStrokeColor":"#6c7086","pieTitleTextColor":"#cdd6f4","primaryBorderColor":"#a6adc8","primaryColor":"#313244","primaryTextColor":"#cdd6f4","secondBkg":"#313244","secondaryBorderColor":"#6c7086","secondaryColor":"#313244","secondaryTextColor":"#cdd6f4","sequenceNumberColor":"#1e1e2e","signalColor":"#a6adc8","signalTextColor":"#cdd6f4","tertiaryBorderColor":"#6c7086","tertiaryColor":"#313244","tertiaryTextColor":"#cdd6f4","textColor":"#cdd6f4","titleColor":"#cdd6f4"}}}%%
sequenceDiagram
    participant host as host { host }
    participant p_default as default { host }
    participant hm_host as hm-host { host }
    participant hm_user as hm-user { host, user }
    participant user as user { host, user }

    host ->> p_default: resolve
    host ->> hm_host: resolve
    hm_host ->> hm_user: resolve
    host ->> user: resolve
    user ->> p_default: resolve

    Note over host: monitoring/alerting, backup, virtualization/docker, host/aspect(host), host/cross-provide(<anon>), host/self-provide(host), +8 more
    Note over p_default: default, default/aspect(default), provides/default/aspect(default):den/provides, default/cross-provide(host), default/cross-provide(user), default/self-provide(default), +3 more
    Note over hm_host: hm-host, hm-host/aspect(hm-host), hm-host/cross-provide(host), hm-host/self-provide(hm-host)
    Note over hm_user: hm-user, hm-user/aspect(hm-user), hm-user/cross-provide(hm-host), hm-user/self-provide(hm-user)
    Note over user: deploy, user, user/aspect(user), user/cross-provide(host), user/self-provide(user)
```
