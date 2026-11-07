-- ============================================================================
-- Finance Tracker (financemuse) — P0 migration
-- File: 20261107210000_financemuse_p0.sql
-- Date: 2026-11-07 | PRD: Finance Tracker PRD v1.0 (§5, §9 ledger, §10 data
--   model, §11.2 budget/forecast example, §14 AC-05/06/07/14)
-- Target: self-hosted Supabase on oracle, Postgres DB `postgres`,
--   schema `financemuse` (created empty beforehand; this file fills it).
--
-- MONEY: integer minor units EVERYWHERE (amount_minor BIGINT). IDR exponent
--   is 0, so minor units = rupiah. Never float for money. Signed
--   amount_minor appears ONLY on journal_lines (double-entry signs);
--   every business amount (transactions, splits, budgets, goals, debts)
--   is amount_minor > 0 (unsigned magnitude).
--
-- LEDGER SIGN CONVENTION (financemuse.post_journal_for_transaction):
--   expense    => account line -amount, category line +amount
--   income     => account line +amount, category line -amount
--   transfer   => source account -amount, destination account +amount
--                (category NULL on both lines; income/expense neutral)
--   adjustment => account line +amount, offset line (account NULL,
--                category NULL) -amount, memo 'adjustment offset'
--   Balances = opening_balance_minor + SUM(posted journal_lines for the
--   account). Only status='posted' transactions are journalled, and only
--   status='posted' journal entries count toward balances.
--
-- ROLLBACK NOTE (do NOT execute unless intentionally tearing down):
--   DROP SCHEMA financemuse CASCADE;
--   removes ALL 34 tables below, all functions/triggers/policies, the
--   v_account_balances view, the seed system categories, and every row of
--   user finance data in this schema. It does NOT touch auth.users,
--   public.*, private.*, or any other schema. There is no partial
--   rollback: the schema is one unit. Back up first:
--   pg_dump -U postgres -d postgres -n financemuse > financemuse.bak.sql
--
-- IDEMPOTENCY: CREATE TABLE/INDEX IF NOT EXISTS, CREATE OR REPLACE
--   FUNCTION, DROP TRIGGER/POLICY IF EXISTS before CREATE, seed via
--   INSERT ... ON CONFLICT DO NOTHING. Safe to re-run.
-- API EXPOSURE: this migration deliberately does NOT change
--   PGRST_DB_SCHEMAS and does NOT add financemuse to PostgREST exposure.
--   Access is via service layer / SQL only until the API decision is made.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS financemuse;

-- --------------------------------------------------------------------------
-- Tables
-- --------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS financemuse.profiles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT NOT NULL,
  username_normalized TEXT NOT NULL UNIQUE,
  display_name TEXT,
  base_currency TEXT NOT NULL DEFAULT 'IDR',
  timezone TEXT NOT NULL DEFAULT 'Asia/Jakarta',
  theme TEXT NOT NULL DEFAULT 'system' CHECK (theme IN ('dark', 'light', 'system')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended')),
  must_change_password BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (username ~ '^[a-z0-9_]{3,24}$'),
  CHECK (username_normalized = lower(username))
);

CREATE TABLE IF NOT EXISTS financemuse.user_roles (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('admin', 'user')),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, role)
);

