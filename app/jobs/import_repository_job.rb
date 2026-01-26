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
