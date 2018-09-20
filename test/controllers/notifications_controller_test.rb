# frozen_string_literal: true
require 'test_helper'

class NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Octobox.config.stubs(:github_app).returns(false)
    stub_background_jobs_enabled(value: false)
    stub_fetch_subject_enabled(value: false)
    stub_notifications_request
    stub_repository_request
    @user = create(:user)
  end

  test 'will render the home page if not authenticated' do
    get '/'
    assert_response :success
    assert_template 'pages/home'
  end

  test 'will render 401 if not authenticated as json' do
    get notifications_path(format: :json)
    assert_response :unauthorized
  end

  test 'will render 404 if not json' do
    sign_in_as(@user)
    assert_raises ActionController::UrlGenerationError do
      get notifications_path
    end
  end

  test 'renders the index page if authenticated' do
    sign_in_as(@user)

    get '/'
    assert_response :success
    assert_template 'notifications/index', file: 'notifications/index.html.erb'
  end

  test 'will render the home page with filters' do
    sign_in_as(@user)

    # Repo Filter
    get '/?repo=a/b'
    assert_response :success
    assert_template 'notifications/index', file: 'notifications/index.html.erb'
    assert_select "span.filter-options *", text: 'a/b'

    # Reason Filter
    get '/?reason=Assign'
    assert_response :success
    assert_template 'notifications/index', file: 'notifications/index.html.erb'
    assert_select "span.filter-options *", text: 'Assign'

    # Type Filter
    get '/?type=repository_a_b'
    assert_response :success
    assert_template 'notifications/index', file: 'notifications/index.html.erb'
    assert_select "span.filter-options *", text: 'A b'

    # Unread Filter
    get '/?unread=true'
    assert_response :success
    assert_template 'notifications/index', file: 'notifications/index.html.erb'
    assert_select "span.filter-options *", text: 'Unread'

    # Owner Filter
    get '/?owner=bob'
    assert_response :success
    assert_template 'notifications/index', file: 'notifications/index.html.erb'
    assert_select "span.filter-options *", text: 'bob'

    # State Filter
    get '/?state=archive'
    assert_response :success
    assert_template 'notifications/index', file: 'notifications/index.html.erb'
    assert_select "span.filter-options *", text: 'Archive'

    # query Filter
    get '/?q=query'
    assert_response :success
    assert_template 'notifications/index', file: 'notifications/index.html.erb'
    assert_select "span.filter-options *", text: 'Search: query'

    get '/?label=bug'
    assert_response :success
    assert_template 'notifications/index', file: 'notifications/index.html.erb'
    assert_select "span.filter-options *", text: 'Label: bug'
  end

  test 'renders the index page as json if authenticated' do
    sign_in_as(@user)

    get notifications_path(format: :json)
    assert_response :success
    assert_template 'notifications/index', file: 'notifications/index.json.jbuilder'
  end

  test 'renders the starred page' do
    sign_in_as(@user)

    get '/?starred=true'
    assert_response :success
    assert_template 'notifications/index'
  end

  test 'renders the archive page' do
    sign_in_as(@user)

    get '/?archive=true'
    assert_response :success
    assert_template 'notifications/index'
  end

  test 'renders notifications filtered by label' do
    stub_fetch_subject_enabled
    sign_in_as(@user)

    get '/'
    assert_response :success
    assert_template 'notifications/index'
    assert_select 'table tr.notification', {count: 2}

    get '/?label=question'
    assert_response :success
    assert_template 'notifications/index'
    assert_select 'table tr.notification', {count: 1}

    get '/?label=other-label'
    assert_response :success
    assert_template 'notifications/index'
    assert_select 'table tr.notification', {count: 0}
  end

  test 'shows archived search results by default' do
    sign_in_as(@user)
    5.times.each { create(:notification, user: @user, archived: true, subject_title:'release-1') }
    get '/?q=release'
    assert_equal assigns(:notifications).length, 5
  end

  test 'shows only 20 notifications per page' do
    sign_in_as(@user)
    25.times.each { create(:notification, user: @user, archived: false) }

    get '/'
    assert_equal assigns(:notifications).length, 20
  end

  test 'redirect back to last page of results if page is out of bounds' do
    sign_in_as(@user)
    25.times.each { create(:notification, user: @user, archived: false) }

    get '/?page=3'
    assert_redirected_to '/?page=2'
  end

  test 'redirect back to last page of results if page is out of bounds and send filters' do
    sign_in_as(@user)
    25.times.each { create(:notification, user: @user, archived: false, unread: true) }

    get '/?page=3&reason=subscribed&unread=true'
    assert_redirected_to '/?page=2&reason=subscribed&unread=true'
  end

  test 'archives multiple notifications' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user, archived: false)
    notification2 = create(:notification, user: @user, archived: false)
    notification3 = create(:notification, user: @user, archived: false)

    stub_request(:patch, /https:\/\/api.github.com\/notifications\/threads/)

    post '/notifications/archive_selected', params: { id: [notification1.id, notification2.id], value: true }, xhr: true

    assert_response :ok

    assert notification1.reload.archived?
    assert notification2.reload.archived?
    refute notification3.reload.archived?
  end

  test 'archives all notifications' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user, archived: false)
    notification2 = create(:notification, user: @user, archived: false)
    notification3 = create(:notification, user: @user, archived: false)

    stub_request(:patch, /https:\/\/api.github.com\/notifications\/threads/)

    post '/notifications/archive_selected', params: { id: ['all'], value: true }, xhr: true

    assert_response :ok

    assert notification1.reload.archived?
    assert notification2.reload.archived?
    assert notification3.reload.archived?
  end

  test 'archives respects current filters' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user, archived: false, unread: false)
    notification2 = create(:notification, user: @user, archived: false)
    notification3 = create(:notification, user: @user, archived: false)

    post '/notifications/archive_selected', params: { unread: true, id: ['all'], value: true }, xhr: true

    assert_response :ok

    refute notification1.reload.archived?
    assert notification2.reload.archived?
    assert notification3.reload.archived?
  end


  test 'mutes multiple notifications' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user, archived: false)
    notification2 = create(:notification, user: @user, archived: false)
    notification3 = create(:notification, user: @user, archived: false)

    Notification.expects(:mute).with([notification1, notification2])

    post '/notifications/mute_selected', params: { id: [notification1.id, notification2.id] }, xhr: true
    assert_response :ok
  end

  test 'mutes all notifications in current scope' do
    sign_in_as(@user)
    Notification.destroy_all
    notification1 = create(:notification, user: @user, archived: false)
    notification2 = create(:notification, user: @user, archived: false)
    notification3 = create(:notification, user: @user, archived: false)

    Notification.expects(:mute).with([notification1, notification2, notification3])

    post '/notifications/mute_selected', params: { id: ['all'] }, xhr: true
    assert_response :ok
  end

  test 'marks read multiple notifications' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user, archived: false)
    notification2 = create(:notification, user: @user, archived: false)
    notification3 = create(:notification, user: @user, archived: false)

    Notification.expects(:mark_read).with([notification1, notification2])

    post '/notifications/mark_read_selected', params: { id: [notification1.id, notification2.id] }
    assert_response :ok
  end

  test 'marks read all notifications' do
    sign_in_as(@user)
    Notification.destroy_all
    notification1 = create(:notification, user: @user, archived: false)
    notification2 = create(:notification, user: @user, archived: false)
    notification3 = create(:notification, user: @user, archived: false)

    Notification.expects(:mark_read).with([notification1, notification2, notification3])

    post '/notifications/mark_read_selected', params: { id: ['all'] }
    assert_response :ok
  end

  test 'toggles starred on a notification' do
    notification = create(:notification, user: @user, starred: false)

    sign_in_as(@user)

    post "/notifications/#{notification.id}/star"
    assert_response :ok

    assert notification.reload.starred?
  end

  test 'toggles unread on a notification' do
    notification = create(:notification, user: @user, unread: true)

    sign_in_as(@user)

    post "/notifications/#{notification.id}/mark_read"
    assert_response :ok

    refute notification.reload.unread?
  end

  test 'syncs users notifications' do
    sign_in_as(@user)

    get "/notifications/sync"
    assert_response :redirect
  end

  test 'syncs users notifications async' do
    stub_background_jobs_enabled
    # Initial sync means we won't enqueue a sync immediately on login
    sign_in_as(@user, initial_sync: true)
    job_id = @user.sync_job_id

    inline_sidekiq_status do
      get "/notifications/sync"
      @user.reload

      assert_response :redirect
      assert_equal 1, SyncNotificationsWorker.jobs.size
      assert_not_equal job_id, @user.sync_job_id
      assert_not_nil @user.sync_job_id, 'Sync job id was nil'
    end
  end

  test 'syncs users notifications as json' do
    sign_in_as(@user)

    post "/notifications/sync.json"
    assert_response :no_content
  end

  test 'get to syncs redirects' do
    sign_in_as(@user)

    get "/notifications/sync"
    assert_response :redirect
  end

  test 'gracefully handles failed user notification syncs' do
    sign_in_as(@user)
    User.any_instance.stubs(:sync_notifications_in_foreground).raises(Octokit::BadGateway)

    get "/notifications/sync"
    assert_response :redirect
    assert_equal "Having issues connecting to GitHub. Please try again.", flash[:error]
  end

  test 'gracefully handles failed user notification syncs as json' do
    sign_in_as(@user)
    User.any_instance.stubs(:sync_notifications_in_foreground).raises(Octokit::BadGateway)

    post "/notifications/sync.json"
    assert_response :service_unavailable
  end

  test 'gracefully handles failed user notification syncs with wrong token' do
    sign_in_as(@user)
    User.any_instance.stubs(:sync_notifications_in_foreground).raises(Octokit::Unauthorized)

    get "/notifications/sync"
    assert_response :redirect
    assert_equal "Your GitHub token seems to be invalid. Please try again.", flash[:error]
  end

  test 'gracefully handles forbidden user notification syncs' do
    sign_in_as(@user)
    User.any_instance.stubs(:sync_notifications_in_foreground).raises(Octokit::Forbidden)

    get "/notifications/sync"
    assert_response :redirect
    assert_equal "Your GitHub token seems to be invalid. Please try again.", flash[:error]
  end

  test 'gracefully handles failed user notification syncs with bad token as json' do
    sign_in_as(@user)
    User.any_instance.stubs(:sync_notifications_in_foreground).raises(Octokit::Unauthorized)

    post "/notifications/sync.json"
    assert_response :service_unavailable
  end

  test 'gracefully handles failed user notification syncs when user is offline' do
    sign_in_as(@user)
    User.any_instance.stubs(:sync_notifications_in_foreground).raises(Faraday::ConnectionFailed.new('offline error'))

    get "/notifications/sync"
    assert_response :redirect
    assert_equal "You seem to be offline. Please try again.", flash[:error]
  end

  test 'gracefully handles failed user notification syncs when user is offline as json' do
    sign_in_as(@user)
    User.any_instance.stubs(:sync_notifications_in_foreground).raises(Faraday::ConnectionFailed.new('offline error'))

    post "/notifications/sync.json"
    assert_response :service_unavailable
  end

  test 'syncing returns ok when not syncing' do
    sign_in_as(@user)

    User.any_instance.expects(:syncing?).returns(false)
    get "/notifications/syncing.json"
    assert_response :ok
  end

  test 'syncing returns locked when not syncing' do
    sign_in_as(@user)

    User.any_instance.expects(:syncing?).returns(true)
    get "/notifications/syncing.json"
    assert_response :locked
  end

  test 'renders the inbox notification count in the sidebar' do
    sign_in_as(@user)
    create(:notification, user: @user, archived: false)
    create(:notification, user: @user, archived: false)
    create(:notification, user: @user, archived: false)

    create(:notification, user: @user, archived: true)
    create(:notification, user: @user, archived: true)

    create(:notification, user: @user, starred: true)
    create(:notification, user: @user, starred: true)
    create(:notification, user: @user, starred: true)

    get '/'
    assert_response :success

    assert_select("li[role='presentation'] > a > span") do |elements|
      assert_equal elements[0].text, '8'
    end
  end

  test 'renders pagination info for notifications in json' do
    sign_in_as(@user)

    get notifications_path(format: :json)

    assert_response :success
    json = JSON.parse(response.body)
    notification_count = Notification.inbox.where(user: @user).count
    assert_equal notification_count, json["pagination"]["total_notifications"]
    assert_equal 0, json["pagination"]["page"]
    assert_equal (notification_count.to_f / 20).ceil, json["pagination"]["total_pages"]
    assert_equal [notification_count, 20].min, json["pagination"]["per_page"]
  end

  test 'renders pagination info for zero notifications in json' do
    sign_in_as(@user)
    Notification.destroy_all

    get notifications_path(format: :json)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 0, json["pagination"]["total_notifications"]
    assert_equal 0, json["pagination"]["page"]
    assert_equal 0, json["pagination"]["total_pages"]
    assert_equal 0, json["pagination"]["per_page"]
  end

  test 'renders a union of notifications when multiple reasons given' do
    sign_in_as(@user)
    Notification.destroy_all

    notification1 = create(:notification, user: @user, archived: false, reason: "assign")
    notification2 = create(:notification, user: @user, archived: false, reason: "mention")
    notification3 = create(:notification, user: @user, archived: false, reason: "subscribed")

    get notifications_path(format: :json, reason: "assign,mention")

    assert_response :success

    json = JSON.parse(response.body)
    notification_ids = json["notifications"].map { |n| n["id"] }

    assert notification_ids.include?(notification1.id)
    assert notification_ids.include?(notification2.id)
    refute notification_ids.include?(notification3.id)
  end

  test 'search results can filter by repo' do
    sign_in_as(@user)
    create(:notification, user: @user, repository_full_name: 'a/b')
    create(:notification, user: @user, repository_full_name: 'b/c')
    get '/?q=repo%3Aa%2Fb'
    assert_equal assigns(:notifications).length, 1
  end

  test 'search results can filter by multiple repo' do
    sign_in_as(@user)
    create(:notification, user: @user, repository_full_name: 'a/b')
    create(:notification, user: @user, repository_full_name: 'b/c')
    get '/?q=repo%3Aa%2Fb%2Cb%2Fc'
    assert_equal assigns(:notifications).length, 2
  end

  test 'search results can filter to exclude a repo' do
    sign_in_as(@user)
    @user.notifications.delete_all
    create(:notification, user: @user, repository_full_name: 'a/b')
    create(:notification, user: @user, repository_full_name: 'b/c')
    get '/?q=-repo%3Aa%2Fb'
    assert_equal assigns(:notifications).length, 1
    assert_equal assigns(:notifications).first.repository_full_name, 'b/c'
  end

  test 'search results can filter to exclude multiple repos' do
    sign_in_as(@user)
    @user.notifications.delete_all
    create(:notification, user: @user, repository_full_name: 'a/b')
    create(:notification, user: @user, repository_full_name: 'b/c')
    get '/?q=-repo%3Aa%2Fb%2Cb%2Fc'
    assert_equal assigns(:notifications).length, 0
  end

  test 'search results can filter by owner' do
    sign_in_as(@user)
    create(:notification, user: @user, repository_owner_name: 'andrew')
    create(:notification, user: @user, repository_owner_name: 'octobox')
    get '/?q=owner%3Aoctobox'
    assert_equal assigns(:notifications).length, 1
  end

  test 'search results can filter by multiple owners' do
    sign_in_as(@user)
    @user.notifications.delete_all
    create(:notification, user: @user, repository_owner_name: 'andrew')
    create(:notification, user: @user, repository_owner_name: 'octobox')
    get '/?q=owner%3Aoctobox%2Candrew'
    assert_equal assigns(:notifications).length, 2
  end

  test 'search results can filter to exclude owner' do
    sign_in_as(@user)
    @user.notifications.delete_all
    create(:notification, user: @user, repository_owner_name: 'andrew')
    create(:notification, user: @user, repository_owner_name: 'octobox')
    get '/?q=-owner%3Aoctobox'
    assert_equal assigns(:notifications).length, 1
    assert_equal assigns(:notifications).first.repository_owner_name, 'andrew'
  end

  test 'search results can filter to exclude multiple owners' do
    sign_in_as(@user)
    @user.notifications.delete_all
    create(:notification, user: @user, repository_owner_name: 'andrew')
    create(:notification, user: @user, repository_owner_name: 'octobox')
    get '/?q=-owner%3Aoctobox%2Candrew'
    assert_equal assigns(:notifications).length, 0
  end

  test 'search results can filter by type' do
    sign_in_as(@user)
    create(:notification, user: @user, subject_type: 'Issue')
    create(:notification, user: @user, subject_type: 'PullRequest')
    get '/?q=type%3Apull_request'
    assert_equal assigns(:notifications).length, 1
  end

  test 'search results can filter to exclude type' do
    sign_in_as(@user)
    @user.notifications.delete_all
    create(:notification, user: @user, subject_type: 'Issue')
    create(:notification, user: @user, subject_type: 'PullRequest')
    get '/?q=-type%3Apull_request'
    assert_equal assigns(:notifications).length, 1
    assert_equal assigns(:notifications).first.subject_type, 'Issue'
  end

  test 'search results can filter by reason' do
    sign_in_as(@user)
    create(:notification, user: @user, reason: 'assign')
    create(:notification, user: @user, reason: 'mention')
    get '/?q=reason%3Amention'
    assert_equal assigns(:notifications).length, 1
  end

  test 'search results can filter to exclude reason' do
    sign_in_as(@user)
    @user.notifications.delete_all
    create(:notification, user: @user, reason: 'assign')
    create(:notification, user: @user, reason: 'mention')
    get '/?q=-reason%3Amention'
    assert_equal assigns(:notifications).length, 1
    assert_equal assigns(:notifications).first.reason, 'assign'
  end

  test 'search results can filter by starred' do
    sign_in_as(@user)
    create(:notification, user: @user, starred: true)
    create(:notification, user: @user, starred: false)
    get '/?q=starred%3Atrue'
    assert_equal assigns(:notifications).length, 1
  end

  test 'search results can filter by archived' do
    sign_in_as(@user)
    create(:notification, user: @user, archived: true)
    create(:notification, user: @user, archived: false)
    get '/?q=archived%3Atrue'
    assert_equal assigns(:notifications).length, 1
  end

  test 'search results can filter by inbox' do
    sign_in_as(@user)
    @user.notifications.delete_all
    notification1 = create(:notification, user: @user, archived: true)
    notification2 = create(:notification, user: @user, archived: false)
    get '/?q=inbox%3Atrue'
    assert_equal assigns(:notifications).length, 1
    assert_equal assigns(:notifications).to_a, [notification2]
  end

  test 'search results can filter by unread' do
    sign_in_as(@user)
    create(:notification, user: @user, unread: true)
    create(:notification, user: @user, unread: false)
    get '/?q=unread%3Afalse'
    assert_equal assigns(:notifications).length, 1
  end

  test 'search results can filter by author' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user, subject_type: 'Issue')
    notification2 = create(:notification, user: @user, subject_type: 'PullRequest')
    create(:subject, notifications: [notification1], author: 'andrew')
    create(:subject, notifications: [notification2], author: 'benjam')
    get '/?q=author%3Aandrew'
    assert_equal assigns(:notifications).length, 1
  end

  test 'search results can filter by multiple authors' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user, subject_type: 'Issue')
    notification2 = create(:notification, user: @user, subject_type: 'PullRequest')
    create(:subject, notifications: [notification1], author: 'andrew')
    create(:subject, notifications: [notification2], author: 'benjam')
    get '/?q=author%3Aandrew%2Cbenjam'
    assert_equal assigns(:notifications).length, 2
  end

  test 'search results can filter to exclude author' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user, subject_type: 'Issue')
    notification2 = create(:notification, user: @user, subject_type: 'PullRequest')
    create(:subject, notifications: [notification1], author: 'andrew')
    create(:subject, notifications: [notification2], author: 'benjam')
    get '/?q=-author%3Aandrew'
    assert_equal assigns(:notifications).length, 1
    assert_equal assigns(:notifications).first.subject.author, 'benjam'
  end

  test 'search results can filter to exclude multiple authors' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user, subject_type: 'Issue')
    notification2 = create(:notification, user: @user, subject_type: 'PullRequest')
    create(:subject, notifications: [notification1], author: 'andrew')
    create(:subject, notifications: [notification2], author: 'benjam')
    get '/?q=-author%3Aandrew%2Cbenjam'
    assert_equal assigns(:notifications).length, 0
  end

  test 'search results can filter by label' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user)
    notification2 = create(:notification, user: @user)
    subject1 = create(:subject, notifications: [notification1])
    subject2 = create(:subject, notifications: [notification2])
    create(:label, subject: subject1, name: 'bug')
    create(:label, subject: subject2, name: 'feature')
    get '/?q=label%3Abug'
    assert_equal assigns(:notifications).length, 1
  end

  test 'search results can filter by multiple labels' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user)
    notification2 = create(:notification, user: @user)
    subject1 = create(:subject, notifications: [notification1])
    subject2 = create(:subject, notifications: [notification2])
    create(:label, subject: subject1, name: 'bug')
    create(:label, subject: subject2, name: 'feature')
    get '/?q=label%3Abug%2Cfeature'
    assert_equal assigns(:notifications).length, 2
  end

  test 'search results can filter to exclude label' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user)
    notification2 = create(:notification, user: @user)
    subject1 = create(:subject, notifications: [notification1])
    subject2 = create(:subject, notifications: [notification2])
    create(:label, subject: subject1, name: 'bug')
    create(:label, subject: subject2, name: 'feature')
    get '/?q=-label%3Abug'
    assert_equal assigns(:notifications).length, 1
    assert_equal assigns(:notifications).first.labels.first.name, 'feature'
  end

  test 'search results can filter to exclude multiple labels' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user)
    notification2 = create(:notification, user: @user)
    subject1 = create(:subject, notifications: [notification1])
    subject2 = create(:subject, notifications: [notification2])
    create(:label, subject: subject1, name: 'bug')
    create(:label, subject: subject2, name: 'feature')
    get '/?q=-label%3Abug%2Cfeature'
    assert_equal assigns(:notifications).length, 0
  end

  test 'search results can filter by state' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user)
    notification2 = create(:notification, user: @user)
    create(:subject, notifications: [notification1], state: "open")
    create(:subject, notifications: [notification2], state: "closed")
    get '/?q=state%3Aopen'
    assert_equal assigns(:notifications).length, 1
  end

  test 'search results can filter by multiple states' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user)
    notification2 = create(:notification, user: @user)
    create(:subject, notifications: [notification1], state: "open")
    create(:subject, notifications: [notification2], state: "closed")
    get '/?q=state%3Aopen%2Cclosed'
    assert_equal assigns(:notifications).length, 2
  end

  test 'search results can filter to exclude state' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user)
    notification2 = create(:notification, user: @user)
    create(:subject, notifications: [notification1], state: "open")
    create(:subject, notifications: [notification2], state: "closed")
    get '/?q=-state%3Aopen'
    assert_equal assigns(:notifications).length, 1
    assert_equal assigns(:notifications).first.subject.state, 'closed'
  end

  test 'search results can filter to exclude multiple states' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user)
    notification2 = create(:notification, user: @user)
    create(:subject, notifications: [notification1], state: "open")
    create(:subject, notifications: [notification2], state: "closed")
    get '/?q=-state%3Aopen%2Cclosed'
    assert_equal assigns(:notifications).length, 0
  end

  test 'search results can filter by assignee' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user)
    notification2 = create(:notification, user: @user)
    create(:subject, notifications: [notification1], assignees: ":andrew:")
    create(:subject, notifications: [notification2], assignees: ":benjam:")
    get '/?q=assignee%3Aandrew'
    assert_equal assigns(:notifications).length, 1
  end

  test 'search results can filter by multiple assignees' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user)
    notification2 = create(:notification, user: @user)
    create(:subject, notifications: [notification1], assignees: ":andrew:")
    create(:subject, notifications: [notification2], assignees: ":benjam:")
    get '/?q=assignee%3Aandrew%2Cbenjam'
    assert_equal assigns(:notifications).length, 2
  end

  test 'search results can filter to exclude assignee' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user)
    notification2 = create(:notification, user: @user)
    create(:subject, notifications: [notification1], assignees: ":andrew:")
    create(:subject, notifications: [notification2], assignees: ":benjam:")
    get '/?q=-assignee%3Aandrew'
    assert_equal assigns(:notifications).length, 1
    assert_equal assigns(:notifications).first.subject.assignees, ":benjam:"
  end

  test 'search results can filter to exclude multiple assignees' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user)
    notification2 = create(:notification, user: @user)
    create(:subject, notifications: [notification1], assignees: ":andrew:")
    create(:subject, notifications: [notification2], assignees: ":benjam:")
    get '/?q=-assignee%3Aandrew%2Cbenjam'
    assert_equal assigns(:notifications).length, 0
  end

  test 'search results can filter by locked:true' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user, subject_type: 'Issue')
    notification2 = create(:notification, user: @user, subject_type: 'PullRequest')
    create(:subject, notifications: [notification1], locked: true)
    create(:subject, notifications: [notification2], locked: true)
    get '/?q=locked%3Atrue'
    assert_equal assigns(:notifications).length, 2
  end

  test 'search results can filter by locked:false' do
    sign_in_as(@user)
    notification1 = create(:notification, user: @user, subject_type: 'Issue')
    notification2 = create(:notification, user: @user, subject_type: 'PullRequest')
    create(:subject, notifications: [notification1], locked: false)
    create(:subject, notifications: [notification2], locked: true)
    get '/?q=locked%3Afalse'
    assert_equal assigns(:notifications).length, 1
  end

  test 'search results can filter by muted:true' do
    sign_in_as(@user)
    create(:notification, user: @user, muted_at: Time.current)
    create(:notification, user: @user)
    get '/?q=muted%3Atrue'
    assert_equal assigns(:notifications).length, 1
  end

  test 'search results can filter by muted:false' do
    sign_in_as(@user)
    Notification.destroy_all
    create(:notification, user: @user, muted_at: Time.current)
    create(:notification, user: @user)
    get '/?q=muted%3Afalse'
    assert_equal assigns(:notifications).length, 1
  end

  test 'sets the per_page cookie' do
    sign_in_as(@user)
    get '/?per_page=100'
    assert_equal '100', cookies[:per_page]
  end

  test 'uses the per_page cookie' do
    sign_in_as(@user)
    get '/?per_page=100'
    get '/'
    assert_equal assigns(:per_page), 100
  end
end