CREATE TABLE IF NOT EXISTS financemuse.accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('Cash', 'Bank', 'E-wallet', 'Other')),
  currency TEXT NOT NULL DEFAULT 'IDR',
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
  opening_balance_minor BIGINT NOT NULL DEFAULT 0,
  allow_negative BOOLEAN NOT NULL DEFAULT FALSE,
  color TEXT,
  icon TEXT,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE, -- NULL = system template
  type TEXT NOT NULL CHECK (type IN ('income', 'expense')),
  parent_id UUID REFERENCES financemuse.categories(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  color TEXT,
  icon TEXT,
  sort_order INT NOT NULL DEFAULT 0,
  archived BOOLEAN NOT NULL DEFAULT FALSE,
  is_system BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS categories_user_type_name_uidx
  ON financemuse.categories ((COALESCE(user_id::text, '')), type, (lower(name)));

CREATE TABLE IF NOT EXISTS financemuse.transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('expense', 'income', 'transfer', 'adjustment')),
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'pending', 'posted', 'voided')),
  account_id UUID NOT NULL REFERENCES financemuse.accounts(id),
  destination_account_id UUID REFERENCES financemuse.accounts(id),
  effective_at TIMESTAMPTZ NOT NULL,
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  currency TEXT NOT NULL DEFAULT 'IDR',
  category_id UUID REFERENCES financemuse.categories(id),
  merchant TEXT,
  description TEXT,
  notes TEXT,
  source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'agent', 'import', 'recurring', 'template')),
  reversal_of UUID REFERENCES financemuse.transactions(id),
  row_version INT NOT NULL DEFAULT 1,
  idempotency_key TEXT,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (type <> 'transfer' OR (destination_account_id IS NOT NULL AND destination_account_id <> account_id AND category_id IS NULL)),
  CHECK (type = 'transfer' OR (destination_account_id IS NULL AND category_id IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS transactions_user_idem_uidx
  ON financemuse.transactions (user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS financemuse.transaction_splits (
  transaction_id UUID NOT NULL REFERENCES financemuse.transactions(id) ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES financemuse.categories(id),
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (transaction_id, category_id)
);

CREATE TABLE IF NOT EXISTS financemuse.journal_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  transaction_id UUID REFERENCES financemuse.transactions(id),
  posted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  status TEXT NOT NULL DEFAULT 'posted' CHECK (status IN ('posted', 'reversed', 'voided')),
  reversal_of UUID REFERENCES financemuse.journal_entries(id),
  currency TEXT NOT NULL DEFAULT 'IDR',
  memo TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS journal_entries_tx_uidx
  ON financemuse.journal_entries (transaction_id) WHERE transaction_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS financemuse.journal_lines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id UUID NOT NULL REFERENCES financemuse.journal_entries(id) ON DELETE CASCADE,
  account_id UUID REFERENCES financemuse.accounts(id),
  category_id UUID REFERENCES financemuse.categories(id),
  amount_minor BIGINT NOT NULL CHECK (amount_minor <> 0),
  currency TEXT NOT NULL DEFAULT 'IDR',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.transaction_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('expense', 'income', 'transfer', 'adjustment')),
  amount_minor BIGINT CHECK (amount_minor IS NULL OR amount_minor > 0),
  account_id UUID REFERENCES financemuse.accounts(id),
  category_id UUID REFERENCES financemuse.categories(id),
  merchant TEXT,
  description TEXT,
  tags TEXT[] NOT NULL DEFAULT '{}',
  payload_json JSONB NOT NULL DEFAULT '{}',
  favourite BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.custom_field_definitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('transaction', 'account')),
  field_key TEXT NOT NULL,
  field_type TEXT NOT NULL CHECK (field_type IN ('text', 'number', 'date', 'boolean', 'enum')),
  options_json JSONB,
  required BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, entity_type, field_key)
);

CREATE TABLE IF NOT EXISTS financemuse.custom_field_values (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id UUID NOT NULL REFERENCES financemuse.transactions(id) ON DELETE CASCADE,
  field_definition_id UUID NOT NULL REFERENCES financemuse.custom_field_definitions(id) ON DELETE CASCADE,
  value_json JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (transaction_id, field_definition_id)
);

CREATE TABLE IF NOT EXISTS financemuse.tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS tags_user_name_uidx
  ON financemuse.tags (user_id, (lower(name)));

CREATE TABLE IF NOT EXISTS financemuse.transaction_tags (
  transaction_id UUID NOT NULL REFERENCES financemuse.transactions(id) ON DELETE CASCADE,
  tag_id UUID NOT NULL REFERENCES financemuse.tags(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (transaction_id, tag_id)
);

CREATE TABLE IF NOT EXISTS financemuse.budgets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  category_id UUID REFERENCES financemuse.categories(id), -- NULL = global budget
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  currency TEXT NOT NULL DEFAULT 'IDR',
  cadence TEXT NOT NULL DEFAULT 'monthly' CHECK (cadence IN ('monthly', 'weekly', 'custom')),
  rollover TEXT NOT NULL DEFAULT 'none' CHECK (rollover IN ('none', 'carry')),
  alert_thresholds INT[] NOT NULL DEFAULT ARRAY[50, 75, 90, 100],
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.budget_periods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  budget_id UUID NOT NULL REFERENCES financemuse.budgets(id) ON DELETE CASCADE,
  start_at DATE NOT NULL,
  end_at DATE NOT NULL,
  planned_amount_minor BIGINT NOT NULL CHECK (planned_amount_minor > 0),
  version INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (budget_id, start_at),
  CHECK (end_at >= start_at)
);

