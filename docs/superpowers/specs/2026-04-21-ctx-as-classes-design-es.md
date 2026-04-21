# den.ctx como Registro de Clases

**Fecha:** 2026-04-21
**Rama:** feat/rm-legacy
**Estado:** Borrador — pendiente de revisión por pares

## Problema

`den.ctx` está sobrecargado. Un solo nodo `den.ctx.host` sirve simultáneamente como:

1. **Definición de clase** — qué significa "host" estructuralmente (transiciones, proveedores, forma del esquema)
2. **Registro de esquema** — `den.ctx ? ${kind}` controla si un tipo de entidad participa en la resolución de aspectos
3. **Vinculador de alcance** — `ctxApply` estampa `__scopeHandlers` para que las funciones paramétricas reciban argumentos `{ host }`
4. **Fábrica de aspectos** — llamar a `den.ctx.host { host = config; }` produce un attrset con forma de aspecto para el pipeline

Esta conflación causa:
- **~24 nodos ctx** donde solo 3-4 representan tipos de entidad reales; el resto son andamiaje intermedio del pipeline (`hm-host`, `hm-user`, `flake-system`, `flake-os`, etc.)
- **`into` en cada nodo** — la topología de transiciones integrada en las definiciones de clase, haciendo que las clases sean responsables de conocer sus relaciones
- **`provides` con doble función** — auto-identidad (`provides.host = {host}: host.aspect`) y enrutamiento entre clases (`provides.hm-user = forwardToHost {...}`) en el mismo mecanismo
- **Sin lugar para definir la forma de una entidad** (opciones como `name`, `system`, `class`, `users`) junto a su comportamiento en el pipeline — estas viven en archivos separados (`nix/lib/types.nix` vs `modules/context/*.nix`)

Posición de Vic: eliminar `den.ctx` por completo.
Posición de Sini: el rol de definición de clase es real y necesario; mantener el nombre por compatibilidad retroactiva pero tratar los nodos como clases.

## Diseño: ctx = Registro de Clases

### Principio Fundamental

`den.ctx.host` es una **definición de clase**, no un nodo del pipeline de contexto. Una clase define:
- Qué forma estructural tienen las entidades de este tipo (opciones)
- Qué claves de capacidad reconoce (nixos, darwin, homeManager, etc.)

Todo lo demás — transiciones, reenvío, enrutamiento de salida — se mueve fuera de la definición de clase a sistemas diseñados para ese propósito.

### Qué Permanece en den.ctx

Cada entrada en `den.ctx` es una clase. El registro se reduce de ~24 nodos a los tipos de entidad reales:

| Clase | Propósito |
|-------|-----------|
| `host` | Entidad de configuración de SO (nixos/darwin/systemManager) |
| `user` | Entidad de cuenta de usuario (anidada bajo host) |
| `home` | Entidad de configuración home-manager independiente |
| `default` | Objetivo base de aspecto (recibe includes incondicionales) |

Una definición de clase contiene:
- **Forma del esquema** — las opciones de la entidad (name, system, class, aspect, etc.), actualmente dispersas en `nix/lib/types.nix`
- **Claves de capacidad** — qué claves de clase (nixos, darwin, homeManager) reconoce este tipo de entidad, detectadas estructuralmente según el diseño de capacidades
- **Metadatos** — descripción, documentación

Una definición de clase NO contiene:
- Transiciones `into` (se mueven a políticas de relación)
- Declaraciones `provides` (la auto-identidad se vuelve implícita; el enrutamiento entre clases se mueve a relaciones)
- Magia de `__functor` (ctxApply se simplifica a solo vinculación de alcance)

### Qué Se Mueve a Políticas de Relación

Cada definición `into` actual sigue un patrón: enumerar entidades, construir diccionario de contexto. Estas son declaraciones de relación, no comportamiento de clase.

**Antes (en la clase):**
```nix
den.ctx.host.into.user = { host }:
  map (user: { inherit host user; }) (lib.attrValues host.users);
```

**Después (política de relación):**
```nix
den.relationships.host-users = {
  from = "host";
  to = "user";
  resolve = { host }:
    map (user: { inherit host user; }) (lib.attrValues host.users);
};
```

La clase no conoce sus transiciones. Las relaciones se declaran externamente y el pipeline las recorre.

### Qué Se Vuelve Implícito

**Provides de auto-identidad** — Cada clase actualmente declara `provides.X = {x}: x.aspect`. Esto es universal y mecánico. Bajo el modelo de clases, el aspecto de una entidad ES su identidad. No se necesita declaración; el pipeline lo infiere.

