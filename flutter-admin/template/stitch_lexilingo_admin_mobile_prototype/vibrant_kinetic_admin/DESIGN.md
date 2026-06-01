---
name: Vibrant Kinetic Admin
colors:
  surface: '#f8f9ff'
  surface-dim: '#cbdbf5'
  surface-bright: '#f8f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#eff4ff'
  surface-container: '#e5eeff'
  surface-container-high: '#dce9ff'
  surface-container-highest: '#d3e4fe'
  on-surface: '#0b1c30'
  on-surface-variant: '#5c4037'
  inverse-surface: '#213145'
  inverse-on-surface: '#eaf1ff'
  outline: '#916f65'
  outline-variant: '#e6beb2'
  surface-tint: '#ad3200'
  primary: '#a93100'
  on-primary: '#ffffff'
  primary-container: '#d43f00'
  on-primary-container: '#fffbff'
  inverse-primary: '#ffb59e'
  secondary: '#4e6071'
  on-secondary: '#ffffff'
  secondary-container: '#d1e5f9'
  on-secondary-container: '#546677'
  tertiary: '#4f5c76'
  on-tertiary: '#ffffff'
  tertiary-container: '#67758f'
  on-tertiary-container: '#fefcff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#ffdbd0'
  primary-fixed-dim: '#ffb59e'
  on-primary-fixed: '#3a0b00'
  on-primary-fixed-variant: '#852400'
  secondary-fixed: '#d1e5f9'
  secondary-fixed-dim: '#b5c9dc'
  on-secondary-fixed: '#091d2c'
  on-secondary-fixed-variant: '#364959'
  tertiary-fixed: '#d6e3ff'
  tertiary-fixed-dim: '#b9c7e4'
  on-tertiary-fixed: '#0d1c32'
  on-tertiary-fixed-variant: '#39475f'
  background: '#f8f9ff'
  on-background: '#0b1c30'
  surface-variant: '#d3e4fe'
typography:
  h1:
    fontFamily: Space Grotesk
    fontSize: 48px
    fontWeight: '700'
    lineHeight: '1.1'
    letterSpacing: -0.02em
  h2:
    fontFamily: Space Grotesk
    fontSize: 32px
    fontWeight: '600'
    lineHeight: '1.2'
    letterSpacing: -0.01em
  h3:
    fontFamily: Space Grotesk
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.3'
  body-lg:
    fontFamily: Space Grotesk
    fontSize: 18px
    fontWeight: '400'
    lineHeight: '1.6'
  body-md:
    fontFamily: Space Grotesk
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.5'
  label-caps:
    fontFamily: Space Grotesk
    fontSize: 12px
    fontWeight: '700'
    lineHeight: '1'
    letterSpacing: 0.05em
  stat-value:
    fontFamily: Space Grotesk
    fontSize: 36px
    fontWeight: '700'
    lineHeight: '1'
    letterSpacing: -0.03em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 8px
  container-padding: 32px
  gutter: 24px
  stack-gap: 16px
  section-gap: 48px
---

## Brand & Style

The design system is engineered for high-performance linguistic administration, balancing the energetic urgency of educational growth with the precision of a technical dashboard. The brand personality is authoritative yet invigorating, moving away from passive corporate blues into a high-intensity, "always-on" aesthetic.

The design style is **High-Contrast Modern**, utilizing massive typographic scales and a saturated primary palette to drive focus. It borrows from **Minimalism** for its spatial discipline and **Glassmorphism** for its subtle layer treatment, ensuring that while the colors are bold, the interface remains legible and sophisticated for long-term professional use.

## Colors

The palette is anchored by **Vibrant Orange (#FF4E00)**, used strategically for primary actions, critical data highlights, and brand reinforcement. To prevent visual fatigue, this is balanced against a **Light Blue Tint (#D7EBFF)** which serves as the foundational canvas for the application background, providing a cool contrast to the warm primary.

**Pure White (#FFFFFF)** is reserved for elevated "work surfaces" like cards and modals, ensuring a crisp distinction between the structural layout and interactive content. Tertiary Navy (#0A192F) is used for high-contrast text and sidebar elements to ground the vibrant accents.

## Typography

This design system exclusively employs **Space Grotesk** to leverage its technical, geometric character. The typeface is treated with tight letter-spacing for headlines to emphasize its futuristic qualities, while body copy maintains standard spacing for readability.

Numerical data and administrative metrics should utilize the `stat-value` style to ensure high glanceability. All labels and secondary metadata should be set in the `label-caps` style to provide a distinct visual layer that doesn't compete with primary body content.

## Layout & Spacing

The system follows a **12-column fluid grid** with fixed sidebars for navigation. High-density administrative views use a "Card-on-Tint" approach, where white surfaces sit atop the light blue background with generous 32px external margins.

Vertical rhythm is maintained through an 8px base unit. Component stacks (like form groups or list items) use 16px gaps, while major layout sections are separated by 48px to allow the interface to "breathe" despite the high-saturation color palette.

## Elevation & Depth

Visual hierarchy in this design system is achieved through **Ambient Shadows** and **Tonal Layering**. 

1.  **Level 0 (Background):** Light Blue Tint (#D7EBFF).
2.  **Level 1 (Surface):** Pure White (#FFFFFF) with a soft, diffused shadow (15% opacity of the primary orange or a neutral slate) to create a "lifted" appearance.
3.  **Level 2 (Interactive):** Elements like buttons or active states use a slightly more aggressive shadow (Y: 4px, Blur: 12px) to signify "clickability."

Avoid heavy borders; instead, use 1px stroke in a darker tint of the background blue (#BDD6EE) to define boundaries where shadows might be too heavy.

## Shapes

The design system adopts a **Rounded-2xl** philosophy. All primary containers, including dashboard cards, input fields, and modals, utilize a `1.5rem` (24px) corner radius. This softens the high-contrast color scheme, making the professional environment feel modern and accessible rather than harsh.

Buttons and smaller interactive components (chips, tags) should scale down to `1rem` (16px) to maintain a consistent silhouette without feeling overly "bubbly."

## Components

### Buttons & Controls
Primary buttons are solid Vibrant Orange with white text. Secondary buttons utilize a ghost style with an orange border and text. Hover states should involve a subtle scale-up (1.02x) rather than a color shift to maintain the brand's specific orange hue.

### Input Fields
Inputs feature a white background with a subtle 1px border in the secondary blue tint. Upon focus, the border transitions to a 2px Vibrant Orange stroke with a soft orange outer glow.

### Cards & Statistics
Cards are the primary structural element. They must be pure white with `rounded-2xl` corners. High-performance stats should feature a small icon in a circular orange container (10% opacity orange background, 100% opacity orange icon) to the left of the value.

### Chips & Badges
Use "Pill" shapes for status indicators. Success states (Green) and Error states (Red) should be low-saturation backgrounds with high-saturation text to ensure the primary orange remains the most dominant visual element on the screen.

### Navigation Sidebar
The sidebar should use the Tertiary Navy (#0A192F) to provide a vertical anchor for the layout. Active links are highlighted with a vertical orange pill indicator on the left edge and a transition of the icon color to Vibrant Orange.