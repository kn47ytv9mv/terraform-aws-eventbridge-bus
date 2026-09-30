# terraform-aws-eventbridge-bus

Terraform module for a custom EventBridge event bus — the router an
application publishes its own domain events to, rather than only
reacting to the events AWS publishes about itself.

## Cost

EventBridge bills per million custom events published to a bus. Events
that AWS's own services publish about themselves arrive on the account's
default bus and carry no charge at all, so the cost of this module is
entirely the cost of an application choosing to publish its own events.
Delivery to another account or another region is billed as an additional
published event. An archive of a bus bills for the volume of events it
holds, and replaying an archive is billed separately from the original
publication. The bus itself carries no standing charge, so one with no
publisher costs nothing. See AWS's
[EventBridge pricing](https://aws.amazon.com/eventbridge/pricing/) page
for current rates.

## Design

A bus is only a router: it accepts events and matches them against
rules, and it does nothing on its own. The rules that match events on
this bus and the targets they invoke belong to
[`terraform-aws-eventbridge-rule`](https://github.com/kn47ytv9mv/terraform-aws-eventbridge-rule),
which identifies the bus it attaches to
by name through its `event_bus_name` input. That is what this module's `name` output is for,
and it is also why a deliberate name is worth more here than a generated
one — the name is the contract every publisher and every rule is written
against.

### The default bus is not this module

Every account already has an event bus named `default`. It cannot be
created, renamed, or destroyed, it is where every AWS service publishes
its own events, and it is the only bus on which a scheduled rule works.
This module creates custom buses and rejects the name `default` outright,
so a configuration reaching for it in order to configure the account's
existing bus is in the wrong place: point a rule at the default bus by
name instead, and create nothing.

A custom bus is worth creating when the events are the application's
own. Publishing to a separate bus keeps an application's events out of
the same match space as every AWS service event in the account, allows
the bus itself to be encrypted and to carry its own access policy, and
makes one team's event traffic something another team can be granted or
denied at the bus boundary.

### What this module bundles, and what it leaves out

`aws_cloudwatch_event_bus_policy` is bundled here, driven by the `policy`
variable. AWS permits at most one such policy per bus, it replaces the
whole document rather than accumulating statements, and the provider's
schema gives it no ARN and no identifier of its own — its `id` is simply
the bus name this module already outputs. Nothing outside this module can
therefore reference the policy specifically, and there is no second
instance to distinguish, so both conditions of the bundle-versus-split
test fall on the bundle side. This is the same shape as the companion
resources bundled into
[`terraform-aws-s3`](https://github.com/kn47ytv9mv/terraform-aws-s3) and
into
[`terraform-aws-ecr-repository`](https://github.com/kn47ytv9mv/terraform-aws-ecr-repository).

The provider also offers `aws_cloudwatch_event_permission`, which writes
a single statement identified by its own `statement_id`. That is a
heterogeneous set of instances a caller would want to address one at a
time, which is the split side of the same test, and it is not bundled
here. Managing individual statements with it while also setting `policy`
would have the two fight over the same document, so choose one.

Archives are deliberately not created here. `aws_cloudwatch_event_archive`
carries its own ARN, which is the identifier the EventBridge replay API
takes as its event source, so an outside consumer genuinely needs to
reference one archive specifically. A bus may also hold several archives,
each with its own event pattern and its own retention period, which makes
them structurally heterogeneous rather than a homogeneous list. Either
condition alone puts archives on the split side; both do. An archive also
outlives the events it holds and is usually retained on a different
schedule from the bus, so bundling it would tie a retention decision to
the lifetime of the router.

### Encryption with a customer managed key

`kms_key_identifier` requires a customer managed key. EventBridge rejects
an AWS managed key such as `alias/aws/events`, and this module rejects
that alias form at plan time rather than letting the apply discover it.

Supplying a key is not sufficient on its own. EventBridge encrypts and
decrypts under the key as a service principal, so the key policy must
grant `events.amazonaws.com` `kms:DescribeKey`, `kms:GenerateDataKey`,
and `kms:Decrypt`.
[`terraform-aws-kms-key`](https://github.com/kn47ytv9mv/terraform-aws-kms-key)
creates a key with AWS's own default key policy, which grants the account
root full access and grants no service principal anything — so a bus
handed such a key without an extended `policy` fails at apply, not at
plan. This is the same trap CloudWatch Logs sets with a customer managed
key, and it is described the same way in
[`terraform-aws-architecture-serverless`](https://github.com/kn47ytv9mv/terraform-aws-architecture-serverless);
the principal is the only part that differs.

The grant belongs in the `policy` variable of the `key` module and looks
like this:

```json
{
  "Sid": "Allow_EventBridge_for_CMK",
  "Effect": "Allow",
  "Principal": { "Service": ["events.amazonaws.com"] },
  "Action": ["kms:DescribeKey", "kms:GenerateDataKey", "kms:Decrypt"],
  "Resource": "*"
}
```

The key must be symmetric and must live in the same region as the bus,
and scheduling it for deletion makes every event held on the bus and in
its archives permanently unreadable.

### The dead-letter queue

`dead_letter_queue_arn` names an SQS queue that receives events this bus
could not deliver to any target. It is the bus-wide fallback: a rule
target that defines its own dead-letter queue uses that one instead, and
without either, an undeliverable event is discarded after EventBridge
exhausts its retries, with nothing left to investigate.
[`terraform-aws-sqs-queue`](https://github.com/kn47ytv9mv/terraform-aws-sqs-queue)
produces the ARN, and a long `message_retention_seconds` on that queue is
what keeps a failed event around long enough for somebody to look at it.

EventBridge writes to that queue as a service principal, so the queue's
own access policy must permit `events.amazonaws.com` to call
`sqs:SendMessage` on it. This module does not create that policy — the
queue owns it, through `terraform-aws-sqs-queue`'s `policy` variable —
and without it every undeliverable event is lost exactly as if no
dead-letter queue had been configured at all.

`enable_dead_letter_queue` is a separate boolean from the ARN rather than
the module inferring the feature from a non-null value. The ARN is
normally another module's output, and Terraform decides how many resources
and blocks to create before it knows any value AWS computes, so behavior
gated on whether that ARN is null fails on exactly the composition the
input exists to support. A boolean the caller writes literally is always
known that early. Setting one without the other is rejected in both
directions rather than silently ignored. `enable_policy` and `policy`
work the same way and for the same reason.

### Partner event buses

Setting `event_source_name` makes the bus a partner event bus, which is a
different kind of thing from an ordinary custom one. It receives events a
SaaS provider publishes into the account through a partner event source,
nothing in the account can publish to it, and AWS requires the bus to be
named exactly after the source, so `name` and `event_source_name` must
carry the same value. A partner event source name always begins with
`aws.partner/`.

Both rules are validated here, because a caller who sets
`event_source_name` on what was meant to be an ordinary bus otherwise
gets a failure from the EventBridge API that names neither mistake
clearly. Leave `event_source_name` null for the ordinary case of an
application publishing its own events, which is what this module is
mostly for.

### Logging

`log_config` chooses what the bus records about the events passing
through it: `level` of `ERROR` records only failed invocations, `INFO`
adds successful ones, and `TRACE` records every step of every
invocation. `include_detail` of `FULL` adds each event's own payload to
those records, which puts whatever the event carries — including
anything sensitive in it — into a log that is retained and readable
separately from the bus.

Setting `log_config` chooses what is recorded and not where it goes. The
destination is configured separately through the CloudWatch Logs
delivery resources, which this module does not create, and until a
delivery exists nothing is written anywhere no matter what level is set.

## Usage

```hcl
module "order_events" {
  source = "kn47ytv9mv/eventbridge-bus/aws"

  name        = "order-events"
  description = "Domain events published by the ordering service"
}
```

Or directly from this repository, with a dead-letter queue for events
that reach no target, error-level logging, and a policy letting a second
account publish to the bus:

```hcl
module "order_events_dlq" {
  source = "github.com/kn47ytv9mv/terraform-aws-sqs-queue"

  name                      = "order-events-dlq"
  message_retention_seconds = 1209600
}

module "order_events" {
  source = "github.com/kn47ytv9mv/terraform-aws-eventbridge-bus"

  name        = "order-events"
  description = "Domain events published by the ordering service"

  enable_dead_letter_queue = true
  dead_letter_queue_arn    = module.order_events_dlq.arn

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
```

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.9 |
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |
| random | ~> 3.9 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| name | Name of the event bus, which is how every publisher and every rule identifies it. Cannot be `'default'`. If null, a unique name is generated. | `null` | no |
| description | Description of the event bus. Worth setting — the events a bus carries are not discoverable from its name alone. | `null` | no |
| event_source_name | Name of the partner event source this bus receives events from, which makes it a partner event bus and must equal `name` — see Design. | `null` | no |
| enable_policy | Whether the document in `policy` is attached to the bus. A separate switch from the document — see Design. | `false` | no |
| policy | Resource policy document (JSON) naming the accounts, organizations, or principals permitted to publish to the bus and to create rules on it. Requires `enable_policy`. | `null` | no |
| kms_key_identifier | Customer managed KMS key encrypting events on the bus. An AWS managed key is rejected, and the key policy must grant `events.amazonaws.com` — see Design. | `null` | no |
| enable_dead_letter_queue | Whether events the bus cannot deliver are sent to `dead_letter_queue_arn`. A separate switch from the ARN — see Design. | `false` | no |
| dead_letter_queue_arn | ARN of the SQS queue receiving events this bus could not deliver to any target. The queue's own policy must permit `events.amazonaws.com` to send. | `null` | no |
| log_config | What the bus records about the events passing through it: `level` of `'OFF'`, `'ERROR'`, `'INFO'`, or `'TRACE'`, and `include_detail` of `'NONE'` or `'FULL'`. The log destination is configured separately — see Design. | `null` | no |
| tags | A map of tags to assign to the event bus. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| id | The ID of the event bus, which is its name. |
| arn | The ARN of the event bus. A cross-account policy or an IAM policy granting `events:PutEvents` scopes itself to this ARN. |
| name | The name of the event bus. Feed this into `terraform-aws-eventbridge-rule`'s `event_bus_name`, and into the `PutEvents` call a publisher makes. |

## License

MIT — see [LICENSE.md](LICENSE.md).
