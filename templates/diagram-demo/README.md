# Diag Demo

Aspect-resolution visualization via `den.lib.diag`.

## Directory Structure

```
diagrams/
  hosts/<host>/    — per-host views (aspects, dag, seq, etc.)
  users/<host>-<user>/ — per-user views
  homes/<home>/    — per-home views
  fleet/           — fleet-wide views
```

## Hosts

| Host     | Pattern                                                       |
| -------- | ------------------------------------------------------------- |
| `laptop` | Baseline workstation, full tree                               |
| `server` | Relay role + provider exclusion + prefix filtering             |
| `devbox` | Dual role + bracket includes + compound exclusions + multi-user |

## Per-Host Views

| View | Description |
| ---- | ----------- |
| `dag` | Full DAG (mermaid + dot + puml) |
| `aspects` | Aspect hierarchy with stage subgraphs |
| `simple` | Simplified (providers folded) |
| `ctx` | Context pipeline stages |
| `stage-seq` | Stage sequence (compact) |
| `stage-seq-full` | Stage sequence (expanded) |
| `policy-seq` | Policy resolution sequence |
| `stage-edges` | Stage topology |
| `providers` | Provider hierarchy |
| `providers-resolved` | Provider → resolved output |
| `adapters` | Constraint impact |
| `decisions` | Structural decisions |
| `declared` | User-declared aspects |
| `class-<name>` | Per-class slice (dynamic) |
| `diff-classes` | nixos vs homeManager diff |
| `c4component` | C4 component view |
| `ir` | Graph IR (JSON) |

## Usage

```bash
nix run .#write-diagrams    # writes all views
```
