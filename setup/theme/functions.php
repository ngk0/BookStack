<?php
/**
 * LAPORTE Custom Theme for BookStack
 *
 * Customizations:
 * - Hides grid/list view toggle (forces list view)
 * - Entity renaming handled via lang/ overrides
 *
 * Brand Colors (for reference):
 * - Primary Dark Blue: #00263b
 * - Accent Golden Yellow: #E9B52D
 * - Text Dark Gray: #4a4a4a
 * - Light Blue Background: #eef6f9
 */

use BookStack\Theming\ThemeEvents;
use BookStack\Facades\Theme;

// Inject custom CSS to hide grid/list view toggle
Theme::listen(ThemeEvents::APP_BOOT, function($app) {
    // Add CSS to hide view mode toggle buttons
    $css = <<<'CSS'
<style>
/* LAPORTE Theme - Hide grid/list view toggle (force list view) */
.view-toggle,
.grid-list-toggle,
[href*="view_type=grid"],
[href*="view_type=list"],
a[title="Grid View"],
a[title="List View"],
.icon-list-item[href*="view_type"],
.text-link[href*="view_type"] {
    display: none !important;
}
</style>
CSS;

    // Share CSS to be included in head via customHeadContent
    $existingContent = view()->shared('customHeadContent', '');
    view()->share('customHeadContent', $existingContent . $css);
});