**`ctxApply` se simplifica** — Hoy preserva `into`, `provides`, estampa `__ctx` + `__scopeHandlers`. Después: solo estampa manejadores de alcance (vinculando valores de entidad como argumentos paramétricos). No hay `into` ni `provides` que transportar.

### Qué Se Elimina

Los **nodos ctx intermedios** desaparecen por completo:

| Nodo | Rol Actual | Reemplazo |
|------|-----------|-----------|
| `hm-host`, `hm-user` | Andamiaje del pipeline de home-manager | Política de relación con activación `homeEnv` |
| `maid-host`, `maid-user` | Andamiaje del pipeline de maid | Ídem |
| `hjem-host`, `hjem-user` | Andamiaje del pipeline de hjem | Ídem |
| `wsl-host` | Pipeline condicional de WSL | Política de relación con activación condicional |
| `flake`, `flake-system` | Enumeración de salidas del flake | Sistema de adaptadores de salida |
| `flake-os`, `flake-hm` | Enrutamiento de salida OS/HM | Sistema de adaptadores de salida |
| `flake-packages`, etc. | Enrutamiento por tipo de salida | Sistema de adaptadores de salida |
| `os` | Reenvío OS del árbol de importación | Capacidad en la clase host |
| `hm` (árbol de importación) | Reenvío HM del árbol de importación | Capacidad en la clase home/user |

La cadena de 3 nodos de `makeHomeEnv` (`host.into.X-host` -> `X-host.into.X-user` -> `X-user.provides`) se colapsa a una sola declaración de política de relación.

### Simplificación de ctxSubmodule

**Antes:**
```nix
ctxSubmodule = lib.types.submodule {
  imports = den.lib.aspects.types.aspectType.getSubModules;
  options.into = ...;        # funciones de transición
  options.__functor = ...;   # callable de ctxApply
  # Más todas las opciones de aspectType (name, meta, includes, provides, claves de clase freeform)
};
```

**Después:**
```nix
classType = lib.types.submodule {
  options = {
    # Forma de la entidad — las opciones que esta clase define
    entityOptions = ...;
    # Metadatos de la clase
    description = ...;
    # Claves de capacidad que esta clase reconoce (inicializadas desde definiciones de entidad)
    capabilities = ...;
  };
  # Sin into, sin provides, sin __functor
};
```

El tipo de clase es datos puros. Sin functor invocable, sin funciones de transición.

### Cableado del Esquema

La auto-resolución del esquema en `options.nix` permanece estructuralmente similar pero lee de la clase simplificada:

```nix
# Actual: den.ctx.${kind} (filterAttrs ... // { ${kind} = config; })
# Después: den.lib.instantiateClass kind (filterAttrs ... // { ${kind} = config; })
```

La verificación de existencia `den.ctx ? ${kind}` sigue controlando la participación. El registro de clases sigue siendo la fuente de verdad para "qué tipos de entidad existen".

## Reorganización de Archivos

### Disposición Actual (dispersa)

```
nix/lib/types.nix                        # hostType + userType + homeType (290 líneas, todo mezclado)
nix/lib/ctx-types.nix                    # ctxTreeType, ctxSubmodule, intoCtxType
nix/lib/ctx-apply.nix                    # functor ctxApply
nix/nixModule/ctx.nix                    # declaración de opción den.ctx
modules/context/host.nix                 # den.ctx.host (into, provides)
modules/context/user.nix                 # den.ctx.user (into, provides)
modules/context/has-aspect.nix           # API de consulta hasAspect
modules/context/perHost-perUser.nix      # guardas deprecadas
modules/options.nix                      # schemaEntryType, den.hosts/homes/schema
modules/aspects/provides/home-manager.nix # den.ctx.home enterrada aquí
```

### Disposición Propuesta (entidad por archivo)

```
nix/lib/entities/
  _types.nix          # Compartido: strOpt, systemType, homeSystemType, schemaEntryType, definición de classType
  _has-aspect.nix     # Módulo de consulta de entidad hasAspect (desde modules/context/has-aspect.nix)
  host.nix            # hostType (forma de entidad) + den.ctx.host (def. de clase)
  user.nix            # userType (forma de entidad) + den.ctx.user (def. de clase)
  home.nix            # homeType (forma de entidad) + den.ctx.home (def. de clase, extraída)
  home-env.nix        # Fábrica makeHomeEnv (genera políticas de relación para hm/hjem/maid)

nix/lib/ctx/
  types.nix           # ctxTreeType (simplificado — sin intoCtxType tras eliminar into)
  apply.nix           # Instanciación de clase (ctxApply simplificado — solo vinculación de alcance)
```