CREATE TABLE IF NOT EXISTS financemuse.forecast_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  period_start DATE,
  period_end DATE,
  method TEXT NOT NULL CHECK (method IN ('run_rate', 'scheduled', 'hybrid')),
  model_version TEXT NOT NULL DEFAULT 'run_rate_v1',
  assumptions_json JSONB NOT NULL DEFAULT '[]',
  totals_json JSONB NOT NULL DEFAULT '{}',
  confidence TEXT NOT NULL DEFAULT 'low' CHECK (confidence IN ('low', 'medium', 'high')),
  generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.forecast_points (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL REFERENCES financemuse.forecast_runs(id) ON DELETE CASCADE,
  point_date DATE,
  actual_amount_minor BIGINT,
  predicted_amount_minor BIGINT,
  lower_minor BIGINT,
  upper_minor BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.forecast_scenarios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  base_run_id UUID REFERENCES financemuse.forecast_runs(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  changes_json JSONB NOT NULL DEFAULT '{}',
  result_json JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.recurring_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  cadence TEXT NOT NULL CHECK (cadence IN ('daily', 'weekly', 'monthly', 'yearly', 'custom')),
  interval_days INT NOT NULL DEFAULT 1,
  next_at TIMESTAMPTZ,
  start_at TIMESTAMPTZ,
  end_at TIMESTAMPTZ,
  expected_amount_minor BIGINT CHECK (expected_amount_minor IS NULL OR expected_amount_minor > 0),
  account_id UUID REFERENCES financemuse.accounts(id),
  category_id UUID REFERENCES financemuse.categories(id),
  type TEXT NOT NULL CHECK (type IN ('expense', 'income', 'transfer')),
  mode TEXT NOT NULL DEFAULT 'draft' CHECK (mode IN ('scheduled', 'draft', 'auto-post')),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  payload_json JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.savings_goals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  target_amount_minor BIGINT NOT NULL CHECK (target_amount_minor > 0),
  target_date DATE,
  allocation_account_id UUID REFERENCES financemuse.accounts(id),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'achieved', 'paused')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.goal_allocations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  goal_id UUID NOT NULL REFERENCES financemuse.savings_goals(id) ON DELETE CASCADE,
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  transaction_id UUID REFERENCES financemuse.transactions(id),
  allocated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.debts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('debt', 'receivable')),
  counterparty TEXT,
  principal_minor BIGINT NOT NULL CHECK (principal_minor > 0),
  rate NUMERIC(5, 4),
  start_date DATE,
  due_date DATE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paid', 'overdue')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.debt_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  debt_id UUID NOT NULL REFERENCES financemuse.debts(id) ON DELETE CASCADE,
  transaction_id UUID REFERENCES financemuse.transactions(id),
  principal_paid_minor BIGINT NOT NULL DEFAULT 0 CHECK (principal_paid_minor >= 0),
  interest_paid_minor BIGINT NOT NULL DEFAULT 0 CHECK (interest_paid_minor >= 0),
  paid_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.import_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  format TEXT NOT NULL CHECK (format IN ('csv', 'pdf')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'needs_review', 'completed', 'failed')),
  mapping_json JSONB NOT NULL DEFAULT '{}',
  source_ref TEXT,
  totals_json JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.import_rows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES financemuse.import_jobs(id) ON DELETE CASCADE,
  line_no INT,
  normalized_json JSONB NOT NULL DEFAULT '{}',
  confidence NUMERIC(3, 2),
  disposition TEXT NOT NULL DEFAULT 'pending' CHECK (disposition IN ('pending', 'skip', 'replace', 'create', 'needs_review', 'imported')),
  error_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.export_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('transactions', 'budget', 'forecast')),
  format TEXT NOT NULL CHECK (format IN ('csv', 'pdf')),
  filter_snapshot JSONB NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  output_path TEXT,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.agent_connections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  oauth_client_id TEXT NOT NULL,
  display_name TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked', 'paused')),
  connected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at TIMESTAMPTZ,
  last_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, oauth_client_id)
);

CREATE TABLE IF NOT EXISTS financemuse.agent_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  connection_id UUID NOT NULL REFERENCES financemuse.agent_connections(id) ON DELETE CASCADE,
  permission TEXT NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (connection_id, permission)
);

