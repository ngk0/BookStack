# Roles & Permissions

BookStack uses role-based access control. Your role determines what you can view, edit, and create.

## Role Overview

| Role | Description | Typical Members |
|------|-------------|-----------------|
| **New Hire** | Limited view access during onboarding | New employees in first weeks |
| **Technician** | View all, edit own content | Field technicians |
| **Engineer** | View all, edit own content | Design engineers |
| **Lead Engineer** | View all, edit all content | Senior engineers, project leads |
| **Standards Authority** | Full content access, approve standards | Senior technical leadership |
| **Read-Only** | View specific shelves only | External stakeholders, clients |
| **Admin** | Full system access | System administrators |

## Permission Details

### New Hire

**Can view:**
- Getting Started shelf (full access)
- Training & Development shelf

**Can edit:**
- Nothing (view only)

**Can create:**
- Nothing

**Special abilities:**
- Can leave comments on pages

**Purpose:** Allows new employees to access onboarding materials without access to sensitive standards or procedures until they complete training.

---

### Technician

**Can view:**
- All shelves and content

**Can edit:**
- Pages they created
- Content tagged with their owner tag

**Can create:**
- New pages in designated areas

**Special abilities:**
- Can comment on all pages
- Primary focus on SOPs & Procedures

**Purpose:** Field technicians can document procedures they develop and maintain their own content while referencing all standards.

---

### Engineer

**Can view:**
- All shelves and content

**Can edit:**
- Pages they created
- Content in their assigned areas

**Can create:**
- New pages in most areas

**Special abilities:**
- Can comment on all pages
- Can upload attachments

**Purpose:** Working engineers can create and maintain technical documentation relevant to their projects.

---

### Lead Engineer

**Can view:**
- All shelves and content

**Can edit:**
- All content (any page)

**Can create:**
- Pages, chapters, and books

**Special abilities:**
- Can comment on all pages
- Can move and reorganize content
- Can delete content they created

**Purpose:** Project leads and senior engineers can manage content across their areas and mentor others' contributions.

---

### Standards Authority

**Can view:**
- All shelves and content

**Can edit:**
- All content (any page)

**Can create:**
- Pages, chapters, books, and shelves

**Special abilities:**
- Can approve standards (change tag to `status:approved`)
- Can archive outdated content
- Can delete any content
- Can manage page templates

**Purpose:** Technical leadership responsible for maintaining official standards and approving content for general use.

---

### Read-Only

**Can view:**
- Specific shelves only (configured per user)

**Can edit:**
- Nothing

**Can create:**
- Nothing

**Special abilities:**
- None

**Purpose:** External stakeholders, clients, or auditors who need visibility into specific documentation without edit access.

---

### Admin

**Can view:**
- Everything

**Can edit:**
- Everything

**Can create:**
- Everything

**Special abilities:**
- Manage users and roles
- Configure system settings
- Access audit logs
- Manage API tokens

**Purpose:** System administrators who maintain the BookStack platform itself.

## How Roles Are Assigned

1. **New employees** start as New Hire
2. After onboarding, role upgraded based on position:
   - Field staff → Technician
   - Office engineers → Engineer
3. Promotions to Lead Engineer based on responsibility
4. Standards Authority is a designated position

**To request a role change:** Contact your supervisor or admin.

## Checking Your Permissions

Not sure what you can do?

1. Try to edit a page - if you see "Edit", you have permission
2. Try to create a page - if you see "New Page" in a book, you can create there
3. Contact admin if you believe you need additional access

## Content Ownership

The `owner:XXX` tag system tracks content ownership:

- Tag pages with `owner:` followed by your initials
- Owners are responsible for keeping content current
- Ownership transfers when people leave or change roles

## Permission Requests

Need access to something?

1. **Temporary project need:** Ask a Lead Engineer to update the content for you
2. **Ongoing access need:** Request a role change from your supervisor
3. **External access:** Coordinate through admin for Read-Only accounts