**Principio clave:** El tipo de entidad y la definición de clase viven en el mismo archivo porque son dos caras del mismo concepto. La forma de un host (qué opciones tiene) y su identidad de clase (qué claves de capacidad reconoce) están inherentemente acopladas.

### Ruta de Migración

Esta reorganización es un **renombrar + consolidar**, no una reescritura. El código del tipo de entidad se mueve de `nix/lib/types.nix` a archivos por entidad. Las definiciones de clase se mueven de `modules/context/*.nix` a los mismos archivos. Sin cambios de comportamiento en este paso.

Los cambios de comportamiento (eliminar `into`/`provides` de las clases, introducir políticas de relación) ocurren en trabajo posterior cuando se implemente la especificación de políticas de relación.

**Superficie de migración aguas abajo:** Las plantillas y baterías que referencian nodos ctx intermedios (`den.ctx.hm-host`, `den.ctx.flake-packages`, etc.) necesitarán actualización cuando esos nodos se eliminen. Esto incluye los fixtures de prueba en `templates/ci/modules/features/` y `templates/flake-parts-modules/` que construye cadenas `into` personalizadas sobre `den.ctx.flake-parts`. Los módulos de batería como `os-user.nix`, `mutual-provider.nix` y `os-class.nix` que contribuyen `includes` a nodos ctx (`den.ctx.user.includes`, `den.ctx.default.includes`) están bien para las clases que sobreviven, pero el patrón de contribuir a nodos intermedios (e.g., `den.ctx.hm-host.includes` en plantillas) necesita un destino de migración. Este trabajo aguas abajo está dentro del alcance de la implementación de políticas de relación, no de este paso de reorganización.

**Riesgo de detección estructural de `ctxTreeType`:** La fusión recursiva en `ctxTreeType` usa rastreo estructural de claves (`into`, `provides`, `_`, `includes`, `_module`) para distinguir nodos ctx hoja de contenedores de espacios de nombres. Cuando `into`/`provides` se eliminan de las definiciones de clase, esta heurística cambia. Durante la migración, las claves de detección deben actualizarse para coincidir con lo que use el `classType` simplificado — o el tipo de árbol puede reemplazarse con un registro plano si ya no se necesitan espacios de nombres anidados (ver pregunta abierta 4).

### Eliminaciones

- `modules/context/perHost-perUser.nix` — guardas deprecadas, las políticas de relación reemplazan el patrón
- `modules/context/host.nix` — absorbido en `nix/lib/entities/host.nix`
- `modules/context/user.nix` — absorbido en `nix/lib/entities/user.nix`
- `nix/lib/types.nix` — dividido en archivos por entidad + `_types.nix`

## Relación con Otras Especificaciones

- **Políticas de Relación** (`2026-04-20-relationship-policies-design.md`): Esta especificación define ADÓNDE se mueven `into`/`provides`. La especificación del registro de clases define DE DÓNDE se mueven.
- **Diseño de Capacidades**: Las clases reconocen claves de capacidad mediante detección estructural. El registro de clases es donde ocurre la inicialización de capacidades (nombres de clase conocidos desde las definiciones de entidad).
- **Efectos provide-to**: El enrutamiento entre clases actualmente en `provides` se mueve a políticas de relación, que emiten efectos `provide-to`.

## Arte Previo y Justificación del Diseño

La separación tripartita (estructura de entidad, relaciones de entidad, comportamiento de resolución) es un patrón universal en sistemas maduros. El diseño del registro de clases de den se inspira en varios:

### Typeclasses de Haskell — analogía más cercana

Una declaración `data` en Haskell define estructura. Una `typeclass instance` declara capacidades por separado. `instance Resolvable Host where resolve = ...` agrega comportamiento sin modificar la definición de Host.

Mapeo en den: `den.ctx.host` = declaración de tipo (qué ES un host). Claves de capacidad (nixos, darwin) = instancias de typeclass (qué PUEDE HACER un host). Políticas de relación = restricciones de typeclass (`Resolvable a => Deployable a` — ordenamiento del pipeline).

Esto valida separar las definiciones de clase del comportamiento de resolución. La clase es el tipo; las capacidades y relaciones se declaran externamente.

### CRDs + Controladores de Kubernetes — separación spec/status

Los CRDs definen esquema puro (qué campos tiene un recurso). Los controladores proporcionan comportamiento de reconciliación (converger el estado actual hacia el estado deseado). Son procesos separados — el servidor API almacena datos, los controladores agregan comportamiento.

Mapeo en den: opciones del tipo de entidad = spec del CRD (forma declarada). Pipeline de resolución = controlador (converge aspectos en configuración NixOS). `config.resolved` = status (salida observada). Esto valida mantener la definición de clase como datos puros sin `__functor` de comportamiento.

