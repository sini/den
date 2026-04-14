# C4 Container View: desktop-gdm

![C4 Container](./desktop-gdm-c4container.puml.svg)

```plantuml
@startuml
!include <C4/C4_Container>
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


title Container view: desktop-gdm

System_Boundary(desktop_gdm, "desktop-gdm") {
  Container(ctx_host, "host", "nixos", "12 aspects")
  Container(ctx_default, "default", "homeManager+nixos+nixos", "10 aspects")
  Container(ctx_hm_host, "hm-host", "nixos", "4 aspects")
  Container(ctx_hm_user, "hm-user", "nixos", "4 aspects")
  Container(ctx_user, "user", "homeManager+nixos+homeManager+nixos", "10 aspects")
}

@enduml
```
