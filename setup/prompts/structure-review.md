# EIC BookStack Structure Review

## Project Context

You are reviewing the content structure for EIC's engineering training and knowledge management system.

**Organization**: EIC (Engineering Integration Company)
**Industry**: Electrical and Controls Engineering for industrial automation

**This BookStack instance serves**:
- Electrical/Controls engineers and designers
- Field technicians
- New hires going through onboarding
- Project managers needing reference material

**Content Types**:
- Onboarding and orientation materials
- Engineering standards (electrical, controls, documentation)
- Standard Operating Procedures (SOPs)
- Training and career development tracks
- Reference materials (vendor docs, codes, templates)
- Lessons learned and project knowledge

**Target Deliverables** the training supports:
- One-line diagrams
- Control panel designs
- PLC programs (Allen-Bradley, Siemens)
- HMI screens (FactoryTalk, Ignition)
- Wiring diagrams and schematics
- Arc flash studies
- Commissioning documentation
- As-built drawings

---

## Current Structure

Below is the current content hierarchy defined in structure.yaml:

```yaml
{{STRUCTURE_YAML}}
```

---

## Your Task

Review this structure as a Senior Electrical/Controls Engineer and Training Director. Identify:

1. **Missing Topics**: What topics should exist given the scope but are not present?
   - Consider: common engineering tasks, frequent pain points, regulatory requirements

2. **Organizational Issues**: Are items in the wrong shelf/book? Should anything be reorganized?

3. **Gaps in Coverage**: Are there books that need additional chapters?
   - Consider: What would a new engineer need to know?
   - What causes the most RFIs and rework?

4. **Naming Improvements**: Are any names unclear or inconsistent?

5. **Redundancy**: Is anything duplicated that should be consolidated?

---

## Output Format

Return your analysis in this exact format:

### Summary
(2-3 sentences summarizing your findings)

### Suggested Additions
```yaml
# Add these to structure.yaml
# Comments explain why each addition is recommended

shelves:
  <Shelf Name>:
    books:
      <Book Name>:
        description: <description>
        chapters:
          <Chapter Name>: <description>  # Why: <reason>
```

### Organizational Changes
(List any items that should be moved, with reasoning)

### Naming Improvements
(List any items that should be renamed, with old → new)

### Priority Ranking
1. (Most important addition/change)
2. (Second most important)
3. (Third most important)

---

## Guidelines

- Focus on practical, real-world engineering needs
- Consider what causes problems in the field
- Think about what new hires struggle with most
- Don't suggest theoretical or academic topics
- Keep suggestions aligned with contractor-ready, deliverable-first philosophy
- Be specific - don't suggest vague categories

---

Begin your review now.
