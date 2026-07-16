---
name: Obsidian Neon
colors:
  surface: '#15121d'
  surface-dim: '#15121d'
  surface-bright: '#3b3744'
  surface-container-lowest: '#100c18'
  surface-container-low: '#1d1a26'
  surface-container: '#211e2a'
  surface-container-high: '#2c2834'
  surface-container-highest: '#373340'
  on-surface: '#e7dff0'
  on-surface-variant: '#ccc2d9'
  inverse-surface: '#e7dff0'
  inverse-on-surface: '#322e3b'
  outline: '#968da2'
  outline-variant: '#4a4456'
  surface-tint: '#d2bcff'
  primary: '#d2bcff'
  on-primary: '#3e008e'
  primary-container: '#7a22ff'
  on-primary-container: '#e8daff'
  inverse-primary: '#7516fa'
  secondary: '#d3bbff'
  on-secondary: '#3f0689'
  secondary-container: '#592da2'
  on-secondary-container: '#c8aaff'
  tertiary: '#4cd7f6'
  on-tertiary: '#003640'
  tertiary-container: '#006d80'
  on-tertiary-container: '#a4ebff'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#eaddff'
  primary-fixed-dim: '#d2bcff'
  on-primary-fixed: '#25005a'
  on-primary-fixed-variant: '#5900c7'
  secondary-fixed: '#ebdcff'
  secondary-fixed-dim: '#d3bbff'
  on-secondary-fixed: '#260059'
  on-secondary-fixed-variant: '#572ba0'
  tertiary-fixed: '#acedff'
  tertiary-fixed-dim: '#4cd7f6'
  on-tertiary-fixed: '#001f26'
  on-tertiary-fixed-variant: '#004e5c'
  background: '#15121d'
  on-background: '#e7dff0'
  surface-variant: '#373340'
typography:
  display-lg:
    fontFamily: Hanken Grotesk
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  display-lg-mobile:
    fontFamily: Hanken Grotesk
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
  headline-md:
    fontFamily: Hanken Grotesk
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  body-lg:
    fontFamily: Geist
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Geist
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-sm:
    fontFamily: Geist
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.05em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  xs: 4px
  sm: 12px
  md: 24px
  lg: 48px
  xl: 80px
  container-max: 1200px
  gutter: 24px
---

## Brand & Style
The design system is engineered for a premium, high-performance VPN experience. The personality is "Cyber-Security Sophistication"—merging the mystery of deep space with the precision of high-end hardware. It targets a tech-savvy audience that values privacy, speed, and cutting-edge aesthetics.

The visual style is **Futuristic Glassmorphism**. It utilizes a "Deep Obsidian" foundation to minimize eye strain while highlighting "Vibrant Violet" and "Electric Cyan" accents to represent active energy and secure connections. Interfaces are characterized by translucent layers, fine-lined metallic borders, and subtle neon glows that simulate light-emitting hardware components.

## Colors
The palette is rooted in the "Deep Obsidian" abyss, creating a high-contrast environment where accents feel luminous.

- **Primary (Vibrant Violet):** Used for core actions, active connection states, and critical branding elements. It should often carry a 10-20px outer glow.
- **Secondary (Deep Purple-Indigo):** Used for depth, hover states on primary elements, and structural grouping.
- **Tertiary (Electric Cyan):** Reserved for "Safe" statuses, successful connection indicators, and data-flow visualizations.
- **Neutrals:** The background transitions from a pure black-void (#0B0813) to a slightly elevated charcoal (#120F1D) to define depth without losing the "Dark Mode" purity.

## Typography
The system uses a pairing of **Hanken Grotesk** for headlines and **Geist** for UI and body text.

- **Headlines:** Set in Hanken Grotesk with tight tracking to evoke a modern, bold feel. Large display titles should use white (#FFFFFF) to pop against the dark canvas.
- **Body & Technical Data:** Geist provides a clean, monospaced-adjacent clarity that feels "developer-friendly" and high-tech.
- **Secondary Text:** Use Muted Amethyst (#A78BFA) for sub-headers and descriptions to maintain visual hierarchy.
- **Labels:** Small labels use uppercase with increased letter spacing for a "HUD" (Heads-Up Display) aesthetic.

## Layout & Spacing
The layout follows a precise, mathematical grid to emphasize the "High-Tech" nature of the product.

- **Grid Model:** A 12-column fluid grid for desktop and a 4-column grid for mobile.
- **Margins:** Large 48px-80px external margins on desktop to allow the UI to "breathe" in the center of the dark void.
- **Rhythm:** An 8px base unit drives all padding and margins. Vertical rhythm should be generous to maintain a minimalist feel.
- **Content Reflow:** On mobile, cards stack vertically, and background blurs are intensified to maintain legibility over complex background gradients.

## Elevation & Depth
Depth is achieved through translucency and light, rather than traditional shadows.

- **Glassmorphism:** All primary containers use the "Translucent Dark Violet" (#1C162E at 70% opacity) with a 20px backdrop-blur. 
- **Metallic Borders:** Containers should have a 1px solid border. Use a linear gradient for the border: `linear-gradient(135deg, rgba(255,255,255,0.2) 0%, rgba(255,255,255,0.05) 100%)` to simulate a thin metallic edge.
- **Neon Glow:** Active elements (like the "Connect" button) utilize an `0px 0px 20px rgba(122, 34, 255, 0.5)` drop shadow to appear as if they are emitting light.
- **Z-Axis:** Higher elevation levels are indicated by increased background opacity and brighter border highlights.

## Shapes
The shape language is "Calculated Softness." Elements are predominantly rectangular but feature precise 8px (0.5rem) corner radii to prevent the UI from feeling overly aggressive or sharp.

- **Standard Buttons & Cards:** 0.5rem (8px).
- **Status Indicators:** Fully circular (pill-shaped) for a softer, organic "active" feel.
- **Input Fields:** 0.5rem (8px) with inset metallic strokes.

## Components
- **Buttons:** The primary "Connect" button is a solid Vibrant Violet gradient with a neon glow. Secondary buttons use the "Ghost" style—transparent with a 1px metallic border and Muted Amethyst text.
- **Cards/Containers:** Must use the backdrop-blur effect. The "Connection Status" card should feature a subtle Electric Cyan inner glow when protected.
- **Chips/Status:** Used for server locations. These feature a small dot indicator (Electric Cyan for fast, Amethyst for slow) and a Dark Charcoal background.
- **Input Fields:** Deep Obsidian background with a 1px Dark Violet border. On focus, the border transitions to Vibrant Violet with a 4px soft outer glow.
- **Lists:** Server lists use thin separators (1px, 10% white opacity). Hovering over a list item increases the background opacity to 100% of the Dark Charcoal (#120F1D) color.
- **Specialty Component (The Orb):** A central connection toggle. When "ON," it pulse-animates with a Vibrant Violet gradient; when "OFF," it remains a hollow metallic ring.