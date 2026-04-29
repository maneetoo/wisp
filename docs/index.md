---
# https://vitepress.dev/reference/default-theme-home-page
layout: home

hero:
  name: "Wisp"
  text: "All-in-One Networking for Roblox"
  tagline: Buffer-Based. Safety. Schemas. Fast.
  image:
    light: docs/assets/Wisp-Logo.png
    dark: docs/assets/Wisp-Logo.png
    alt: Wisp Logo

  actions:
    - theme: brand
      text: Getting started
      link: /tutorials
    - theme: alt
      text: API Reference
      link: /api
    #- theme: alt
    #  text: Benchmarks
    #  link: /benchmarks
    - theme: alt
      text: Download
      link: https://github.com/maneetoo/wisp/releases
---

::: warning Pre-Beta Release
Wisp is in active development. Although the module passes all checks, some edge-cases may cause errors, data loss, and so on. For large projects, it is better wait for a stable version of Wisp or use similar alternatives. We would appreciate your help in finding vulnerabilities in the module by opening Issues and Pull Requests! Thank you so much!
:::

<ScrollIndicator />

<NextSteps 
  :links="[
    {
      title: 'Getting Started',
      description: 'Installation, quick start, and your first UI component',
      href: '/tutorials'
    },
    {
      title: 'API Reference',
      description: 'Complete documentation for all reactive primitives',
      href: '/api-reference'
    },
    {
      title: 'Benchmarks',
      description: 'See benchmarks compared to other libraries',
      href: '/benchmarks'
    }
  ]"
/>

## About Wisp

Wisp is a binary networking framework for Roblox built on the buffer library. It handles serialization, compression, batching, delta encoding, and schema validation in a single package designed to work together from the start.

Every component was built with awareness of the others. The serializer knows what the compressor needs. The batcher knows which queue to use. The schema validator knows how to call the migration system when old data arrives.

Wisp supports 51 Roblox types natively, validates every argument at runtime, and includes versioned schemas with automatic migration so your protocol can evolve without breaking old clients.

## Why Wisp?

Building networking in Roblox the traditional way means choosing between convenience and control. You either use a simple wrapper that hides the complexity but adds overhead you can't remove, or you write everything from scratch using raw [RemoteEvents](https://create.roblox.com/docs/scripting/events/remote) and spend weeks reinventing compression, delta encoding, and batch queues. Neither approach scales well as your game grows.

Wisp gives you both. It handles every aspect of networking — [serialization](https://create.roblox.com/docs/reference/engine/libraries/buffer), compression, batching, delta encoding, rate limiting, schema validation — while keeping you in full control of how each remote behaves. Need positions sent as fast as possible without guarantees? Make it unreliable with [UnreliableRemoteEvents](https://create.roblox.com/docs/scripting/events/unreliable-remote) and priority queuing. Need purchases to never be lost? Switch it to reliable with automatic retry. Every decision is a one-line configuration change, not a rewrite.

Wisp operates at the binary level, not the string level. Where other libraries send JSON objects with repeated field names and unnecessary markup, Wisp packs your data into the smallest possible [buffer](https://create.roblox.com/docs/reference/engine/libraries/buffer) using a custom 51-type serializer. A [Vector3](https://create.roblox.com/docs/reference/engine/datatypes/Vector3) becomes 13 bytes instead of 40. A table of ten player stats becomes a compact binary stream instead of hundreds of characters. Multiply that by thousands of packets per minute and the difference is measured in megabytes of bandwidth and milliseconds of latency.

The framework is also designed for games that evolve. Wisp includes schema versioning and migration functions, so you can change your data format without breaking old clients. Delta encoding with cache synchronization means you only send what changed, not the entire state, with automatic detection and recovery when client and server fall out of sync.

Wisp validates every argument to every public method before it reaches your game logic. A typo in a remote name or a missing player argument is caught immediately with a clear error message, not silently ignored until it causes a cascade of bugs hours later. Combined with extensive unit tests covering every module, you can refactor with confidence.

Wisp is written in [Luau](https://luau.org/) with `--!strict` mode and `--!native` optimizations enabled throughout. The entire framework is built on the [buffer](https://create.roblox.com/docs/reference/engine/libraries/buffer) library introduced by Roblox for maximum performance, avoiding the overhead of string-based serialization entirely.

When you choose Wisp, you're not just picking a networking library. You're choosing a foundation that handles the hard parts of multiplayer — bandwidth optimization, data integrity, protocol evolution — so you can focus on building your game.

## Key Features

::: tip Minimal Packet Size
Binary serialization with a custom 51-type encoder built on Roblox's [buffer](https://create.roblox.com/docs/reference/engine/libraries/buffer) library. A Vector3 is 13 bytes instead of 40. A CFrame is 29 bytes instead of 150. Every byte counts.
:::

::: tip Smart Compression
Three compression algorithms — LZ4HC for speed, Deflate for text, Zstd for large payloads — plus an XOR pre-processor that breaks repetitive patterns before compression, improving ratios by up to 15%.
:::

::: tip Delta Encoding
Send only what changed between packets. Wisp tracks state per-player and transmits just the differences, with automatic cache synchronization and recovery when client and server fall out of sync.
:::

::: tip Dual-Channel Batching
Separate reliable and unreliable batch queues with priority ordering. High-frequency position updates go through UnreliableRemoteEvents for minimum latency. Critical purchases go through guaranteed delivery. All batched per-frame to minimize RemoteEvent calls.
:::

::: tip Schema Validation & Migration
Define your data structure once with typed schemas. Wisp validates every packet before it reaches your game logic. When your protocol evolves, migration functions upgrade old data automatically — no broken clients, no manual version checks.
:::

::: tip Zero-Configuration Types
51 Roblox types work out of the box — Vectors, CFrames, Colors, Enums, Instances, and more. No manual serialization, no type registration, no boilerplate.
:::
