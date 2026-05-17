---
name: Cyber-Analyst UI
colors:
  surface: '#0d1516'
  surface-dim: '#0d1516'
  surface-bright: '#333a3c'
  surface-container-lowest: '#080f11'
  surface-container-low: '#161d1f'
  surface-container: '#1a2123'
  surface-container-high: '#242b2d'
  surface-container-highest: '#2f3638'
  on-surface: '#dce4e6'
  on-surface-variant: '#bac9cd'
  inverse-surface: '#dce4e6'
  inverse-on-surface: '#2a3233'
  outline: '#859397'
  outline-variant: '#3b494c'
  surface-tint: '#00daf8'
  primary: '#baf2ff'
  on-primary: '#00363f'
  primary-container: '#00e0ff'
  on-primary-container: '#005f6d'
  inverse-primary: '#006877'
  secondary: '#ddb7ff'
  on-secondary: '#490080'
  secondary-container: '#6f00be'
  on-secondary-container: '#d6a9ff'
  tertiary: '#ffe6b6'
  on-tertiary: '#3f2e00'
  tertiary-container: '#fec42e'
  on-tertiary-container: '#6f5200'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#a5eeff'
  primary-fixed-dim: '#00daf8'
  on-primary-fixed: '#001f25'
  on-primary-fixed-variant: '#004e5a'
  secondary-fixed: '#f0dbff'
  secondary-fixed-dim: '#ddb7ff'
  on-secondary-fixed: '#2c0051'
  on-secondary-fixed-variant: '#6900b3'
  tertiary-fixed: '#ffdf9d'
  tertiary-fixed-dim: '#f7be27'
  on-tertiary-fixed: '#251a00'
  on-tertiary-fixed-variant: '#5b4300'
  background: '#0d1516'
  on-background: '#dce4e6'
  surface-variant: '#2f3638'
typography:
  display-lg:
    fontFamily: Space Grotesk
    fontSize: 40px
    fontWeight: '700'
    lineHeight: '1.1'
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Space Grotesk
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.2'
  body-base:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.5'
  label-tech:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '700'
    lineHeight: '1'
    letterSpacing: 0.1em
  data-mono:
    fontFamily: monospace
    fontSize: 14px
    fontWeight: '500'
    lineHeight: '1.4'
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 4px
  gutter: 16px
  margin: 20px
  stack-sm: 8px
  stack-md: 16px
  stack-lg: 32px
---

## Brand & Style

The design system is engineered to evoke the sensation of operating a high-stakes tactical network dashboard. It targets a professional audience that demands both aesthetic sophistication and immediate data clarity. The brand personality is "Intelligence-First"—it feels elite, analytical, and futuristic, moving away from consumer-grade softness toward a more specialized, high-tech instrument feel.

The style is a hybrid of **Glassmorphism** and **Cyberpunk-inspired Sci-Fi**. It utilizes deep translucent layers to create a sense of infinite depth, paired with high-contrast glowing accents that draw the eye to critical system states. The interface should feel "alive," as if it is a real-time monitor of invisible waves, using subtle motion and luminous feedback to represent data flow and signal oscillations.

## Colors

The palette is anchored in a deep navy-black foundation to maximize the "pop" of luminous UI elements. The Primary Cyan is used exclusively for active network states and core navigation, creating a focused visual path. Secondary Purple is reserved for AI-driven insights and advanced "Spectre" features, distinguishing machine-learning logic from raw hardware data.

Semantic colors for Success, Warning, and Danger are highly saturated to ensure they pierce through the dark interface. The Signal Gradient is a critical functional element: use the Emerald-to-Rose spectrum to visualize dBm ranges (-50 to -90), ensuring that network health is instantly recognizable without reading specific text values.

## Typography

The typography strategy prioritizes a "tech-utility" aesthetic. **Space Grotesk** provides a geometric, futuristic feel for headlines and large data readouts, suggesting a cutting-edge scientific environment. **Inter** handles the heavy lifting for body text and descriptive labels, ensuring high legibility even at smaller mobile scales.

A critical distinction in this design system is the use of a **Monospaced font** for all technical strings (MAC addresses, IP addresses, packet sizes). This creates a visual separation between human-readable content and raw data streams. Use uppercase tracking for technical labels to mimic the feel of military or industrial equipment markings.

## Layout & Spacing

This design system uses a **Fluid Grid** model optimized for high-density information display. The layout is built on a 4px baseline grid to maintain tight technical precision. 

Margins are set at 20px to provide a comfortable frame for the "glass" containers. Within cards, padding should be generous (16px to 20px) to allow complex data to breathe. Components should be stacked using a 12-column internal fluid system, where data pips and status indicators take up minimal horizontal space while primary metrics dominate the view.

## Elevation & Depth

Depth is achieved through **Glassmorphism** rather than traditional drop shadows. Surfaces are defined by their background blur intensity and subtle inner borders.

1.  **Base Layer:** The navy-black background with a very subtle particle mesh overlay.
2.  **Card Layer:** #131821 with a 15px backdrop blur and a 1px solid border (#1E2532). This creates a "submerged" look.
3.  **Active Layer:** Elements that are being interacted with or require immediate attention gain a 10px-20px "Bloom" or outer glow using the primary color at low opacity (15-20%).
4.  **Floating Elements:** Modals and tooltips utilize a more intense blur (30px+) and a slightly brighter border to appear physically closer to the user.

## Shapes

The shape language balances modern software aesthetics with industrial design. A "Rounded" (0.5rem) base is used for primary cards to keep the UI feeling premium and accessible. 

For high-tech accents, consider "clipped" corners or subtle 45-degree chamfers on technical buttons and status pips to reinforce the sci-fi theme. Interaction targets like buttons and input fields should maintain consistent rounding to ensure they are perceived as tactile, clickable elements.

## Components

**Glassmorphism Cards:** The primary container. Must include the 1px #1E2532 border. For AI-recommended insights, use a subtle #A855F7 (Purple) top-border or corner accent.

**Animated Signal Bars:** Five-tier vertical bars. Instead of flat colors, use the Signal Gradient. Active bars should have a subtle "pulse" animation. Inactive bars should be #1E2532 at 50% opacity.

**Buttons:** 
- *Primary:* Solid Cyan background with black text for maximum contrast.
- *Secondary:* Ghost style with Cyan border and a soft inner glow on hover.
- *AI-Action:* Purple gradient with a "sparkle" icon.

**Status Indicators:** Small circular pips with a "heartbeat" glow animation. Emerald for "Stable," Amber for "Interference," Rose for "Disconnected."

**Input Fields:** Darker than the card background, using a monospace font for technical entry. The focus state must trigger a Cyan outer glow.

**Custom Line Icons:** Use a thin 1.5px stroke weight. Icons should be simplified, geometric, and strictly monochromatic unless representing a state change (e.g., a red lock for an unsecured network).