require "danger"
require "gitlab/dangerfiles/changes"

module DangerSpecHelper
  # These functions are a subset of https://github.com/danger/danger/blob/master/spec/spec_helper.rb
  # If you are expanding these files, see if it's already been done ^.

  # A silent version of the user interface
  def self.testing_ui
    Cork::Board.new(silent: true)
  end

  # Example environment (ENV) that would come from
  # running a PR on TravisCI
  def self.testing_env
    {
      "GITLAB_CI" => "true",
      "DANGER_GITLAB_HOST" => "gitlab.example.com",
      "CI_MERGE_REQUEST_IID" => 28_493,
      "DANGER_GITLAB_API_TOKEN" => "123sbdq54erfsd3422gdfio"
    }
  end

  # A stubbed out Dangerfile for use in tests
  def self.testing_dangerfile
    env = Danger::EnvironmentManager.new(testing_env)
    Danger::Dangerfile.new(env, testing_ui).tap do |dangerfile|
      dangerfile.defined_in_file = Dir.pwd
    end
  end

  def self.fake_danger
    Class.new do
      attr_reader :git, :gitlab, :helper

      # rubocop:disable Gitlab/ModuleWithInstanceVariables
      def initialize(git: nil, gitlab: nil, helper: nil)
        @git = git
        @gitlab = gitlab
        @helper = helper
      end

      # rubocop:enable Gitlab/ModuleWithInstanceVariables
    end
  end
end

RSpec::Matchers.define :match_teammates do |expected|
  match do |actual|
    expected.each do |expected_person|
      matched_person = actual.find { |actual_person| actual_person.name == expected_person.username }

      matched_person &&
        matched_person.name == expected_person.name &&
        matched_person.role == expected_person.role &&
        matched_person.projects == expected_person.projects
    end
  end
end

RSpec.shared_context "with dangerfile" do
  let(:dangerfile) { DangerSpecHelper.testing_dangerfile }
  let(:added_files) { %w[added-from-git] }
  let(:modified_files) { %w[modified-from-git] }
  let(:deleted_files) { %w[deleted-from-git] }
  let(:renamed_before_file) { "renamed_before-from-git" }
  let(:renamed_after_file) { "renamed_after-from-git" }
  let(:renamed_files) { [{ before: renamed_before_file, after: renamed_after_file }] }
  let(:change_class) { Gitlab::Dangerfiles::Change }
  let(:changes_class) { Gitlab::Dangerfiles::Changes }
  let(:ee_change) { nil }
  let(:changes) { changes_class.new([]) }
  let(:mr_title) { "Fake Title" }
  let(:mr_labels) { [] }

  let(:fake_git) { double("fake-git", added_files: added_files, modified_files: modified_files, deleted_files: deleted_files, renamed_files: renamed_files) }
  let(:fake_helper) { double("fake-helper", changes: changes, added_files: added_files, modified_files: modified_files, deleted_files: deleted_files, renamed_files: renamed_files, mr_iid: 1234, mr_title: mr_title, mr_labels: mr_labels) }

  before do
    allow(dangerfile).to receive(:git).and_return(fake_git)
    allow(dangerfile.helper).to receive(:changes).and_return(changes) if dangerfile.respond_to?(:helper)
  end
end

