# Design System Specification: The Kinetic Luminescence

## 1. Overview & Creative North Star
Standard POS systems are utilitarian tools—cold, grid-locked, and uninspired. This design system rejects the "calculator" aesthetic in favor of **"The Digital Concierge."** 

Our Creative North Star is **Atmospheric Precision**. We treat the retail interface not as a static spreadsheet, but as a high-end editorial experience. We achieve this through:
*   **Intentional Asymmetry:** Breaking the expected 12-column grid to draw focus toward high-value actions (the "checkout" or "total").
*   **Tonal Depth:** Moving away from flat surfaces to layered, translucent materials.
*   **Typographic Gravity:** Using extreme scale shifts—massive headlines paired with micro-labels—to create an authoritative visual hierarchy that guides the eye instantly in fast-paced environments.

---

## 2. Colors: Depth Over Definition
This palette is anchored in deep, midnight purples, utilizing pink-red accents as high-energy triggers.

### The "No-Line" Rule
**Explicit Instruction:** Use of 1px solid borders for sectioning is strictly prohibited. Traditional "boxes" feel cheap. Instead, define boundaries through:
*   **Background Shifts:** Place a `surface-container-low` section against a `surface` background.
*   **Soft Gradients:** Use a subtle vertical shift from `primary` to `primary-container` for active states.

### Surface Hierarchy & Nesting
Treat the UI as a series of stacked, physical layers. 
*   **Base:** `surface` (#131313)
*   **Sections:** `surface-container-low` (#1c1b1b) for secondary sidebars.
*   **Interactive Cards:** `surface-container` (#201f1f) for product tiles.
*   **Active Overlays:** `surface-container-highest` (#353534) for modals.

### The "Glass & Gradient" Rule
To achieve a signature premium feel, use **Glassmorphism** for floating elements (like the "Current Cart" or "Payment Summary"). 
*   **Recipe:** `surface` color at 70% opacity + 24px Backdrop Blur.
*   **CTA Soul:** Primary buttons should use a linear gradient: `primary` (#cfbdff) to `on_primary_container` (#b296ff) at a 135-degree angle.

---

## 3. Typography: The Editorial Scale
We use a tri-font system to balance character with extreme legibility.

*   **Display & Headline (Manrope):** Our "voice." Use `display-lg` (3.5rem) for the total amount due. It must be unmissable.
*   **Titles & Body (Inter):** Our "workhorse." Use `title-lg` for product names and `body-md` for descriptions. Inter’s tall x-height ensures readability under harsh retail lighting.
*   **Labels (Plus Jakarta Sans):** Our "utility." Use `label-md` for technical data (SKUs, tax rates). The geometric nature of Jakarta Sans keeps small data sets clean.

**Hierarchy Note:** Always prioritize the "Total" and "Primary Action." If everything is bold, nothing is bold.

---

## 4. Elevation & Depth: Tonal Layering
We do not use shadows to indicate "elevation" in the traditional sense; we use **Light and Transparency.**

*   **The Layering Principle:** Rather than a drop shadow, elevate a card by moving from `surface-container-low` to `surface-container-high`. The "lift" is perceived through the change in luminosity.
*   **Ambient Shadows:** If a floating element (like a pop-over numeric keypad) requires a shadow, use a diffuse 64px blur at 6% opacity, tinted with `primary` (#cfbdff) to simulate the glow of the screen reflecting off a surface.
*   **The "Ghost Border" Fallback:** For accessibility in high-glare environments, use a 1px border of `outline-variant` (#4a4452) at **15% opacity**. It should be felt, not seen.

---

## 5. Components: Fluid Primitives

### Buttons: The Action Drivers
*   **Primary:** Large (min-height: `10`), `secondary` (#ffb3b5) background. This pink-red accent is reserved *only* for finalization (e.g., "Charge," "Complete").
*   **Secondary:** `primary_container` (#4700b1) with `on_primary_container` text. Used for "Add to Cart" or "Modify."
*   **Tertiary:** No background. Bold `primary` text. Used for "Cancel" or "Back."

### Cards & Lists: The Content Rule
*   **Forbid Dividers:** Do not use lines between list items. Use a `1.5` (0.5rem) spacing gap or a subtle toggle between `surface-container-low` and `surface-container-lowest`.
*   **Touch Targets:** Every interactive element must have a minimum hit area of 48x48px, regardless of its visual size.

### Inputs & Keypads
*   **Stateful Design:** An active input should not just change border color; it should "glow." Use a `surface_bright` (#393939) background with a soft `primary` outer glow (8px blur, 20% opacity).
*   **Keypads:** High-fidelity glass keys. `surface_container_highest` with 40% opacity and a `xl` (0.75rem) corner radius.

### Context-Specific: The "Live Total" Ribbon
A persistent, glassmorphic bar at the bottom or side of the screen using the `secondary_container` (#de0541) at 20% opacity to highlight the transaction's urgency and status.

---

## 6. Do’s and Don’ts

### Do:
*   **Use Generous Whitespace:** Use the `8` (2.75rem) and `10` (3.5rem) spacing tokens to separate the "Cart" from the "Product Grid."
*   **Embrace Large Radii:** Use `xl` (0.75rem) for all main containers to soften the professional environment.
*   **Prioritize Reachability:** Place primary actions (Pay, Checkout) in the bottom-right "Thumb Zone" for tablet users.

### Don’t:
*   **Don't use pure black (#000):** It kills the "premium" depth. Always use `surface` (#131313).
*   **Don't use high-contrast borders:** They create visual "noise" that slows down a cashier's processing time.
*   **Don't use standard icons:** Use "Light" or "Thin" weight iconography to match the sophisticated typography. Thick icons look "cheap" and "app-like."