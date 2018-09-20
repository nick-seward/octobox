# frozen_string_literal: true
require 'test_helper'

class RepositoryTest < ActiveSupport::TestCase
  setup do
    @repository = create(:repository)
  end

  test 'must have a unique github_id' do
    repository = build(:repository, github_id: @repository.github_id)
    refute repository.valid?
  end

  test 'must have an full_name' do
    @repository.full_name = nil
    refute @repository.valid?
  end

  test 'must have a unique full_name' do
    repository = build(:repository, full_name: @repository.full_name)
    refute repository.valid?
  end

  test 'github_app_installed if app_installation_id present' do
    @repository.app_installation_id = 1
    assert @repository.github_app_installed?
  end

  test 'github_app_installed if app_installation_id missing' do
    @repository.app_installation_id = nil
    refute @repository.github_app_installed?
  end

  test 'finds subjects by full_name' do
    subject = create(:subject, url: "https://api.github.com/repos/#{@repository.full_name}/issues/1", repository_full_name: @repository.full_name)
    subject2 = create(:subject, url: "https://api.github.com/repos/foo/bar/issues/1", repository_full_name: 'foo/bar')
    assert_equal @repository.subjects.length, 1
    assert_equal @repository.subjects.first, subject
  end

  test 'updates full_name and ower_name of notifications of repository if full_name is updated' do
    notification = create(
      :notification,
      repository_id: @repository.github_id,
      repository_full_name: @repository.full_name,
      repository_owner_name: @repository.owner,
      subject_url: "https://api.github.com/repos/#{@repository.full_name}/issues/1",
      archived: false
    )

    @repository.full_name = "octobox_hq/octobox"
    @repository.owner = "octobox_hq"
    @repository.save

    notification.reload

    assert_equal notification.repository_owner_name, @repository.owner
    assert_equal notification.repository_full_name, @repository.full_name
  end
end
