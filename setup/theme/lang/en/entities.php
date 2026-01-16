<?php
/**
 * LAPORTE Theme - Entity Name Overrides
 *
 * Renames BookStack hierarchy:
 *   Shelves → Areas
 *   Books → Topics
 *   Chapters → Subtopics
 *   Sections → Sections (unchanged)
 *   Pages → Pages (unchanged)
 */

return [
    // ==========================================================================
    // Singular Forms
    // ==========================================================================
    'shelf' => 'Area',
    'book' => 'Topic',
    'chapter' => 'Subtopic',

    // ==========================================================================
    // Plural Forms
    // ==========================================================================
    'shelves' => 'Areas',
    'books' => 'Topics',
    'chapters' => 'Subtopics',

    // ==========================================================================
    // Count Forms (used in "5 Books" type displays)
    // ==========================================================================
    'x_shelves' => ':count Area|:count Areas',
    'x_books' => ':count Topic|:count Topics',
    'x_chapters' => ':count Subtopic|:count Subtopics',

    // ==========================================================================
    // Shelf (Area) Labels
    // ==========================================================================
    'shelves_new_action' => 'New Area',
    'shelves_create' => 'Create New Area',
    'shelves_edit' => 'Edit Area',
    'shelves_edit_named' => 'Edit Area :name',
    'shelves_delete' => 'Delete Area',
    'shelves_delete_named' => 'Delete Area :name',
    'shelves_delete_explain' => 'This will delete the area with the name \':name\'. Contained topics will not be deleted.',
    'shelves_delete_confirmation' => 'Are you sure you want to delete this area?',
    'shelves_permissions' => 'Area Permissions',
    'shelves_permissions_updated' => 'Area Permissions Updated',
    'shelves_permissions_active' => 'Area Permissions Active',
    'shelves_permissions_cascade_warning' => 'Permissions on areas do not automatically cascade to contained topics. This is because a topic can exist on multiple areas. Permissions can however be copied down to child topics using the option found below.',
    'shelves_permissions_create' => 'Area create permissions are only used for copying permissions to child topics using the action below. They do not control the ability to create topics.',
    'shelves_copy_permissions_to_books' => 'Copy Permissions to Topics',
    'shelves_copy_permissions' => 'Copy Permissions',
    'shelves_copy_permissions_explain' => 'This will apply the current permission settings of this area to all topics contained within. Before activating, ensure any changes to the permissions of this area have been saved.',
    'shelves_copy_permission_success' => 'Area permissions copied to :count topics',
    'shelves_save' => 'Save Area',
    'shelves_books' => 'Topics on this area',
    'shelves_add_books' => 'Add topics to this area',
    'shelves_drag_books' => 'Drag topics below to add them to this area',
    'shelves_empty_contents' => 'This area has no topics assigned to it',

    // ==========================================================================
    // Book (Topic) Labels
    // ==========================================================================
    'books_create' => 'Create New Topic',
    'books_edit' => 'Edit Topic',
    'books_edit_named' => 'Edit Topic :name',
    'books_form_book_name' => 'Topic Name',
    'books_save' => 'Save Topic',
    'books_permissions' => 'Topic Permissions',
    'books_permissions_updated' => 'Topic Permissions Updated',
    'books_empty' => 'No topics have been created',
    'books_popular' => 'Popular Topics',
    'books_recent' => 'Recent Topics',
    'books_new' => 'New Topics',
    'books_new_action' => 'New Topic',
    'books_popular_empty' => 'The most popular topics will appear here.',
    'books_new_empty' => 'The most recently created topics will appear here.',
    'books_copy' => 'Copy Topic',
    'books_copy_success' => 'Topic successfully copied',
    'books_delete' => 'Delete Topic',
    'books_delete_named' => 'Delete Topic :name',
    'books_delete_explain' => 'This will delete the topic with the name \':name\'. All pages and subtopics will be removed.',
    'books_delete_confirmation' => 'Are you sure you want to delete this topic?',
    'books_sort' => 'Sort Topic Contents',
    'books_sort_desc' => 'Move subtopics and pages within a topic to reorganise its contents. Other topics can be added which allows easy moving of subtopics and pages between topics.',
    'books_sort_named' => 'Sort Topic :name',
    'books_sort_name' => 'Sort by Name',
    'books_sort_created' => 'Sort by Created Date',
    'books_sort_updated' => 'Sort by Updated Date',
    'books_sort_chapters_first' => 'Subtopics First',
    'books_sort_chapters_last' => 'Subtopics Last',
    'books_sort_show_other' => 'Show Other Topics',
    'books_sort_save' => 'Save New Order',
    'books_sort_show_other_desc' => 'Add other topics here to include them in the sort operation, and allow easy cross-topic reorganisation.',
    'books_sort_move_up' => 'Move Up',
    'books_sort_move_down' => 'Move Down',
    'books_sort_move_prev_book' => 'Move to Previous Topic',
    'books_sort_move_next_book' => 'Move to Next Topic',
    'books_sort_move_prev_chapter' => 'Move Into Previous Subtopic',
    'books_sort_move_next_chapter' => 'Move Into Next Subtopic',
    'books_sort_move_book_start' => 'Move to Start of Topic',
    'books_sort_move_book_end' => 'Move to End of Topic',
    'books_sort_move_before_chapter' => 'Move to Before Subtopic',
    'books_sort_move_after_chapter' => 'Move to After Subtopic',
    'books_copy_permissions_to_chapters' => 'Copy Permissions to Subtopics',
    'books_copy_permissions_to_chapters_desc' => 'Copy the current permissions of this topic to all subtopics within. Before activating, ensure any changes to the permissions of this topic have been saved.',

    // ==========================================================================
    // Chapter (Subtopic) Labels
    // ==========================================================================
    'chapters_create' => 'Create New Subtopic',
    'chapters_edit' => 'Edit Subtopic',
    'chapters_edit_named' => 'Edit Subtopic :name',
    'chapters_save' => 'Save Subtopic',
    'chapters_move' => 'Move Subtopic',
    'chapters_move_named' => 'Move Subtopic :name',
    'chapters_copy' => 'Copy Subtopic',
    'chapters_copy_success' => 'Subtopic successfully copied',
    'chapters_permissions' => 'Subtopic Permissions',
    'chapters_empty' => 'No subtopics are currently in this topic.',
    'chapters_permissions_active' => 'Subtopic Permissions Active',
    'chapters_permissions_success' => 'Subtopic Permissions Updated',
    'chapters_search_this' => 'Search this subtopic',
    'chapters_delete' => 'Delete Subtopic',
    'chapters_delete_named' => 'Delete Subtopic :name',
    'chapters_delete_explain' => 'This will delete the subtopic with the name \':name\'. All pages that exist within this subtopic will also be deleted.',
    'chapters_delete_confirm' => 'Are you sure you want to delete this subtopic?',
    'chapters_new' => 'New Subtopic',
    'chapters_new_action' => 'New Subtopic',
    'chapters_popular' => 'Popular Subtopics',

    // ==========================================================================
    // Page Labels (keeping as "Page")
    // ==========================================================================
    'pages_not_in_chapter' => 'Page is not in a subtopic',
    'pages_move_chapter_none' => '(No Subtopic)',
    'pages_move_book_note' => 'Select a topic to move the page to. Moving to another topic will reset any permissions that have been applied to this page.',
    'pages_copy_book_note' => 'Select a topic to copy the page to.',
    'pages_move' => 'Move Page',
    'pages_copy_desination' => 'Copy Destination',
    'pages_initial_revision' => 'Initial publish',
    'pages_references_update_revision' => 'System auto-update of internal links',
    'pages_initial_name' => 'New Page',
    'pages_editing_draft_notification' => 'You are currently editing a draft that was last saved :timeDiff.',
    'pages_draft_discarded' => 'Draft discarded! The editor has been updated with the current page content',
    'pages_draft_deleted' => 'Draft deleted! The editor has been updated with the current page content',

    // ==========================================================================
    // Misc
    // ==========================================================================
    'entity_select_lack_permission' => 'You don\'t have the required permissions to select this item',
];
