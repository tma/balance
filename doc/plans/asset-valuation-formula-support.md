# Asset Valuation Formula Support

## Overview

Add support for simple mathematical formulas in the asset valuations mass edit form. Users can input expressions like `5*10` which will display the calculated result (`50`) when blurred, but show the original formula when focused for editing. The formula is stored in the database so it can be edited later or copied to other cells.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Storage | New `formula` text column on `asset_valuations` | Keeps numeric `value` for calculations while preserving original formula |
| Operations | `+ - * /` with `()` grouping | Covers common use cases without complexity |
| Evaluation | JavaScript in browser + Ruby on server | Fast UX, server validates before save |
| Cell references | None (standalone only) | Keeps implementation simple |
| Display | Result shown, formula on focus | Natural spreadsheet-like behavior |
| Plain numbers | Clear formula, store only value | Simple values don't need formula storage |
| Invalid formulas | Reject with visual feedback | Prevents bad data, clear user feedback |
| Formula indicator | Indigo `ƒ` badge in top-right corner | Clear visual cue without being intrusive |

---

## Implementation Plan

### Phase 1: Database Migration

#### New file: `db/migrate/XXXXXX_add_formula_to_asset_valuations.rb`

```ruby
class AddFormulaToAssetValuations < ActiveRecord::Migration[8.1]
  def change
    add_column :asset_valuations, :formula, :string
  end
end
```

---

### Phase 2: CSS Styles

#### Modify: `app/assets/stylesheets/application.css`

Add formula indicator badge styles:

```css
/* Formula indicator badge */
.has-formula {
  position: relative;
}

.has-formula::after {
  content: "ƒ";
  position: absolute;
  top: 2px;
  right: 4px;
  font-size: 10px;
  font-style: italic;
  color: #6366f1; /* indigo-500 */
  pointer-events: none;
  line-height: 1;
}

/* Dark mode */
@media (prefers-color-scheme: dark) {
  .has-formula::after {
    color: #818cf8; /* indigo-400 */
  }
}
```

---

### Phase 3: JavaScript - Formula Evaluation

#### Modify: `app/javascript/controllers/currency_input_controller.js`

