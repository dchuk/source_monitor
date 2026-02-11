# Tailwind CSS Integration with Hotwire

## Principles

- Mobile-first responsive design
- Semantic HTML with accessibility
- Consistent color palette and spacing
- Focus states on all interactive elements

## Responsive Breakpoints

```
sm:  640px+  (small tablets)
md:  768px+  (tablets)
lg:  1024px+ (desktops)
xl:  1280px+ (large desktops)
```

## Common Patterns

### Responsive Grid

```erb
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
  <%= render @items %>
</div>
```

### Button Variants

```erb
<%# Primary %>
<%= link_to "Save", path, class: "bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 px-4 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors" %>

<%# Secondary %>
<%= link_to "Cancel", path, class: "bg-gray-100 hover:bg-gray-200 text-gray-700 font-semibold py-2 px-4 rounded-md border border-gray-300 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2 transition-colors" %>

<%# Danger %>
<%= button_to "Delete", path, method: :delete, data: { turbo_confirm: "Are you sure?" }, class: "bg-red-600 hover:bg-red-700 text-white font-semibold py-2 px-4 rounded-md focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 transition-colors" %>
```

### Form Fields

```erb
<div class="space-y-1">
  <%= f.label :name, class: "block text-sm font-medium text-gray-700" %>
  <%= f.text_field :name, class: "w-full px-3 py-2 rounded-md border border-gray-300 focus:border-blue-500 focus:ring-2 focus:ring-blue-500 transition-colors", placeholder: "Enter name..." %>
</div>
```

### Cards

```erb
<div class="bg-white rounded-lg shadow-md p-6">
  <h3 class="text-xl font-semibold text-gray-800 mb-2">Title</h3>
  <p class="text-gray-600">Content</p>
</div>
```

### Badges

```erb
<span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">Active</span>
<span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">Inactive</span>
```

### Alerts

```erb
<div class="bg-green-50 border border-green-200 text-green-800 px-4 py-3 rounded-md" role="alert">
  <p class="font-medium">Success!</p>
</div>
```

## Turbo-Specific Styling

### Turbo Frame Loading State

```erb
<turbo-frame id="comments" src="<%= comments_path %>" loading="lazy" class="space-y-4">
  <div class="flex items-center justify-center p-8">
    <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
  </div>
</turbo-frame>
```

### Skeleton Loader

```erb
<div class="animate-pulse space-y-4">
  <div class="h-4 bg-gray-200 rounded w-3/4"></div>
  <div class="h-4 bg-gray-200 rounded w-1/2"></div>
</div>
```

## Accessibility

- Use semantic HTML (`<nav>`, `<main>`, `<article>`, `<button>`)
- Include `aria-label` for icon-only buttons
- Ensure focus states with `focus:ring-` classes
- Add `sr-only` class for screen-reader-only text
- Minimum contrast ratio WCAG AA: 4.5:1

## Color Usage

| Color | Purpose |
|-------|---------|
| `blue-*` | Primary actions, links |
| `green-*` | Success, confirmations |
| `red-*` | Errors, destructive actions |
| `yellow-*` | Warnings |
| `gray-*` | Neutral, borders, disabled |
