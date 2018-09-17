# frozen_string_literal: true
class SavedSearchesController < ApplicationController

  def index
    @saved_searches = current_user.saved_searches
  end

  def create

  end

  def update

  end

end
