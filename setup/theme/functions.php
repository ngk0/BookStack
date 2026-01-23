<?php
/**
 * LAPORTE Custom Theme for BookStack
 *
 * Customizations:
 * - Hides grid/list view toggle (forces list view)
 * - Admin banner with content-generator integration
 * - Entity renaming handled via lang/ overrides
 * - Custom CSS/JS injected on ALL pages (including admin via blade override)
 *
 * Brand Colors (for reference):
 * - Primary Dark Blue: #00263b
 * - Accent Golden Yellow: #E9B52D
 * - Text Dark Gray: #4a4a4a
 * - Light Blue Background: #eef6f9
 */

// No theme events needed - we use blade template overrides instead
// to inject custom head content on ALL pages including settings.