Add formula handling:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { liability: Boolean, original: String, formula: String }

  connect() {
    this.element.classList.add("currency-input")
    // Store formula separately so we can restore it
    this.currentFormula = this.formulaValue || null
    if (this.currentFormula) {
      this.element.parentElement.classList.add("has-formula")
    }
    this.format()
    this.checkModified()
  }

  format() {
    const rawValue = this.element.value
    if (rawValue === "" || rawValue === null) return

    // Check if this looks like a formula (contains operators)
    if (this.isFormula(rawValue)) {
      const result = this.evaluateFormula(rawValue)
      if (result !== null) {
        this.currentFormula = rawValue
        this.element.dataset.formula = rawValue
        this.element.parentElement.classList.add("has-formula")
        this.displayValue(result)
      } else {
        // Invalid formula - mark as error
        this.markError()
        return
      }
    } else {
      // Plain number - clear any formula
      this.currentFormula = null
      delete this.element.dataset.formula
      this.element.parentElement.classList.remove("has-formula")
      const num = parseFloat(rawValue.replace(/[-']/g, ""))
      if (!isNaN(num)) {
        this.displayValue(num)
      }
    }
    
    this.clearError()
    this.checkModified()
  }

  unformat() {
    // On focus, show the formula if present, otherwise show raw number
    if (this.currentFormula) {
      this.element.value = this.currentFormula
    } else {
      const value = this.element.value
      if (value !== "" && value !== null) {
        this.element.value = value.replace(/[-']/g, "")
      }
    }
  }

  isFormula(value) {
    // Contains operators beyond just a number (but not just a negative sign at start)
    const withoutLeadingMinus = value.replace(/^-/, "")
    return /[+\-*/()]/.test(withoutLeadingMinus)
  }

  evaluateFormula(formula) {
    // Sanitize: only allow digits, operators, parentheses, decimals, spaces
    const sanitized = formula.replace(/\s/g, "")
    if (!/^[\d+\-*/().]+$/.test(sanitized)) {
      return null
    }
    
    // Check for balanced parentheses
    let depth = 0
    for (const char of sanitized) {
      if (char === "(") depth++
      if (char === ")") depth--
      if (depth < 0) return null
    }
    if (depth !== 0) return null
    
    try {
      // Use Function constructor for safe eval (only math)
      const result = new Function(`return (${sanitized})`)()
      if (typeof result !== "number" || !isFinite(result)) {
        return null
      }
      return result
    } catch (e) {
      return null
    }
  }

  displayValue(num) {
    const parts = num.toFixed(2).split(".")
    parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, "'")
    const decimal = parseFloat("0." + parts[1])
    const formatted = decimal > 0 ? parts.join(".") : parts[0]
    this.element.value = this.liabilityValue ? "-" + formatted : formatted
  }

  markError() {
    this.element.classList.add("border-red-400", "bg-red-50")
    this.element.classList.remove("border-slate-300", "border-amber-400", "bg-amber-50")
  }

  clearError() {
    this.element.classList.remove("border-red-400", "bg-red-50")
  }

  checkModified() {
    // Compare current formula or value against original
    const currentFormula = this.currentFormula
    const originalFormula = this.formulaValue || null
    
    let isModified = false
    
    if (currentFormula !== originalFormula) {
      // Formula changed
      isModified = true
    } else {
      // Compare numeric values
      const currentRaw = this.element.value.replace(/[-']/g, "")
      const originalRaw = (this.originalValue || "").replace(/[-']/g, "")
      const current = parseFloat(currentRaw) || 0
      const original = parseFloat(originalRaw) || 0
      const epsilon = 0.001
      isModified = Math.abs(current - original) > epsilon
    }
    
    if (isModified) {
      this.element.classList.add("border-amber-400", "bg-amber-50")
      this.element.classList.remove("border-slate-300")
    } else {
      this.element.classList.remove("border-amber-400", "bg-amber-50")
      this.element.classList.add("border-slate-300")
    }
  }
}
```

---

### Phase 4: Form Submission Handling

#### Modify: `app/javascript/controllers/currency_form_controller.js`

Update `unformatAll()` to include formula in hidden fields:

```javascript
unformatAll() {
  this.inputTargets.forEach((input) => {
    // If there's a formula, store the computed value for submission
    // but keep formula in data attribute for server to read
    const formula = input.dataset.formula
    if (formula) {
      // Evaluate and set numeric value
      const result = this.evaluateFormula(formula)
      if (result !== null) {
        input.value = result.toString()
        // Add hidden input for formula
        const formulaInput = document.createElement("input")
        formulaInput.type = "hidden"
        formulaInput.name = input.name.replace(/\]$/, "_formula]")
        formulaInput.value = formula
        input.parentNode.appendChild(formulaInput)
      }
    } else {
      // Regular unformat
      const value = input.value
      if (value !== "" && value !== null) {
        input.value = value.replace(/[-']/g, "")
      }
    }
  })
}

evaluateFormula(formula) {
  const sanitized = formula.replace(/\s/g, "")
  if (!/^[\d+\-*/().]+$/.test(sanitized)) return null
  try {
    const result = new Function(`return (${sanitized})`)()
    return typeof result === "number" && isFinite(result) ? result : null
  } catch (e) {
    return null
  }
}
```

---

### Phase 5: Controller Updates

#### Modify: `app/controllers/asset_valuations_controller.rb`

**Update `bulk_update` action** to handle formulas:

```ruby
def bulk_update
  updated_count = 0

  ActiveRecord::Base.transaction do
    params[:valuations]&.each do |asset_id, months_data|
      asset = Asset.find(asset_id)

      months_data.each do |date_str, value|
        # Skip formula keys (they're handled with their corresponding value)
        next if date_str.end_with?("_formula")
        next if value.blank?

        date = Date.parse(date_str)
        
        # Check for formula (in separate param)
        formula_key = "#{date_str}_formula"
        formula = months_data[formula_key]
        
        # Sanitize value
        sanitized_value = value.to_s.gsub(/[^\d.]/, "")
        next if sanitized_value.blank?

        new_value = BigDecimal(sanitized_value)

        valuation = asset.asset_valuations.find_or_initialize_by(date: date)

        # Track if anything changed
        value_changed = valuation.new_record? || valuation.value != new_value
        formula_changed = valuation.formula != formula

        if value_changed || formula_changed
          valuation.value = new_value
          valuation.formula = formula.presence  # nil if blank/plain number
          valuation.save!
          updated_count += 1

          if date == asset.asset_valuations.maximum(:date) || asset.asset_valuations.count == 1
            asset.update_column(:value, new_value)
          end
        end
      end
    end
  end

  redirect_to update_valuations_path, notice: "Saved #{updated_count} #{'valuation'.pluralize(updated_count)}."
rescue ActiveRecord::RecordInvalid => e
  redirect_to update_valuations_path, alert: "Update failed: #{e.message}"
end
```

**Update `build_valuations_lookup`** to include formulas:

```ruby
def build_valuations_lookup
  lookup = Hash.new { |h, k| h[k] = {} }
  formulas = Hash.new { |h, k| h[k] = {} }

  AssetValuation.all.each do |v|
    lookup[v.asset_id][v.date] = v.value
    formulas[v.asset_id][v.date] = v.formula if v.formula.present?
  end

  @formulas_by_asset_and_month = formulas
  lookup
end
```

---

### Phase 6: View Updates

#### Modify: `app/views/asset_valuations/bulk_edit.html.erb`

Update input fields to include formula data (in both active and archived asset sections):

```erb
<% existing_value = @valuations_by_asset_and_month[asset.id][month] %>
<% existing_formula = @formulas_by_asset_and_month[asset.id][month] %>
<% is_liability = asset.asset_type.is_liability %>
<input type="text"
       inputmode="decimal"
       name="valuations[<%= asset.id %>][<%= month.iso8601 %>]"
       value="<%= existing_formula.presence || existing_value&.to_f %>"
       tabindex="<%= tab_index %>"
       data-controller="currency-input"
       data-currency-form-target="input"
       data-currency-input-liability-value="<%= is_liability %>"
       data-currency-input-original-value="<%= existing_value&.to_f %>"
       data-currency-input-formula-value="<%= existing_formula %>"
       data-action="focus->currency-input#unformat blur->currency-input#format"
       ...>
```

Note: The `value` attribute shows the formula if present, so it displays when focused. The Stimulus controller will evaluate and display the result on connect/blur.

---

## Data Flow Summary

1. **User enters formula** (e.g., `5*10`) in input
2. **On blur**: JavaScript evaluates formula → displays `50` (formatted) → stores `5*10` in `data-formula` → adds `has-formula` class to parent
3. **Visual indicator**: `ƒ` badge appears in top-right corner
4. **On focus**: JavaScript restores `5*10` to input for editing
5. **On submit**: `currency_form_controller` creates hidden inputs with formula values
6. **Server receives**: `value=50` and `formula=5*10` 
7. **Database stores**: `value=50.0` (decimal) and `formula="5*10"` (string)
8. **On reload**: View passes formula to input, controller shows result, formula restored on focus

---

## Edge Cases Handled

| Case | Behavior |
|------|----------|
| Plain number `100` | No formula stored, works as before |
| Invalid formula `5*+3` | Red border, not saved |
| Unbalanced parens `5*(10` | Red border, not saved |
| Division by zero `5/0` | Returns Infinity, rejected as invalid |
| Empty cell | No change |
| Copy/paste formula | Formula preserved when copying cell value |
| Negative number `-50` | Treated as plain number (leading minus only) |
| Formula with negative `10*-5` | Evaluated correctly as `-50` |

---

## Testing Checklist

### Manual Testing
- [ ] Enter `5*10` → displays `50`, focus shows `5*10`
- [ ] Enter `100+50/2` → displays `125`
- [ ] Enter `(100+50)/2` → displays `75`
- [ ] Enter plain `100` → displays `100`, no formula stored
- [ ] Enter invalid `5**3` → red border, not saved
- [ ] Enter `5*(10` → red border (unbalanced)
- [ ] Save and reload → formula preserved
- [ ] Edit existing formula → changes saved correctly
- [ ] Clear formula by entering plain number → formula removed
- [ ] Formula cells show `ƒ` badge in top-right corner
- [ ] Badge is indigo colored (visible in light and dark mode)
- [ ] Badge disappears when formula is replaced with plain number
- [ ] Badge appears when entering a new formula
- [ ] Badge doesn't interfere with editing or selection

### Automated Tests
- [ ] Model test: `AssetValuation` saves with formula
- [ ] Controller test: `bulk_update` processes formulas correctly
- [ ] System test: Formula input, display, and persistence

---

## Files to Modify (Summary)

1. **New migration**: `db/migrate/XXXXXX_add_formula_to_asset_valuations.rb`
2. `app/assets/stylesheets/application.css` - Add formula badge styles
3. `app/javascript/controllers/currency_input_controller.js` - Formula evaluation and display
4. `app/javascript/controllers/currency_form_controller.js` - Form submission with formulas
5. `app/controllers/asset_valuations_controller.rb` - Save formulas, build lookup
6. `app/views/asset_valuations/bulk_edit.html.erb` - Pass formula data to inputs (2 places)

---

## Order of Implementation

1. Create migration and run `rails db:migrate`
2. Add CSS styles to `application.css`
3. Update `currency_input_controller.js` with formula evaluation
4. Update `currency_form_controller.js` for form submission
5. Update `asset_valuations_controller.rb` bulk_update and lookup
6. Update `bulk_edit.html.erb` to pass formula data
7. Manual testing
8. Write automated tests
