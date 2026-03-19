require "cgi"

class GithubClient
  BASE_URL = "https://api.github.com"

  class RateLimitError < StandardError; end
  class NotFoundError < StandardError; end

  def initialize(token = ENV["GITHUB_TOKEN"])
    raise ArgumentError, "GITHUB_TOKEN environment variable is required" if token.blank?

    @conn = Faraday.new(url: BASE_URL) do |f|
      f.request :json
      f.response :json
      f.headers["Authorization"] = "Bearer #{token}"
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
    encoded_username = CGI.escape(username)
    response = @conn.get("/users/#{encoded_username}")
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
