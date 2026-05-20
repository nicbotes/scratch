# Reference: Athena Schema — Full Data Dictionary

Generated from `information_schema.columns` on 2026-05-19.
Refresh with: `bash .agents/tools/athena-query.sh "SELECT table_name, column_name, data_type, ordinal_position FROM information_schema.columns WHERE table_schema = '$ROOT_ORG_ID' ORDER BY table_name, ordinal_position"`

## Global conventions

| Convention | Rule |
|---|---|
| `environment` filter | Required on every query against tables that have the column (rules.md #1). **Not all tables have it — see per-table note.** |
| Money columns (`bigint`) | Always cents. Divide by 100 at display time only (rules.md #2). |
| Timestamps (`timestamp(3)`) | ISO 8601 UTC strings. Wrap with `from_iso8601_timestamp()` (rules.md #3). |
| JSON columns (`varchar`) | Use `JSON_EXTRACT_SCALAR()` / `JSON_EXTRACT()` (rules.md #5). Common names: `module`, `charges`, `data`, `app_data`, `module_data`, `input_data`, `config`, `settings`, `permissions`, `beneficiaries`, `covered_items`, `block_states`. |
| PII tables | `policyholders`, `members`, `leads`, `payment_methods` (account numbers), `calls` (phone numbers). Handle carefully in exports. |
| **Sensitive column metadata** | `references/pii-columns.json` is the machine-readable source — every `pii`, `restricted`, and `json_sensitive` column tagged. The PII firewall (rules.md #26–#28) reads it inline with `athena-query.sh` execution; see `references/pii-safety.md` for the full safety model. |

## Tables without `environment` column

These are org-level or platform-level tables. Do **not** add a `WHERE environment = ...` filter.

`users`, `organizations`, `organization_roles`, `organization_groups`, `organization_group_users`, `organization_group_restrictions`, `organization_user_roles`, `organization_notification_templates`, `notification_templates`, `product_modules`, `product_module_definitions`, `user_audit_logs`, `attachments`, `embed_session_impressions`, `organization_product_modules`, `current_version`

---

## Core insurance

### `policies`
| Column | Type | Notes |
|---|---|---|
| `policy_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `policy_number` | varchar | human-readable reference |
| `status` | varchar | `active`, `lapsed`, `cancelled`, `expired`, `not_taken_up` |
| `scheme_type` | varchar | |
| `package_name` | varchar | |
| `sum_assured` | bigint | **cents** |
| `monthly_premium` | bigint | **cents** |
| `billing_amount` | bigint | **cents** |
| `base_premium` | bigint | **cents** |
| `billing_frequency` | varchar | |
| `billing_day` | integer | |
| `billing_month` | integer | |
| `start_date` | timestamp(3) | |
| `end_date` | timestamp(3) | |
| `cancelled_at` | timestamp(3) | |
| `status_updated_at` | timestamp(3) | |
| `module` | varchar | **JSON** — product-specific policy data |
| `app_data` | varchar | **JSON** |
| `charges` | varchar | **JSON array** |
| `covered_items` | varchar | **JSON** |
| `covered_people` | varchar | **JSON** |
| `beneficiaries` | varchar | **JSON** |
| `application_id` | varchar | FK → `applications` |
| `policyholder_id` | varchar | FK → `policyholders` |
| `payment_method_id` | varchar | FK → `payment_methods` |
| `product_module_id` | varchar | FK → `product_modules` |
| `product_module_definition_id` | varchar | FK → `product_module_definitions` |
| `debicheck_mandate_id` | varchar | FK → `debicheck_mandates` |
| `claim_ids` | varchar | **JSON array** |
| `complaint_ids` | varchar | **JSON array** |
| `currency` | varchar | |
| `flushed` | boolean | soft-delete flag |
| `external_reference` | varchar | partner/system ref |
| `data_import_id` | varchar | |
| `reason_cancelled` | varchar | |
| `cancellation_type` | varchar | |
| `cancellation_requestor` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |

### `policyholders`
PII-heavy. Use carefully in queries leaving the framework.

| Column | Type | Notes |
|---|---|---|
| `policyholder_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `type` | varchar | `individual` or `company` |
| `first_name`, `last_name`, `middle_name`, `initials` | varchar | **PII** |
| `title` | varchar | |
| `gender` | varchar | |
| `date_of_birth` | timestamp(3) | **PII** |
| `identification_number` | varchar | **PII** — national ID / passport |
| `identification_type` | varchar | |
| `identification_country` | varchar | |
| `identification_expiration_date` | timestamp(3) | |
| `email` | varchar | **PII** |
| `cellphone` | varchar | **PII** |
| `phone_other` | varchar | |
| `company_name` | varchar | |
| `registration_number` | varchar | |
| `address_line_1`, `address_line_2`, `suburb`, `city`, `country`, `area_code` | varchar | **PII** |
| `google_place_id` | varchar | **PII** |
| `geo_coordinates_latitude`, `geo_coordinates_longitude` | varchar | |
| `app_data` | varchar | **JSON** |
| `policy_ids` | varchar | **JSON array** |
| `attachments` | varchar | **JSON** |
| `notes` | varchar | |
| `flushed` | boolean | |
| `external_reference` | varchar | |
| `data_import_id` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |
| `archived_by` | varchar | |

### `applications`
| Column | Type | Notes |
|---|---|---|
| `application_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `status` | varchar | |
| `type` | varchar | |
| `policyholder_id` | varchar | FK |
| `policy_id` | varchar | FK (set on conversion) |
| `quote_package_id` | varchar | FK |
| `payment_method_id` | varchar | FK |
| `product_module_definition_id` | varchar | FK |
| `package_name` | varchar | |
| `sum_assured` | bigint | **cents** |
| `base_premium` | bigint | **cents** |
| `monthly_premium` | bigint | **cents** |
| `billing_frequency` | varchar | |
| `billing_day` | integer | |
| `billing_month` | integer | |
| `module` | varchar | **JSON** |
| `input_data` | varchar | **JSON** |
| `beneficiaries` | varchar | **JSON** |
| `attachments` | varchar | **JSON** |
| `notes` | varchar | |
| `currency` | varchar | |
| `flushed` | boolean | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |
| `archived_at` | timestamp(3) | |
| `archived_by` | varchar | |

### `quote_packages`
| Column | Type | Notes |
|---|---|---|
| `quote_package_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `package_name` | varchar | |
| `sum_assured` | bigint | **cents** |
| `base_premium` | bigint | **cents** |
| `suggested_premium` | bigint | **cents** |
| `monthly_premium` | bigint | **cents** |
| `billing_frequency` | varchar | |
| `module` | varchar | **JSON** |
| `input_data` | varchar | **JSON** |
| `currency` | varchar | |
| `product_module_definition_id` | varchar | FK |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |

### `alteration_packages`
| Column | Type | Notes |
|---|---|---|
| `alteration_package_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `policy_id` | varchar | FK |
| `product_module_definition_id` | varchar | FK |
| `status` | varchar | |
| `sum_assured` | bigint | **cents** |
| `monthly_premium` | bigint | **cents** |
| `currency` | varchar | |
| `module` | varchar | **JSON** |
| `input_data` | varchar | **JSON** |
| `change_description` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |

### `members`
| Column | Type | Notes |
|---|---|---|
| `member_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `policy_id` | varchar | FK |
| `status` | varchar | |
| `external_id` | varchar | |
| `start_date`, `end_date` | timestamp(3) | |
| `first_name`, `last_name` | varchar | **PII** |
| `identification_number` | varchar | **PII** |
| `identification_type`, `identification_country` | varchar | |
| `date_of_birth` | varchar | **PII** |
| `gender` | varchar | |
| `email`, `cellphone` | varchar | **PII** |
| `module` | varchar | **JSON** |
| `app_data` | varchar | **JSON** |
| `beneficiaries` | varchar | **JSON** |
| `certificate_versions` | varchar | **JSON** |
| `claim_ids`, `complaint_ids` | varchar | **JSON arrays** |
| `flushed` | boolean | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |

### `annuity_requests`
| Column | Type | Notes |
|---|---|---|
| `annuity_request_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `policy_id` | varchar | FK |
| `claim_id` | varchar | FK |
| `status` | varchar | |
| `amount` | bigint | **cents** |
| `frequency` | varchar | |
| `duration` | varchar | |
| `flushed` | boolean | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `archived_at` | timestamp(3) | |
| `archived_by` | varchar | |

---

## Financial

### `payments`
| Column | Type | Notes |
|---|---|---|
| `payment_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `policy_id` | varchar | FK |
| `payment_method_id` | varchar | FK |
| `payment_batch_id` | varchar | FK |
| `status` | varchar | `successful`, `failed`, `pending`, `reversed` |
| `amount` | bigint | **cents** |
| `currency` | varchar | |
| `payment_date` | timestamp(3) | |
| `billing_date` | timestamp(3) | |
| `action_date` | timestamp(3) | |
| `payment_type` | varchar | |
| `premium_type` | varchar | |
| `collection_type` | varchar | |
| `source` | varchar | |
| `external_payment` | boolean | |
| `failure_reason` | varchar | |
| `failure_code` | varchar | |
| `retry_of` | varchar | FK to prior payment |
| `reversal_of_payment_id` | varchar | |
| `reversed_at` | timestamp(3) | |
| `charges` | varchar | **JSON** |
| `app_data` | varchar | **JSON** |
| `covered_item_ids` | varchar | **JSON** |
| `external_ref`, `customer_ref` | varchar | |
| `data_import_id` | varchar | |
| `submitted_at` | timestamp(3) | |
| `submitted_by` | varchar | |
| `finalized_at` | timestamp(3) | |
| `finalized_by` | varchar | |
| `reviewed_at` | timestamp(3) | |
| `reviewed_by` | varchar | |
| `tracking_days` | integer | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |

### `payment_methods`
| Column | Type | Notes |
|---|---|---|
| `payment_method_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `type` | varchar | `debit_order`, `card`, etc. |
| `policyholder_id` | varchar | FK |
| `payment_method_config_id` | varchar | FK |
| `account_holder` | varchar | **PII** |
| `first_name`, `last_name` | varchar | **PII** |
| `bank`, `branch_code` | varchar | |
| `account_number` | varchar | **PII** |
| `account_type` | varchar | |
| `account_holder_identification` | varchar | **PII** |
| `banv_status` | varchar | bank account verification status |
| `banv_submitted_at` | timestamp(3) | |
| `banv_auto_verified` | boolean | |
| `bin`, `holder`, `card_brand`, `expiry_year`, `expiry_month`, `last_4_digits` | varchar | card details |
| `key`, `registration_id`, `external_reference` | varchar | |
| `verification_batch_id` | varchar | FK |
| `data_import_id` | varchar | |
| `blocked_reason` | varchar | |
| `dismissed_at` | timestamp(3) | |
| `dismissed_by` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |

### `payment_batches`
| Column | Type | Notes |
|---|---|---|
| `payment_batch_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `status` | varchar | |
| `payment_type` | varchar | |
| `payment_method_type` | varchar | |
| `payment_method_provider_id` | varchar | FK |
| `payment_method_config_id` | varchar | FK |
| `action_date` | timestamp(3) | |
| `process_date` | timestamp(3) | |
| `submitted_at` | timestamp(3) | |
| `submitted_by` | varchar | |
| `provider_fee` | bigint | **cents** |
| `tracking_days` | integer | |
| `failure_reason` | varchar | |
| `external_reference` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |
| `updated_by` | varchar | |
| `archived_at` | timestamp(3) | |
| `archived_by` | varchar | |

### `payment_coupons`
| Column | Type | Notes |
|---|---|---|
| `payment_coupon_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `policy_id` | varchar | FK |
| `status` | varchar | |
| `type` | varchar | |
| `amount` | bigint | **cents** |
| `payment_date` | timestamp(3) | |
| `billing_date` | timestamp(3) | |
| `redeemable_from`, `redeemable_to` | varchar | |
| `reason` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |
| `updated_by` | varchar | |

### `policy_ledger`
| Column | Type | Notes |
|---|---|---|
| `entry_id` | varchar | PK |
| `policy_id` | varchar | FK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `payment_id` | varchar | FK |
| `payment_coupon_id` | varchar | FK |
| `amount` | bigint | **cents** |
| `currency` | varchar | |
| `description` | varchar | |
| `data_import_id` | varchar | |
| `created_at` | timestamp(3) | |

### `payout_requests`
| Column | Type | Notes |
|---|---|---|
| `id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `status` | varchar | |
| `type` | varchar | |
| `amount` | bigint | **cents** |
| `description` | varchar | |
| `payee` | varchar | **JSON** |
| `linked_entities` | varchar | **JSON** |
| `action_date` | timestamp(3) | |
| `finalised_at` | timestamp(3) | |
| `finalised_by` | varchar | |
| `rejection_reason` | varchar | |
| `proof_of_payment_id` | varchar | |
| `flushed` | boolean | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `archived_at` | timestamp(3) | |
| `archived_by` | varchar | |

### `debicheck_mandates`
| Column | Type | Notes |
|---|---|---|
| `debicheck_mandate_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `policy_id` | varchar | FK |
| `payment_method_id` | varchar | FK |
| `debicheck_mandate_batch_id` | varchar | FK |
| `status` | varchar | |
| `mandate_reference`, `external_reference`, `contract_reference`, `authorization_code` | varchar | |
| `amount` | integer | **cents** |
| `max_collection_amount` | integer | **cents** |
| `first_collection_amount` | integer | **cents** |
| `frequency` | varchar | |
| `start_date`, `first_collection_date` | timestamp(3) | |
| `collection_day` | varchar | |
| `debtor_name`, `debtor_account_number`, `debtor_branch_code`, `debtor_account_type` | varchar | **PII** |
| `creditor_name`, `creditor_account_number`, `creditor_scheme_id` | varchar | |
| `failure_reasons`, `failure_codes` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |
| `updated_by` | varchar | |
| `authorized_at`, `submitted_at`, `rejected_at`, `cancelled_at` | timestamp(3) | |

### `verification_batches`
| Column | Type | Notes |
|---|---|---|
| `verification_batch_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `status` | varchar | |
| `payment_method_type` | varchar | |
| `provider_fee` | bigint | **cents** |
| `retry_count` | bigint | |
| `failure_reason` | varchar | |
| `submitted_at` | timestamp(3) | |
| `submitted_by` | varchar | |
| `created_at` | timestamp(3) | |
| `archived_at` | timestamp(3) | |
| `archived_by` | varchar | |

### `payment_method_configs`
Configuration per payment method type per org.

| Column | Type | Notes |
|---|---|---|
| `payment_method_config_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `payment_method_type` | varchar | |
| `provider_id` | varchar | FK |
| `payment_method_config_key` | varchar | |
| `is_default` | boolean | |
| `product_module_id` | varchar | FK |
| `config` | varchar | **JSON** |
| `billing_strategy_settings` | varchar | **JSON** |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |
| `updated_by` | varchar | |

### `external_payment_methods`
| Column | Type | Notes |
|---|---|---|
| `payment_method_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `key` | varchar | |
| `outbound_channels` | varchar | **JSON** |
| `config` | varchar | **JSON** |
| `external_reference` | varchar | |
| `data_import_id` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |

---

## Claims & compliance

### `claims`
| Column | Type | Notes |
|---|---|---|
| `claim_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `policy_id` | varchar | FK |
| `policyholder_id` | varchar | FK |
| `member_id` | varchar | FK |
| `claim_number` | varchar | human-readable |
| `status` | varchar | |
| `approval_status` | varchar | |
| `incident_type` | varchar | |
| `incident_cause` | varchar | |
| `incident_date` | timestamp(3) | |
| `requested_amount` | bigint | **cents** |
| `granted_amount` | bigint | **cents** |
| `rejection_reason` | varchar | |
| `claimant` | varchar | **JSON** |
| `module_data` | varchar | **JSON** |
| `app_data` | varchar | **JSON** |
| `block_states` | varchar | **JSON** |
| `checklist_items` | varchar | **JSON** |
| `covered_item_id` | varchar | |
| `external_reference` | varchar | |
| `data_import_id` | varchar | |
| `notes` | varchar | |
| `attachments` | varchar | **JSON** |
| `currency` | varchar | |
| `flushed` | boolean | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |

### `complaints`
| Column | Type | Notes |
|---|---|---|
| `complaint_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `policy_id` | varchar | FK |
| `policyholder_id` | varchar | FK |
| `member_id` | varchar | FK |
| `complaint_number` | varchar | |
| `status` | varchar | |
| `complainant` | varchar | **JSON** |
| `app_data` | varchar | **JSON** |
| `notes` | varchar | |
| `attachments` | varchar | **JSON** |
| `flushed` | boolean | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |

### `sanctions_matches`
| Column | Type | Notes |
|---|---|---|
| `sanctions_match_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `policyholder_id` | varchar | FK |
| `policy_id` | varchar | FK |
| `beneficiary_id` | varchar | |
| `source_name` | varchar | |
| `entity` | varchar | **JSON** |
| `original_record` | varchar | **JSON** |
| `archived_reason` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `archived_at` | timestamp(3) | |
| `archived_by` | varchar | |

### `sanctions_screening_requests`
| Column | Type | Notes |
|---|---|---|
| `sanctions_screening_request_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `request_type` | varchar | |
| `matched` | boolean | |
| `matches` | varchar | **JSON** |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |

### `sanctions_screenings`
No `environment` column.

| Column | Type | Notes |
|---|---|---|
| `sanctions_screening_id` | varchar | PK |
| `organization_id` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `completed_at` | timestamp(3) | |

---

## Platform / product

### `product_modules`
No `environment` column.

| Column | Type | Notes |
|---|---|---|
| `product_module_id` | varchar | PK |
| `key` | varchar | short code |
| `name` | varchar | |
| `restricted` | boolean | |
| `owned_by_organization_id` | varchar | |
| `draft_id`, `live_id`, `review_id` | varchar | FK → `product_module_definitions` |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `archived_at` | timestamp(3) | |

### `product_module_definitions`
No `environment` column. One row per published version.

| Column | Type | Notes |
|---|---|---|
| `product_module_definition_id` | varchar | PK |
| `product_module_id` | varchar | FK |
| `version_major`, `version_minor` | integer | |
| `settings` | varchar | **JSON** |
| `published_at` | timestamp(3) | null if draft |
| `published_by` | varchar | |
| `code_id` | varchar | |
| `quote_schema_id`, `application_schema_id`, `claim_schema_id`, `claim_blocks_schema_id` | varchar | |
| `terms_file_id`, `welcome_letter_id`, `schedule_id`, `member_certificate_id`, `policy_anniversary_file_id` | varchar | |
| `product_module_embed_config` | varchar | **JSON** |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |

### `product_module_code_runs`
| Column | Type | Notes |
|---|---|---|
| `product_module_code_run_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `product_module_id` | varchar | FK |
| `product_module_definition_id` | varchar | FK |
| `policy_id` | varchar | FK |
| `function_name` | varchar | e.g. `getQuote`, `getPolicy` |
| `status` | varchar | |
| `triggered_by` | varchar | |
| `created_at` | timestamp(3) | |
| `completed_at` | timestamp(3) | |

### `organization_product_modules`
No `environment` column.

| Column | Type | Notes |
|---|---|---|
| `product_module_id` | varchar | FK |
| `organization_id` | varchar | |
| `sandbox` | boolean | |
| `live` | boolean | |

---

## Organisation & users

### `organizations`
No `environment` column.

| Column | Type | Notes |
|---|---|---|
| `organization_id` | varchar | PK = `$ROOT_ORG_ID` |
| `name` | varchar | used by `whoami.sh` |
| `owner_id` | varchar | |
| `description`, `website` | varchar | |
| `contact_number` | varchar | |
| `valid_user_domains` | varchar | **JSON** |
| `valid_outbound_email_domains` | varchar | **JSON** |
| `whitelisted_ip_cidr_blocks` | varchar | **JSON** |
| `fica_enabled`, `qa_enabled`, `banv_disabled`, `reports_enabled` | boolean | feature flags |
| `is_legacy_client_app` | boolean | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `reviewed_at` | timestamp(3) | |

### `users`
No `environment` column. Dashboard/API users — not policyholders.

| Column | Type | Notes |
|---|---|---|
| `id` | varchar | PK |
| `email` | varchar | **PII** |
| `first_name`, `last_name` | varchar | **PII** |
| `cellphone` | varchar | **PII** |
| `date_of_birth` | varchar | |
| `company_name` | varchar | |
| `state` | varchar | `activated`, etc. |
| `locked` | boolean | account lock |
| `is_root_admin` | boolean | platform-wide admin |
| `insurance_access` | varchar | |
| `login_attempts` | integer | failed attempts counter |
| `profile_picture_url` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `last_logged_in` | varchar | timestamp with tz stored as varchar; cast before arithmetic |
| `password_last_changed` | varchar | timestamp with tz stored as varchar; cast before arithmetic; NULL for ~42/51 users (field newly added, backfill incomplete) |

> No MFA columns — 2FA method and enforcement policy are not available in the data adapter. Source from Root Dashboard → Team or Root API `/v1/users`. `password_last_changed` and `last_logged_in` are now present but stored as varchar.

**Aliases / lookup helper.** If you're hunting for one of these and grep fails:

| You searched for | Actual column / source |
|---|---|
| `password_changed_at` | `password_last_changed` (varchar; cast before arithmetic) |
| `last_login_at`, `last_login` | `last_logged_in` (varchar) |
| `mfa_enabled`, `mfa_method`, `2fa_*` | Not in data adapter. Root API `/v1/users` |
| `password_strength`, `password_age_days` | Derive client-side from `password_last_changed`; raw strength signals not stored |
| `failed_login_count` | `login_attempts` (integer) |

### `user_audit_logs`
No `environment` column. Org-membership events only — not auth/security events.

| Column | Type | Notes |
|---|---|---|
| `user_audit_log_id` | varchar | PK |
| `user_id` | varchar | FK → `users` |
| `organization_id` | varchar | |
| `type` | varchar | `added_to_organization`, `removed_from_organization`, `organization_role_changed`, `organization_group_changed`, `user_group_changed` |
| `data` | varchar | **JSON** |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |

### `organization_roles`
No `environment` column.

| Column | Type | Notes |
|---|---|---|
| `organization_role_id` | varchar | PK |
| `organization_id` | varchar | |
| `name`, `description` | varchar | |
| `permissions` | varchar | **JSON** |
| `has_live_access`, `has_sandbox_access` | boolean | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |
| `updated_by` | varchar | |
| `archived_at` | timestamp(3) | |
| `archived_by` | varchar | |

### `organization_user_roles`
No `environment` column. M:M join — user to role within org.

| Column | Type | Notes |
|---|---|---|
| `organization_id` | varchar | |
| `user_id` | varchar | FK |
| `organization_role_id` | varchar | FK |
| `created_at` | timestamp(3) | |
| `archived_at` | timestamp(3) | |

### `organization_groups`
No `environment` column.

| Column | Type | Notes |
|---|---|---|
| `organization_group_id` | varchar | PK |
| `organization_id` | varchar | |
| `name`, `key`, `description` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |
| `updated_by` | varchar | |
| `archived_at` | timestamp(3) | |
| `archived_by` | varchar | |

### `organization_group_users`
No `environment` column.

| Column | Type | Notes |
|---|---|---|
| `organization_group_user_id` | varchar | PK |
| `organization_id` | varchar | |
| `organization_group_id` | varchar | FK |
| `user_id` | varchar | FK |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |
| `updated_by` | varchar | |
| `archived_at` | timestamp(3) | |
| `archived_by` | varchar | |

### `organization_group_restrictions`
No `environment` column.

| Column | Type | Notes |
|---|---|---|
| `organization_group_id` | varchar | FK |
| `domain` | varchar | |
| `enabled` | boolean | |

### `api_keys`
| Column | Type | Notes |
|---|---|---|
| `api_key_id` | varchar | PK |
| `owner_id` | varchar | FK → `users` or `organization` |
| `environment` | varchar | filter required |
| `description` | varchar | |
| `permissions` | varchar | **JSON** |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `revoked_at` | timestamp(3) | |
| `revoked_by` | varchar | |

---

## Notifications & webhooks

### `notifications`
| Column | Type | Notes |
|---|---|---|
| `notification_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `channel` | varchar | `email`, `sms`, etc. |
| `notification_type` | varchar | |
| `custom_event_key` | varchar | |
| `status` | varchar | |
| `provider` | varchar | |
| `linked_entities` | varchar | **JSON** |
| `data` | varchar | **JSON** |
| `receipt` | varchar | **JSON** |
| `status_updates` | varchar | **JSON** |
| `failure_reason` | varchar | |
| `external_reference` | varchar | |
| `sent_at` | timestamp(3) | |
| `failed_at` | timestamp(3) | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |

### `notification_templates`
No `environment` column.

| Column | Type | Notes |
|---|---|---|
| `notification_template_id` | varchar | PK |
| `organization_id` | varchar | |
| `event_type` | varchar | |
| `custom_event_key` | varchar | |
| `product_module` | varchar | |
| `channel` | varchar | |
| `version` | integer | |
| `content` | varchar | template body |
| `config` | varchar | **JSON** |
| `published_at` | timestamp(3) | |
| `published_by` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |

### `organization_notification_templates`
No `environment` column.

| Column | Type | Notes |
|---|---|---|
| `organization_id` | varchar | |
| `event_type` | varchar | |
| `custom_event_key`, `custom_event_name`, `custom_event_type` | varchar | |
| `product_module` | varchar | |
| `channel` | varchar | |
| `draft_id`, `published_id` | varchar | FK → `notification_templates` |
| `enabled` | boolean | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `archived_at` | timestamp(3) | |
| `archived_by` | varchar | |
| `draft_updated_at`, `published_updated_at` | timestamp(3) | |
| `draft_updated_by`, `published_updated_by` | varchar | |

### `webhooks`
| Column | Type | Notes |
|---|---|---|
| `webhook_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `name`, `description` | varchar | |
| `url` | varchar | |
| `subscriptions` | varchar | **JSON** |
| `verification_token` | varchar | sensitive |
| `archived` | boolean | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |

---

## Data & exports

### `scheduled_data_exports`
| Column | Type | Notes |
|---|---|---|
| `scheduled_data_export_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `name` | varchar | |
| `status` | varchar | |
| `frequency` | varchar | |
| `adapter` | varchar | SFTP / S3 / HTTPS |
| `export_type` | varchar | |
| `data_range` | varchar | **JSON** |
| `template_id` | varchar | FK |
| `restricted` | boolean | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |

### `data_export_templates`
No `environment` column.

| Column | Type | Notes |
|---|---|---|
| `template_id` | varchar | PK |
| `organization_id` | varchar | |
| `template_name` | varchar | |
| `data_source` | varchar | |
| `product_module_id` | varchar | FK |
| `fields` | varchar | **JSON** |
| `filter` | varchar | **JSON** |
| `is_active` | boolean | |
| `restricted` | boolean | |
| `description` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |

### `data_imports`
| Column | Type | Notes |
|---|---|---|
| `data_import_id` | varchar | PK |
| `sequence_number` | bigint | |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `product_module_id` | varchar | FK |
| `type`, `description` | varchar | |
| `status` | varchar | |
| `failure_reason` | varchar | |
| `csv_file_id`, `result_file_id`, `error_file_id` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `uploaded_at`, `validated_at`, `instantiated_at`, `rolled_back_at` | timestamp(3) | |
| `uploaded_by`, `validated_by`, `instantiated_by`, `rolled_back_by` | varchar | |

### `data_store_entities`
| Column | Type | Notes |
|---|---|---|
| `data_store_entity_id` | varchar | PK |
| `data_store_id` | varchar | FK |
| `organization_id` | varchar | |
| `data` | varchar | **JSON** |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |
| `updated_by` | varchar | |
| `archived_at` | timestamp(3) | |
| `archived_by` | varchar | |

---

## Embed & sales

### `embed_sessions`
| Column | Type | Notes |
|---|---|---|
| `embed_session_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `product_module_id` | varchar | FK |
| `created_at` | timestamp(3) | |

### `embed_session_impressions`
No `environment` column.

| Column | Type | Notes |
|---|---|---|
| `embed_session_impression_id` | varchar | PK |
| `embed_session_id` | varchar | FK |
| `organization_id` | varchar | |
| `stage` | varchar | funnel stage |
| `user_agent` | varchar | |
| `created_at` | timestamp(3) | |

### `leads`
| Column | Type | Notes |
|---|---|---|
| `lead_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `entity_type` | varchar | |
| `first_name`, `last_name`, `middle_name` | varchar | **PII** |
| `identification_number` | varchar | **PII** |
| `identification_type`, `identification_country`, `identification_expiration_date` | varchar | |
| `date_of_birth`, `gender` | varchar | |
| `email`, `cellphone`, `phone_other` | varchar | **PII** |
| `company_name`, `registration_number` | varchar | |
| `address_line_1`, `address_line_2`, `suburb`, `city`, `country`, `area_code` | varchar | **PII** |
| `app_data` | varchar | **JSON** |
| `leads_batch_upload_id` | varchar | FK |
| `notes` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |
| `updated_by` | varchar | |
| `archived_at` | timestamp(3) | |
| `archived_by` | varchar | |

### `leads_batch_uploads`
| Column | Type | Notes |
|---|---|---|
| `leads_batch_upload_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `status` | varchar | |
| `file_type` | varchar | |
| `file_id`, `error_file_id` | varchar | |
| `file_name`, `error_file_name` | varchar | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `archived_at` | timestamp(3) | |
| `archived_by` | varchar | |

### `sales_insights`
| Column | Type | Notes |
|---|---|---|
| `sales_insight_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `product_module_id` | varchar | FK |
| `from_date`, `to_date` | timestamp(3) | |
| `sales_insight` | varchar | **JSON** |
| `created_at` | timestamp(3) | |
| `updated_at` | timestamp(3) | |

### `calls`
| Column | Type | Notes |
|---|---|---|
| `call_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `claim_id` | varchar | FK |
| `policyholder_id` | varchar | FK |
| `attachment_id` | varchar | FK |
| `direction` | varchar | |
| `from_number`, `to_number` | varchar | **PII** |
| `topic` | varchar | |
| `call_duration`, `call_status` | varchar | |
| `recording_url` | varchar | |
| `flushed` | boolean | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |

### `attachments`
No `environment` column.

| Column | Type | Notes |
|---|---|---|
| `id` | varchar | PK |
| `url` | varchar | |
| `filename` | varchar | |
| `type` | varchar | |
| `resource_id` | varchar | FK (polymorphic) |
| `owner_id` | varchar | |
| `created_at` | timestamp(3) | |

### `fulfillment_requests`
| Column | Type | Notes |
|---|---|---|
| `fulfillment_request_id` | varchar | PK |
| `fulfillment_type_id` | varchar | |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `policy_id` | varchar | FK |
| `claim_id` | varchar | FK |
| `fulfillment_data` | varchar | **JSON** |
| `status` | varchar | |
| `flushed` | boolean | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `finalized_at` | varchar | |
| `finalized_by` | varchar | |

---

## Event-sourcing tables

These tables follow a standard pattern: `(sequence, persistence_key, created_at, version, data, deleted)`. No `organization_id` or `environment` column — they are keyed by `persistence_key` (which encodes the entity id). Query them by joining on the entity id embedded in `persistence_key` or by filtering on `data` JSON.

| Table | Entity |
|---|---|
| `application_events` | `applications` |
| `call_events` | `calls` |
| `claim_events` | `claims` |
| `member_events` | `members` |
| `organization_role_events` | `organization_roles` |
| `policy_events` | `policies` |
| `policyholder_events` | `policyholders` |
| `quote_package_events` | `quote_packages` |
| `scheduled_data_export_events` | `scheduled_data_exports` |

Common columns:

| Column | Type | Notes |
|---|---|---|
| `sequence` | integer | ordering within entity |
| `persistence_key` | varchar | entity identifier |
| `version` | bigint | |
| `data` | varchar | **JSON** — event payload |
| `deleted` | boolean | tombstone flag |
| `created_at` | timestamp(3) | |

---

## System

### `current_version`
Single-row table — snapshot timestamp.

| Column | Type |
|---|---|
| `current_version` | timestamp(3) |

### `idempotency_requests`
| Column | Type | Notes |
|---|---|---|
| `idempotency_request_id` | varchar | PK |
| `organization_id` | varchar | |
| `environment` | varchar | filter required |
| `idempotency_key` | varchar | |
| `status` | varchar | |
| `request`, `response` | varchar | **JSON** |
| `original_request` | boolean | |
| `created_at` | timestamp(3) | |
| `created_by` | varchar | |
| `updated_at` | timestamp(3) | |
| `updated_by` | varchar | |

---

## Views

### `my_limited_claims_view`
Same columns as `claims`. Filtered subset — check with `DESCRIBE my_limited_claims_view` to confirm active filters.

---

→ Refresh this file by re-running the `information_schema.columns` query at the top.
→ For JSONB key discovery on a specific table, use `derive-jsonb-schema`.
→ When you find a column missing or wrong here, call `observe --kind reference-thrash --target .agents/references/schema.md`.
