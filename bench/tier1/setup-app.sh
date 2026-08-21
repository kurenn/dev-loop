#!/usr/bin/env bash
# Build the pristine benchmark app + a bare origin remote. Idempotent-ish: pass --force to rebuild.
# The app is deliberately ordinary Rails: a gitignored config/master.key (so worktree
# provisioning is a real test), a green minitest suite (so "baseline" means something),
# and enough domain surface that a feature task needs more than one layer.
set -euo pipefail
BENCH="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$BENCH/.work"
APP="$WORK/app-pristine"
ORIGIN="$WORK/origin.git"
export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"

if [ "${1:-}" = "--force" ]; then rm -rf "$APP" "$ORIGIN"; fi
mkdir -p "$WORK"

if [ ! -d "$APP" ]; then
  rails new "$APP" --database=sqlite3 --skip-git --skip-action-mailbox --skip-action-text \
    --skip-active-storage --skip-action-cable --skip-jbuilder --skip-kamal --skip-solid \
    --skip-docker --skip-ci --skip-rubocop --skip-brakeman --skip-devcontainer --no-rc
fi

cd "$APP"

# --- .gitignore: --skip-git suppresses it, and we need master.key ignored on purpose ---
cat > .gitignore <<'GI'
/.bundle
/log/*
/tmp/*
!/log/.keep
!/tmp/.keep
/storage/*
!/storage/.keep
/public/assets
/db/*.sqlite3
/db/*.sqlite3-*
/config/master.key
/.env
/.worktrees/
GI

# --- domain: only generate once ---
if [ ! -f app/models/project.rb ]; then
  bin/rails g model Project name:string description:text archived:boolean --no-test-framework
  bin/rails g model Task project:references title:string done:boolean --no-test-framework

  cat > app/models/project.rb <<'RB'
class Project < ApplicationRecord
  has_many :tasks, dependent: :destroy

  validates :name, presence: true

  scope :active, -> { where(archived: false) }
end
RB

  cat > app/models/task.rb <<'RB'
class Task < ApplicationRecord
  belongs_to :project

  validates :title, presence: true

  scope :open, -> { where(done: false) }
end
RB

  cat > app/controllers/projects_controller.rb <<'RB'
class ProjectsController < ApplicationController
  def index
    @projects = Project.active.order(:name)
    render json: @projects.as_json(only: [ :id, :name, :archived ])
  end

  def show
    @project = Project.find(params[:id])
    render json: @project.as_json(only: [ :id, :name, :description, :archived ])
  end
end
RB

  cat > config/routes.rb <<'RB'
Rails.application.routes.draw do
  resources :projects, only: [ :index, :show ]
  root "projects#index"
end
RB

  mkdir -p test/models test/controllers test/fixtures
  cat > test/fixtures/projects.yml <<'YML'
alpha:
  name: Alpha
  description: First project
  archived: false

zulu:
  name: Zulu
  description: Archived project
  archived: true
YML

  cat > test/fixtures/tasks.yml <<'YML'
one:
  project: alpha
  title: Write the thing
  done: false

two:
  project: alpha
  title: Ship the thing
  done: true
YML

  cat > test/models/project_test.rb <<'RB'
require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "requires a name" do
    assert_not Project.new(name: nil).valid?
  end

  test "active scope excludes archived projects" do
    assert_includes Project.active, projects(:alpha)
    assert_not_includes Project.active, projects(:zulu)
  end

  test "destroys dependent tasks" do
    assert_difference "Task.count", -2 do
      projects(:alpha).destroy
    end
  end
end
RB

  cat > test/models/task_test.rb <<'RB'
require "test_helper"

class TaskTest < ActiveSupport::TestCase
  test "requires a title" do
    assert_not Task.new(title: nil, project: projects(:alpha)).valid?
  end

  test "open scope excludes done tasks" do
    assert_includes Task.open, tasks(:one)
    assert_not_includes Task.open, tasks(:two)
  end
end
RB

  cat > test/controllers/projects_controller_test.rb <<'RB'
require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  test "index lists only active projects" do
    get projects_url
    assert_response :success
    names = JSON.parse(response.body).map { |p| p["name"] }
    assert_includes names, "Alpha"
    assert_not_includes names, "Zulu"
  end

  test "show returns a project" do
    get project_url(projects(:alpha))
    assert_response :success
    assert_equal "Alpha", JSON.parse(response.body)["name"]
  end
end
RB
fi

bin/rails db:prepare >/dev/null
echo "--- baseline suite ---"
bin/rails test

# --- git: pin a base SHA, and a bare origin so push assertions are testable ---
if [ ! -d .git ]; then
  git init -q -b main
  git add -A
  git -c user.name=bench -c user.email=bench@local commit -q -m "chore: benchmark base app"
  git tag -f bench-base
fi
if [ ! -d "$ORIGIN" ]; then
  git init -q --bare "$ORIGIN"
fi
git remote remove origin 2>/dev/null || true
git remote add origin "$ORIGIN"
git push -q --force origin main
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

echo
echo "pristine app : $APP  (@ $(git rev-parse --short HEAD))"
echo "bare origin  : $ORIGIN"
echo "master.key   : $( [ -f config/master.key ] && echo present ) / gitignored: $(git check-ignore -q config/master.key && echo yes || echo NO)"
