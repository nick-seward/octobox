# frozen_string_literal: true
require 'test_helper'

class NotificationTest < ActiveSupport::TestCase
  include NotificationTestHelper

  test 'unarchive_if_updated unarchives when updated_at is newer' do
    notification = create(:archived)
    notification.updated_at += 1
    notification.unarchive_if_updated
    refute notification.archived?
  end

  test 'unarchive_if_updated does nothing when updated_at is older' do
    notification = create(:archived)
    notification.updated_at -= 1
    notification.unarchive_if_updated
    assert notification.archived?
  end

  test 'unarchive_if_updated does nothing unless updated_at is changed' do
    notification = create(:archived)
    notification.subject_title = "whatever"
    notification.unarchive_if_updated
    assert notification.archived?
  end

  test 'unarchive_if_updated does nothing if nothing is changed' do
    notification = create(:archived)
    notification.unarchive_if_updated
    assert notification.archived?
  end

  test '#mute mutes multiple notifications' do
    user = create(:user)

    notification1 = create(:notification, archived: false, user: user)
    notification2 = create(:notification, archived: false, user: user)

    stub_notifications_request(method: :patch, url: "https://api.github.com/notifications/threads/#{notification1.github_id}")
    stub_notifications_request(method: :put, url: "https://api.github.com/notifications/threads/#{notification1.github_id}/subscription")
    stub_notifications_request(method: :patch, url: "https://api.github.com/notifications/threads/#{notification2.github_id}")
    stub_notifications_request(method: :put, url: "https://api.github.com/notifications/threads/#{notification2.github_id}/subscription")

    Notification.mute([notification1, notification2])

    assert notification1.reload.archived? && notification1.muted_at?
    assert notification2.reload.archived? && notification2.muted_at?
  end

  test '#mute doesnt fail if there is no notifications given' do
    Notification.mute([])
  end

  test '#mark_read marks multiple notifications as read' do
    user = create(:user)

    notification1 = create(:notification, user: user)
    notification2 = create(:notification, user: user)

    stub_notifications_request(method: :patch, url: "https://api.github.com/notifications/threads/#{notification1.github_id}")
    stub_notifications_request(method: :patch, url: "https://api.github.com/notifications/threads/#{notification2.github_id}")

    Notification.mark_read([notification1, notification2])

    refute notification1.reload.unread?
    refute notification2.reload.unread?
  end

  test '#mark_read doesnt fail if nothing is to be marked as read' do
    user = create(:user)
    notification1 = create(:notification, user: user, unread: false)
    Notification.mark_read([notification1])
  end

  test 'update_from_api_response updates attributes' do
    stub_fetch_subject_enabled(value: false)
    api_response = notifications_from_fixture('morty_notifications.json').first
    notification = create(:morty_updated)
    expected_attributes = notification.attributes.merge(
      {
        last_read_at: '2016-12-19 22:01:45 UTC',
        updated_at: Time.zone.parse('2016-12-19T22:01:45Z'),
        unread: true,
        archived: false,
        latest_comment_url: "https://api.github.com/repos/octobox/octobox/issues/comments/123"
      }.stringify_keys)
    notification.update_from_api_response(api_response, unarchive: true)
    assert notification.unread?
    refute notification.archived?
    assert_equal expected_attributes, notification.attributes
  end

  test 'update_from_api_response updates attributes on a new notification' do
    stub_fetch_subject_enabled(value: false)
    user = create(:morty)
    expected_attributes = {
      user_id: user.id,
      github_id: 421,
      repository_id: 930405,
      repository_full_name: 'octobox/octobox',
      subject_title: 'More stuff',
      subject_url: 'https://api.github.com/repos/octobox/octobox/issues/560',
      subject_type: 'Issue',
      reason: 'subscribed',
      unread: true,
      last_read_at: nil,
      url: 'https://api.github.com/notifications/threads/421',
      archived: false,
      starred: false,
      repository_owner_name: 'andrew',
      updated_at: Time.zone.parse('2016-12-19T22:00:00Z')
    }.stringify_keys
    api_response = notifications_from_fixture('morty_notifications.json').second
    n = user.notifications.find_or_initialize_by(github_id: api_response[:id])
    n.update_from_api_response(api_response, unarchive: true)
    attributes = n.attributes
    assert_equal attributes, attributes.merge(expected_attributes)
  end

  test 'update_from_api_response does not create a subject when fetch_subject is disabled' do
    stub_fetch_subject_enabled(value: false)

    user = create(:user)
    api_response = notifications_from_fixture('morty_notifications.json').second
    notification = user.notifications.find_or_initialize_by(github_id: api_response[:id])
    notification.update_from_api_response(api_response, unarchive: true)

    assert_nil notification.subject
  end

  test 'update_from_api_response creates a subject when fetch_subject is enabled' do
    stub_background_jobs_enabled(value: false)
    stub_fetch_subject_enabled
    stub_repository_request
    url = 'https://api.github.com/repos/octobox/octobox/issues/560'
    response = { status: 200, body: file_fixture('open_issue.json'), headers: { 'Content-Type' => 'application/json' } }
    stub_request(:get, url).and_return(response)

    user = create(:user)
    api_response = notifications_from_fixture('morty_notifications.json').second
    notification = user.notifications.find_or_initialize_by(github_id: api_response[:id])
    notification.update_from_api_response(api_response, unarchive: true)

    notification.reload

    refute_nil notification.subject
    assert_equal url, notification.subject.url
    assert_equal "open", notification.subject.state
    assert_equal "andrew", notification.subject.author
  end

  test 'update_from_api_response does not update the subject if the subject was recently updated' do
    stub_fetch_subject_enabled
    stub_repository_request
    url = 'https://api.github.com/repos/octobox/octobox/issues/560'

    api_response = notifications_from_fixture('morty_notifications.json').second
    notification_updated_at = Time.parse(api_response.updated_at)
    user = create(:morty)
    subject = create(:subject, url: url, updated_at: (notification_updated_at - 1.seconds))
    notification = create(:morty_updated, updated_at: (notification_updated_at - 1.minute), subject_url: url)
    notification.update_from_api_response(api_response, unarchive: true)

    refute_requested :get, subject.url
  end

  test 'update_from_api_response updates the subject if the subject was not recently updated' do
    stub_background_jobs_enabled(value: false)
    stub_fetch_subject_enabled
    stub_repository_request
    url = 'https://api.github.com/repos/octobox/octobox/issues/560'
    response = { status: 200, body: file_fixture('open_issue.json'), headers: { 'Content-Type' => 'application/json' } }
    stub_request(:get, url).and_return(response)

    api_response = notifications_from_fixture('morty_notifications.json').second
    notification_updated_at = Time.parse(api_response.updated_at)
    user = create(:morty)
    subject = create(:subject, url: url, updated_at: (notification_updated_at - 5.seconds))
    notification = create(:morty_updated, updated_at: (notification_updated_at - 1.minute), subject_url: url)
    notification.update_from_api_response(api_response, unarchive: true)

    assert_requested :get, subject.url
  end

  test 'update_from_api_response updates the subject with no author available' do
    stub_background_jobs_enabled(value: false)
    stub_fetch_subject_enabled
    stub_repository_request
    url = 'https://api.github.com/repos/octobox/octobox/commits/6dcb09b5b57875f334f61aebed695e2e4193db5e'
    response = { status: 200, body: file_fixture('commit_no_author.json'), headers: { 'Content-Type' => 'application/json' } }
    stub_request(:get, url).and_return(response)

    api_response = notifications_from_fixture('commit_notification_no_author.json').first
    notification = create(:morty_updated)

    assert_difference 'Subject.count' do
      notification.update_from_api_response(api_response, unarchive: true)
    end
  end

  test 'update_from_api_response updates the subject that returns a 40x error' do
    stub_fetch_subject_enabled
    stub_repository_request
    url = 'https://api.github.com/repos/octobox/octobox/commits/6dcb09b5b57875f334f61aebed695e2e4193db5e'
    response = { status: 401, headers: { 'Content-Type' => 'application/json' } }
    stub_request(:get, url).and_return(response)

    api_response = notifications_from_fixture('commit_notification_no_author.json').first
    notification = create(:morty_updated)

    assert_no_difference 'Subject.count' do
      notification.update_from_api_response(api_response, unarchive: true)
    end
  end

  test 'updated_from_api_response updates the existing subject if present' do
    stub_background_jobs_enabled(value: false)
    stub_fetch_subject_enabled
    stub_repository_request
    url = 'https://api.github.com/repos/octobox/octobox/pulls/403'
    response = { status: 200, body: file_fixture('merged_pull_request.json'), headers: { 'Content-Type' => 'application/json' } }
    stub_request(:get, url).and_return(response)

    api_response = notifications_from_fixture('morty_notifications.json').third
    notification_updated_at = Time.parse(api_response.updated_at)
    user = create(:morty)
    subject = create(:subject, state: 'open', url: url, updated_at: (notification_updated_at - 5.seconds))
    notification = create(:morty_updated, updated_at: (notification_updated_at - 1.minute), subject_url: url)
    notification.update_from_api_response(api_response, unarchive: true)

    subject.reload
    assert_equal 'merged', subject.state
  end
end
