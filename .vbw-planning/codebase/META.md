# META

## Mapping Metadata

| Field | Value |
|-------|-------|
| mapped_at | 2026-02-09T00:00:00Z |
| git_hash | 1fb781a35575c2d46bfb8cd96f90c64ddf6ed210 |
| file_count | 530 |
| mode | full |
| monorepo | false |
| mapping_tier | solo (inline) |

## Documents

| File | Domain | Description |
|------|--------|-------------|
| `STACK.md` | Tech Stack | Technology choices, framework versions, build pipeline |
| `DEPENDENCIES.md` | Tech Stack | Runtime, dev, and test dependency analysis with coupling assessment |
| `ARCHITECTURE.md` | Architecture | System overview, domain modules, data model, job architecture |
| `STRUCTURE.md` | Architecture | Full directory tree with file counts and organization |
| `CONVENTIONS.md` | Quality | Naming conventions, code style, frontend patterns |
| `TESTING.md` | Quality | Test framework, CI pipeline, coverage strategy, profiling |
| `CONCERNS.md` | Concerns | Technical debt, security risks, performance, operational risks |
| `INDEX.md` | Synthesis | Cross-referenced index with key findings and quick references |
| `PATTERNS.md` | Synthesis | 14 recurring patterns across the codebase |
| `META.md` | Meta | This file -- mapping metadata and document inventory |

## Language Breakdown

| Language | File Count | Notes |
|----------|-----------|-------|
| Ruby (.rb) | ~324 | Models, controllers, jobs, lib modules, tests |
| ERB (.erb) | ~48 | View templates |
| Markdown (.md) | ~45 | Documentation |
| YAML (.yml) | ~16 | Configuration files |
| JavaScript (.js) | ~14 | Stimulus controllers, build entry points |
| CSS (.css) | ~2 | Tailwind input and build output |

## Project Summary

SourceMonitor is a mountable Rails 8 engine (v0.2.1) that ingests RSS/Atom/JSON feeds, scrapes full article content via pluggable adapters, and provides Solid Queue-powered dashboards for monitoring and remediation. It is distributed as a RubyGem, requires PostgreSQL and Ruby >= 3.4.0, and integrates with host Rails applications via the standard engine mounting pattern with an isolated namespace.
