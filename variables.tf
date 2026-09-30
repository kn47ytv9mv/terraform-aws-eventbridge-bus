variable "name" {
  default     = null
  description = "Name of the event bus. Every publisher and every rule identifies this bus by name rather than by ARN, so a name chosen for the domain it carries ('order-events') is worth more than a generated one. If null, a unique name is generated. The name cannot be 'default', which is the account's own bus and is not managed by this module."

  validation {
    condition     = var.name == null || can(regex("^[0-9A-Za-z_./-]+$", var.name))
    error_message = "An event bus name may contain only letters, digits, periods, hyphens, underscores, and forward slashes."
  }

  validation {
    condition     = var.name == null || length(var.name) <= 256
    error_message = "An event bus name may be at most 256 characters."
  }

  validation {
    condition     = var.name != "default"
    error_message = "The bus named 'default' already exists in every account and cannot be created or destroyed. This module creates custom buses only."
  }
}

variable "description" {
  default     = null
  description = "Description of the event bus. Worth setting — a bus is a bare name in the console and in an audit trail, and the events it carries are not discoverable from that name alone."
}

variable "event_source_name" {
  default     = null
  description = "Name of the partner event source this bus receives events from, such as 'aws.partner/example.com/acct1/repo1'. Setting it makes the bus a partner event bus rather than an ordinary custom one: it carries events a SaaS provider publishes, nothing in this account can publish to it, and AWS requires name to be spelled exactly the same as this value. Leave it null for the ordinary case of an application publishing its own events."

  validation {
    condition     = var.event_source_name == null || startswith(var.event_source_name, "aws.partner/")
    error_message = "A partner event source name always begins with 'aws.partner/'. An ordinary custom bus does not take event_source_name at all — leave it null and set only name."
  }

  validation {
    condition     = var.event_source_name == null || var.name == var.event_source_name
    error_message = "A partner event bus must be named after its event source, so name and event_source_name must hold the same value. Set name explicitly rather than leaving it to the generated fallback."
  }
}

variable "enable_policy" {
  default     = false
  description = "Whether the document in policy is attached to the bus. This is a separate switch because Terraform decides how many resources to create before it knows any value AWS computes, and a policy naming a role or an account reference produced elsewhere in the same configuration is not known that early."

  validation {
    condition     = !var.enable_policy || var.policy != null
    error_message = "enable_policy requires policy to hold the document being attached."
  }

  validation {
    condition     = var.policy == null || var.enable_policy
    error_message = "policy is set but enable_policy is false, so nothing would be attached. Set enable_policy = true."
  }
}

variable "policy" {
  default     = null
  description = "Resource policy document (JSON) for the bus, naming the accounts, organizations, or principals permitted to publish events to it and to create rules on it. Requires enable_policy. If left unset the bus accepts events only from principals in its own account that hold events:PutEvents in their own IAM policy, which is all a single-account deployment needs. This replaces the whole policy rather than adding one statement to it."
}

variable "kms_key_identifier" {
  default     = null
  description = "Customer managed KMS key encrypting events held on the bus and in any archive of it, given as a key ID, key ARN, or alias. AWS rejects an AWS managed key here, and the key policy must grant events.amazonaws.com kms:DescribeKey, kms:GenerateDataKey, and kms:Decrypt — a key from terraform-aws-kms-key is created with AWS's default policy, which grants no service principal anything, so encryption fails at apply until that policy is extended. See this module's README. If null, AWS encrypts events with a key it owns."

  validation {
    condition     = var.kms_key_identifier == null || !startswith(var.kms_key_identifier, "alias/aws/")
    error_message = "An event bus requires a customer managed key. An AWS managed key such as 'alias/aws/events' is rejected by EventBridge, and its policy cannot be edited to grant the access EventBridge needs."
  }
}

variable "enable_dead_letter_queue" {
  default     = false
  description = "Whether events the bus cannot deliver are sent to the queue named by dead_letter_queue_arn. This is a separate switch from that ARN because the ARN is normally another module's output, which Terraform does not know while it is building the plan, while a boolean the caller writes literally always is."

  validation {
    condition     = !var.enable_dead_letter_queue || var.dead_letter_queue_arn != null
    error_message = "enable_dead_letter_queue requires dead_letter_queue_arn, the ARN of the queue that receives the undelivered events."
  }

  validation {
    condition     = var.enable_dead_letter_queue || var.dead_letter_queue_arn == null
    error_message = "dead_letter_queue_arn has no effect unless enable_dead_letter_queue is true. Set the boolean or drop the ARN."
  }
}

variable "dead_letter_queue_arn" {
  default     = null
  description = "ARN of the SQS queue receiving events this bus could not deliver to any target, for a target that defines no dead-letter queue of its own. Takes terraform-aws-sqs-queue's arn output. The queue's own access policy must permit events.amazonaws.com to call sqs:SendMessage on it, which this module does not create. Takes effect only when enable_dead_letter_queue is true."
}

variable "log_config" {
  default     = null
  description = "Logging detail the bus records about the events passing through it. level is 'OFF', 'ERROR', 'INFO', or 'TRACE', where 'ERROR' records only failed invocations and 'TRACE' records every step of every one. include_detail of 'FULL' adds each event's own payload to those records, which puts whatever the event carries into a log; 'NONE', the default, records only metadata. Setting this chooses what is recorded, not where it goes — the log destination is configured separately with CloudWatch Logs delivery resources this module does not create, and until one exists nothing is written anywhere."

  type = object({
    level          = string
    include_detail = optional(string)
  })

  validation {
    condition     = var.log_config == null || contains(["OFF", "ERROR", "INFO", "TRACE"], var.log_config.level)
    error_message = "log_config.level must be one of 'OFF', 'ERROR', 'INFO', or 'TRACE', spelled exactly as shown."
  }

  validation {
    condition     = var.log_config == null || var.log_config.include_detail == null || contains(["NONE", "FULL"], var.log_config.include_detail)
    error_message = "log_config.include_detail must be 'NONE' or 'FULL', spelled exactly as shown."
  }
}

variable "tags" {
  default     = null
  description = "A map of tags to assign to the event bus."
}
