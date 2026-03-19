# Crew

A GitHub Developer Intelligence Platform built with Rails 8.1. Discover, track, and manage developers by analyzing GitHub repositories.

## Overview

Crew helps teams build developer pipelines by importing GitHub repositories and aggregating contributor profiles. Use it for recruiting, developer relations, community building, or tracking open-source contributors across multiple projects.

## Features

- **Project Organization** - Group repositories into projects for focused analysis
- **Repository Import** - Add GitHub repos by URL; automatic background processing
- **Developer Profiles** - Comprehensive profiles with GitHub data, location, languages, and contact info
- **Pipeline Management** - Track developer status: new, interesting, contacted, not_a_fit
- **Filtering & Sorting** - Filter by status, location, email availability; sort by contributions, followers, or recency
- **CSV Export** - Export filtered developer lists for CRM integration or analysis
- **Real-time Updates** - Turbo Streams for instant status changes without page reload

## Tech Stack

- **Framework**: Rails 8.1 / Ruby 3.4.4
- **Database**: SQLite 3
- **Background Jobs**: Solid Queue
- **Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS
- **HTTP Client**: Faraday (GitHub API)
- **Deployment**: Docker / Kamal

## Quick Start (Docker)

The fastest way to run Crew locally. You just need Docker and a GitHub token.

```bash
docker pull nickrobinson/crew:latest
docker run -p 3000:3000 -e GITHUB_TOKEN=your_token_here nickrobinson/crew:latest
```

Visit `http://localhost:3000`

Generate a token at [GitHub Settings > Developer settings > Personal access tokens](https://github.com/settings/tokens) with `public_repo` scope.

## Setup (from source)

### Prerequisites

- Ruby 3.4.4
- Node.js (for Tailwind CSS)
- GitHub Personal Access Token (for API access)

### Installation

```bash
git clone https://github.com/nickrobinson/crew.git
cd crew

bundle install

cp .env.example .env  # or create .env manually
```

Add your GitHub token to `.env`:

```
GITHUB_TOKEN=your_github_personal_access_token
```

### Database Setup

```bash
bin/rails db:prepare
```

### Running the Application

```bash
# Start all services (web server + Tailwind watcher)
bin/dev

# Or start individually
bin/rails server
bin/rails tailwindcss:watch  # in another terminal
```

Visit `http://localhost:3000`

### Building the Docker Image Locally

```bash
docker build -f Dockerfile.dev -t crew-dev .
docker run -p 3000:3000 -e GITHUB_TOKEN=your_token_here crew-dev
```

## Usage

1. **Create a Project** - Give it a name and description
2. **Add Repositories** - Paste GitHub repository URLs (e.g., `https://github.com/rails/rails`)
3. **Wait for Import** - Background job fetches repo metadata and all contributors
4. **Review Developers** - Browse profiles, filter by criteria, update statuses
5. **Export Data** - Download CSV of filtered developers for external use

## Data Model

```
Projects
  └── Repositories (import status, metadata)
        └── Contributions (developer + repo + count)
              └── Developers (GitHub profile data, status, notes)
```

- **Projects** group related repositories
- **Repositories** store GitHub metadata and import state
- **Developers** are unique by GitHub ID, shared across projects
- **Contributions** track per-repo contribution counts
- **ProjectDevelopers** join table with project-specific status and notes

## API Rate Limits

The GitHub API has rate limits (5,000 requests/hour for authenticated users). The import job handles rate limiting with automatic retry after a 5-minute delay. Large repositories with many contributors may require multiple import attempts.

## Development

```bash
# Run linter
bin/rubocop

# Run security audit
bin/brakeman

# Run bundler audit
bundle audit
```

## License

MIT
