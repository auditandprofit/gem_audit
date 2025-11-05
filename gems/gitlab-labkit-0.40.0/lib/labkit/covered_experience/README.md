# Covered Experience

This module covers the definition for Covered Experiences, as described in the [blueprint](https://handbook.gitlab.com/handbook/engineering/architecture/design-documents/covered_experience_slis/#covered-experience-definition).

## Configuration

### Logger Configuration

By default, `Labkit::CoveredExperience` uses `Labkit::Logging::JsonLogger.new($stdout)` for logging. You can configure a custom logger:

```ruby
Labkit::CoveredExperience.configure do |config|
  config.logger = Labkit::Logging::JsonLogger.new($stdout)
end
```

This configuration affects all Covered Experience instances and their logging output.

### Covered Experience Definitions

Covered experience definitions will be lazy loaded from the default directory (`config/covered_experiences`).

Create a new covered experience file in the registry directory, e.g. config/covered_experiences/merge_request_creation.yaml

The basename of the file will be taken as the covered_experience_id.

The schema header is optional, but if you're using VSCode (or any other editor with support), you can get them validated
instantaneously in the editor via a [JSON schema plugin](https://marketplace.visualstudio.com/items?itemName=remcohaszing.schemastore).

```yaml
# yaml-language-server: $schema=https://gitlab.com/gitlab-org/ruby/gems/labkit-ruby/-/raw/master/config/covered_experiences/schema.json
description: "Creating a new merge request in a project"
feature_category: "source_code_management"
urgency: "sync_fast"
```

**Feature category**

https://docs.gitlab.com/development/feature_categorization/#feature-categorization.

**Urgency**

| Threshold    | Description                                                                                                                                                      | Examples                                                                       | Value |
|--------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------|-------|
| `sync_fast`  | A user is awaiting a synchronous response which needs to be returned before they can continue with their action                                                  | A full-page render                                                             | 2s    |
| `sync_slow`  | A user is awaiting a synchronous response which needs to be returned before they can continue with their action, but which the user may accept a slower response | Displaying a full-text search response while displaying an amusement animation | 5s    |
| `async_fast` | An async process which may block a user from continuing with their user journey                                                                                  | MR diff update after git push                                                  | 15s   |
| `async_slow` | An async process which will not block a user and will not be immediately noticed as being slow                                                                   | Notification following an assignment                                           | 5m    |

## Usage

The `Labkit::CoveredExperience` module provides a simple API for measuring and tracking covered experiences in your application.


#### Accessing a Covered Experience

```ruby
# Get a covered experience by ID
experience = Labkit::CoveredExperience.get('merge_request_creation')
```

#### Using with a Block (Recommended)

The simplest way to use covered experiences is with a block, which automatically handles starting and completing the experience:

```ruby
Labkit::CoveredExperience.start('merge_request_creation') do |experience|
  # Your code here
  create_merge_request

  # Add checkpoints for important milestones
  experience.checkpoint

  validate_merge_request
  experience.checkpoint

  send_notifications
end
```

#### Manual Control

For more control, you can manually start, checkpoint, and complete experiences:

```ruby
experience = Labkit::CoveredExperience.get('merge_request_creation')
experience.start

# Perform some work
create_merge_request

# Mark important milestones
experience.checkpoint

# Perform more work
validate_merge_request
experience.checkpoint

# Complete the experience
experience.complete
```

### Error Handling

When using the block form, errors are automatically captured:

```ruby
Labkit::CoveredExperience.start('merge_request_creation') do |experience|
  # If this raises an exception, it will be captured automatically
  risky_operation
end
```

For manual control, you can mark errors explicitly:

```ruby
experience = Labkit::CoveredExperience.get('merge_request_creation')
experience.start

begin
  risky_operation
rescue StandardError => e
  experience.error!(e)
  raise
ensure
  experience.complete
end
```

### Error Behavior

- In `development` and `test` environments, accessing a non-existent covered experience will raise a `NotFoundError`
- In other environments, a null object is returned that safely ignores all method calls
- Attempting to checkpoint or complete an unstarted experience will raise an `UnstartedError` in `development` and `test` environments
