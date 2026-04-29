<div align="center">
  <img src="./git-assets/Wisp-Logo.png" width = "175" alt="Wisp-Logo">
</div>

<h1 align="center">Wisp</h1> 

<div align="center">
  <a href="https://create.roblox.com/dashboard/creations/store/92555075031933/"><img src="https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/7c1fc7d1b321e76aeb6bd69d597a5af3e343c76a/Badges/Roblox-Styled/Creator/link-creator-store-middle.svg" alt="Creator Store"></a> 
  <a href="https://maneetoo.github.io/Wisp/"><img src="https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/7c1fc7d1b321e76aeb6bd69d597a5af3e343c76a/Badges/Roblox-Styled/Original/link-docs.svg" alt="Docs"></a> 
  <a href="https://github.com/maneetoo/wisp/releases"><img src="https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/7c1fc7d1b321e76aeb6bd69d597a5af3e343c76a/Badges/Roblox-Styled/Original/link-download.svg" alt="Download"></a>
  <a href="https://wally.run/package/maneetoo/wisp"><img src="https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/7c1fc7d1b321e76aeb6bd69d597a5af3e343c76a/Badges/Community/Package/link-wally.svg" alt="Wally"></a>
  <a href="https://pesde.dev/packages/maneetoo/wisp"><img src="https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/7c1fc7d1b321e76aeb6bd69d597a5af3e343c76a/Badges/Community/Package/link-pesde.svg" alt="Pesde"></a>
</div>

<br/>

[Wisp](https://maneetoo.github.io/wisp/) - Roblox Networking between client and server, based on [buffer](https://create.roblox.com/docs/reference/engine/libraries/buffer) written in [Luau](https://luau.org/) for [Roblox](https://www.roblox.com/). The main feature of Wisp is the almost possible minimum packet size, which is achieved through careful buffering, schemas, and table compression ([LZ4HC](https://lz4.org/), [Deflate](https://github.com/libyal/assorted/blob/main/documentation/Deflate%20(zlib)%20compressed%20data%20format.asciidoc?ysclid=mofdhd7ye6229227322), [Zstd](http://www.zstd.net/)). It also offers maximum ease of use and fast transmission between parties.

> [!WARNING]
> Wisp is in active development. Although the module passes all checks, some edge-cases may cause errors, data loss, and so on. For large projects, it is better wait for a stable version of Wisp or use similar alternatives. We would appreciate your help in finding vulnerabilities in the module by opening Issues and Pull Requests! Thank you so much!

## Documentation
[Jump!](https://maneetoo.github.io/wisp/)

## Installation
Wally:
```toml
[dependencies]
Wisp = "manetoo/wisp@VERSION"
```

Pesde:
```bash
pesde add maneetoo/wisp
```

## Contribution
We 💝 Pull Requests and Issues! You found a bug or error? Open Issue in Issues or if you want to help - open pull request with new/fixed code! Thanks so much for your help!

## License
Wisp is released under the [MIT License](https://github.com/maneetoo/wisp/blob/main/LICENSE)
