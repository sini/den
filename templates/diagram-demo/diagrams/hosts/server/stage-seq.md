# Stage Sequence: server

![Stage sequence](./stage-seq.mmd.svg)

```mermaid
%%{init: {"theme":"base","themeVariables":{"activationBkgColor":"#313244","activationBorderColor":"#6c7086","actorBkg":"#313244","actorBorder":"#a6adc8","actorLineColor":"#a6adc8","actorTextColor":"#cdd6f4","background":"#1e1e2e","classText":"#cdd6f4","clusterBkg":"#313244","clusterBorder":"#6c7086","edgeLabelBackground":"#1e1e2e","labelBoxBkgColor":"#313244","labelBoxBorderColor":"#a6adc8","labelTextColor":"#cdd6f4","lineColor":"#a6adc8","loopTextColor":"#cdd6f4","mainBkg":"#313244","nodeBkg":"#313244","nodeBorder":"#a6adc8","nodeTextColor":"#cdd6f4","noteBkgColor":"#313244","noteBorderColor":"#6c7086","noteTextColor":"#cdd6f4","pie1":"#f38ba8","pie2":"#fab387","pie3":"#f9e2af","pie4":"#a6e3a1","pie5":"#94e2d5","pie6":"#89b4fa","pie7":"#cba6f7","pie8":"#f2cdcd","pieLegendTextColor":"#cdd6f4","pieOuterStrokeColor":"#6c7086","pieSectionTextColor":"#cdd6f4","pieStrokeColor":"#6c7086","pieTitleTextColor":"#cdd6f4","primaryBorderColor":"#a6adc8","primaryColor":"#313244","primaryTextColor":"#cdd6f4","secondBkg":"#313244","secondaryBorderColor":"#6c7086","secondaryColor":"#313244","secondaryTextColor":"#cdd6f4","sequenceNumberColor":"#1e1e2e","signalColor":"#a6adc8","signalTextColor":"#cdd6f4","tertiaryBorderColor":"#6c7086","tertiaryColor":"#313244","tertiaryTextColor":"#cdd6f4","textColor":"#cdd6f4","titleColor":"#cdd6f4"}}}%%
sequenceDiagram
    participant host as host
    participant p_default as default
    participant hm_host as hm-host
    participant hm_user as hm-user
    participant user as user

    host ->> p_default: resolve
    host ->> hm_host: resolve
    hm_host ->> hm_user: resolve
    host ->> user: resolve

    hm_host -->> hm_user: hm-host-to-hm-user
    host -->> p_default: host-to-default
    host -->> hjem_host: host-to-hjem-host
    host -->> hm_host: host-to-hm-host
    host -->> maid_host: host-to-maid-host
    host -->> user: host-to-users
    host -->> wsl_host: host-to-wsl-host
    user -->> p_default: user-to-default

    activate host
    host ->> host: backup(home, host, user)
    host ->> host: host/resolve(host)(host)
    host ->> host: server(host)
    deactivate host
    Note over host: monitoring/alerting, default, virtualization/docker, hm-host<br/>host/resolve(<anon>:0), monitoring, networking, monitoring/nginx-exporter<br/>monitoring/node-exporter, tailscale, user, virtualization

    activate p_default
    p_default ->> p_default: provides/default/resolve(hostname):den/provides(host)
    p_default ->> p_default: default/resolve(server)(host)
    deactivate p_default
    Note over p_default: default/resolve(default), provides/default/resolve(define-user):den/provides, provides/default/resolve(mutual-provider):den/provides, provides/define-user<br/>provides/hostname, provides/mutual-provider

    activate hm_host
    hm_host ->> hm_host: hm-host/hm-host(host)
    hm_host ->> hm_host: hm-host/resolve(hm-host)(host, user)
    hm_host ->> hm_host: provides/hm-host/resolve(hm-host):den/provides(host, user)
    deactivate hm_host
    Note over hm_host: hm-host/resolve(server), hm-user

    activate hm_user
    hm_user ->> hm_user: hm-user/hm-user(host, user)
    deactivate hm_user
    Note over hm_user: hm-user/resolve(hm-user)

    activate user
    user ->> user: deploy(host, user)
    user ->> user: user/resolve(user)(host, user)
    deactivate user
    Note over user: user/resolve(deploy,server)
```
