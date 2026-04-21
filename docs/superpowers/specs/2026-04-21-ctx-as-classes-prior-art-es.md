# Arte Previo: Registros de Tipos de Entidad con Relaciones y Resolución

**Fecha:** 2026-04-21
**Compañero de:** `2026-04-21-ctx-as-classes-design.md`

## El Patrón del Problema

Un framework necesita definir tipos de entidad (Host, User, Home), sus relaciones (host tiene muchos usuarios, usuario pertenece a host), y cómo las instancias de entidad fluyen a través de un pipeline de resolución que produce configuración de salida. ¿Cómo separan estos conceptos los sistemas existentes?

## Tabla Comparativa

| Sistema | Definición de Entidad | Relaciones | Datos vs Comportamiento | Resolución/Pipeline |
|---|---|---|---|---|
| **Rails AR** | Clase modelo hereda de `ApplicationRecord`; esquema de BD en migraciones | Macros declarativas: `has_many :users`, `belongs_to :host` | Esquema = migraciones (DDL), Comportamiento = clase del modelo | Constructor de consultas perezoso; callbacks forman pipeline de ciclo de vida |
| **GraphQL** | `type Host { name: String! }` — forma de datos pura | Los campos referencian otros tipos: `users: [User!]!` — los bordes del grafo son campos tipados | Tipos = esquema (SDL), Comportamiento = funciones resolver conectadas por separado | El árbol de resolvers recorre la consulta; cada campo tiene resolver independiente |
| **Terraform** | `resource "aws_instance" "web" { ami = "..." }` — bloque tipado con atributos de esquema | Implícitas vía referencias de atributos (`vpc_id = aws_vpc.main.id`), explícitas vía `depends_on` | Esquema = esquema de recursos del proveedor, Comportamiento = métodos CRUD del proveedor | Basado en DAG: construye grafo de dependencias, recorre en orden topológico |
| **K8s CRD+Controlador** | CRD define `spec` (esquema OpenAPI); las instancias son documentos YAML | Referencias de propietario, selectores de etiquetas — convenciones, no a nivel de esquema | Spec = estado deseado (datos), Controlador = bucle de reconciliación (comportamiento) | Disparado por nivel: el controlador observa recursos, compara spec vs status, converge |
| **ECS** | Entidad = ID vacío. Eso es todo. | Sin relaciones de primera clase; las entidades almacenan IDs de otras entidades en componentes | Componentes = estructuras de datos puros, Sistemas = funciones que consultan conjuntos de componentes | Los sistemas iteran sobre entidades que coinciden con la firma de componentes |
| **Django** | Clase modelo con declaraciones de campo en línea; `class Meta` para metadatos estructurales | `ForeignKey(Host, on_delete=CASCADE)`, `ManyToManyField(User)` — en campos | Esquema + relaciones + comportamiento todo en una clase | Pipeline Manager/QuerySet; señales tipo middleware para ciclo de vida |
| **Haskell TC** | `data Host = Host { hostname :: Text }` — tipo de datos algebraico | Codificadas en tipos: campo `[User]` en Host | Datos = declaración de tipo, Comportamiento = instancias de typeclass | Despacho por typeclass; componible vía restricciones |

## Análisis Detallado

### Typeclasses de Haskell — Analogía Más Cercana a den.ctx

La clase del modelo ES la definición de entidad. Una `typeclass instance` declara capacidades por separado. `instance Resolvable Host where resolve = ...` agrega comportamiento sin modificar la definición de Host. Abierta a extensión — se pueden definir nuevas typeclasses y agregar instancias.

**Mapeo en den:**
- `den.ctx.host` = declaración de tipo (qué ES un host)
- Claves de capacidad (nixos, darwin) = instancias de typeclass (qué PUEDE HACER un host)
- Políticas de relación = restricciones de typeclass (`Resolvable a => Deployable a` — ordenamiento del pipeline)

**Conclusión:** Valida separar las definiciones de clase del comportamiento de resolución. La clase es el tipo; las capacidades y relaciones se declaran externamente.

**Anti-patrón:** Las instancias huérfanas (definir comportamiento para un tipo en un módulo de terceros) causan problemas de coherencia. Den debe asegurar que las declaraciones de capacidad estén co-ubicadas o explícitamente importadas, nunca ambientales.

### CRDs + Controladores de Kubernetes — Separación Spec/Status

Los CRDs definen esquema puro (qué campos tiene un recurso). Los controladores proporcionan comportamiento de reconciliación (converger el estado actual hacia el estado deseado). Son procesos separados — el servidor API almacena datos, los controladores agregan comportamiento.

**Mapeo en den:**
- Opciones del tipo de entidad = spec del CRD (forma declarada)
- Pipeline de resolución = controlador (converge aspectos en configuración NixOS)
- `config.resolved` = status (salida observada)

**Conclusión:** Valida mantener la definición de clase como datos puros sin `__functor` de comportamiento. La reconciliación disparada por nivel ("converger al estado deseado") es el modelo mental correcto para el pipeline de resolución.

**Anti-patrón:** Las relaciones son una ocurrencia tardía. Las referencias de propietario son primitivas. No hay forma de declarar "una Base de Datos requiere un Cluster" a nivel de esquema — los controladores simplemente fallan en tiempo de ejecución si las dependencias están ausentes. Den debe hacer las relaciones de primera clase.