CREATE TABLE IF NOT EXISTS financemuse.agent_policies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  connection_id UUID NOT NULL REFERENCES financemuse.agent_connections(id) ON DELETE CASCADE UNIQUE,
  limits_json JSONB NOT NULL DEFAULT '{}',
  account_allowlist UUID[] NOT NULL DEFAULT '{}',
  category_allowlist UUID[] NOT NULL DEFAULT '{}',
  approval_mode TEXT NOT NULL DEFAULT 'auto' CHECK (approval_mode IN ('auto', 'approval_always')),
  daily_write_cap_minor BIGINT,
  max_actions_per_hour INT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.agent_pending_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  connection_id UUID NOT NULL REFERENCES financemuse.agent_connections(id) ON DELETE CASCADE,
  tool_name TEXT NOT NULL,
  payload_hash TEXT,
  payload_json JSONB,
  expected_version INT,
  expires_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('proposed', 'pending', 'approved', 'rejected', 'expired', 'cancelled', 'executed', 'failed')),
  decided_at TIMESTAMPTZ,
  decided_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.agent_executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action_id UUID REFERENCES financemuse.agent_pending_actions(id) ON DELETE SET NULL,
  idempotency_key TEXT,
  execution_result JSONB NOT NULL DEFAULT '{}',
  executed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS agent_executions_user_idem_uidx
  ON financemuse.agent_executions (user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS financemuse.agent_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  connection_id UUID REFERENCES financemuse.agent_connections(id) ON DELETE SET NULL,
  event_type TEXT,
  tool_name TEXT,
  actor_type TEXT CHECK (actor_type IN ('user', 'agent', 'admin', 'system')),
  safe_diff_json JSONB NOT NULL DEFAULT '{}',
  outcome TEXT,
  request_id TEXT,
  idempotency_key TEXT,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS financemuse.admin_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  target_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT,
  reason TEXT,
  old_value JSONB,
  new_value JSONB,
  request_id TEXT,
  result TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  -- no updated_at: append-only admin audit
);

CREATE TABLE IF NOT EXISTS financemuse.idempotency_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  operation TEXT NOT NULL,
  key TEXT NOT NULL,
  request_hash TEXT,
  response_ref TEXT,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, operation, key)
);

-- --------------------------------------------------------------------------
-- Functions + triggers
-- --------------------------------------------------------------------------

-- Generic updated_at maintainer.
CREATE OR REPLACE FUNCTION financemuse.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = financemuse, pg_catalog
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Attach set_updated_at to every table that has an updated_at column.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT table_name FROM information_schema.columns
    WHERE table_schema = 'financemuse' AND column_name = 'updated_at'
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_set_updated_at ON financemuse.%I', r.table_name);
    EXECUTE format('CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON financemuse.%I FOR EACH ROW EXECUTE FUNCTION financemuse.set_updated_at()', r.table_name);
  END LOOP;
END $$;

-- Optimistic concurrency: every UPDATE of a transaction bumps row_version.
CREATE OR REPLACE FUNCTION financemuse.bump_row_version()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = financemuse, pg_catalog
AS $$
BEGIN
  NEW.row_version = OLD.row_version + 1;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_bump_row_version ON financemuse.transactions;
CREATE TRIGGER trg_bump_row_version
  BEFORE UPDATE ON financemuse.transactions
  FOR EACH ROW EXECUTE FUNCTION financemuse.bump_row_version();

-- Admin check (SECURITY DEFINER so it can read user_roles past RLS).
CREATE OR REPLACE FUNCTION financemuse.is_admin(p_uid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = financemuse, pg_catalog
AS $$
  SELECT EXISTS (
    SELECT 1 FROM financemuse.user_roles
    WHERE user_id = p_uid AND role = 'admin'
  );
$$;

-- A transaction may only reference accounts/categories owned by the same
-- user (or system categories, user_id IS NULL). Same-user checks for
-- splits/tags/custom-field values are covered by the parent FK + RLS.
CREATE OR REPLACE FUNCTION financemuse.enforce_tx_ownership()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = financemuse, pg_catalog
AS $$
BEGIN
  IF NEW.account_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM financemuse.accounts
    WHERE id = NEW.account_id AND user_id = NEW.user_id
  ) THEN
    RAISE EXCEPTION 'account % does not belong to user %', NEW.account_id, NEW.user_id;
  END IF;
  IF NEW.destination_account_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM financemuse.accounts
    WHERE id = NEW.destination_account_id AND user_id = NEW.user_id
  ) THEN
    RAISE EXCEPTION 'destination account % does not belong to user %', NEW.destination_account_id, NEW.user_id;
  END IF;
  IF NEW.category_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM financemuse.categories
    WHERE id = NEW.category_id AND (user_id = NEW.user_id OR user_id IS NULL)
  ) THEN
    RAISE EXCEPTION 'category % does not belong to user %', NEW.category_id, NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_tx_ownership ON financemuse.transactions;
