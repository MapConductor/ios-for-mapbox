# MapConductor Mapbox Module

MapConductor Mapbox Module provides the Mapbox Maps–specific
implementation of the MapConductor unified API for iOS.

This module contains both the SwiftUI-based unified API bindings and
the driver logic required to translate provider-agnostic map semantics
into concrete behavior using the Mapbox Maps SDK for iOS.

---

## Overview

The Mapbox Maps module is responsible for connecting the MapConductor
conceptual API to the Mapbox Maps SDK.

While the unified API of MapConductor is conceptually shared across all
map providers, its SwiftUI bindings and runtime behavior must be
implemented in a provider-specific manner to account for differences in
rendering, lifecycle management, and interaction models.

This module fulfills that role for Mapbox Maps.

## Role in the architecture

```
┌────────────────────────────────────────────┐
│ Application / App Logic                    │
├────────────────────────────────────────────┤
│ MapConductor Unified API (SwiftUI)         │
│  (provider-specific implementation)        │
│  - Unified API (SwiftUI bindings)          │
│  - Internal controllers                    │
├────────────────────────────────────────────┤
│ MapConductor iOS Core                      │
│  - Domain models                           │
│  - State & behavior                        │
│  - Provider-agnostic logic                 │
├────────────────────────────────────────────┤
│ Mapbox Maps Module                         │
│  - Mapbox Maps Driver                      │
│  - Internal renderers                      │
├────────────────────────────────────────────┤
│ Mapbox Maps SDK for iOS                    │
└────────────────────────────────────────────┘
```

In this architecture:

- The **unified API** defines what a map operation means

- The [core module](https://github.com/MapConductor/ios-sdk-core/tree/main) defines provider-agnostic semantics and state

- This **Mapbox Maps** module defines how those semantics are realized using the Mapbox Maps SDK

## What this module does

This module is responsible for:

- Providing the Mapbox Maps–specific implementation of the MapConductor unified API (SwiftUI)

- Translating provider-agnostic domain models and state into Mapbox Maps SDK operations

- Managing provider-specific controllers for camera, overlays, gestures, and interactions

- Implementing Mapbox Maps–specific rendering logic and workarounds where required

In short, this module answers the question:

> "How should this unified map operation behave on Mapbox Maps?"

## What this module does NOT do

Internally, this module typically consists of:

- **SwiftUI unified API bindings**
  Provider-specific implementations of the unified API surface

- **Controllers**
  Components that manage state synchronization and event handling between SwiftUI, the core module, and the Mapbox Maps SDK

- **Renderers**
  Low-level components that create and update Mapbox Maps SDK objects such as markers, overlays, and camera updates

These components are considered implementation details and are not part of the public API.

## Design philosophy

This module follows these design principles:

- **Conceptually unified, operationally specialized**
  The meaning of map operations is shared across providers, while implementation details remain provider-specific.

- **Isolation of provider-specific behavior**
  Mapbox Maps quirks and limitations should not leak into the core module or unified API definitions.

- **No lowest common denominator APIs**
  Differences in provider capabilities are handled through adaptation, not by reducing the expressive power of the unified API.

## Who should use or modify this module

This module is primarily intended for:

- Contributors implementing or maintaining Mapbox Maps support

- Developers debugging provider-specific map behavior

- Contributors extending MapConductor with new Mapbox Maps features

If you are using MapConductor via the unified API in an application,
you typically do not need to interact with this module directly.

## Relationship to other modules

- **MapConductor iOS Core**
  https://github.com/MapConductor/ios-sdk-core/tree/main
  Defines provider-agnostic domain models, state, and semantics

- **Other provider modules**
  (e.g. MapKit, MapLibre, Google Maps) implement the same semantic contract for different map SDKs
