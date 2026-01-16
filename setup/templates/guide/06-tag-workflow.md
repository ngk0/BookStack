# Tag Workflow

Since BookStack doesn't have a built-in approval workflow, we use tags to track document status. This system ensures content is reviewed before being marked as official.

## Document Lifecycle

Every document follows this progression:

```
┌─────────────┐    ┌─────────────┐    ┌──────────────┐
│   DRAFT     │ → │   REVIEW    │ → │   APPROVED   │
│             │    │             │    │              │
│ status:draft│    │status:review│    │status:approved│
└─────────────┘    └─────────────┘    └──────────────┘
                                             │
                                             ↓
                                      ┌──────────────┐
                                      │   ARCHIVED   │
                                      │              │
                                      │status:archived│
                                      └──────────────┘
```

## Status Tags

### status:draft

**Meaning:** Work in progress - not ready for use

**Who applies it:** Anyone creating new content

**When to use:**
- New pages being written
- Pages under active revision
- Content not yet reviewed

**Important:** Draft content should not be relied upon for official work.

---

### status:review

**Meaning:** Ready for peer or authority review

**Who applies it:** Content author when ready for review

**When to use:**
- Content is complete and ready for feedback
- Author believes it's ready for approval
- Waiting for Standards Authority sign-off

**What happens next:**
- Reviewer checks content for accuracy
- May suggest changes (returns to draft)
- May approve (moves to approved)

---

### status:approved

**Meaning:** Official, approved content - safe to use

**Who applies it:** Standards Authority or Lead Engineers

**When to use:**
- Content has been reviewed and verified
- Ready for general use by the team
- Considered authoritative

**Important:** Only approved content should be used for official work.

---

### status:archived

**Meaning:** No longer current - kept for reference only

**Who applies it:** Standards Authority or content owners

**When to use:**
- Superseded by newer version
- Process or standard no longer applies
- Historical reference only

**Important:** Archived content may be outdated or incorrect.

---

### review:required

**Meaning:** Needs Standards Authority review specifically

**Who applies it:** Anyone who believes content needs official review

**When to use:**
- Content affects safety or compliance
- Changes to official standards
- Uncertainty about correctness

---

### owner:XXX

**Meaning:** Content owner identified by initials

**Who applies it:** Content authors

**Format:** `owner:` followed by initials (e.g., `owner:JDS`)

**Purpose:**
- Identifies who to contact about the content
- Shows who is responsible for keeping it current
- Helps with content governance

## The Review Process

### For Authors

1. **Create content** and tag with `status:draft`
2. **Complete your content** - make sure it's ready
3. **Change tag to `status:review`**
4. **Notify a reviewer:**
   - For standards: Contact Standards Authority
   - For procedures: Contact a Lead Engineer
   - For general content: Contact any Lead Engineer
5. **Address feedback** if changes requested
6. **Wait for approval** - reviewer will update tag

### For Reviewers

1. **Find content tagged `status:review`**
2. **Review for:**
   - Technical accuracy
   - Completeness
   - Clarity and formatting
   - Correct location in structure
3. **Either:**
   - Request changes (change back to `status:draft`, add comment)
   - Approve (change to `status:approved`)

### For Standards Authority

Additional review criteria:
- Alignment with company standards
- Safety implications
- Regulatory compliance
- Consistency with other approved content

## Best Practices

### Do:
- Always tag new content with `status:draft`
- Add your owner tag to content you create
- Move to `status:review` only when truly ready
- Check tags before using content for official work

### Don't:
- Use draft content for official purposes
- Self-approve your own content to `status:approved`
- Remove tags without updating status
- Ignore archived content warnings

## Finding Content by Status

Use search or click tags to filter:

- **Find approved content:** Search `status:approved`
- **Find content needing review:** Search `status:review`
- **Find drafts:** Search `status:draft`
- **Find your content:** Search `owner:YourInitials`

## When Content Needs Updates

Existing approved content may need revision:

1. Make edits to the page
2. Change tag from `status:approved` to `status:review`
3. Add note in revision history explaining changes
4. Notify reviewer for re-approval

Minor fixes (typos, formatting) don't require re-review.
