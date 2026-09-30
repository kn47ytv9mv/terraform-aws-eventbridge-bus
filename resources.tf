resource "random_uuid" "resource" {}

resource "aws_cloudwatch_event_bus" "resource" {
  name        = coalesce(var.name, random_uuid.resource.id)
  description = var.description

  event_source_name  = var.event_source_name
  kms_key_identifier = var.kms_key_identifier

  dynamic "dead_letter_config" {
    for_each = var.enable_dead_letter_queue ? [1] : []

    content {
      arn = var.dead_letter_queue_arn
    }
  }

  dynamic "log_config" {
    for_each = var.log_config[*]

    content {
      level          = log_config.value.level
      include_detail = log_config.value.include_detail
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_event_bus_policy" "resource" {
  count = var.enable_policy ? 1 : 0

  event_bus_name = aws_cloudwatch_event_bus.resource.name
  policy         = var.policy
}

output "id" {
  description = "The ID of the event bus, which is its name."
  value       = aws_cloudwatch_event_bus.resource.id
}

output "arn" {
  description = "The ARN of the event bus. A cross-account policy or an IAM policy granting events:PutEvents scopes itself to this ARN."
  value       = aws_cloudwatch_event_bus.resource.arn
}

output "name" {
  description = "The name of the event bus. Feed this into terraform-aws-eventbridge-rule's event_bus_name, and into the EventBridge PutEvents call a publisher makes — every EventBridge API identifies a bus by name rather than by ARN."
  value       = aws_cloudwatch_event_bus.resource.name
}
