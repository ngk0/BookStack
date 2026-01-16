# Best Practices

Follow these guidelines to create clear, useful, and maintainable documentation.

## Writing Guidelines

### Be Clear and Direct

- Use simple, straightforward language
- Write for someone who doesn't know the topic
- Avoid jargon unless necessary (and define it when used)
- One idea per paragraph

**Good:** "Turn off the power before opening the panel."
**Avoid:** "Prior to accessing the interior of the enclosure, ensure de-energization of all power sources."

### Use Active Voice

- Say who does what
- Makes instructions clearer

**Good:** "The technician verifies the voltage."
**Avoid:** "The voltage is verified."

### Be Specific

- Include specific values, part numbers, settings
- Avoid vague terms like "some" or "various"

**Good:** "Set the VFD acceleration time to 10 seconds."
**Avoid:** "Set the VFD acceleration time appropriately."

## Formatting Guidelines

### Use Headings

Break content into scannable sections:

```
# Main Title (H1) - one per page
## Major Section (H2)
### Subsection (H3)
#### Detail (H4) - use sparingly
```

### Use Lists

For steps or items:

**Numbered lists** for sequential steps:
1. First do this
2. Then do this
3. Finally do this

**Bullet lists** for non-sequential items:
- Item one
- Item two
- Item three

### Use Tables

For reference information:

| Parameter | Value | Notes |
|-----------|-------|-------|
| Voltage | 480V | 3-phase |
| Current | 50A | Full load |

### Use Code Blocks

For commands, settings, or technical syntax:

```
IP Address: 192.168.1.100
Subnet: 255.255.255.0
Gateway: 192.168.1.1
```

## Naming Conventions

### Page Titles

- Be specific and descriptive
- Include the topic and scope
- Use title case

**Good:**
- "VFD Parameter Settings for Conveyor Applications"
- "Panel Build QC Checklist"
- "PLC Tagging Standard"

**Avoid:**
- "VFDs" (too vague)
- "Checklist" (which one?)
- "Parameters" (for what?)

### File Attachments

Name files clearly:

**Good:**
- `VFD-Parameter-Sheet-AB-PowerFlex525.pdf`
- `Panel-QC-Checklist-v2.xlsx`

**Avoid:**
- `Document1.pdf`
- `New Spreadsheet.xlsx`
- `Copy of Copy of checklist.xlsx`

## Content Organization

### One Topic Per Page

- Each page should cover one topic thoroughly
- If a page gets too long, split it into multiple pages
- Link between related pages

### Use Templates

For standard document types, use the provided templates:
- SOP Template - for procedures
- Technical Specification - for standards
- Competency Checklist - for training
- QC Checklist - for quality checks

### Keep It Current

- Update pages when procedures change
- Add revision notes when making significant changes
- Archive (don't delete) outdated content

## Quality Checklist

Before marking content for review, verify:

- [ ] **Accurate** - Information is correct and verified
- [ ] **Complete** - All necessary information included
- [ ] **Clear** - Easy to understand
- [ ] **Formatted** - Uses headings, lists, tables appropriately
- [ ] **Tagged** - Has appropriate status and owner tags
- [ ] **Located** - In the correct shelf/book/chapter
- [ ] **Linked** - References related content where helpful
- [ ] **Titled** - Has a clear, descriptive title

## What Not to Document

Some things don't belong in BookStack:

- **Project-specific documents** - Use project folders on shared drives
- **Temporary notes** - Use personal notes or email
- **Confidential HR information** - Use appropriate HR systems
- **Active design files** - Use version control (Git) or project folders
- **Client-proprietary information** - Follow client agreements

## Contributing Etiquette

### Do:
- Improve content you find errors in
- Add useful information when you learn something
- Follow up on comments and feedback
- Thank reviewers for their time

### Don't:
- Delete others' content without discussion
- Make major changes without notifying owner
- Ignore review feedback
- Create duplicate pages

## Getting Feedback

Want input on your content?

1. Tag with `status:draft` and save
2. Share the page link with colleagues
3. Ask them to add comments
4. Incorporate feedback
5. Move to `status:review` when ready

Comments appear at the bottom of each page and notify the page owner.
