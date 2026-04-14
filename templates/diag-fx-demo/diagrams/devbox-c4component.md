# C4 Component View: devbox

![C4 Component](./devbox-c4component.puml.svg)

```plantuml
@startuml
!include <C4/C4_Component>
skinparam backgroundColor #1e1e2e
skinparam defaultFontColor #cdd6f4
skinparam defaultFontName "JetBrains Mono,monospace"
skinparam arrowColor #a6adc8
skinparam arrowFontColor #cdd6f4
skinparam PersonBackgroundColor #313244
skinparam PersonBorderColor #a6adc8
skinparam PersonFontColor #cdd6f4
skinparam SystemBackgroundColor #313244
skinparam SystemBorderColor #a6adc8
skinparam SystemFontColor #cdd6f4
skinparam ContainerBackgroundColor #313244
skinparam ContainerBorderColor #a6adc8
skinparam ContainerFontColor #cdd6f4
skinparam ComponentBackgroundColor #313244
skinparam ComponentBorderColor #a6adc8
skinparam ComponentFontColor #cdd6f4
skinparam BoundaryBackgroundColor #313244
skinparam BoundaryBorderColor #6c7086
skinparam BoundaryFontColor #cdd6f4
skinparam RectangleBackgroundColor #313244
skinparam RectangleBorderColor #a6adc8
skinparam RectangleFontColor #cdd6f4


title Component view: devbox

System_Boundary(devbox, "devbox") {
  Container_Boundary(host, "host") {
    Component(monitoring__alerting, "monitoring/alerting", "nixos")
    Component(backup, "backup", "")
    Component(desktop, "desktop", "nixos")
    Component(virtualization__docker, "virtualization/docker", "nixos")
    Component(monitoring, "monitoring", "nixos")
    Component(networking, "networking", "nixos")
    Component(monitoring__nginx_exporter, "monitoring/nginx-exporter", "nixos")
    Component(monitoring__node_exporter, "monitoring/node-exporter", "nixos")
    Component(virtualization__podman, "virtualization/podman", "nixos")
    Component(regreet, "regreet", "nixos")
    Component(server, "server", "")
    Component(tailscale, "tailscale", "nixos")
    Component(virtualization, "virtualization", "nixos")
    Component(workstation, "workstation", "")
}
  Container_Boundary(c4_default, "default") {
    Component(den__provides__define_user, "provides/define-user", "")
    Component(den__provides__hostname, "provides/hostname", "")
    Component(den__provides__mutual_provider, "provides/mutual-provider", "")
    Component(alice__to_hosts, "alice/to-hosts", "nixos")
}
  Container_Boundary(user, "user") {
    Component(alice, "alice", "homeManager+nixos")
    Component(demo_shell, "demo-shell", "homeManager")
    Component(dev_tools, "dev-tools", "homeManager")
    Component(hyprland, "hyprland", "homeManager+nixos")
    Component(primary_user, "primary-user", "")
    Component(den__provides__primary_user, "provides/primary-user", "nixos")
}
}

Rel(alice, demo_shell, "includes")
Rel(alice, dev_tools, "includes")
Rel(alice, hyprland, "includes")
Rel(alice, primary_user, "includes")
Rel(alice, den__provides__primary_user, "includes")
Rel(alice__to_hosts, den__provides__define_user, "includes")
Rel(alice__to_hosts, den__provides__hostname, "includes")
Rel(alice__to_hosts, den__provides__mutual_provider, "includes")
Rel(backup, server, "includes")
Rel(backup, workstation, "includes")
Rel(den__provides__mutual_provider, den__provides__define_user, "includes")
Rel(den__provides__mutual_provider, den__provides__hostname, "includes")
Rel(den__provides__mutual_provider, alice__to_hosts, "includes")
Rel(den__provides__hostname, den__provides__define_user, "includes")
Rel(den__provides__define_user, den__provides__hostname, "includes")
Rel(den__provides__define_user, den__provides__mutual_provider, "includes")
Rel(den__provides__hostname, den__provides__mutual_provider, "includes")
Rel(den__provides__define_user, alice__to_hosts, "includes")
Rel(den__provides__hostname, alice__to_hosts, "includes")
Rel(demo_shell, hyprland, "includes")
Rel(demo_shell, alice, "includes")
Rel(demo_shell, dev_tools, "includes")
Rel(den__provides__primary_user, demo_shell, "includes")
Rel(desktop, backup, "includes")
Rel(desktop, server, "includes")
Rel(desktop, workstation, "includes")
Rel(desktop, regreet, "includes")
Rel(desktop, virtualization, "includes")
Rel(dev_tools, alice, "includes")
Rel(dev_tools, demo_shell, "includes")
Rel(dev_tools, hyprland, "includes")
Rel(monitoring, backup, "includes")
Rel(monitoring__alerting, backup, "includes")
Rel(monitoring__nginx_exporter, backup, "includes")
Rel(monitoring__node_exporter, backup, "includes")
Rel(networking, backup, "includes")
Rel(regreet, backup, "includes")
Rel(server, backup, "includes")
Rel(tailscale, backup, "includes")
Rel(virtualization, backup, "includes")
Rel(virtualization__docker, backup, "includes")
Rel(virtualization__podman, backup, "includes")
Rel(workstation, backup, "includes")
Rel(monitoring, server, "includes")
Rel(monitoring__alerting, server, "includes")
Rel(monitoring__nginx_exporter, server, "includes")
Rel(monitoring__node_exporter, server, "includes")
Rel(networking, server, "includes")
Rel(regreet, server, "includes")
Rel(tailscale, server, "includes")
Rel(virtualization, server, "includes")
Rel(virtualization__docker, server, "includes")
Rel(virtualization__podman, server, "includes")
Rel(workstation, server, "includes")
Rel(monitoring, workstation, "includes")
Rel(monitoring__alerting, workstation, "includes")
Rel(monitoring__nginx_exporter, workstation, "includes")
Rel(monitoring__node_exporter, workstation, "includes")
Rel(networking, workstation, "includes")
Rel(regreet, workstation, "includes")
Rel(server, workstation, "includes")
Rel(tailscale, workstation, "includes")
Rel(virtualization, workstation, "includes")
Rel(virtualization__docker, workstation, "includes")
Rel(virtualization__podman, workstation, "includes")
Rel(hyprland, dev_tools, "includes")
Rel(hyprland, alice, "includes")
Rel(hyprland, demo_shell, "includes")
Rel(monitoring, monitoring__node_exporter, "includes")
Rel(monitoring__alerting, tailscale, "includes")
Rel(monitoring__nginx_exporter, monitoring__alerting, "includes")
Rel(monitoring__node_exporter, monitoring__nginx_exporter, "includes")
Rel(networking, monitoring, "includes")
Rel(networking, tailscale, "includes")
Rel(primary_user, demo_shell, "includes")
Rel(regreet, desktop, "includes")
Rel(server, monitoring__alerting, "includes")
Rel(server, virtualization__docker, "includes")
Rel(server, monitoring, "includes")
Rel(server, networking, "includes")
Rel(server, monitoring__nginx_exporter, "includes")
Rel(server, monitoring__node_exporter, "includes")
Rel(server, tailscale, "includes")
Rel(server, virtualization, "includes")
Rel(tailscale, desktop, "includes")
Rel(tailscale, regreet, "includes")
Rel(tailscale, virtualization, "includes")
Rel(virtualization, virtualization__docker, "includes")
Rel(virtualization, virtualization__podman, "includes")
Rel(workstation, desktop, "includes")
Rel(workstation, networking, "includes")
Rel(workstation, virtualization__podman, "includes")
Rel(workstation, tailscale, "includes")
Rel(workstation, virtualization, "includes")
@enduml
```
