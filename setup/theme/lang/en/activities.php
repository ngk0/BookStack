<?php
/**
 * LAPORTE Theme - Activity Log Translation Overrides
 *
 * Remaps activity log messages to use custom terminology:
 *   Shelves → Areas
 *   Books → Topics
 *   Chapters → Subtopics
 */

return [
    // ==========================================================================
    // Area (Shelf) Activities
    // ==========================================================================
    'bookshelf_create' => 'created area',
    'bookshelf_create_notification' => 'Area successfully created',
    'bookshelf_create_from_book' => 'converted topic to area',
    'bookshelf_create_from_book_notification' => 'Topic successfully converted to an area',
    'bookshelf_update' => 'updated area',
    'bookshelf_update_notification' => 'Area successfully updated',
    'bookshelf_delete' => 'deleted area',
    'bookshelf_delete_notification' => 'Area successfully deleted',

    // ==========================================================================
    // Topic (Book) Activities
    // ==========================================================================
    'book_create' => 'created topic',
    'book_create_notification' => 'Topic successfully created',
    'book_create_from_chapter' => 'converted subtopic to topic',
    'book_create_from_chapter_notification' => 'Subtopic successfully converted to a topic',
    'book_update' => 'updated topic',
    'book_update_notification' => 'Topic successfully updated',
    'book_delete' => 'deleted topic',
    'book_delete_notification' => 'Topic successfully deleted',
    'book_sort' => 'sorted topic',
    'book_sort_notification' => 'Topic successfully re-sorted',

    // ==========================================================================
    // Subtopic (Chapter) Activities
    // ==========================================================================
    'chapter_create' => 'created subtopic',
    'chapter_create_notification' => 'Subtopic successfully created',
    'chapter_update' => 'updated subtopic',
    'chapter_update_notification' => 'Subtopic successfully updated',
    'chapter_delete' => 'deleted subtopic',
    'chapter_delete_notification' => 'Subtopic successfully deleted',
    'chapter_move' => 'moved subtopic',
    'chapter_move_notification' => 'Subtopic successfully moved',
];
