# frozen_string_literal: true

require "rails_helper"

RSpec.describe "wiki_nav_tree mod" do
  let(:source) { Rails.root.join("mod/wiki_nav_tree/set/all/wiki_nav_tree.rb").read }

  it "defines wiki_nav_tree and wiki_nav_tree_branch views" do
    expect(source).to include("view :wiki_nav_tree")
    expect(source).to include("view :wiki_nav_tree_branch")
  end
end
