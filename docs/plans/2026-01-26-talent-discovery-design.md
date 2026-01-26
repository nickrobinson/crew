# Talent Discovery Platform Design

Personal recruiting tool for finding developers via GitHub contributions.

## Overview

A Rails application that imports contributors from GitHub repositories you specify, letting you discover and track niche developers (e.g., WASM experts, Bazel contributors) for hiring.

## Core Workflow

1. Paste a GitHub repo URL (e.g., `https://github.com/aspect-build/rules_lint`)
2. System imports all contributors with their profile data
3. Browse, filter, and track developers through a simple pipeline
4. Reach out to promising candidates via their public email

## Data Model

```ruby
# Repository - GitHub repos you've imported
create_table :repositories do |t|
  t.string :github_url, null: false, index: { unique: true }
  t.string :name, null: false                    # "aspect-build/rules_lint"
  t.text :description
  t.string :primary_language
  t.integer :stars_count, default: 0
  t.string :import_status, default: "pending"    # pending, importing, imported, failed
  t.datetime :imported_at
  t.timestamps
end

# Developer - People who contribute to imported repos
create_table :developers do |t|
  t.string :github_username, null: false, index: { unique: true }
  t.integer :github_id, null: false, index: { unique: true }
  t.string :avatar_url
  t.string :profile_url
  t.string :name
  t.text :bio
  t.string :location
  t.string :company
  t.string :email
  t.integer :followers_count, default: 0
  t.integer :public_repos_count, default: 0
  t.json :top_languages, default: []             # ["Rust", "TypeScript", "Go"]
  t.string :status, default: "new"               # new, interesting, contacted, not_a_fit
  t.text :notes
  t.timestamps
end

# Contribution - Join table tracking who contributed to what
create_table :contributions do |t|
  t.references :developer, null: false, foreign_key: true
  t.references :repository, null: false, foreign_key: true
  t.integer :contributions_count, default: 0     # Commits to this repo
  t.timestamps
end
add_index :contributions, [:developer_id, :repository_id], unique: true
```

## Pages

### Dashboard (`/`)
- Quick stats: total developers, count by status, recent imports
- "Add Repository" shortcut form

### Repositories Index (`/repositories`)
- List of imported repos with name, stars, contributor count
- "Add Repository" form
- Click repo to see its contributors

### Repository Show (`/repositories/:id`)
- Repo details (description, stars, language)
- Contributors table sorted by contribution count
- Filter by developer status

### Developers Index (`/developers`)
- All developers across all imported repos
- Filters: status, language, location, min contributions
- Sort: total contributions, followers, recently added
- Bulk status updates

### Developer Show (`/developers/:id`)
- Full profile with GitHub link
- Repos they've contributed to (from your imports)
- Status dropdown + notes (auto-saves)

## GitHub Import Flow

1. User submits repo URL
2. Repository created with `import_status: "pending"`
3. `ImportRepositoryJob` enqueued (Solid Queue)
4. Job fetches:
   - Repo metadata via `GET /repos/:owner/:repo`
   - Contributors via `GET /repos/:owner/:repo/contributors` (paginated)
   - Each contributor's profile via `GET /users/:username`
5. Turbo Streams update the page as developers are imported
6. On completion, `import_status` set to "imported"

### Rate Limits
- GitHub PAT: 5,000 requests/hour
- Typical repo (200 contributors): ~201 requests
- Job pauses and retries if rate limited

### Deduplication
- Developers matched by `github_id`
- Existing profiles updated, new Contribution records added
- Surfaces developers active across multiple repos

## Technical Stack

- **Rails 8** with SQLite
- **Hotwire** (Turbo + Stimulus) for interactivity
- **Solid Queue** for background jobs (no Redis)
- **Tailwind CSS** for styling
- **Faraday** for HTTP requests

## Configuration

```bash
# .env
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
```

No authentication - this is a personal tool.

## Future Extensibility

For community forum integration (Discord, Discourse, etc.):

```ruby
# Option A: Add source tracking to Developer
add_column :developers, :sources, :json, default: []
# e.g., ["github", "discord", "discourse"]

# Option B: Polymorphic sources table
create_table :developer_sources do |t|
  t.references :developer, foreign_key: true
  t.string :source_type    # "github", "discord", "discourse"
  t.string :source_id      # username/id on that platform
  t.json :metadata         # platform-specific data
  t.timestamps
end
```

## File Structure

```
app/
├── controllers/
│   ├── dashboard_controller.rb
│   ├── repositories_controller.rb
│   └── developers_controller.rb
├── models/
│   ├── repository.rb
│   ├── developer.rb
│   └── contribution.rb
├── jobs/
│   └── import_repository_job.rb
├── services/
│   └── github_client.rb
└── views/
    ├── dashboard/
    ├── repositories/
    └── developers/
```
