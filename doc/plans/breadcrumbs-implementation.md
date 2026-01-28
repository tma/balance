# Breadcrumbs Implementation

## Problem
- The broker connection show page has "Back to Connections" links at the bottom
- These are inconsistent with modern UX patterns
- User wants breadcrumbs at the top of pages for navigation

## Current State
- "Back to X" links exist at the bottom of detail pages (broker_connections/show, broker_positions/show)
- No breadcrumb system exists in the app
- Layout has a main content area starting at line 111-124 in application.html.erb

## Proposed Solution

### Approach: content_for with helper
Use Rails' `content_for :breadcrumbs` pattern with a UI helper for consistent styling.

### Changes Required

1. **Add breadcrumb helper methods to `app/helpers/ui_helper.rb`**
   - `ui_breadcrumbs(&block)` - wrapper for breadcrumb list
   - `ui_breadcrumb_item(text, path, current: false)` - individual crumb

2. **Modify `app/views/layouts/application.html.erb`**
   - Add `yield :breadcrumbs` before `yield` in main content area
   - Display only if breadcrumbs content exists

3. **Update `app/views/admin/broker_connections/show.html.erb`**
   - Remove "Back to Connections" link at bottom
   - Add breadcrumbs at top: Settings > Brokers > [Connection Name]

4. **Update `app/views/admin/broker_positions/show.html.erb`**
   - Remove "Back to" link at bottom  
   - Add breadcrumbs: Settings > Brokers > [Connection Name] > [Symbol]

5. **Optionally update other admin pages for consistency**
   - broker_connections/edit.html.erb
   - broker_connections/new.html.erb

## Implementation

### Breadcrumb HTML structure (Tailwind)
```erb
<nav aria-label="Breadcrumb" class="mb-4">
  <ol class="flex items-center gap-2 text-sm text-slate-500 dark:text-slate-400">
    <li><a href="..." class="hover:text-slate-700 dark:hover:text-slate-200">Parent</a></li>
    <li class="text-slate-300 dark:text-slate-600">/</li>
    <li class="text-slate-700 dark:text-slate-200 font-medium">Current</li>
  </ol>
</nav>
```

### Helper Usage
```erb
<% content_for :breadcrumbs do %>
  <%= ui_breadcrumbs do %>
    <%= ui_breadcrumb_item "Settings", "#" %>
    <%= ui_breadcrumb_item "Brokers", admin_broker_connections_path %>
    <%= ui_breadcrumb_item @connection.name, nil, current: true %>
  <% end %>
<% end %>
```

## Files to Modify
- `app/helpers/ui_helper.rb` - add breadcrumb helpers
- `app/views/layouts/application.html.erb` - add breadcrumb yield
- `app/views/admin/broker_connections/show.html.erb` - add breadcrumbs, remove back link
- `app/views/admin/broker_positions/show.html.erb` - add breadcrumbs, remove back link
- `app/views/admin/broker_connections/edit.html.erb` - add breadcrumbs (optional)
- `app/views/admin/broker_connections/new.html.erb` - add breadcrumbs (optional)
