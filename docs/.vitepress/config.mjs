import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
  base: '/wisp/',
  title: "Wisp",
  description: "All-in-One, Fast & Buffer-Based Networking for Roblox",
  themeConfig: {
    logo: {
      light: '/Wisp-Logo.png',
      dark: '/Wisp-Logo.png',
      alt: 'WispLogo'
    },

    search: {
      provider: 'local'
    },

    // https://vitepress.dev/reference/default-theme-config
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Tutorials', link: '/tutorials' },
      { text: 'API Reference', link: '/api-reference' },
      //{ text: 'Benchmarks', link: '/benchmarks' },
      { text: 'Download', link: 'https://github.com/maneetoo/wisp/releases' },
    ],

    sidebar: {
      "/tutorials/": [
        {
          text: 'Guidelines',
          items: [
            { text: 'Introduction', link: '/tutorials/' },
            { text: 'Installation', link: '/tutorials/Installation' },
            { text: 'Basic Usage', link: '/tutorials/BasicUsage' },
            { text: 'Encoding Modes', link: '/tutorials/Modes' },
            { text: 'Supported Types', link: '/tutorials/SupportedTypes' }
          ]
        }
      ],
      "/api-reference/": [
        {
          text: 'General',
          items: [
            { text: 'Wisp', link: '/api-reference/' },
            { text: 'Client', link: '/api-reference/Client' },
            { text: 'Server', link: '/api-reference/Server' },
          ]
        },
        {
          text: 'Modules',
          items: [
              { text: 'Buffer', link: '/api-reference/modules/Buffer' },
              { text: 'Compress', link: '/api-reference/modules/Compress' },
              { text: 'Pool', link: '/api-reference/modules/Pool' },
              { text: 'Remote', link: '/api-reference/modules/Remote' },
              { text: 'XOR', link: '/api-reference/modules/XOR' },
          ]
        },
      ]
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/maneetoo/wisp' }
    ],

    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2026 maneetoo'
    }
  },

  head: [
    ['link', { rel: 'icon', href: '/favicon.ico' }],
    ['link', { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/favicon-32x32.png' }],
    ['link', { rel: 'icon', type: 'image/png', sizes: '16x16', href: '/favicon-16x16.png' }],
  ]
})