CREATE TRIGGER trg_enforce_tx_ownership
  BEFORE INSERT OR UPDATE ON financemuse.transactions
  FOR EACH ROW EXECUTE FUNCTION financemuse.enforce_tx_ownership();

-- Journal balance: for each affected entry, SUM(amount_minor) per currency
-- must be 0. Deferred so multi-line inserts inside one transaction pass.
CREATE OR REPLACE FUNCTION financemuse.check_journal_balanced()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = financemuse, pg_catalog
AS $$
DECLARE
  v_entry UUID;
  v_bad TEXT;
BEGIN
  FOR v_entry IN
    SELECT DISTINCT e FROM (
      SELECT NEW.entry_id AS e WHERE TG_OP IN ('INSERT', 'UPDATE') AND NEW.entry_id IS NOT NULL
      UNION
      SELECT OLD.entry_id WHERE TG_OP IN ('UPDATE', 'DELETE') AND OLD.entry_id IS NOT NULL
    ) s
  LOOP
    SELECT string_agg(currency || ':' || s, ', ') INTO v_bad
    FROM (
      SELECT currency, COALESCE(SUM(amount_minor), 0) AS s
      FROM financemuse.journal_lines
      WHERE entry_id = v_entry
      GROUP BY currency
      HAVING COALESCE(SUM(amount_minor), 0) <> 0
    ) t;
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION 'journal entry % is not balanced: %', v_entry, v_bad;
    END IF;
  END LOOP;
  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;
DROP TRIGGER IF EXISTS trg_check_journal_balanced ON financemuse.journal_lines;
CREATE CONSTRAINT TRIGGER trg_check_journal_balanced
  AFTER INSERT OR UPDATE OR DELETE ON financemuse.journal_lines
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION financemuse.check_journal_balanced();

-- Split sum: when a transaction has splits, their sum must equal the
-- parent amount_minor. Deferred so splits can be inserted one by one.
CREATE OR REPLACE FUNCTION financemuse.check_split_sum()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = financemuse, pg_catalog
AS $$
DECLARE
  v_tx UUID;
  v_sum BIGINT;
  v_n BIGINT;
  v_parent BIGINT;
BEGIN
  FOR v_tx IN
    SELECT DISTINCT t FROM (
      SELECT NEW.transaction_id AS t WHERE TG_OP IN ('INSERT', 'UPDATE') AND NEW.transaction_id IS NOT NULL
      UNION
      SELECT OLD.transaction_id WHERE TG_OP IN ('UPDATE', 'DELETE') AND OLD.transaction_id IS NOT NULL
    ) s
  LOOP
    SELECT COALESCE(SUM(amount_minor), 0), COUNT(*) INTO v_sum, v_n
    FROM financemuse.transaction_splits WHERE transaction_id = v_tx;
    IF v_n > 0 THEN
      SELECT amount_minor INTO v_parent
      FROM financemuse.transactions WHERE id = v_tx;
      IF v_parent IS NOT NULL AND v_sum <> v_parent THEN
        RAISE EXCEPTION 'splits for transaction % sum to % but parent amount is %', v_tx, v_sum, v_parent;
      END IF;
    END IF;
  END LOOP;
  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;
DROP TRIGGER IF EXISTS trg_check_split_sum ON financemuse.transaction_splits;
CREATE CONSTRAINT TRIGGER trg_check_split_sum
  AFTER INSERT OR UPDATE OR DELETE ON financemuse.transaction_splits
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION financemuse.check_split_sum();

