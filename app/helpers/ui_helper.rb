module UiHelper
  # ===========================================
  # Layout & Containers
  # ===========================================

  # Main card/box container
  def ui_card_class
    "bg-white dark:bg-slate-800 rounded-xl border border-slate-200 dark:border-slate-700"
  end

  # Card with overflow hidden (for tables)
  def ui_card_table_class
    "#{ui_card_class} overflow-hidden"
  end

  # Card header section
  def ui_card_header_class
    "p-4 border-b border-slate-200 dark:border-slate-700"
  end

  # Card body/content section
  def ui_card_body_class
    "bg-white dark:bg-slate-800"
  end

  # Empty state container
  def ui_empty_class
    "p-6 text-center"
  end

  # ===========================================
  # Typography
  # ===========================================

  # Page title (h1)
  def ui_title_class
    "text-2xl font-bold text-slate-800 dark:text-slate-100"
  end

  # Section title (h2)
  def ui_heading_class
    "text-lg font-semibold text-slate-800 dark:text-slate-100"
  end

  # Card/subsection title (h3)
  def ui_subheading_class
    "text-sm font-semibold text-slate-800 dark:text-slate-100"
  end

  # Primary text (main content)
  def ui_text_class
    "text-slate-700 dark:text-slate-200"
  end

  # Secondary/muted text
  def ui_text_muted_class
    "text-slate-500 dark:text-slate-400"
  end

  # Tertiary/subtle text
  def ui_text_subtle_class
    "text-slate-400 dark:text-slate-500"
  end

  # Large display number (e.g., net worth)
  def ui_display_number_class
    "text-4xl font-bold text-slate-800 dark:text-slate-100"
  end

  # ===========================================
  # Tables
  # ===========================================

  # Table header row
  def ui_table_header_class
    "bg-slate-50 dark:bg-slate-800 border-b border-slate-200 dark:border-slate-700"
  end

  # Table header cell
  def ui_table_th_class
    "px-4 py-2 text-left text-xs font-medium text-slate-500 dark:text-slate-400 uppercase tracking-wider"
  end

  # Table body row
  def ui_table_row_class
    "border-b border-slate-100 dark:border-slate-700/50 last:border-b-0 hover:bg-slate-50 dark:hover:bg-slate-900 transition"
  end

  # Table cell
  def ui_table_td_class
    "px-4 py-2 text-sm"
  end

  # Table group header row (for grouped tables)
  def ui_table_group_header_class
    "bg-slate-200 dark:bg-slate-700"
  end

  # Text color for group header (matches darker bg)
  def ui_table_group_text_class
    "text-slate-700 dark:text-slate-200"
  end

  # Table subtotal row
  def ui_table_subtotal_class
    "bg-slate-50 dark:bg-slate-800 border-t border-slate-200 dark:border-slate-600"
  end

  # Table total/footer row
  def ui_table_total_class
    "bg-slate-200 dark:bg-slate-700 border-t-4 border-slate-300 dark:border-slate-600"
  end

  # ===========================================
  # Forms
  # ===========================================

  # Form label
  def ui_label_class
    "block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1"
  end

  # Text input / textarea / select
  def ui_input_class
    "w-full px-3 py-2 border border-slate-300 dark:border-slate-600 rounded-lg " \
    "bg-white dark:bg-slate-700 text-slate-900 dark:text-slate-100 " \
    "placeholder-slate-400 dark:placeholder-slate-500 " \
    "focus:outline-none focus:ring-2 focus:ring-cyan-500 focus:border-cyan-500"
  end

  # Small input variant
  def ui_input_sm_class
    "px-2 py-1.5 text-sm border border-slate-300 dark:border-slate-600 rounded-lg " \
    "bg-white dark:bg-slate-700 text-slate-900 dark:text-slate-100 " \
    "focus:outline-none focus:ring-2 focus:ring-cyan-500 focus:border-cyan-500"
  end

  # Checkbox / radio
  def ui_checkbox_class
    "rounded border-slate-300 dark:border-slate-600 text-cyan-600 " \
    "focus:ring-cyan-500 dark:bg-slate-700"
  end

  # ===========================================
  # Buttons
  # ===========================================

  # Primary button (cyan)
  def ui_btn_primary_class
    "px-4 py-2 bg-cyan-500 hover:bg-cyan-600 text-white font-medium rounded-lg transition"
  end

  # Secondary button (slate)
  def ui_btn_secondary_class
    "px-4 py-2 bg-slate-100 dark:bg-slate-700 hover:bg-slate-200 dark:hover:bg-slate-600 " \
    "text-slate-600 dark:text-slate-300 font-medium rounded-lg transition"
  end

  # Danger button (rose)
  def ui_btn_danger_class
    "px-4 py-2 bg-rose-500 hover:bg-rose-600 text-white font-medium rounded-lg transition"
  end

  # Ghost/link button
  def ui_btn_ghost_class
    "px-4 py-2 text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-100 " \
    "hover:bg-slate-100 dark:hover:bg-slate-700 rounded-lg transition"
  end

  # Small button modifier
  def ui_btn_sm_class
    "px-3 py-1.5 text-sm"
  end

  # ===========================================
  # Links
  # ===========================================

  # Primary link (cyan)
  def ui_link_class
    "text-cyan-600 dark:text-cyan-400 hover:text-cyan-700 dark:hover:text-cyan-300 hover:underline"
  end

  # Muted link
  def ui_link_muted_class
    "text-slate-500 dark:text-slate-400 hover:text-slate-700 dark:hover:text-slate-200"
  end

  # ===========================================
  # Badges & Tags
  # ===========================================

  # Neutral badge
  def ui_badge_class
    "px-2 py-0.5 text-xs rounded bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300"
  end

  # Success badge (green)
  def ui_badge_success_class
    "px-2 py-0.5 text-xs rounded bg-emerald-100 dark:bg-emerald-900/50 text-emerald-700 dark:text-emerald-300"
  end

  # Warning badge (amber)
  def ui_badge_warning_class
    "px-2 py-0.5 text-xs rounded bg-amber-100 dark:bg-slate-700 text-amber-700 dark:text-amber-300 border border-amber-200 dark:border-amber-400/50"
  end

  # Danger badge (rose)
  def ui_badge_danger_class
    "px-2 py-0.5 text-xs rounded bg-rose-100 dark:bg-rose-900/50 text-rose-700 dark:text-rose-300"
  end

  # Info badge (cyan)
  def ui_badge_info_class
    "px-2 py-0.5 text-xs rounded bg-cyan-50 dark:bg-cyan-900/50 text-cyan-600 dark:text-cyan-300"
  end

  # ===========================================
  # Alerts / Flash Messages
  # ===========================================

  # Success alert
  def ui_alert_success_class
    "p-4 rounded-lg bg-emerald-50 dark:bg-emerald-900/30 border border-emerald-200 dark:border-emerald-800 " \
    "text-emerald-700 dark:text-emerald-300"
  end

  # Error alert
  def ui_alert_error_class
    "p-4 rounded-lg bg-rose-50 dark:bg-rose-900/30 border border-rose-200 dark:border-rose-800 " \
    "text-rose-700 dark:text-rose-300"
  end

  # Warning alert
  def ui_alert_warning_class
    "p-4 rounded-lg bg-amber-50 dark:bg-slate-800 border border-amber-200 dark:border-slate-700 " \
    "border-l-4 border-l-amber-300 dark:border-l-amber-400 text-amber-800 dark:text-slate-200"
  end

  # Info alert
  def ui_alert_info_class
    "p-4 rounded-lg bg-cyan-50 dark:bg-slate-800 border border-cyan-200 dark:border-slate-700 " \
    "border-l-4 border-l-cyan-400 dark:border-l-cyan-500 text-cyan-800 dark:text-slate-200"
  end

  # ===========================================
  # Dividers
  # ===========================================

  def ui_divider_class
    "border-t border-slate-200 dark:border-slate-700"
  end

  # ===========================================
  # Positive/Negative values (for financial data)
  # ===========================================

  def ui_positive_class
    "text-emerald-600 dark:text-emerald-400"
  end

  def ui_negative_class
    "text-rose-500 dark:text-rose-400"
  end

  # ===========================================
  # Breadcrumbs
  # ===========================================

  # Breadcrumb container - wraps the breadcrumb items
  def ui_breadcrumbs(&block)
    content_tag(:nav, aria: { label: "Breadcrumb" }) do
      content_tag(:ol, class: "flex items-center gap-2 text-sm text-slate-500 dark:text-slate-400", &block)
    end
  end

  # Individual breadcrumb item
  # Pass path: nil for current/non-linked items
  def ui_breadcrumb_item(text, path = nil, current: false)
    item_class = current ? "text-slate-700 dark:text-slate-200 font-medium" : ""
    link_class = "hover:text-slate-700 dark:hover:text-slate-200"
    separator = content_tag(:li, "/", class: "text-slate-300 dark:text-slate-600")

    item = if path && !current
             content_tag(:li) { link_to(text, path, class: link_class) }
    else
             content_tag(:li, text, class: item_class)
    end

    # Return item with separator, unless it's the first item (handled by caller context)
    safe_join([ separator, item ])
  end

  # First breadcrumb item (no preceding separator)
  def ui_breadcrumb_first(text, path = nil)
    link_class = "hover:text-slate-700 dark:hover:text-slate-200"

    if path
      content_tag(:li) { link_to(text, path, class: link_class) }
    else
      content_tag(:li, text)
    end
  end
end