RSpec.shared_context "with teammates" do
  let(:backend_available) { true }
  let(:backend_tz_offset_hours) { 2.0 }
  let(:backend_maintainer_project) { { "gitlab" => "maintainer backend" } }
  let(:backend_maintainer) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "backend-maintainer",
      "name" => "Backend maintainer",
      "role" => "Backend engineer",
      "projects" => backend_maintainer_project,
      "available" => backend_available,
      "tz_offset_hours" => backend_tz_offset_hours
    )
  end

  let(:another_backend_maintainer) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "another-backend-maintainer",
      "name" => "Another Backend Maintainer",
      "role" => "Backend engineer",
      "projects" => backend_maintainer_project,
      "available" => backend_available,
      "tz_offset_hours" => backend_tz_offset_hours
    )
  end

  let(:backend_reviewer_available) { true }
  let(:backend_reviewer) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "backend-reviewer",
      "name" => "Backend reviewer",
      "role" => "Backend engineer",
      "projects" => { "gitlab" => "reviewer backend" },
      "available" => backend_reviewer_available,
      "tz_offset_hours" => 1.0
    )
  end

  let(:frontend_reviewer) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "frontend-reviewer",
      "name" => "Frontend reviewer",
      "role" => "Frontend engineer",
      "projects" => { "gitlab" => "reviewer frontend" },
      "available" => true,
      "tz_offset_hours" => 2.0
    )
  end

  let(:frontend_maintainer) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "frontend-maintainer",
      "name" => "Frontend maintainer",
      "role" => "Frontend engineer",
      "projects" => { "gitlab" => "maintainer frontend" },
      "available" => true,
      "tz_offset_hours" => 2.0
    )
  end

  let(:ux_reviewer) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "ux-reviewer",
      "name" => "UX reviewer",
      "role" => "Product Designer",
      "projects" => { "gitlab" => "reviewer ux" },
      "specialty" => "Create: Source Code",
      "available" => true,
      "tz_offset_hours" => 2.0
    )
  end

  let(:software_engineer_in_test) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "software-engineer-in-test",
      "name" => "Software Engineer in Test",
      "role" => "Software Engineer in Test, Create:Source Code",
      "projects" => { "gitlab" => "maintainer qa", "gitlab-qa" => "maintainer" },
      "available" => true,
      "tz_offset_hours" => 2.0
    )
  end

  let(:software_engineer_in_import_integrate_fe) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "software-engineer-in-import-and-integrate-fe",
      "name" => "Frontend Engineer in Import and Integrate",
      "role" => "AnyRole Frontend Engineer, AnyStage:Import and Integrate",
      "projects" => { "gitlab" => "reviewer frontend" },
      "available" => true,
      "tz_offset_hours" => 2.0
    )
  end

  let(:software_engineer_in_import_integrate_be) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "software-engineer-in-import-and-integrate-be",
      "name" => "Backend Engineer in Import and Integrate",
      "role" => "AnyRole Backend Engineer, AnyStage:Import and Integrate",
      "projects" => { "gitlab" => "reviewer backend" },
      "available" => true,
      "tz_offset_hours" => 2.0
    )
  end

  let(:tooling_reviewer) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "eng-prod-reviewer",
      "name" => "EP engineer",
      "role" => "Engineering Productivity",
      "projects" => { "gitlab" => "reviewer tooling" },
      "available" => true,
      "tz_offset_hours" => 2.0
    )
  end

  let(:ci_template_reviewer) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "ci-template-maintainer",
      "name" => "CI Template engineer",
      "role" => '~"ci::templates"',
      "projects" => { "gitlab" => "reviewer ci_template" },
      "available" => true,
      "tz_offset_hours" => 2.0
    )
  end

  let(:analytics_instrumentation_reviewer) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "analytics-instrumentation-reviewer",
      "name" => "PI engineer",
      "role" => "Backend Engineer, Analytics: Analytics Instrumentation",
      "projects" => { "gitlab" => "reviewer analytics_instrumentation" },
      "available" => true,
      "tz_offset_hours" => 2.0
    )
  end

  let(:import_and_integrate_backend_reviewer) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "import-and-integrate-backend-reviewer",
      "name" => "Import and Integrate BE engineer",
      "role" => "AnyRole Backend Engineer, AnyStage:Import and Integrate",
      "projects" => { "gitlab" => "reviewer backend" },
      "available" => backend_reviewer_available,
      "tz_offset_hours" => 2.0
    )
  end

  let(:import_and_integrate_frontend_reviewer) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "import-and-integrate-frontend-reviewer",
      "name" => "Import and Integrate FE engineer",
      "role" => "AnyRole Frontend Engineer, AnyStage:Import and Integrate",
      "projects" => { "gitlab" => "reviewer frontend" },
      "available" => true,
      "tz_offset_hours" => 2.0
    )
  end

  let(:workhorse_reviewer) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "workhorse-reviewer",
      "name" => "Workhorse reviewer",
      "role" => "Backend engineer",
      "projects" => { "gitlab-workhorse" => "reviewer" },
      "available" => true,
      "tz_offset_hours" => 2.0
    )
  end

  let(:workhorse_maintainer) do
    Gitlab::Dangerfiles::Teammate.new(
      "username" => "workhorse-maintainer",
      "name" => "Workhorse maintainer",
      "role" => "Backend engineer",
      "projects" => { "gitlab-workhorse" => "maintainer" },
      "available" => true,
      "tz_offset_hours" => 2.0
    )
  end

  let(:teammates) do
    [
      backend_maintainer.to_h,
      backend_reviewer.to_h,
      frontend_maintainer.to_h,
      frontend_reviewer.to_h,
      ux_reviewer.to_h,
      software_engineer_in_test.to_h,
      tooling_reviewer.to_h,
      ci_template_reviewer.to_h,
      workhorse_reviewer.to_h,
      workhorse_maintainer.to_h,
      analytics_instrumentation_reviewer.to_h,
      import_and_integrate_backend_reviewer.to_h,
      import_and_integrate_frontend_reviewer.to_h,
      software_engineer_in_import_integrate_fe.to_h,
      software_engineer_in_import_integrate_be.to_h
    ]
  end

  let(:teammate_json) { teammates.to_json }
  let(:ux_fallback_reviewer) { instance_double(Gitlab::Dangerfiles::Teammate) }
  let(:company_members) { Gitlab::Dangerfiles::Teammate.fetch_company_members }

  before do
    WebMock
      .stub_request(:get, Gitlab::Dangerfiles::Teammate::ROULETTE_DATA_URL)
      .to_return(body: teammate_json)

    # This avoid changing the internal state of the class
    allow(Gitlab::Dangerfiles::Teammate).to receive(:warnings).and_return([])
    allow(Gitlab::Dangerfiles::Teammate).to receive(:company_members).and_return(company_members)
  end
end