-- Account balance = opening balance + SUM(posted journal lines).
CREATE OR REPLACE FUNCTION financemuse.account_balance(p_account_id UUID)
RETURNS BIGINT
LANGUAGE sql
STABLE
SET search_path = financemuse, pg_catalog
AS $$
  SELECT COALESCE(a.opening_balance_minor, 0) + COALESCE((
    SELECT SUM(l.amount_minor)
    FROM financemuse.journal_lines l
    JOIN financemuse.journal_entries e ON e.id = l.entry_id
    WHERE l.account_id = p_account_id AND e.status = 'posted'
  ), 0)
  FROM financemuse.accounts a
  WHERE a.id = p_account_id;
$$;

-- Post the balanced journal for one posted transaction. SECURITY DEFINER
-- (runs as owner, bypasses RLS; callers still need EXECUTE grant).
-- Sign convention: see header comment. Raises if the transaction does not
-- exist, is not posted, already has a journal entry, or lines do not
-- balance. Returns the new journal_entries id.
CREATE OR REPLACE FUNCTION financemuse.post_journal_for_transaction(p_transaction_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = financemuse, pg_catalog
AS $$
DECLARE
  t RECORD;
  v_entry UUID;
BEGIN
  SELECT * INTO t FROM financemuse.transactions WHERE id = p_transaction_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'transaction % not found', p_transaction_id;
  END IF;
  IF t.status <> 'posted' THEN
    RAISE EXCEPTION 'transaction % is not posted (status=%)', p_transaction_id, t.status;
  END IF;
  IF EXISTS (SELECT 1 FROM financemuse.journal_entries WHERE transaction_id = p_transaction_id) THEN
    RAISE EXCEPTION 'journal entry already exists for transaction %', p_transaction_id;
  END IF;

  INSERT INTO financemuse.journal_entries (user_id, transaction_id, status, currency, memo)
  VALUES (t.user_id, t.id, 'posted', t.currency, 'auto-posted from transaction ' || t.id::text)
  RETURNING id INTO v_entry;

  IF t.type = 'expense' THEN
    INSERT INTO financemuse.journal_lines (entry_id, account_id, category_id, amount_minor, currency) VALUES
      (v_entry, t.account_id, NULL, -t.amount_minor, t.currency),
      (v_entry, NULL, t.category_id, t.amount_minor, t.currency);
  ELSIF t.type = 'income' THEN
    INSERT INTO financemuse.journal_lines (entry_id, account_id, category_id, amount_minor, currency) VALUES
      (v_entry, t.account_id, NULL, t.amount_minor, t.currency),
      (v_entry, NULL, t.category_id, -t.amount_minor, t.currency);
  ELSIF t.type = 'transfer' THEN
    INSERT INTO financemuse.journal_lines (entry_id, account_id, category_id, amount_minor, currency) VALUES
      (v_entry, t.account_id, NULL, -t.amount_minor, t.currency),
      (v_entry, t.destination_account_id, NULL, t.amount_minor, t.currency);
  ELSIF t.type = 'adjustment' THEN
    INSERT INTO financemuse.journal_lines (entry_id, account_id, category_id, amount_minor, currency) VALUES
      (v_entry, t.account_id, NULL, t.amount_minor, t.currency),
      (v_entry, NULL, NULL, -t.amount_minor, t.currency); -- adjustment offset
  ELSE
    RAISE EXCEPTION 'unknown transaction type %', t.type;
  END IF;

  IF (SELECT COALESCE(SUM(amount_minor), 0) FROM financemuse.journal_lines WHERE entry_id = v_entry) <> 0 THEN
    RAISE EXCEPTION 'journal lines do not balance for entry %', v_entry;
  END IF;

  RETURN v_entry;
END;
$$;

-- Balance view.
CREATE OR REPLACE VIEW financemuse.v_account_balances AS
SELECT a.id AS account_id, a.user_id, financemuse.account_balance(a.id) AS balance_minor
FROM financemuse.accounts a;

-- --------------------------------------------------------------------------
-- Indexes (§7 + PRD §10)
-- --------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS transactions_user_effective_idx
  ON financemuse.transactions (user_id, effective_at DESC, id);
CREATE INDEX IF NOT EXISTS transactions_user_category_idx
  ON financemuse.transactions (user_id, category_id, effective_at);
CREATE INDEX IF NOT EXISTS transactions_user_status_idx
  ON financemuse.transactions (user_id, status);
CREATE INDEX IF NOT EXISTS journal_lines_entry_idx
  ON financemuse.journal_lines (entry_id);
CREATE INDEX IF NOT EXISTS journal_entries_user_posted_idx
  ON financemuse.journal_entries (user_id, posted_at);
CREATE INDEX IF NOT EXISTS agent_pending_actions_conn_status_idx
  ON financemuse.agent_pending_actions (connection_id, status, expires_at);
CREATE INDEX IF NOT EXISTS agent_audit_logs_user_occurred_idx
  ON financemuse.agent_audit_logs (user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS import_rows_job_line_idx
  ON financemuse.import_rows (job_id, line_no);
CREATE INDEX IF NOT EXISTS budgets_user_category_idx
  ON financemuse.budgets (user_id, category_id);

-- --------------------------------------------------------------------------
-- Row Level Security
-- --------------------------------------------------------------------------
-- Enable RLS on every table in the schema.
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'financemuse'
  LOOP
    EXECUTE format('ALTER TABLE financemuse.%I ENABLE ROW LEVEL SECURITY', r.tablename);
  END LOOP;
END $$;

-- Owner-only policies for the straightforward user-owned tables.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'profiles', 'accounts', 'transactions', 'journal_entries',
    'transaction_templates', 'custom_field_definitions', 'tags',
    'budgets', 'forecast_runs', 'forecast_scenarios', 'recurring_rules',
    'savings_goals', 'debts', 'import_jobs', 'export_jobs',
    'agent_connections', 'agent_pending_actions', 'agent_executions',
    'idempotency_records'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS p_owner_select ON financemuse.%I', t);
    EXECUTE format('CREATE POLICY p_owner_select ON financemuse.%I FOR SELECT TO authenticated USING (auth.uid() = user_id)', t);
    EXECUTE format('DROP POLICY IF EXISTS p_owner_insert ON financemuse.%I', t);
    EXECUTE format('CREATE POLICY p_owner_insert ON financemuse.%I FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id)', t);
    EXECUTE format('DROP POLICY IF EXISTS p_owner_update ON financemuse.%I', t);
    EXECUTE format('CREATE POLICY p_owner_update ON financemuse.%I FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id)', t);
    EXECUTE format('DROP POLICY IF EXISTS p_owner_delete ON financemuse.%I', t);
    EXECUTE format('CREATE POLICY p_owner_delete ON financemuse.%I FOR DELETE TO authenticated USING (auth.uid() = user_id)', t);
  END LOOP;
END $$;

-- Categories: owner rows + readable system templates (user_id IS NULL).
DROP POLICY IF EXISTS p_owner_select ON financemuse.categories;
CREATE POLICY p_owner_select ON financemuse.categories FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS p_system_select ON financemuse.categories;
CREATE POLICY p_system_select ON financemuse.categories FOR SELECT TO authenticated USING (user_id IS NULL);
DROP POLICY IF EXISTS p_owner_insert ON financemuse.categories;
CREATE POLICY p_owner_insert ON financemuse.categories FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS p_owner_update ON financemuse.categories;
CREATE POLICY p_owner_update ON financemuse.categories FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS p_owner_delete ON financemuse.categories;
CREATE POLICY p_owner_delete ON financemuse.categories FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- Child tables: access via EXISTS on the owning parent row.
DO $$
DECLARE m record;
BEGIN
  FOR m IN SELECT * FROM (VALUES
    ('transaction_splits',  'transactions',       'transaction_id', 'id'),
    ('journal_lines',       'journal_entries',    'entry_id',       'id'),
    ('custom_field_values', 'transactions',       'transaction_id', 'id'),
    ('transaction_tags',    'transactions',       'transaction_id', 'id'),
    ('budget_periods',      'budgets',            'budget_id',      'id'),
    ('forecast_points',     'forecast_runs',      'run_id',         'id'),
    ('goal_allocations',    'savings_goals',      'goal_id',        'id'),
    ('debt_payments',       'debts',              'debt_id',        'id'),
    ('import_rows',         'import_jobs',        'job_id',         'id'),
    ('agent_permissions',   'agent_connections',  'connection_id',  'id'),
    ('agent_policies',      'agent_connections',  'connection_id',  'id')
  ) AS v(child_tbl, parent_tbl, fk_col, pk_col)
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS p_parent_select ON financemuse.%I', m.child_tbl);
    EXECUTE format('CREATE POLICY p_parent_select ON financemuse.%I FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM financemuse.%I p WHERE p.%I = %I.%I AND p.user_id = auth.uid()))',
      m.child_tbl, m.parent_tbl, m.pk_col, m.child_tbl, m.fk_col);
    EXECUTE format('DROP POLICY IF EXISTS p_parent_insert ON financemuse.%I', m.child_tbl);
    EXECUTE format('CREATE POLICY p_parent_insert ON financemuse.%I FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM financemuse.%I p WHERE p.%I = %I.%I AND p.user_id = auth.uid()))',
      m.child_tbl, m.parent_tbl, m.pk_col, m.child_tbl, m.fk_col);
    EXECUTE format('DROP POLICY IF EXISTS p_parent_update ON financemuse.%I', m.child_tbl);
    EXECUTE format('CREATE POLICY p_parent_update ON financemuse.%I FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM financemuse.%I p WHERE p.%I = %I.%I AND p.user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM financemuse.%I p WHERE p.%I = %I.%I AND p.user_id = auth.uid()))',
      m.child_tbl, m.parent_tbl, m.pk_col, m.child_tbl, m.fk_col, m.parent_tbl, m.pk_col, m.child_tbl, m.fk_col);
    EXECUTE format('DROP POLICY IF EXISTS p_parent_delete ON financemuse.%I', m.child_tbl);
    EXECUTE format('CREATE POLICY p_parent_delete ON financemuse.%I FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM financemuse.%I p WHERE p.%I = %I.%I AND p.user_id = auth.uid()))',
      m.child_tbl, m.parent_tbl, m.pk_col, m.child_tbl, m.fk_col);
  END LOOP;
END $$;

-- user_roles: SELECT own row or admin; NO insert/update/delete for authenticated.
DROP POLICY IF EXISTS p_user_roles_select ON financemuse.user_roles;
CREATE POLICY p_user_roles_select ON financemuse.user_roles FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR financemuse.is_admin(auth.uid()));

-- admin_audit_logs: SELECT only for admins; NO insert/update/delete for authenticated.
DROP POLICY IF EXISTS p_admin_audit_select ON financemuse.admin_audit_logs;
CREATE POLICY p_admin_audit_select ON financemuse.admin_audit_logs FOR SELECT TO authenticated
  USING (financemuse.is_admin(auth.uid()));

-- agent_audit_logs: append-only for authenticated (SELECT own + INSERT own).
DROP POLICY IF EXISTS p_agent_audit_select ON financemuse.agent_audit_logs;
CREATE POLICY p_agent_audit_select ON financemuse.agent_audit_logs FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS p_agent_audit_insert ON financemuse.agent_audit_logs;
CREATE POLICY p_agent_audit_insert ON financemuse.agent_audit_logs FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

-- --------------------------------------------------------------------------
-- Grants (no API exposure change: PGRST_DB_SCHEMAS untouched)
-- --------------------------------------------------------------------------
GRANT USAGE ON SCHEMA financemuse TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA financemuse TO authenticated, service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA financemuse TO authenticated, service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA financemuse TO authenticated, service_role;

-- --------------------------------------------------------------------------
-- Seed: system categories (PRD §5.4), idempotent
-- --------------------------------------------------------------------------
INSERT INTO financemuse.categories (user_id, type, name, sort_order, is_system) VALUES
  (NULL, 'income', 'Salary/Bonus', 1, TRUE),
  (NULL, 'income', 'Freelance', 2, TRUE),
  (NULL, 'income', 'Business', 3, TRUE),
  (NULL, 'income', 'Gifts', 4, TRUE),
  (NULL, 'income', 'Refund/Other', 5, TRUE),
  (NULL, 'expense', 'Food & Drinks', 1, TRUE),
  (NULL, 'expense', 'Groceries', 2, TRUE),
  (NULL, 'expense', 'Transport', 3, TRUE),
  (NULL, 'expense', 'Housing', 4, TRUE),
  (NULL, 'expense', 'Utilities', 5, TRUE),
  (NULL, 'expense', 'Shopping', 6, TRUE),
  (NULL, 'expense', 'Health', 7, TRUE),
  (NULL, 'expense', 'Family & Education', 8, TRUE),
  (NULL, 'expense', 'Entertainment', 9, TRUE),
  (NULL, 'expense', 'Subscriptions', 10, TRUE),
  (NULL, 'expense', 'Fees', 11, TRUE),
  (NULL, 'expense', 'Other', 12, TRUE)
ON CONFLICT DO NOTHING;
