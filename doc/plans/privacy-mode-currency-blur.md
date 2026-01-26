# Privacy Mode: Currency Blur Feature

## Overview
Add a toggle button that blurs all currency/money values across the UI for privacy when viewing the app in public. The setting is stored in browser `sessionStorage` so it persists across page requests but clears when the browser tab closes.

## Design Decisions
- **Storage:** `sessionStorage` - clears when tab closes (privacy by default)
- **Visual treatment:** CSS blur filter (`filter: blur(6px)`)
- **Scope:** Currency displays AND form inputs
- **Button placement:** Right-aligned in sidebar header (desktop) and mobile header
- **Icons:** Emoji (👁 when active/hidden, 👁‍🗨 when inactive/visible)

---

## Implementation Plan

### Files to Create

#### 1. `app/javascript/controllers/privacy_toggle_controller.js`

New Stimulus controller that:
- Reads/writes `privacyMode` from `sessionStorage`
- Toggles `privacy-mode` class on `document.body`
- Updates icon targets (👁 when active, 👁‍🗨 when inactive)
- Listens to `turbo:load` to re-apply state on Turbo navigation

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["icon"]
  
  connect() {
    this.applyState()
    document.addEventListener("turbo:load", this.applyState.bind(this))
  }
  
  disconnect() {
    document.removeEventListener("turbo:load", this.applyState.bind(this))
  }
  
  toggle() {
    const isActive = sessionStorage.getItem("privacyMode") === "true"
    sessionStorage.setItem("privacyMode", !isActive)
    this.applyState()
  }
  
  applyState() {
    const isActive = sessionStorage.getItem("privacyMode") === "true"
    document.body.classList.toggle("privacy-mode", isActive)
    this.iconTargets.forEach(icon => {
      icon.textContent = isActive ? "👁" : "👁‍🗨"
    })
  }
}
```

---

### Files to Modify

#### 2. `app/assets/stylesheets/application.css`

Add CSS rules for privacy mode blur effect:

```css
/* Privacy mode - blur currency values */
body.privacy-mode .currency-value {
  filter: blur(6px);
  user-select: none;
}

/* Also blur currency inputs */
body.privacy-mode input.currency-input {
  filter: blur(6px);
}

/* Unblur on focus so user can still edit */
body.privacy-mode input.currency-input:focus {
  filter: none;
}
```

#### 3. `app/helpers/application_helper.rb`

Wrap currency output in a span with `currency-value` class:

```ruby
def format_currency(amount, currency: nil, precision: 2)
  currency ||= Currency.default&.code || "USD"
  formatted = number_to_currency(
    amount,
    unit: "#{currency} ",
    delimiter: "'",
    separator: ".",
    precision: precision,
    format: "%u%n"
  )
  content_tag(:span, formatted, class: "currency-value")
end

def format_amount(amount, precision: 2)
  formatted = number_to_currency(
    amount,
    unit: "",
    delimiter: "'",
    separator: ".",
    precision: precision,
    format: "%n"
  )
  content_tag(:span, formatted, class: "currency-value")
end
```

#### 4. `app/javascript/controllers/currency_input_controller.js`

Add `currency-input` class to the input element in `connect()` method so form inputs get blurred:

```javascript
connect() {
  this.element.classList.add("currency-input")
  // ... existing code
}
```

#### 5. `app/views/layouts/application.html.erb`

**Add to `<body>` tag:**
```erb
<body class="bg-slate-50 min-h-screen" data-controller="privacy-toggle">
```

**Add toggle button in desktop sidebar header** (right-aligned, after logo link, around line 44):
```erb
<div class="flex items-center h-16 px-2 border-b border-slate-200">
  <a href="/" class="flex items-center gap-3 px-4">
    <!-- existing logo SVG -->
    <span class="text-xl font-semibold tracking-tight text-slate-800">Balance</span>
  </a>
  <button type="button" 
          data-action="privacy-toggle#toggle"
          class="ml-auto mr-2 p-2 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-lg"
          title="Toggle privacy mode">
    <span data-privacy-toggle-target="icon">👁‍🗨</span>
  </button>
</div>
```

**Add toggle button in mobile header** (right side, around line 95):
```erb
<div class="flex items-center justify-between h-14 px-4">
  <a href="/" class="flex items-center gap-2.5 pl-1">
    <!-- existing logo -->
  </a>
  <button type="button"
          data-action="privacy-toggle#toggle" 
          class="p-2 text-slate-400 hover:text-slate-600"
          title="Toggle privacy mode">
    <span data-privacy-toggle-target="icon">👁‍🗨</span>
  </button>
</div>
```

---

## Prerequisite (DONE)

~~**`app/views/dashboard/net_worth.html.erb`** - Consolidated to use `format_currency` helper instead of direct `number_to_currency` calls.~~ 

Committed in `008b184`: "Consolidate currency formatting through helper"

---

## Order of Implementation
1. Create the Stimulus controller (`privacy_toggle_controller.js`)
2. Add CSS styles to `application.css`
3. Modify `application_helper.rb` to wrap currency output in span
4. Update `currency_input_controller.js` to add class to inputs
5. Update `application.html.erb` with buttons and body data-controller

---

## Edge Cases Handled

1. **Turbo navigation:** Controller listens to `turbo:load` to re-apply state after page transitions
2. **Form inputs:** Blurred but unblur on focus so user can still edit values
3. **Multiple buttons:** Both desktop/mobile buttons share state via single controller on body
4. **Tab close:** `sessionStorage` automatically clears when tab closes (privacy by default)

---

## Testing Checklist

### Manual Testing
- [ ] Toggle button appears in desktop sidebar header (right-aligned)
- [ ] Toggle button appears in mobile header (right side)
- [ ] Clicking toggle blurs all currency values
- [ ] Clicking again unblurs
- [ ] Icon changes appropriately (👁 = hidden, 👁‍🗨 = visible)
- [ ] Refreshing page preserves blur state
- [ ] Opening new tab starts with unblurred state (sessionStorage)
- [ ] All currency values blurred: dashboard, transactions, assets, budgets, etc.
- [ ] Form inputs with currency are blurred
- [ ] Focusing a blurred input unblurs it for editing
- [ ] Navigating between pages preserves blur state

### Automated Tests
- [ ] Helper test: `format_currency` outputs span with `currency-value` class
- [ ] Helper test: `format_amount` outputs span with `currency-value` class
- [ ] System test: Toggle button presence and functionality
