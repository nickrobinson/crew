# Talent Discovery Platform Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Rails 8 app to discover developers by importing GitHub repository contributors.

**Architecture:** Server-rendered Rails with Hotwire for interactivity. Solid Queue handles background imports. GitHub API wrapped in a service class. SQLite for storage.

**Tech Stack:** Rails 8, SQLite, Hotwire (Turbo/Stimulus), Solid Queue, Tailwind CSS, Faraday

---

## Task 1: Create Rails Application

**Files:**
- Create: New Rails app in current directory

**Step 1: Generate Rails app with SQLite and Tailwind**

```bash
cd /Users/nickrobinson/Development/sandbox/crew
rails new . --database=sqlite3 --css=tailwind --skip-test --skip-system-test --force
```

Note: Using `--force` to overwrite existing files. Using `--skip-test` because we'll add tests manually.

**Step 2: Verify app was created**

```bash
ls -la app/
```

Expected: See controllers/, models/, views/ directories

**Step 3: Add required gems to Gemfile**

Add after existing gems:

```ruby
gem "faraday"
gem "dotenv-rails", groups: [:development, :test]
```

**Step 4: Bundle install**

```bash
bundle install
```

**Step 5: Create .env file for GitHub token**

```bash
echo "GITHUB_TOKEN=your_token_here" > .env
echo ".env" >> .gitignore
```

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: initialize Rails 8 app with Tailwind and dependencies"
```

---

## Task 2: Create Database Models

**Files:**
- Create: `db/migrate/*_create_repositories.rb`
- Create: `db/migrate/*_create_developers.rb`
- Create: `db/migrate/*_create_contributions.rb`
- Create: `app/models/repository.rb`
- Create: `app/models/developer.rb`
- Create: `app/models/contribution.rb`

**Step 1: Generate Repository model**

```bash
rails g model Repository \
  github_url:string:uniq \
  name:string \
  description:text \
  primary_language:string \
  stars_count:integer \
  import_status:string \
  imported_at:datetime
```

**Step 2: Generate Developer model**

```bash
rails g model Developer \
  github_username:string:uniq \
  github_id:integer:uniq \
  avatar_url:string \
  profile_url:string \
  name:string \
  bio:text \
  location:string \
  company:string \
  email:string \
  followers_count:integer \
  public_repos_count:integer \
  top_languages:json \
  status:string \
  notes:text
```

**Step 3: Generate Contribution model**

```bash
rails g model Contribution \
  developer:references \
  repository:references \
  contributions_count:integer
```

**Step 4: Edit Repository migration to add defaults**

In `db/migrate/*_create_repositories.rb`, update:

```ruby
class CreateRepositories < ActiveRecord::Migration[8.0]
  def change
    create_table :repositories do |t|
      t.string :github_url, null: false
      t.string :name, null: false
      t.text :description
      t.string :primary_language
      t.integer :stars_count, default: 0
      t.string :import_status, default: "pending"
      t.datetime :imported_at

      t.timestamps
    end
    add_index :repositories, :github_url, unique: true
  end
end
```

**Step 5: Edit Developer migration to add defaults**

In `db/migrate/*_create_developers.rb`, update:

```ruby
class CreateDevelopers < ActiveRecord::Migration[8.0]
  def change
    create_table :developers do |t|
      t.string :github_username, null: false
      t.integer :github_id, null: false
      t.string :avatar_url
      t.string :profile_url
      t.string :name
      t.text :bio
      t.string :location
      t.string :company
      t.string :email
      t.integer :followers_count, default: 0
      t.integer :public_repos_count, default: 0
      t.json :top_languages, default: []
      t.string :status, default: "new"
      t.text :notes

      t.timestamps
    end
    add_index :developers, :github_username, unique: true
    add_index :developers, :github_id, unique: true
  end
end
```

**Step 6: Edit Contribution migration to add unique index and default**

In `db/migrate/*_create_contributions.rb`, update:

```ruby
class CreateContributions < ActiveRecord::Migration[8.0]
  def change
    create_table :contributions do |t|
      t.references :developer, null: false, foreign_key: true
      t.references :repository, null: false, foreign_key: true
      t.integer :contributions_count, default: 0

      t.timestamps
    end
    add_index :contributions, [:developer_id, :repository_id], unique: true
  end
end
```

**Step 7: Run migrations**

```bash
rails db:migrate
```

**Step 8: Update Repository model**

```ruby
# app/models/repository.rb
class Repository < ApplicationRecord
  has_many :contributions, dependent: :destroy
  has_many :developers, through: :contributions

  validates :github_url, presence: true, uniqueness: true
  validates :name, presence: true

  IMPORT_STATUSES = %w[pending importing imported failed].freeze
  validates :import_status, inclusion: { in: IMPORT_STATUSES }

  scope :imported, -> { where(import_status: "imported") }
  scope :importing, -> { where(import_status: "importing") }

  def owner
    name.split("/").first
  end

  def repo_name
    name.split("/").last
  end
end
```

**Step 9: Update Developer model**

```ruby
# app/models/developer.rb
class Developer < ApplicationRecord
  has_many :contributions, dependent: :destroy
  has_many :repositories, through: :contributions

  validates :github_username, presence: true, uniqueness: true
  validates :github_id, presence: true, uniqueness: true

  STATUSES = %w[new interesting contacted not_a_fit].freeze
  validates :status, inclusion: { in: STATUSES }

  scope :by_status, ->(status) { where(status: status) if status.present? }
  scope :by_location, ->(loc) { where("location LIKE ?", "%#{loc}%") if loc.present? }
  scope :with_email, -> { where.not(email: [nil, ""]) }

  def total_contributions
    contributions.sum(:contributions_count)
  end

  def status_label
    status.titleize.gsub("_", " ")
  end
end
```

**Step 10: Update Contribution model**

```ruby
# app/models/contribution.rb
class Contribution < ApplicationRecord
  belongs_to :developer
  belongs_to :repository

  validates :developer_id, uniqueness: { scope: :repository_id }
end
```

**Step 11: Commit**

```bash
git add -A
git commit -m "feat: add Repository, Developer, and Contribution models"
```

---

## Task 3: Create GitHub Client Service

**Files:**
- Create: `app/services/github_client.rb`

**Step 1: Create services directory**

```bash
mkdir -p app/services
```

**Step 2: Create GitHub client**

```ruby
# app/services/github_client.rb
class GithubClient
  BASE_URL = "https://api.github.com"

  class RateLimitError < StandardError; end
  class NotFoundError < StandardError; end

  def initialize(token = ENV["GITHUB_TOKEN"])
    @conn = Faraday.new(url: BASE_URL) do |f|
      f.request :json
      f.response :json
      f.headers["Authorization"] = "Bearer #{token}" if token
      f.headers["Accept"] = "application/vnd.github+json"
      f.headers["X-GitHub-Api-Version"] = "2022-11-28"
    end
  end

  def repository(owner, repo)
    response = @conn.get("/repos/#{owner}/#{repo}")
    handle_response(response)
  end

  def contributors(owner, repo, per_page: 100)
    all_contributors = []
    page = 1

    loop do
      response = @conn.get("/repos/#{owner}/#{repo}/contributors") do |req|
        req.params["per_page"] = per_page
        req.params["page"] = page
      end

      data = handle_response(response)
      break if data.empty?

      all_contributors.concat(data)
      page += 1

      # Safety limit
      break if page > 50
    end

    all_contributors
  end

  def user(username)
    response = @conn.get("/users/#{username}")
    handle_response(response)
  end

  def rate_limit
    response = @conn.get("/rate_limit")
    handle_response(response)
  end

  private

  def handle_response(response)
    case response.status
    when 200
      response.body
    when 403
      if response.headers["x-ratelimit-remaining"] == "0"
        reset_time = Time.at(response.headers["x-ratelimit-reset"].to_i)
        raise RateLimitError, "Rate limited until #{reset_time}"
      end
      raise StandardError, "Forbidden: #{response.body["message"]}"
    when 404
      raise NotFoundError, "Not found"
    else
      raise StandardError, "GitHub API error: #{response.status} - #{response.body}"
    end
  end
end
```

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add GitHub API client service"
```

---

## Task 4: Create Import Repository Job

**Files:**
- Create: `app/jobs/import_repository_job.rb`

**Step 1: Generate the job**

```bash
rails g job ImportRepository
```

**Step 2: Implement the job**

```ruby
# app/jobs/import_repository_job.rb
class ImportRepositoryJob < ApplicationJob
  queue_as :default

  retry_on GithubClient::RateLimitError, wait: 5.minutes, attempts: 3

  def perform(repository_id)
    repository = Repository.find(repository_id)
    client = GithubClient.new

    repository.update!(import_status: "importing")

    # Fetch repo metadata
    repo_data = client.repository(repository.owner, repository.repo_name)
    repository.update!(
      description: repo_data["description"],
      primary_language: repo_data["language"],
      stars_count: repo_data["stargazers_count"]
    )

    # Fetch contributors
    contributors = client.contributors(repository.owner, repository.repo_name)

    contributors.each do |contrib|
      import_contributor(client, repository, contrib)
    end

    repository.update!(import_status: "imported", imported_at: Time.current)

  rescue GithubClient::NotFoundError
    repository.update!(import_status: "failed")
  rescue => e
    repository.update!(import_status: "failed")
    raise e
  end

  private

  def import_contributor(client, repository, contrib_data)
    # Fetch full user profile
    user_data = client.user(contrib_data["login"])

    # Find or create developer
    developer = Developer.find_or_initialize_by(github_id: user_data["id"])
    developer.assign_attributes(
      github_username: user_data["login"],
      avatar_url: user_data["avatar_url"],
      profile_url: user_data["html_url"],
      name: user_data["name"],
      bio: user_data["bio"],
      location: user_data["location"],
      company: user_data["company"],
      email: user_data["email"],
      followers_count: user_data["followers"],
      public_repos_count: user_data["public_repos"]
    )
    developer.save!

    # Create or update contribution
    contribution = Contribution.find_or_initialize_by(
      developer: developer,
      repository: repository
    )
    contribution.contributions_count = contrib_data["contributions"]
    contribution.save!

  rescue GithubClient::NotFoundError
    # User may have been deleted, skip
    Rails.logger.warn "Contributor not found: #{contrib_data["login"]}"
  end
end
```

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: add ImportRepositoryJob for background imports"
```

---

## Task 5: Create Dashboard Controller and View

**Files:**
- Create: `app/controllers/dashboard_controller.rb`
- Create: `app/views/dashboard/index.html.erb`

**Step 1: Generate controller**

```bash
rails g controller Dashboard index --skip-routes
```

**Step 2: Implement controller**

```ruby
# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  def index
    @total_developers = Developer.count
    @developers_by_status = Developer.group(:status).count
    @total_repositories = Repository.count
    @recent_imports = Repository.order(created_at: :desc).limit(5)
  end
end
```

**Step 3: Create dashboard view**

```erb
<!-- app/views/dashboard/index.html.erb -->
<div class="max-w-7xl mx-auto px-4 py-8">
  <h1 class="text-3xl font-bold text-gray-900 mb-8">Talent Discovery</h1>

  <!-- Quick Add Repository -->
  <div class="bg-white rounded-lg shadow p-6 mb-8">
    <h2 class="text-lg font-semibold mb-4">Add Repository</h2>
    <%= form_with url: repositories_path, method: :post, class: "flex gap-4" do |f| %>
      <%= f.text_field :github_url,
          placeholder: "https://github.com/owner/repo",
          class: "flex-1 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
      <%= f.submit "Import", class: "bg-indigo-600 text-white px-4 py-2 rounded-md hover:bg-indigo-700 cursor-pointer" %>
    <% end %>
  </div>

  <!-- Stats -->
  <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
    <div class="bg-white rounded-lg shadow p-6">
      <div class="text-2xl font-bold text-gray-900"><%= @total_developers %></div>
      <div class="text-gray-500">Total Developers</div>
    </div>
    <div class="bg-white rounded-lg shadow p-6">
      <div class="text-2xl font-bold text-green-600"><%= @developers_by_status["new"] || 0 %></div>
      <div class="text-gray-500">New</div>
    </div>
    <div class="bg-white rounded-lg shadow p-6">
      <div class="text-2xl font-bold text-yellow-600"><%= @developers_by_status["interesting"] || 0 %></div>
      <div class="text-gray-500">Interesting</div>
    </div>
    <div class="bg-white rounded-lg shadow p-6">
      <div class="text-2xl font-bold text-blue-600"><%= @developers_by_status["contacted"] || 0 %></div>
      <div class="text-gray-500">Contacted</div>
    </div>
  </div>

  <!-- Recent Imports -->
  <div class="bg-white rounded-lg shadow">
    <div class="px-6 py-4 border-b border-gray-200">
      <h2 class="text-lg font-semibold">Recent Imports</h2>
    </div>
    <% if @recent_imports.any? %>
      <ul class="divide-y divide-gray-200">
        <% @recent_imports.each do |repo| %>
          <li class="px-6 py-4 flex items-center justify-between">
            <%= link_to repo.name, repository_path(repo), class: "text-indigo-600 hover:text-indigo-900 font-medium" %>
            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium
              <%= repo.import_status == 'imported' ? 'bg-green-100 text-green-800' :
                  repo.import_status == 'importing' ? 'bg-yellow-100 text-yellow-800' :
                  repo.import_status == 'failed' ? 'bg-red-100 text-red-800' :
                  'bg-gray-100 text-gray-800' %>">
              <%= repo.import_status %>
            </span>
          </li>
        <% end %>
      </ul>
    <% else %>
      <p class="px-6 py-4 text-gray-500">No repositories imported yet.</p>
    <% end %>
  </div>
</div>
```

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add Dashboard with stats and quick add form"
```

---

## Task 6: Create Repositories Controller and Views

**Files:**
- Create: `app/controllers/repositories_controller.rb`
- Create: `app/views/repositories/index.html.erb`
- Create: `app/views/repositories/show.html.erb`

**Step 1: Generate controller**

```bash
rails g controller Repositories index show --skip-routes
```

**Step 2: Implement controller**

```ruby
# app/controllers/repositories_controller.rb
class RepositoriesController < ApplicationController
  def index
    @repositories = Repository.order(created_at: :desc)
  end

  def show
    @repository = Repository.find(params[:id])
    @contributions = @repository.contributions
                                .includes(:developer)
                                .order(contributions_count: :desc)

    if params[:status].present?
      @contributions = @contributions.joins(:developer).where(developers: { status: params[:status] })
    end
  end

  def create
    url = params[:github_url].to_s.strip

    # Parse GitHub URL
    match = url.match(%r{github\.com/([^/]+)/([^/]+)})
    unless match
      redirect_to repositories_path, alert: "Invalid GitHub URL"
      return
    end

    name = "#{match[1]}/#{match[2]}"

    @repository = Repository.find_or_initialize_by(github_url: url)
    if @repository.new_record?
      @repository.name = name
      @repository.save!
      ImportRepositoryJob.perform_later(@repository.id)
      redirect_to @repository, notice: "Import started for #{name}"
    else
      redirect_to @repository, notice: "Repository already exists"
    end
  end
end
```

**Step 3: Create index view**

```erb
<!-- app/views/repositories/index.html.erb -->
<div class="max-w-7xl mx-auto px-4 py-8">
  <div class="flex justify-between items-center mb-8">
    <h1 class="text-3xl font-bold text-gray-900">Repositories</h1>
  </div>

  <!-- Add Repository Form -->
  <div class="bg-white rounded-lg shadow p-6 mb-8">
    <h2 class="text-lg font-semibold mb-4">Add Repository</h2>
    <%= form_with url: repositories_path, method: :post, class: "flex gap-4" do |f| %>
      <%= f.text_field :github_url,
          placeholder: "https://github.com/owner/repo",
          class: "flex-1 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
      <%= f.submit "Import", class: "bg-indigo-600 text-white px-4 py-2 rounded-md hover:bg-indigo-700 cursor-pointer" %>
    <% end %>
  </div>

  <!-- Repositories List -->
  <div class="bg-white rounded-lg shadow overflow-hidden">
    <table class="min-w-full divide-y divide-gray-200">
      <thead class="bg-gray-50">
        <tr>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Repository</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Language</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Stars</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Contributors</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
        </tr>
      </thead>
      <tbody class="bg-white divide-y divide-gray-200">
        <% @repositories.each do |repo| %>
          <tr class="hover:bg-gray-50">
            <td class="px-6 py-4">
              <%= link_to repo.name, repository_path(repo), class: "text-indigo-600 hover:text-indigo-900 font-medium" %>
            </td>
            <td class="px-6 py-4 text-gray-500"><%= repo.primary_language || "-" %></td>
            <td class="px-6 py-4 text-gray-500"><%= number_with_delimiter(repo.stars_count) %></td>
            <td class="px-6 py-4 text-gray-500"><%= repo.developers.count %></td>
            <td class="px-6 py-4">
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium
                <%= repo.import_status == 'imported' ? 'bg-green-100 text-green-800' :
                    repo.import_status == 'importing' ? 'bg-yellow-100 text-yellow-800' :
                    repo.import_status == 'failed' ? 'bg-red-100 text-red-800' :
                    'bg-gray-100 text-gray-800' %>">
                <%= repo.import_status %>
              </span>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    <% if @repositories.empty? %>
      <p class="px-6 py-8 text-center text-gray-500">No repositories imported yet.</p>
    <% end %>
  </div>
</div>
```

**Step 4: Create show view**

```erb
<!-- app/views/repositories/show.html.erb -->
<div class="max-w-7xl mx-auto px-4 py-8">
  <!-- Header -->
  <div class="mb-8">
    <div class="flex items-center gap-4 mb-2">
      <h1 class="text-3xl font-bold text-gray-900"><%= @repository.name %></h1>
      <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium
        <%= @repository.import_status == 'imported' ? 'bg-green-100 text-green-800' :
            @repository.import_status == 'importing' ? 'bg-yellow-100 text-yellow-800' :
            @repository.import_status == 'failed' ? 'bg-red-100 text-red-800' :
            'bg-gray-100 text-gray-800' %>">
        <%= @repository.import_status %>
      </span>
    </div>
    <p class="text-gray-600"><%= @repository.description %></p>
    <div class="mt-2 flex gap-4 text-sm text-gray-500">
      <span><%= @repository.primary_language %></span>
      <span><%= number_with_delimiter(@repository.stars_count) %> stars</span>
      <span><%= @repository.developers.count %> contributors</span>
      <%= link_to "View on GitHub", @repository.github_url, target: "_blank", class: "text-indigo-600 hover:text-indigo-900" %>
    </div>
  </div>

  <!-- Filters -->
  <div class="mb-6 flex gap-2">
    <%= link_to "All", repository_path(@repository),
        class: "px-3 py-1 rounded-md #{params[:status].blank? ? 'bg-indigo-600 text-white' : 'bg-gray-200 text-gray-700 hover:bg-gray-300'}" %>
    <% Developer::STATUSES.each do |status| %>
      <%= link_to status.titleize.gsub("_", " "), repository_path(@repository, status: status),
          class: "px-3 py-1 rounded-md #{params[:status] == status ? 'bg-indigo-600 text-white' : 'bg-gray-200 text-gray-700 hover:bg-gray-300'}" %>
    <% end %>
  </div>

  <!-- Contributors Table -->
  <div class="bg-white rounded-lg shadow overflow-hidden">
    <table class="min-w-full divide-y divide-gray-200">
      <thead class="bg-gray-50">
        <tr>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Developer</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Location</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Contributions</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Followers</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
        </tr>
      </thead>
      <tbody class="bg-white divide-y divide-gray-200">
        <% @contributions.each do |contribution| %>
          <% dev = contribution.developer %>
          <tr class="hover:bg-gray-50">
            <td class="px-6 py-4">
              <div class="flex items-center">
                <img src="<%= dev.avatar_url %>" class="w-10 h-10 rounded-full mr-3" alt="">
                <div>
                  <%= link_to dev.name || dev.github_username, developer_path(dev), class: "text-indigo-600 hover:text-indigo-900 font-medium" %>
                  <div class="text-sm text-gray-500">@<%= dev.github_username %></div>
                </div>
              </div>
            </td>
            <td class="px-6 py-4 text-gray-500"><%= dev.location || "-" %></td>
            <td class="px-6 py-4 text-gray-900 font-medium"><%= contribution.contributions_count %></td>
            <td class="px-6 py-4 text-gray-500"><%= number_with_delimiter(dev.followers_count) %></td>
            <td class="px-6 py-4">
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium
                <%= dev.status == 'new' ? 'bg-gray-100 text-gray-800' :
                    dev.status == 'interesting' ? 'bg-yellow-100 text-yellow-800' :
                    dev.status == 'contacted' ? 'bg-blue-100 text-blue-800' :
                    'bg-red-100 text-red-800' %>">
                <%= dev.status_label %>
              </span>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    <% if @contributions.empty? %>
      <p class="px-6 py-8 text-center text-gray-500">No contributors found.</p>
    <% end %>
  </div>
</div>
```

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Repositories controller and views"
```

---

## Task 7: Create Developers Controller and Views

**Files:**
- Create: `app/controllers/developers_controller.rb`
- Create: `app/views/developers/index.html.erb`
- Create: `app/views/developers/show.html.erb`

**Step 1: Generate controller**

```bash
rails g controller Developers index show --skip-routes
```

**Step 2: Implement controller**

```ruby
# app/controllers/developers_controller.rb
class DevelopersController < ApplicationController
  def index
    @developers = Developer.includes(:contributions).all

    # Filters
    @developers = @developers.by_status(params[:status])
    @developers = @developers.by_location(params[:location]) if params[:location].present?
    @developers = @developers.with_email if params[:has_email] == "1"

    # Sorting
    case params[:sort]
    when "followers"
      @developers = @developers.order(followers_count: :desc)
    when "recent"
      @developers = @developers.order(created_at: :desc)
    else
      # Sort by total contributions (default)
      @developers = @developers.left_joins(:contributions)
                               .group(:id)
                               .order("SUM(contributions.contributions_count) DESC NULLS LAST")
    end

    @developers = @developers.limit(100)
  end

  def show
    @developer = Developer.find(params[:id])
    @contributions = @developer.contributions.includes(:repository).order(contributions_count: :desc)
  end

  def update
    @developer = Developer.find(params[:id])

    if @developer.update(developer_params)
      respond_to do |format|
        format.html { redirect_to @developer, notice: "Developer updated" }
        format.turbo_stream
      end
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def developer_params
    params.require(:developer).permit(:status, :notes)
  end
end
```

**Step 3: Create index view**

```erb
<!-- app/views/developers/index.html.erb -->
<div class="max-w-7xl mx-auto px-4 py-8">
  <h1 class="text-3xl font-bold text-gray-900 mb-8">Developers</h1>

  <!-- Filters -->
  <div class="bg-white rounded-lg shadow p-6 mb-8">
    <%= form_with url: developers_path, method: :get, class: "flex flex-wrap gap-4 items-end" do |f| %>
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1">Status</label>
        <%= f.select :status,
            [["All", ""]] + Developer::STATUSES.map { |s| [s.titleize.gsub("_", " "), s] },
            { selected: params[:status] },
            class: "rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
      </div>
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1">Location</label>
        <%= f.text_field :location,
            value: params[:location],
            placeholder: "e.g., San Francisco",
            class: "rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
      </div>
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1">Sort by</label>
        <%= f.select :sort,
            [["Contributions", "contributions"], ["Followers", "followers"], ["Recently added", "recent"]],
            { selected: params[:sort] || "contributions" },
            class: "rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
      </div>
      <div class="flex items-center gap-2">
        <%= f.check_box :has_email, { checked: params[:has_email] == "1" }, "1", "0" %>
        <label class="text-sm text-gray-700">Has email</label>
      </div>
      <%= f.submit "Filter", class: "bg-indigo-600 text-white px-4 py-2 rounded-md hover:bg-indigo-700 cursor-pointer" %>
      <%= link_to "Clear", developers_path, class: "text-gray-600 hover:text-gray-900 px-4 py-2" %>
    <% end %>
  </div>

  <!-- Developers Table -->
  <div class="bg-white rounded-lg shadow overflow-hidden">
    <table class="min-w-full divide-y divide-gray-200">
      <thead class="bg-gray-50">
        <tr>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Developer</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Location</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Company</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Repos</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Followers</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Email</th>
          <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
        </tr>
      </thead>
      <tbody class="bg-white divide-y divide-gray-200">
        <% @developers.each do |dev| %>
          <tr class="hover:bg-gray-50">
            <td class="px-6 py-4">
              <div class="flex items-center">
                <img src="<%= dev.avatar_url %>" class="w-10 h-10 rounded-full mr-3" alt="">
                <div>
                  <%= link_to dev.name || dev.github_username, developer_path(dev), class: "text-indigo-600 hover:text-indigo-900 font-medium" %>
                  <div class="text-sm text-gray-500">@<%= dev.github_username %></div>
                </div>
              </div>
            </td>
            <td class="px-6 py-4 text-gray-500 text-sm"><%= dev.location || "-" %></td>
            <td class="px-6 py-4 text-gray-500 text-sm"><%= dev.company || "-" %></td>
            <td class="px-6 py-4 text-gray-500"><%= dev.repositories.count %></td>
            <td class="px-6 py-4 text-gray-500"><%= number_with_delimiter(dev.followers_count) %></td>
            <td class="px-6 py-4 text-sm">
              <% if dev.email.present? %>
                <%= mail_to dev.email, dev.email, class: "text-indigo-600 hover:text-indigo-900" %>
              <% else %>
                <span class="text-gray-400">-</span>
              <% end %>
            </td>
            <td class="px-6 py-4">
              <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium
                <%= dev.status == 'new' ? 'bg-gray-100 text-gray-800' :
                    dev.status == 'interesting' ? 'bg-yellow-100 text-yellow-800' :
                    dev.status == 'contacted' ? 'bg-blue-100 text-blue-800' :
                    'bg-red-100 text-red-800' %>">
                <%= dev.status_label %>
              </span>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    <% if @developers.empty? %>
      <p class="px-6 py-8 text-center text-gray-500">No developers found.</p>
    <% end %>
  </div>
</div>
```

**Step 4: Create show view**

```erb
<!-- app/views/developers/show.html.erb -->
<div class="max-w-7xl mx-auto px-4 py-8">
  <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
    <!-- Profile -->
    <div class="lg:col-span-1">
      <div class="bg-white rounded-lg shadow p-6">
        <div class="text-center mb-6">
          <img src="<%= @developer.avatar_url %>" class="w-24 h-24 rounded-full mx-auto mb-4" alt="">
          <h1 class="text-2xl font-bold text-gray-900"><%= @developer.name || @developer.github_username %></h1>
          <p class="text-gray-500">@<%= @developer.github_username %></p>
        </div>

        <% if @developer.bio.present? %>
          <p class="text-gray-600 mb-4"><%= @developer.bio %></p>
        <% end %>

        <dl class="space-y-3 text-sm">
          <% if @developer.company.present? %>
            <div class="flex justify-between">
              <dt class="text-gray-500">Company</dt>
              <dd class="text-gray-900"><%= @developer.company %></dd>
            </div>
          <% end %>
          <% if @developer.location.present? %>
            <div class="flex justify-between">
              <dt class="text-gray-500">Location</dt>
              <dd class="text-gray-900"><%= @developer.location %></dd>
            </div>
          <% end %>
          <% if @developer.email.present? %>
            <div class="flex justify-between">
              <dt class="text-gray-500">Email</dt>
              <dd><%= mail_to @developer.email, @developer.email, class: "text-indigo-600 hover:text-indigo-900" %></dd>
            </div>
          <% end %>
          <div class="flex justify-between">
            <dt class="text-gray-500">Followers</dt>
            <dd class="text-gray-900"><%= number_with_delimiter(@developer.followers_count) %></dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-gray-500">Public Repos</dt>
            <dd class="text-gray-900"><%= @developer.public_repos_count %></dd>
          </div>
        </dl>

        <div class="mt-6">
          <%= link_to "View on GitHub", @developer.profile_url, target: "_blank",
              class: "block w-full text-center bg-gray-800 text-white px-4 py-2 rounded-md hover:bg-gray-900" %>
        </div>
      </div>
    </div>

    <!-- Status & Notes -->
    <div class="lg:col-span-2">
      <!-- Status Update -->
      <div class="bg-white rounded-lg shadow p-6 mb-8" id="developer_<%= @developer.id %>">
        <h2 class="text-lg font-semibold mb-4">Tracking</h2>
        <%= form_with model: @developer, class: "space-y-4" do |f| %>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Status</label>
            <div class="flex gap-2">
              <% Developer::STATUSES.each do |status| %>
                <label class="cursor-pointer">
                  <%= f.radio_button :status, status,
                      class: "sr-only peer",
                      onchange: "this.form.requestSubmit()" %>
                  <span class="inline-flex items-center px-3 py-1.5 rounded-md text-sm font-medium
                    peer-checked:bg-indigo-600 peer-checked:text-white
                    bg-gray-100 text-gray-700 hover:bg-gray-200">
                    <%= status.titleize.gsub("_", " ") %>
                  </span>
                </label>
              <% end %>
            </div>
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Notes</label>
            <%= f.text_area :notes, rows: 4,
                placeholder: "Add your notes about this developer...",
                class: "w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
          </div>
          <%= f.submit "Save Notes", class: "bg-indigo-600 text-white px-4 py-2 rounded-md hover:bg-indigo-700 cursor-pointer" %>
        <% end %>
      </div>

      <!-- Contributed Repositories -->
      <div class="bg-white rounded-lg shadow">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-lg font-semibold">Contributed Repositories</h2>
        </div>
        <ul class="divide-y divide-gray-200">
          <% @contributions.each do |contribution| %>
            <li class="px-6 py-4 flex items-center justify-between">
              <div>
                <%= link_to contribution.repository.name, repository_path(contribution.repository),
                    class: "text-indigo-600 hover:text-indigo-900 font-medium" %>
                <span class="text-sm text-gray-500 ml-2"><%= contribution.repository.primary_language %></span>
              </div>
              <span class="text-gray-900 font-medium"><%= contribution.contributions_count %> contributions</span>
            </li>
          <% end %>
        </ul>
      </div>
    </div>
  </div>
</div>
```

**Step 5: Create turbo stream response for status update**

```erb
<!-- app/views/developers/update.turbo_stream.erb -->
<%= turbo_stream.replace "developer_#{@developer.id}" do %>
  <!-- Re-render the tracking section -->
  <div class="bg-white rounded-lg shadow p-6 mb-8" id="developer_<%= @developer.id %>">
    <h2 class="text-lg font-semibold mb-4">Tracking</h2>
    <%= form_with model: @developer, class: "space-y-4" do |f| %>
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1">Status</label>
        <div class="flex gap-2">
          <% Developer::STATUSES.each do |status| %>
            <label class="cursor-pointer">
              <%= f.radio_button :status, status,
                  class: "sr-only peer",
                  onchange: "this.form.requestSubmit()" %>
              <span class="inline-flex items-center px-3 py-1.5 rounded-md text-sm font-medium
                peer-checked:bg-indigo-600 peer-checked:text-white
                bg-gray-100 text-gray-700 hover:bg-gray-200">
                <%= status.titleize.gsub("_", " ") %>
              </span>
            </label>
          <% end %>
        </div>
      </div>
      <div>
        <label class="block text-sm font-medium text-gray-700 mb-1">Notes</label>
        <%= f.text_area :notes, rows: 4,
            placeholder: "Add your notes about this developer...",
            class: "w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500" %>
      </div>
      <%= f.submit "Save Notes", class: "bg-indigo-600 text-white px-4 py-2 rounded-md hover:bg-indigo-700 cursor-pointer" %>
    <% end %>
    <p class="mt-2 text-sm text-green-600">Saved!</p>
  </div>
<% end %>
```

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Developers controller and views"
```

---

## Task 8: Configure Routes and Layout

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/views/layouts/application.html.erb`

**Step 1: Configure routes**

```ruby
# config/routes.rb
Rails.application.routes.draw do
  root "dashboard#index"

  resources :repositories, only: [:index, :show, :create]
  resources :developers, only: [:index, :show, :update]
end
```

**Step 2: Update application layout with navigation**

```erb
<!-- app/views/layouts/application.html.erb -->
<!DOCTYPE html>
<html class="h-full bg-gray-100">
  <head>
    <title>Talent Discovery</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag "tailwind", "inter-font", "data-turbo-track": "reload" %>
    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>

  <body class="h-full">
    <nav class="bg-white shadow">
      <div class="max-w-7xl mx-auto px-4">
        <div class="flex justify-between h-16">
          <div class="flex">
            <%= link_to "Talent Discovery", root_path, class: "flex items-center text-xl font-bold text-indigo-600" %>
            <div class="ml-10 flex items-center space-x-4">
              <%= link_to "Dashboard", root_path,
                  class: "px-3 py-2 rounded-md text-sm font-medium #{request.path == root_path ? 'bg-indigo-100 text-indigo-700' : 'text-gray-500 hover:text-gray-700'}" %>
              <%= link_to "Repositories", repositories_path,
                  class: "px-3 py-2 rounded-md text-sm font-medium #{request.path.start_with?('/repositories') ? 'bg-indigo-100 text-indigo-700' : 'text-gray-500 hover:text-gray-700'}" %>
              <%= link_to "Developers", developers_path,
                  class: "px-3 py-2 rounded-md text-sm font-medium #{request.path.start_with?('/developers') ? 'bg-indigo-100 text-indigo-700' : 'text-gray-500 hover:text-gray-700'}" %>
            </div>
          </div>
        </div>
      </div>
    </nav>

    <% if notice.present? %>
      <div class="max-w-7xl mx-auto px-4 mt-4">
        <div class="bg-green-50 border border-green-200 text-green-700 px-4 py-3 rounded-md">
          <%= notice %>
        </div>
      </div>
    <% end %>

    <% if alert.present? %>
      <div class="max-w-7xl mx-auto px-4 mt-4">
        <div class="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-md">
          <%= alert %>
        </div>
      </div>
    <% end %>

    <main>
      <%= yield %>
    </main>
  </body>
</html>
```

**Step 3: Commit**

```bash
git add -A
git commit -m "feat: configure routes and navigation layout"
```

---

## Task 9: Setup Solid Queue for Background Jobs

**Files:**
- Modify: `config/environments/development.rb`

**Step 1: Ensure Solid Queue is configured**

In Rails 8, Solid Queue should already be the default. Verify in `config/environments/development.rb`:

```ruby
# Should already have this:
config.active_job.queue_adapter = :solid_queue
```

If not present, add it.

**Step 2: Commit if changes made**

```bash
git add -A
git commit -m "chore: ensure Solid Queue is configured for background jobs"
```

---

## Task 10: Final Verification

**Step 1: Start the Rails server**

```bash
cd /Users/nickrobinson/Development/sandbox/crew
bin/rails server
```

**Step 2: Start Solid Queue worker (in another terminal)**

```bash
cd /Users/nickrobinson/Development/sandbox/crew
bin/jobs
```

**Step 3: Test the application**

1. Open http://localhost:3000
2. Add a small repo like `https://github.com/ruby/debug`
3. Verify import starts and completes
4. Browse developers, filter by status
5. Update a developer's status and notes

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete talent discovery platform MVP"
```

---

## Summary

The implementation creates a complete talent discovery platform with:

- **Dashboard** - Quick stats and repository import form
- **Repositories** - Import and browse GitHub repos
- **Developers** - Filter, sort, and track candidates
- **Background Import** - Non-blocking repo imports via Solid Queue
- **Pipeline Tracking** - Status management (new/interesting/contacted/not a fit)
