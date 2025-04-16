const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "../assets/js/**/*.js",
    "../assets/js/**/*.jsx",
    "../lib/windyfall_web.ex",
    "../lib/windyfall_web/**/*.*ex"
  ],
  theme: {
    extend: {
      // Define a new color palette inspired by wind and water
      colors: {
        // Using CSS variables defined in app.css for broader use
        'primary': 'var(--color-primary)',
        'secondary': 'var(--color-secondary)',
        'accent': 'var(--color-accent)',
        'background': 'var(--color-background)',
        'surface': 'var(--color-surface)',
        'surface-hover': 'var(--color-surface-hover)', // For hover states
        'text-primary': 'var(--color-text)',
        'text-secondary': 'var(--color-text-secondary)', // Lighter text
        'text-tertiary': 'var(--color-text-tertiary)',   // Even lighter text
        'border': 'var(--color-border)',
        'primary-dark': 'var(--color-primary-dark)', // Darker shade for button hover
      },
      animation: {
        // Renamed for clarity and added more options
        'wind-flow': 'wind-flow 15s infinite linear',
        'water-ripple': 'water-ripple 8s infinite ease-in-out',
        'water-flow-bg': 'water-flow-bg 20s ease infinite', // For background gradient
        'water-reflect': 'water-reflect 3s linear infinite', // For button shine
        'float': 'float 20s linear infinite', // For leaves
      },
      keyframes: {
        // Renamed existing Tailwind animations to avoid conflicts if needed
        'wind-flow': { // Subtle horizontal movement for wind patterns
          '0%': { backgroundPosition: '0% 50%' },
          '100%': { backgroundPosition: '100% 50%' },
        },
        'water-ripple': { // Subtle scaling for a ripple effect
          '0%, 100%': { transform: 'scale(1)' },
          '50%': { transform: 'scale(1.02)' },
        },
        'water-flow-bg': { // For the main background gradient
           '0%': { backgroundPosition: '0% 50%' },
           '50%': { backgroundPosition: '100% 50%' },
           '100%': { backgroundPosition: '0% 50%' },
        },
        'water-reflect': { // For button shine effect
          '0%': { transform: 'translateX(-100%) rotate(45deg)' },
          '100%': { transform: 'translateX(100%) rotate(45deg)' },
        },
        'float': { // For floating leaves
           '0%': { transform: 'translateY(0vh) rotate(0deg)' },
           '100%': { transform: 'translateY(-100vh) rotate(360deg)' },
        },
      }
    },
  },
  plugins: [
    require("@tailwindcss/forms")({
      // Add strategy: 'base' to prevent conflicts if needed, or 'class'
      // strategy: 'base', // Add this line only if seeing form styling issues
    }),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({addVariant}) => addVariant("phx-no-feedback", [".phx-no-feedback&", ".phx-no-feedback &"])),
    plugin(({addVariant}) => addVariant("phx-click-loading", [".phx-click-loading&", ".phx-click-loading &"])),
    plugin(({addVariant}) => addVariant("phx-submit-loading", [".phx-submit-loading&", ".phx-submit-loading &"])),
    plugin(({addVariant}) => addVariant("phx-change-loading", [".phx-change-loading&", ".phx-change-loading &"])),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function({matchComponents, theme}) {
      let iconsDir = path.join(__dirname, "../deps/heroicons/optimized")
      let values = {}
      let icons = [
        ["", "/24/outline"],
        ["-solid", "/24/solid"],
        ["-mini", "/20/solid"],
        ["-micro", "/16/solid"]
      ]
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
          let name = path.basename(file, ".svg") + suffix
          values[name] = {name, fullPath: path.join(iconsDir, dir, file)}
        })
      })
      matchComponents({
        "hero": ({name, fullPath}) => {
          let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
          let size = theme("spacing.6")
          if (name.endsWith("-mini")) {
            size = theme("spacing.5")
          } else if (name.endsWith("-micro")) {
            size = theme("spacing.4")
          }
          // Ensure the mask URL is properly encoded
          const encodedContent = encodeURIComponent(content);
          return {
            [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${encodedContent}')`,
            "-webkit-mask": `var(--hero-${name}) no-repeat 50% 50%`, // Add positioning
            "mask": `var(--hero-${name}) no-repeat 50% 50%`,          // Add positioning
            "-webkit-mask-size": "contain",                         // Ensure icon scales nicely
            "mask-size": "contain",                                 // Ensure icon scales nicely
            "background-color": "currentColor",
            "display": "inline-block",
            "width": size,
            "height": size
          }
        }
      }, {values})
    })
  ]
}
