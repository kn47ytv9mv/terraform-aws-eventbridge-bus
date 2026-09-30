mock_provider "aws" {}

run "invalid_characters_in_the_name_are_rejected" {
  command = plan

  variables {
    name = "order events"
  }

  expect_failures = [var.name]
}

run "a_name_past_the_length_limit_is_rejected" {
  command = plan

  variables {
    name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }

  expect_failures = [var.name]
}

run "the_default_bus_name_is_rejected" {
  command = plan

  variables {
    name = "default"
  }

  expect_failures = [var.name]
}

run "an_event_source_name_that_is_not_a_partner_source_is_rejected" {
  command = plan

  variables {
    name              = "order-events"
    event_source_name = "order-events"
  }

  expect_failures = [var.event_source_name]
}

run "an_event_source_name_that_does_not_match_the_name_is_rejected" {
  command = plan

  variables {
    name              = "order-events"
    event_source_name = "aws.partner/example.com/acct1/repo1"
  }

  expect_failures = [var.event_source_name]
}

run "enabling_the_policy_without_a_document_is_rejected" {
  command = plan

  variables {
    name          = "order-events"
    enable_policy = true
  }

  expect_failures = [var.enable_policy]
}

run "a_policy_without_the_switch_is_rejected" {
  command = plan

  variables {
    name   = "order-events"
    policy = "{}"
  }

  expect_failures = [var.enable_policy]
}

run "enabling_the_dead_letter_queue_without_an_arn_is_rejected" {
  command = plan

  variables {
    name                     = "order-events"
    enable_dead_letter_queue = true
  }

  expect_failures = [var.enable_dead_letter_queue]
}

run "a_dead_letter_queue_arn_without_the_switch_is_rejected" {
  command = plan

  variables {
    name                  = "order-events"
    dead_letter_queue_arn = "arn:aws:sqs:us-east-1:123456789012:order-events-dlq"
  }

  expect_failures = [var.enable_dead_letter_queue]
}

run "an_aws_managed_kms_alias_is_rejected" {
  command = plan

  variables {
    name               = "order-events"
    kms_key_identifier = "alias/aws/events"
  }

  expect_failures = [var.kms_key_identifier]
}

run "an_invalid_log_level_is_rejected" {
  command = plan

  variables {
    name       = "order-events"
    log_config = { level = "VERBOSE" }
  }

  expect_failures = [var.log_config]
}

run "an_invalid_log_include_detail_is_rejected" {
  command = plan

  variables {
    name       = "order-events"
    log_config = { level = "INFO", include_detail = "SOME" }
  }

  expect_failures = [var.log_config]
}

run "name_defaults_to_random_uuid" {
  command = apply

  assert {
    condition     = aws_cloudwatch_event_bus.resource.name == random_uuid.resource.id
    error_message = "Leaving name unset should fall back to the generated random_uuid."
  }
}

run "an_ordinary_custom_bus_carries_no_partner_source" {
  command = plan

  variables {
    name = "order-events"
  }

  assert {
    condition     = aws_cloudwatch_event_bus.resource.event_source_name == null
    error_message = "A bus created without event_source_name should be an ordinary custom bus, not a partner one."
  }
}

run "a_partner_bus_is_named_after_its_event_source" {
  command = plan

  variables {
    name              = "aws.partner/example.com/acct1/repo1"
    event_source_name = "aws.partner/example.com/acct1/repo1"
  }

  assert {
    condition     = aws_cloudwatch_event_bus.resource.name == aws_cloudwatch_event_bus.resource.event_source_name
    error_message = "A partner event bus must be named exactly after the partner event source it receives from."
  }
}

run "no_policy_by_default" {
  command = plan

  variables {
    name = "order-events"
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus_policy.resource) == 0
    error_message = "Leaving enable_policy unset should create no bus policy, so the bus is reachable only from its own account."
  }
}

run "enabling_the_policy_creates_one_attached_to_this_bus" {
  command = plan

  variables {
    name          = "order-events"
    enable_policy = true
    policy        = "{}"
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus_policy.resource) == 1
    error_message = "Setting enable_policy should create exactly one bus policy."
  }

  assert {
    condition     = aws_cloudwatch_event_bus_policy.resource[0].event_bus_name == "order-events"
    error_message = "The bus policy should attach to the bus this module creates rather than to any other."
  }
}

run "no_dead_letter_config_by_default" {
  command = plan

  variables {
    name = "order-events"
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus.resource.dead_letter_config) == 0
    error_message = "Leaving enable_dead_letter_queue unset should omit the dead_letter_config block entirely."
  }
}

run "the_dead_letter_queue_is_set_when_enabled" {
  command = plan

  variables {
    name                     = "order-events"
    enable_dead_letter_queue = true
    dead_letter_queue_arn    = "arn:aws:sqs:us-east-1:123456789012:order-events-dlq"
  }

  assert {
    condition     = one(aws_cloudwatch_event_bus.resource.dead_letter_config).arn == "arn:aws:sqs:us-east-1:123456789012:order-events-dlq"
    error_message = "Enabling the dead-letter queue should point the bus at the supplied queue ARN."
  }
}

run "no_log_config_by_default" {
  command = plan

  variables {
    name = "order-events"
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus.resource.log_config) == 0
    error_message = "Leaving log_config unset should omit the block rather than sending AWS an empty one."
  }
}

run "log_config_passes_both_fields_through" {
  command = plan

  variables {
    name       = "order-events"
    log_config = { level = "INFO", include_detail = "FULL" }
  }

  assert {
    condition     = one(aws_cloudwatch_event_bus.resource.log_config).level == "INFO"
    error_message = "log_config.level should reach the bus unchanged."
  }

  assert {
    condition     = one(aws_cloudwatch_event_bus.resource.log_config).include_detail == "FULL"
    error_message = "log_config.include_detail should reach the bus unchanged."
  }
}

run "readme_default_example" {
  command = plan

  variables {
    name        = "order-events"
    description = "Domain events published by the ordering service"
  }
}

run "readme_dead_letter_and_policy_example" {
  command = plan

  variables {
    name        = "order-events"
    description = "Domain events published by the ordering service"

    enable_dead_letter_queue = true
    dead_letter_queue_arn    = "arn:aws:sqs:us-east-1:123456789012:order-events-dlq"

    log_config = {
      level          = "ERROR"
      include_detail = "NONE"
    }

    enable_policy = true
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "AllowReportingAccountToPublish"
          Effect    = "Allow"
          Principal = { AWS = "arn:aws:iam::210987654321:root" }
          Action    = "events:PutEvents"
          Resource  = "arn:aws:events:us-east-1:123456789012:event-bus/order-events"
        }
      ]
    })
  }
}
