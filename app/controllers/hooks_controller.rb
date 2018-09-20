class HooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!
  before_action :authenticate_github_request!

  def create
    case event_header
    when 'issues', 'issue_comment'
      SyncSubjectWorker.perform_async_if_configured(payload['issue'])
    when 'pull_request'
      SyncSubjectWorker.perform_async_if_configured(payload['pull_request'])
    when 'label'
      SyncLabelWorker.perform_async_if_configured(payload) if payload['action'] == 'edited'
    when 'installation'
      case payload['action']
      when 'created'
        SyncInstallationWorker.perform_async_if_configured(payload)
      when 'deleted'
        AppInstallation.find_by_github_id(payload['installation']['id']).try(:destroy)
      end
    when 'installation_repositories'
      SyncInstallationRepositoriesWorker.perform_async_if_configured(payload)
    when 'github_app_authorization'
      SyncGithubAppAuthorizationWorker.perform_async_if_configured(payload['sender']['id'])
    when 'marketplace_purchase'
      MarketplacePurchaseWorker.perform_async_if_configured(payload)
    end

    head :no_content
  end

  private

  HMAC_DIGEST = OpenSSL::Digest.new('sha1')

  def authenticate_github_request!
    secret = Rails.application.secrets.github_webhook_secret

    return unless secret.present?

    expected_signature = "sha1=#{OpenSSL::HMAC.hexdigest(HMAC_DIGEST, secret, request_body)}"
    if signature_header != expected_signature
      raise ActiveSupport::MessageVerifier::InvalidSignature
    end
  end

  def request_body
    @request_body ||= (
      request.body.rewind
      request.body.read
    )
  end

  def payload
    @payload ||= JSON.parse(request_body)
  end

  def signature_header
    request.headers['X-Hub-Signature']
  end

  def event_header
    request.headers['X-GitHub-Event']
  end
end