### Rails ActiveRecord — Vocabulario de Relaciones

`has_many :users`, `belongs_to :host` — macros declarativas que se leen como prosa. Las relaciones son metadatos, no comportamiento. Rails también separa el esquema (migraciones) de la clase del modelo.

**Mapeo en den:**
- `den.relationships.host-users = { from = "host"; to = "user"; ... }` sigue el mismo patrón declarativo
- La especificación de relación son metadatos que el pipeline recorre

**Conclusión:** Las macros declarativas de relación son el estándar de oro en legibilidad. El `through:` de Rails para relaciones indirectas se mapea al patrón de den "host tiene homes a través de users".

**Anti-patrón:** Rails mezcla demasiado en las clases del modelo — modelos dios-objeto con más de 500 líneas mezclando lógica de consulta, validación y callbacks. Den debe resistir agregar comportamiento a las definiciones de clase.

### Proveedores/Recursos de Terraform — Detección Implícita de Relaciones

Terraform infiere su DAG de dependencias a partir de referencias de atributos (`vpc_id = aws_vpc.main.id`). El `depends_on` explícito es la válvula de escape. La mayoría de las relaciones se descubren, no se declaran.

**Mapeo en den:**
- Den podría inferir relaciones a partir de cómo las entidades se referencian entre sí (una configuración de home-manager referencia un usuario que referencia un host)
- Las políticas de relación explícitas son el mecanismo principal, la inferencia estructural las complementa

**Conclusión:** La detección implícita a partir de referencias es poderosa. Den debe soportar tanto la detección implícita (según el diseño de capacidades) como la declaración explícita (políticas de relación).

**Anti-patrón:** `depends_on` es propenso a errores cuando la detección implícita falla. La detección de relaciones exclusivamente implícita puede ser demasiado mágica.

### Entity-Component-System (ECS) — Composición sobre Clasificación

La entidad NO ES NADA — solo un ID. Todo el significado viene de qué componentes están adjuntos. Un "Host" es una entidad con componentes `{HostConfig, NetworkConfig, StorageConfig}`. Los sistemas consultan por firma de componentes.

**Mapeo en den:**
- Una entidad gana capacidades por qué aspectos están adjuntos, no por su jerarquía de clases
- El registro de clases define la forma estructural; la configuración real viene de la composición de aspectos
- Las clases son restricciones sobre composiciones válidas, no prescripciones de comportamiento

**Conclusión:** Valida el modelo de aspectos de den. El encuadre ECS confirma: la identidad viene de la composición, no de la clasificación.

**Anti-patrón:** Sin cumplimiento de esquema — cualquier componente puede adjuntarse a cualquier entidad. Den necesita restricciones estructurales (un Home debe tener un contexto User).

### Esquema GraphQL — Relaciones como Campos Tipados

Los tipos declaran forma. Las relaciones son simplemente campos que devuelven otros tipos — sin palabra clave especial `has_many`. Un tipo `Host` con campo `users: [User!]!` ES la declaración de relación. El esquema es un grafo por construcción.

**Mapeo en den:**
- La idea de que las relaciones son "campos que devuelven otros tipos" es elegante
- Resolver por campo significa que la lógica de resolución es granular e independientemente testeable

**Conclusión:** No se necesita un DSL especial de relaciones si el sistema de tipos es suficientemente expresivo. Pero la explosión de resolvers de GraphQL (cada campo necesita un resolver) es excesiva — la resolución basada en pipeline de den evita esto resolviendo en fases definidas.

### Modelos Django — El Patrón de Clase Meta

Todo en una clase: campos, relaciones, validadores, managers, métodos personalizados y metadatos estructurales (`class Meta`). La clase interna `Meta` es interesante — metadatos SOBRE el modelo (ordenamiento, restricciones, nombre de tabla) estructuralmente separados de campos y métodos.

**Mapeo en den:**
- Las definiciones de entidad podrían tener una sección "meta" para metadatos estructurales (capacidades, ordenamiento del pipeline) separada de los campos/aspectos
- El patrón Manager de Django (personalizar cómo se consultan/resuelven las entidades) se mapea al concepto de adaptador de den

**Anti-patrón:** El modelo monolítico. Los modelos de Django se convierten en dios-objetos incluso más rápido que Rails.

## Perspectiva Universal

Todo sistema que envejece bien separa tres preocupaciones:

1. **Qué ES una entidad** (estructura/esquema) — definiciones de clase de den.ctx
2. **Cómo se RELACIONAN las entidades** (asociaciones) — políticas de den.relationships
3. **Cómo se RESUELVEN las entidades** (comportamiento) — manejadores del pipeline fx

Los sistemas que fusionan cualquier par de estas desarrollan problemas de dios-objeto. El diseño ctx-como-clases mantiene esta separación.

El modelo formal más cercano son las typeclasses de Haskell: tipos de entidad declarando capacidades vía instancias tipo typeclass, con restricciones codificando el ordenamiento del pipeline. El vocabulario se mapea casi 1:1:
- typeclass = interfaz de capacidad
- instancia = implementación del tipo de entidad
- restricción = dependencia del pipeline