### Rails ActiveRecord — vocabulario de relaciones

`has_many :users`, `belongs_to :host` — macros declarativas que se leen como prosa. Las relaciones son metadatos, no comportamiento. Rails también separa el esquema (migraciones) de la clase del modelo.

Mapeo en den: `den.relationships.host-users = { from = "host"; to = "user"; ... }` sigue el mismo patrón declarativo. La especificación de relación son metadatos que el pipeline recorre.

**Anti-patrón a evitar:** Rails mezcla demasiado en las clases del modelo — modelos dios-objeto con más de 500 líneas mezclando lógica de consulta, validación y callbacks. Den debe resistir la tentación de agregar comportamiento a las definiciones de clase.

### Terraform — detección implícita de relaciones

Terraform infiere su DAG de dependencias a partir de referencias de atributos (`vpc_id = aws_vpc.main.id`). El `depends_on` explícito es la válvula de escape. La mayoría de las relaciones se descubren, no se declaran.

Den podría inferir relaciones de manera similar a partir de cómo las entidades se referencian entre sí (una configuración de home-manager referencia un usuario que referencia un host). Las políticas de relación explícitas son el mecanismo principal, pero la inferencia estructural (según el diseño de capacidades) las complementa.

### ECS — composición sobre clasificación

En Entity-Component-System, una entidad no es nada — solo un ID. El significado viene de qué componentes están adjuntos. Los sistemas consultan por firma de componentes.

Esto valida el modelo de aspectos de den: una entidad gana capacidades por qué aspectos están adjuntos, no por su jerarquía de clases. El registro de clases define la forma estructural, pero la configuración real viene de la composición de aspectos. Las clases son restricciones sobre composiciones válidas, no prescripciones de comportamiento.

### Perspectiva clave

Todo sistema que envejece bien separa tres preocupaciones:
1. **Qué ES una entidad** (estructura/esquema) — definiciones de clase de den.ctx
2. **Cómo se RELACIONAN las entidades** (asociaciones) — políticas de den.relationships
3. **Cómo se RESUELVEN las entidades** (comportamiento) — manejadores del pipeline fx

Los sistemas que fusionan cualquier par de estas desarrollan problemas de dios-objeto. El diseño ctx-como-clases mantiene esta separación.

## Preguntas Abiertas

1. **Clase `default`**: ¿Es `default` una clase real o solo un objetivo genérico para aspectos? Si los aspectos que no están vinculados a una entidad aún necesitan un objetivo de resolución, `default` permanece. Si las políticas de relación manejan los includes incondicionales de manera diferente, podría no necesitar ser una clase.

2. **Adaptadores de salida del flake**: Los nodos ctx del flake (`flake`, `flake-system`, `flake-os`, etc.) claramente no son clases de entidad. ¿Qué sistema los reemplaza? ¿Un registro separado de adaptadores de salida? ¿O se convierten en políticas de relación también (el flake "se relaciona con" sus sistemas)?

3. **ctx de espacio de nombres**: `namespace-types.nix` define `ctx` por espacio de nombres. ¿Se aplica el modelo de clases a los espacios de nombres también, o los nodos ctx de espacio de nombres son un concepto separado?

4. **Fusión recursiva de `ctxTreeType`**: Actualmente soporta espacios de nombres anidados (`den.ctx.ns.inner`). Si las clases son planas (host, user, home, default), ¿seguimos necesitando el tipo de árbol recursivo?

5. **`includes` de baterías en nodos eliminados**: Módulos como `os-user.nix` y `mutual-provider.nix` contribuyen `den.ctx.user.includes` y `den.ctx.default.includes` — estos sobreviven ya que `user` y `default` son clases. Pero el patrón de contribuir `includes` a nodos intermedios (e.g., `den.ctx.hm-host.includes` en plantillas) necesita un nuevo hogar. ¿Se convierten en configuración de política de relación, o se adjuntan a la clase padre sobreviviente?

6. **`into` como azúcar sintáctico en línea vs eliminación**: La especificación de políticas de relación (2026-04-20) describe `into` en nodos ctx como azúcar sintáctico que se descompone en políticas. Esta especificación dice que las definiciones de clase NO contienen `into`. Aclarar: ¿sobrevive `into` como sintaxis de conveniencia en `den.ctx` que compila a `den.relationships`, o se elimina completamente? Recomendación: eliminar completamente de las definiciones de clase; si se desea azúcar sintáctico, proporcionarlo como un helper separado (`den.lib.relationship { from = "host"; into.user = ...; }`).
