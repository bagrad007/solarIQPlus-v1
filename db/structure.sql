SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: app; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA app;


--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: ltree; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS ltree WITH SCHEMA public;


--
-- Name: EXTENSION ltree; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION ltree IS 'data type for hierarchical tree-like structures';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: alarm_state; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.alarm_state AS ENUM (
    'normal',
    'warn',
    'critical'
);


--
-- Name: case_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.case_status AS ENUM (
    'open',
    'in_progress',
    'resolved',
    'closed'
);


--
-- Name: organization_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.organization_type AS ENUM (
    'maverick',
    'partner',
    'customer'
);


--
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role AS ENUM (
    'maverick_admin',
    'partner_user',
    'customer_user'
);


--
-- Name: can_see(public.ltree); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.can_see(target_path public.ltree) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT CASE
    WHEN target_path IS NULL THEN false
    WHEN app.is_maverick() AND NOT app.in_view_as() THEN true
    WHEN app.effective_org_path() IS NULL THEN false
    ELSE target_path <@ app.effective_org_path()
  END
$$;


--
-- Name: current_org_id(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.current_org_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  SELECT NULLIF(current_setting('app.org_id', true), '')::uuid
$$;


--
-- Name: current_user_id(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.current_user_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  SELECT NULLIF(current_setting('app.user_id', true), '')::uuid
$$;


--
-- Name: effective_logo_url(uuid); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.effective_logo_url(target_org_id uuid) RETURNS text
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'app'
    AS $$
DECLARE
  result text;
BEGIN
  SELECT nullif(branding_config->>'logo_url', '')
  INTO result
  FROM organizations
  WHERE path @> (SELECT path FROM organizations WHERE id = target_org_id)
    AND nullif(branding_config->>'logo_url', '') IS NOT NULL
  ORDER BY nlevel(path) DESC
  LIMIT 1;

  RETURN result;
END
$$;


--
-- Name: effective_org_id(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.effective_org_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  SELECT CASE
    WHEN app.is_maverick()
         AND app.in_view_as()
         AND app.impersonated_org_id() IS NOT NULL
      THEN app.impersonated_org_id()
    ELSE app.current_org_id()
  END
$$;


--
-- Name: effective_org_path(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.effective_org_path() RETURNS public.ltree
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'app'
    AS $$
DECLARE
  result ltree;
BEGIN
  SELECT path INTO result FROM organizations WHERE id = app.effective_org_id();
  RETURN result;
END
$$;


--
-- Name: enforce_audit_logs_insert_only(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.enforce_audit_logs_insert_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'audit_logs is insert-only (% denied)', TG_OP;
END
$$;


--
-- Name: enforce_case_escalation_lifecycle(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.enforce_case_escalation_lifecycle() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.escalated_to_maverick AND NEW.escalated_at IS NULL THEN
      NEW.escalated_at := now();
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.escalated_to_maverick AND NOT OLD.escalated_to_maverick THEN
    NEW.escalated_at := COALESCE(NEW.escalated_at, now());
  END IF;

  IF OLD.escalated_to_maverick AND NOT NEW.escalated_to_maverick THEN
    IF NOT app.is_maverick() THEN
      RAISE EXCEPTION 'only a Maverick session may de-escalate a case';
    END IF;
  END IF;

  RETURN NEW;
END
$$;


--
-- Name: enforce_case_notes_append_only(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.enforce_case_notes_append_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.notes IS NULL THEN NEW.notes := ''; END IF;
  IF OLD.notes IS NOT NULL AND length(OLD.notes) > 0 AND
     substring(NEW.notes FROM 1 FOR length(OLD.notes)) <> OLD.notes THEN
    RAISE EXCEPTION 'cases.notes is append-only';
  END IF;
  RETURN NEW;
END
$$;


--
-- Name: enforce_case_status_machine(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.enforce_case_status_machine() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.status = 'closed' AND NEW.status <> OLD.status THEN
    RAISE EXCEPTION 'cases.status is final once closed';
  END IF;

  IF NEW.status = 'closed' AND NEW.closed_at IS NULL THEN
    NEW.closed_at := now();
  END IF;
  IF NEW.status <> 'closed' AND NEW.closed_at IS NOT NULL THEN
    NEW.closed_at := NULL;
  END IF;

  RETURN NEW;
END
$$;


--
-- Name: enforce_organization_immutable_columns(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.enforce_organization_immutable_columns() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.path IS DISTINCT FROM OLD.path THEN
    RAISE EXCEPTION 'organizations.path is immutable';
  END IF;
  IF NEW.parent_id IS DISTINCT FROM OLD.parent_id THEN
    RAISE EXCEPTION 'organizations.parent_id is immutable';
  END IF;
  IF NEW.org_type IS DISTINCT FROM OLD.org_type THEN
    RAISE EXCEPTION 'organizations.org_type is immutable';
  END IF;
  RETURN NEW;
END
$$;


--
-- Name: impersonated_org_id(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.impersonated_org_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  SELECT NULLIF(current_setting('app.impersonated_org_id', true), '')::uuid
$$;


--
-- Name: in_view_as(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.in_view_as() RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT current_setting('app.mode', true) = 'view_as'
$$;


--
-- Name: is_maverick(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.is_maverick() RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT current_setting('app.is_maverick', true) = 'true'
$$;


--
-- Name: populate_organization_path(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.populate_organization_path() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  parent_path ltree;
  my_label    text := replace(NEW.id::text, '-', '_');
BEGIN
  IF NEW.parent_id IS NULL THEN
    NEW.path := my_label::ltree;
  ELSE
    SELECT path INTO parent_path FROM organizations WHERE id = NEW.parent_id;
    IF parent_path IS NULL THEN
      RAISE EXCEPTION 'organization %: parent % not found', NEW.id, NEW.parent_id;
    END IF;
    NEW.path := parent_path || my_label::ltree;
  END IF;

  -- Hierarchy depth invariant: maverick=1, partner=2, customer=3.
  IF NEW.org_type = 'maverick' AND nlevel(NEW.path) <> 1 THEN
    RAISE EXCEPTION 'maverick must be the root (depth 1, got %)', nlevel(NEW.path);
  END IF;
  IF NEW.org_type = 'partner' AND nlevel(NEW.path) <> 2 THEN
    RAISE EXCEPTION 'partner must be a direct child of maverick (depth 2, got %)', nlevel(NEW.path);
  END IF;
  IF NEW.org_type = 'customer' AND nlevel(NEW.path) <> 3 THEN
    RAISE EXCEPTION 'customer must be a direct child of a partner (depth 3, got %)', nlevel(NEW.path);
  END IF;

  RETURN NEW;
END
$$;


--
-- Name: populate_tenant_org_path(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.populate_tenant_org_path() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  ref_path ltree;
BEGIN
  IF NEW.organization_id IS NULL THEN
    RAISE EXCEPTION '%.organization_id cannot be null', TG_TABLE_NAME;
  END IF;
  SELECT path INTO ref_path FROM organizations WHERE id = NEW.organization_id;
  IF ref_path IS NULL THEN
    RAISE EXCEPTION '%.organization_id % not found', TG_TABLE_NAME, NEW.organization_id;
  END IF;
  NEW.org_path := ref_path;
  RETURN NEW;
END
$$;


--
-- Name: touch_updated_at(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END
$$;


--
-- Name: validate_site_parent_is_customer(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.validate_site_parent_is_customer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  org_type_val organization_type;
BEGIN
  SELECT o.org_type INTO org_type_val FROM organizations o WHERE o.id = NEW.organization_id;
  IF org_type_val <> 'customer' THEN
    RAISE EXCEPTION 'sites.organization_id % is a %, must be a customer', NEW.organization_id, org_type_val;
  END IF;
  RETURN NEW;
END
$$;


--
-- Name: validate_user_role_matches_org_type(); Type: FUNCTION; Schema: app; Owner: -
--

CREATE FUNCTION app.validate_user_role_matches_org_type() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  org_type_val organization_type;
BEGIN
  SELECT o.org_type INTO org_type_val FROM organizations o WHERE o.id = NEW.organization_id;
  IF (NEW.role = 'maverick_admin' AND org_type_val <> 'maverick') OR
     (NEW.role = 'partner_user'   AND org_type_val <> 'partner')  OR
     (NEW.role = 'customer_user'  AND org_type_val <> 'customer') THEN
    RAISE EXCEPTION 'user role % does not match org_type %', NEW.role, org_type_val;
  END IF;
  RETURN NEW;
END
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    org_path public.ltree NOT NULL,
    actor_user_id uuid NOT NULL,
    auditable_type text NOT NULL,
    auditable_id uuid NOT NULL,
    field_name text NOT NULL,
    old_value text,
    new_value text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT audit_logs_auditable_type_not_blank CHECK ((length(btrim(auditable_type)) > 0)),
    CONSTRAINT audit_logs_field_name_not_blank CHECK ((length(btrim(field_name)) > 0))
);

ALTER TABLE ONLY public.audit_logs FORCE ROW LEVEL SECURITY;


--
-- Name: cases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cases (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    site_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    org_path public.ltree NOT NULL,
    opened_by_user_id uuid NOT NULL,
    subject text NOT NULL,
    notes text DEFAULT ''::text NOT NULL,
    status public.case_status DEFAULT 'open'::public.case_status NOT NULL,
    escalated_to_maverick boolean DEFAULT false NOT NULL,
    escalated_at timestamp with time zone,
    closed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT cases_escalated_at_set_when_escalated CHECK (((escalated_to_maverick AND (escalated_at IS NOT NULL)) OR (NOT escalated_to_maverick))),
    CONSTRAINT cases_subject_not_blank CHECK ((length(btrim(subject)) > 0))
);

ALTER TABLE ONLY public.cases FORCE ROW LEVEL SECURITY;


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    parent_id uuid,
    org_type public.organization_type NOT NULL,
    name text NOT NULL,
    branding_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    path public.ltree NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT organizations_branding_config_is_object CHECK ((jsonb_typeof(branding_config) = 'object'::text)),
    CONSTRAINT organizations_maverick_has_no_parent CHECK ((((org_type = 'maverick'::public.organization_type) AND (parent_id IS NULL)) OR ((org_type <> 'maverick'::public.organization_type) AND (parent_id IS NOT NULL)))),
    CONSTRAINT organizations_name_not_blank CHECK ((length(btrim(name)) > 0))
);

ALTER TABLE ONLY public.organizations FORCE ROW LEVEL SECURITY;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    org_path public.ltree NOT NULL,
    name text NOT NULL,
    gateway_ip inet,
    device_credentials_encrypted text,
    polling_interval_seconds integer DEFAULT 30 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    latitude numeric(9,6),
    longitude numeric(9,6),
    nameplate_kw numeric(6,2),
    CONSTRAINT sites_name_not_blank CHECK ((length(btrim(name)) > 0)),
    CONSTRAINT sites_polling_interval_positive CHECK ((polling_interval_seconds > 0))
);

ALTER TABLE ONLY public.sites FORCE ROW LEVEL SECURITY;


--
-- Name: telemetry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry (
    id uuid DEFAULT uuidv7() NOT NULL,
    site_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    org_path public.ltree NOT NULL,
    recorded_at timestamp with time zone NOT NULL,
    metric_payload jsonb NOT NULL,
    alarm_state public.alarm_state DEFAULT 'normal'::public.alarm_state NOT NULL,
    CONSTRAINT telemetry_metric_payload_is_object CHECK ((jsonb_typeof(metric_payload) = 'object'::text))
)
PARTITION BY RANGE (recorded_at);

ALTER TABLE ONLY public.telemetry FORCE ROW LEVEL SECURITY;


--
-- Name: telemetry_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_default (
    id uuid DEFAULT uuidv7() CONSTRAINT telemetry_id_not_null NOT NULL,
    site_id uuid CONSTRAINT telemetry_site_id_not_null NOT NULL,
    organization_id uuid CONSTRAINT telemetry_organization_id_not_null NOT NULL,
    org_path public.ltree CONSTRAINT telemetry_org_path_not_null NOT NULL,
    recorded_at timestamp with time zone CONSTRAINT telemetry_recorded_at_not_null NOT NULL,
    metric_payload jsonb CONSTRAINT telemetry_metric_payload_not_null NOT NULL,
    alarm_state public.alarm_state DEFAULT 'normal'::public.alarm_state CONSTRAINT telemetry_alarm_state_not_null NOT NULL,
    CONSTRAINT telemetry_metric_payload_is_object CHECK ((jsonb_typeof(metric_payload) = 'object'::text))
);

ALTER TABLE ONLY public.telemetry_default FORCE ROW LEVEL SECURITY;


--
-- Name: telemetry_y2026m04; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_y2026m04 (
    id uuid DEFAULT uuidv7() CONSTRAINT telemetry_id_not_null NOT NULL,
    site_id uuid CONSTRAINT telemetry_site_id_not_null NOT NULL,
    organization_id uuid CONSTRAINT telemetry_organization_id_not_null NOT NULL,
    org_path public.ltree CONSTRAINT telemetry_org_path_not_null NOT NULL,
    recorded_at timestamp with time zone CONSTRAINT telemetry_recorded_at_not_null NOT NULL,
    metric_payload jsonb CONSTRAINT telemetry_metric_payload_not_null NOT NULL,
    alarm_state public.alarm_state DEFAULT 'normal'::public.alarm_state CONSTRAINT telemetry_alarm_state_not_null NOT NULL,
    CONSTRAINT telemetry_metric_payload_is_object CHECK ((jsonb_typeof(metric_payload) = 'object'::text))
);

ALTER TABLE ONLY public.telemetry_y2026m04 FORCE ROW LEVEL SECURITY;


--
-- Name: telemetry_y2026m05; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_y2026m05 (
    id uuid DEFAULT uuidv7() CONSTRAINT telemetry_id_not_null NOT NULL,
    site_id uuid CONSTRAINT telemetry_site_id_not_null NOT NULL,
    organization_id uuid CONSTRAINT telemetry_organization_id_not_null NOT NULL,
    org_path public.ltree CONSTRAINT telemetry_org_path_not_null NOT NULL,
    recorded_at timestamp with time zone CONSTRAINT telemetry_recorded_at_not_null NOT NULL,
    metric_payload jsonb CONSTRAINT telemetry_metric_payload_not_null NOT NULL,
    alarm_state public.alarm_state DEFAULT 'normal'::public.alarm_state CONSTRAINT telemetry_alarm_state_not_null NOT NULL,
    CONSTRAINT telemetry_metric_payload_is_object CHECK ((jsonb_typeof(metric_payload) = 'object'::text))
);

ALTER TABLE ONLY public.telemetry_y2026m05 FORCE ROW LEVEL SECURITY;


--
-- Name: telemetry_y2026m06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_y2026m06 (
    id uuid DEFAULT uuidv7() CONSTRAINT telemetry_id_not_null NOT NULL,
    site_id uuid CONSTRAINT telemetry_site_id_not_null NOT NULL,
    organization_id uuid CONSTRAINT telemetry_organization_id_not_null NOT NULL,
    org_path public.ltree CONSTRAINT telemetry_org_path_not_null NOT NULL,
    recorded_at timestamp with time zone CONSTRAINT telemetry_recorded_at_not_null NOT NULL,
    metric_payload jsonb CONSTRAINT telemetry_metric_payload_not_null NOT NULL,
    alarm_state public.alarm_state DEFAULT 'normal'::public.alarm_state CONSTRAINT telemetry_alarm_state_not_null NOT NULL,
    CONSTRAINT telemetry_metric_payload_is_object CHECK ((jsonb_typeof(metric_payload) = 'object'::text))
);

ALTER TABLE ONLY public.telemetry_y2026m06 FORCE ROW LEVEL SECURITY;


--
-- Name: telemetry_y2026m07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_y2026m07 (
    id uuid DEFAULT uuidv7() CONSTRAINT telemetry_id_not_null NOT NULL,
    site_id uuid CONSTRAINT telemetry_site_id_not_null NOT NULL,
    organization_id uuid CONSTRAINT telemetry_organization_id_not_null NOT NULL,
    org_path public.ltree CONSTRAINT telemetry_org_path_not_null NOT NULL,
    recorded_at timestamp with time zone CONSTRAINT telemetry_recorded_at_not_null NOT NULL,
    metric_payload jsonb CONSTRAINT telemetry_metric_payload_not_null NOT NULL,
    alarm_state public.alarm_state DEFAULT 'normal'::public.alarm_state CONSTRAINT telemetry_alarm_state_not_null NOT NULL,
    CONSTRAINT telemetry_metric_payload_is_object CHECK ((jsonb_typeof(metric_payload) = 'object'::text))
);

ALTER TABLE ONLY public.telemetry_y2026m07 FORCE ROW LEVEL SECURITY;


--
-- Name: telemetry_y2026m08; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.telemetry_y2026m08 (
    id uuid DEFAULT uuidv7() CONSTRAINT telemetry_id_not_null NOT NULL,
    site_id uuid CONSTRAINT telemetry_site_id_not_null NOT NULL,
    organization_id uuid CONSTRAINT telemetry_organization_id_not_null NOT NULL,
    org_path public.ltree CONSTRAINT telemetry_org_path_not_null NOT NULL,
    recorded_at timestamp with time zone CONSTRAINT telemetry_recorded_at_not_null NOT NULL,
    metric_payload jsonb CONSTRAINT telemetry_metric_payload_not_null NOT NULL,
    alarm_state public.alarm_state DEFAULT 'normal'::public.alarm_state CONSTRAINT telemetry_alarm_state_not_null NOT NULL,
    CONSTRAINT telemetry_metric_payload_is_object CHECK ((jsonb_typeof(metric_payload) = 'object'::text))
);

ALTER TABLE ONLY public.telemetry_y2026m08 FORCE ROW LEVEL SECURITY;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    org_path public.ltree NOT NULL,
    role public.user_role NOT NULL,
    email public.citext NOT NULL,
    encrypted_password text DEFAULT ''::text NOT NULL,
    reset_password_token text,
    reset_password_sent_at timestamp with time zone,
    remember_created_at timestamp with time zone,
    name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.users FORCE ROW LEVEL SECURITY;


--
-- Name: telemetry_default; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry ATTACH PARTITION public.telemetry_default DEFAULT;


--
-- Name: telemetry_y2026m04; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry ATTACH PARTITION public.telemetry_y2026m04 FOR VALUES FROM ('2026-03-31 20:00:00-04') TO ('2026-04-30 20:00:00-04');


--
-- Name: telemetry_y2026m05; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry ATTACH PARTITION public.telemetry_y2026m05 FOR VALUES FROM ('2026-04-30 20:00:00-04') TO ('2026-05-31 20:00:00-04');


--
-- Name: telemetry_y2026m06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry ATTACH PARTITION public.telemetry_y2026m06 FOR VALUES FROM ('2026-05-31 20:00:00-04') TO ('2026-06-30 20:00:00-04');


--
-- Name: telemetry_y2026m07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry ATTACH PARTITION public.telemetry_y2026m07 FOR VALUES FROM ('2026-06-30 20:00:00-04') TO ('2026-07-31 20:00:00-04');


--
-- Name: telemetry_y2026m08; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry ATTACH PARTITION public.telemetry_y2026m08 FOR VALUES FROM ('2026-07-31 20:00:00-04') TO ('2026-08-31 20:00:00-04');


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: cases cases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cases
    ADD CONSTRAINT cases_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sites sites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sites
    ADD CONSTRAINT sites_pkey PRIMARY KEY (id);


--
-- Name: telemetry telemetry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry
    ADD CONSTRAINT telemetry_pkey PRIMARY KEY (id, recorded_at);


--
-- Name: telemetry_default telemetry_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_default
    ADD CONSTRAINT telemetry_default_pkey PRIMARY KEY (id, recorded_at);


--
-- Name: telemetry_y2026m04 telemetry_y2026m04_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_y2026m04
    ADD CONSTRAINT telemetry_y2026m04_pkey PRIMARY KEY (id, recorded_at);


--
-- Name: telemetry_y2026m05 telemetry_y2026m05_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_y2026m05
    ADD CONSTRAINT telemetry_y2026m05_pkey PRIMARY KEY (id, recorded_at);


--
-- Name: telemetry_y2026m06 telemetry_y2026m06_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_y2026m06
    ADD CONSTRAINT telemetry_y2026m06_pkey PRIMARY KEY (id, recorded_at);


--
-- Name: telemetry_y2026m07 telemetry_y2026m07_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_y2026m07
    ADD CONSTRAINT telemetry_y2026m07_pkey PRIMARY KEY (id, recorded_at);


--
-- Name: telemetry_y2026m08 telemetry_y2026m08_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.telemetry_y2026m08
    ADD CONSTRAINT telemetry_y2026m08_pkey PRIMARY KEY (id, recorded_at);


--
-- Name: users users_email_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_unique UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_reset_password_token_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_reset_password_token_unique UNIQUE (reset_password_token);


--
-- Name: index_audit_logs_on_actor_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_actor_user_id ON public.audit_logs USING btree (actor_user_id);


--
-- Name: index_audit_logs_on_auditable_type_and_auditable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_auditable_type_and_auditable_id ON public.audit_logs USING btree (auditable_type, auditable_id);


--
-- Name: index_audit_logs_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_created_at ON public.audit_logs USING btree (created_at DESC);


--
-- Name: index_audit_logs_on_org_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_org_path ON public.audit_logs USING gist (org_path);


--
-- Name: index_audit_logs_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_organization_id ON public.audit_logs USING btree (organization_id);


--
-- Name: index_cases_on_escalated_to_maverick_open; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cases_on_escalated_to_maverick_open ON public.cases USING btree (escalated_to_maverick) WHERE (escalated_to_maverick = true);


--
-- Name: index_cases_on_org_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cases_on_org_path ON public.cases USING gist (org_path);


--
-- Name: index_cases_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cases_on_organization_id ON public.cases USING btree (organization_id);


--
-- Name: index_cases_on_site_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cases_on_site_id ON public.cases USING btree (site_id);


--
-- Name: index_cases_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cases_on_status ON public.cases USING btree (status);


--
-- Name: index_organizations_on_org_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organizations_on_org_type ON public.organizations USING btree (org_type);


--
-- Name: index_organizations_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organizations_on_parent_id ON public.organizations USING btree (parent_id);


--
-- Name: index_organizations_on_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organizations_on_path ON public.organizations USING gist (path);


--
-- Name: index_sites_on_org_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sites_on_org_path ON public.sites USING gist (org_path);


--
-- Name: index_sites_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sites_on_organization_id ON public.sites USING btree (organization_id);


--
-- Name: index_telemetry_on_alarm_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_telemetry_on_alarm_state ON ONLY public.telemetry USING btree (alarm_state);


--
-- Name: index_telemetry_on_org_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_telemetry_on_org_path ON ONLY public.telemetry USING gist (org_path);


--
-- Name: index_telemetry_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_telemetry_on_organization_id ON ONLY public.telemetry USING btree (organization_id);


--
-- Name: index_telemetry_on_site_id_and_recorded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_telemetry_on_site_id_and_recorded_at ON ONLY public.telemetry USING btree (site_id, recorded_at DESC);


--
-- Name: index_users_on_org_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_org_path ON public.users USING gist (org_path);


--
-- Name: index_users_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_organization_id ON public.users USING btree (organization_id);


--
-- Name: index_users_on_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_role ON public.users USING btree (role);


--
-- Name: telemetry_default_alarm_state_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_default_alarm_state_idx ON public.telemetry_default USING btree (alarm_state);


--
-- Name: telemetry_default_org_path_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_default_org_path_idx ON public.telemetry_default USING gist (org_path);


--
-- Name: telemetry_default_organization_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_default_organization_id_idx ON public.telemetry_default USING btree (organization_id);


--
-- Name: telemetry_default_site_id_recorded_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_default_site_id_recorded_at_idx ON public.telemetry_default USING btree (site_id, recorded_at DESC);


--
-- Name: telemetry_y2026m04_alarm_state_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m04_alarm_state_idx ON public.telemetry_y2026m04 USING btree (alarm_state);


--
-- Name: telemetry_y2026m04_org_path_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m04_org_path_idx ON public.telemetry_y2026m04 USING gist (org_path);


--
-- Name: telemetry_y2026m04_organization_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m04_organization_id_idx ON public.telemetry_y2026m04 USING btree (organization_id);


--
-- Name: telemetry_y2026m04_site_id_recorded_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m04_site_id_recorded_at_idx ON public.telemetry_y2026m04 USING btree (site_id, recorded_at DESC);


--
-- Name: telemetry_y2026m05_alarm_state_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m05_alarm_state_idx ON public.telemetry_y2026m05 USING btree (alarm_state);


--
-- Name: telemetry_y2026m05_org_path_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m05_org_path_idx ON public.telemetry_y2026m05 USING gist (org_path);


--
-- Name: telemetry_y2026m05_organization_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m05_organization_id_idx ON public.telemetry_y2026m05 USING btree (organization_id);


--
-- Name: telemetry_y2026m05_site_id_recorded_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m05_site_id_recorded_at_idx ON public.telemetry_y2026m05 USING btree (site_id, recorded_at DESC);


--
-- Name: telemetry_y2026m06_alarm_state_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m06_alarm_state_idx ON public.telemetry_y2026m06 USING btree (alarm_state);


--
-- Name: telemetry_y2026m06_org_path_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m06_org_path_idx ON public.telemetry_y2026m06 USING gist (org_path);


--
-- Name: telemetry_y2026m06_organization_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m06_organization_id_idx ON public.telemetry_y2026m06 USING btree (organization_id);


--
-- Name: telemetry_y2026m06_site_id_recorded_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m06_site_id_recorded_at_idx ON public.telemetry_y2026m06 USING btree (site_id, recorded_at DESC);


--
-- Name: telemetry_y2026m07_alarm_state_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m07_alarm_state_idx ON public.telemetry_y2026m07 USING btree (alarm_state);


--
-- Name: telemetry_y2026m07_org_path_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m07_org_path_idx ON public.telemetry_y2026m07 USING gist (org_path);


--
-- Name: telemetry_y2026m07_organization_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m07_organization_id_idx ON public.telemetry_y2026m07 USING btree (organization_id);


--
-- Name: telemetry_y2026m07_site_id_recorded_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m07_site_id_recorded_at_idx ON public.telemetry_y2026m07 USING btree (site_id, recorded_at DESC);


--
-- Name: telemetry_y2026m08_alarm_state_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m08_alarm_state_idx ON public.telemetry_y2026m08 USING btree (alarm_state);


--
-- Name: telemetry_y2026m08_org_path_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m08_org_path_idx ON public.telemetry_y2026m08 USING gist (org_path);


--
-- Name: telemetry_y2026m08_organization_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m08_organization_id_idx ON public.telemetry_y2026m08 USING btree (organization_id);


--
-- Name: telemetry_y2026m08_site_id_recorded_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX telemetry_y2026m08_site_id_recorded_at_idx ON public.telemetry_y2026m08 USING btree (site_id, recorded_at DESC);


--
-- Name: telemetry_default_alarm_state_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_alarm_state ATTACH PARTITION public.telemetry_default_alarm_state_idx;


--
-- Name: telemetry_default_org_path_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_org_path ATTACH PARTITION public.telemetry_default_org_path_idx;


--
-- Name: telemetry_default_organization_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_organization_id ATTACH PARTITION public.telemetry_default_organization_id_idx;


--
-- Name: telemetry_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.telemetry_pkey ATTACH PARTITION public.telemetry_default_pkey;


--
-- Name: telemetry_default_site_id_recorded_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_site_id_and_recorded_at ATTACH PARTITION public.telemetry_default_site_id_recorded_at_idx;


--
-- Name: telemetry_y2026m04_alarm_state_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_alarm_state ATTACH PARTITION public.telemetry_y2026m04_alarm_state_idx;


--
-- Name: telemetry_y2026m04_org_path_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_org_path ATTACH PARTITION public.telemetry_y2026m04_org_path_idx;


--
-- Name: telemetry_y2026m04_organization_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_organization_id ATTACH PARTITION public.telemetry_y2026m04_organization_id_idx;


--
-- Name: telemetry_y2026m04_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.telemetry_pkey ATTACH PARTITION public.telemetry_y2026m04_pkey;


--
-- Name: telemetry_y2026m04_site_id_recorded_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_site_id_and_recorded_at ATTACH PARTITION public.telemetry_y2026m04_site_id_recorded_at_idx;


--
-- Name: telemetry_y2026m05_alarm_state_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_alarm_state ATTACH PARTITION public.telemetry_y2026m05_alarm_state_idx;


--
-- Name: telemetry_y2026m05_org_path_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_org_path ATTACH PARTITION public.telemetry_y2026m05_org_path_idx;


--
-- Name: telemetry_y2026m05_organization_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_organization_id ATTACH PARTITION public.telemetry_y2026m05_organization_id_idx;


--
-- Name: telemetry_y2026m05_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.telemetry_pkey ATTACH PARTITION public.telemetry_y2026m05_pkey;


--
-- Name: telemetry_y2026m05_site_id_recorded_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_site_id_and_recorded_at ATTACH PARTITION public.telemetry_y2026m05_site_id_recorded_at_idx;


--
-- Name: telemetry_y2026m06_alarm_state_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_alarm_state ATTACH PARTITION public.telemetry_y2026m06_alarm_state_idx;


--
-- Name: telemetry_y2026m06_org_path_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_org_path ATTACH PARTITION public.telemetry_y2026m06_org_path_idx;


--
-- Name: telemetry_y2026m06_organization_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_organization_id ATTACH PARTITION public.telemetry_y2026m06_organization_id_idx;


--
-- Name: telemetry_y2026m06_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.telemetry_pkey ATTACH PARTITION public.telemetry_y2026m06_pkey;


--
-- Name: telemetry_y2026m06_site_id_recorded_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_site_id_and_recorded_at ATTACH PARTITION public.telemetry_y2026m06_site_id_recorded_at_idx;


--
-- Name: telemetry_y2026m07_alarm_state_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_alarm_state ATTACH PARTITION public.telemetry_y2026m07_alarm_state_idx;


--
-- Name: telemetry_y2026m07_org_path_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_org_path ATTACH PARTITION public.telemetry_y2026m07_org_path_idx;


--
-- Name: telemetry_y2026m07_organization_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_organization_id ATTACH PARTITION public.telemetry_y2026m07_organization_id_idx;


--
-- Name: telemetry_y2026m07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.telemetry_pkey ATTACH PARTITION public.telemetry_y2026m07_pkey;


--
-- Name: telemetry_y2026m07_site_id_recorded_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_site_id_and_recorded_at ATTACH PARTITION public.telemetry_y2026m07_site_id_recorded_at_idx;


--
-- Name: telemetry_y2026m08_alarm_state_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_alarm_state ATTACH PARTITION public.telemetry_y2026m08_alarm_state_idx;


--
-- Name: telemetry_y2026m08_org_path_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_org_path ATTACH PARTITION public.telemetry_y2026m08_org_path_idx;


--
-- Name: telemetry_y2026m08_organization_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_organization_id ATTACH PARTITION public.telemetry_y2026m08_organization_id_idx;


--
-- Name: telemetry_y2026m08_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.telemetry_pkey ATTACH PARTITION public.telemetry_y2026m08_pkey;


--
-- Name: telemetry_y2026m08_site_id_recorded_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.index_telemetry_on_site_id_and_recorded_at ATTACH PARTITION public.telemetry_y2026m08_site_id_recorded_at_idx;


--
-- Name: audit_logs trg_audit_logs_no_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_logs_no_delete BEFORE DELETE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION app.enforce_audit_logs_insert_only();


--
-- Name: audit_logs trg_audit_logs_no_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_logs_no_update BEFORE UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION app.enforce_audit_logs_insert_only();


--
-- Name: audit_logs trg_audit_logs_populate_org_path; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_logs_populate_org_path BEFORE INSERT ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION app.populate_tenant_org_path();


--
-- Name: cases trg_cases_escalation_lifecycle; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cases_escalation_lifecycle BEFORE INSERT OR UPDATE OF escalated_to_maverick ON public.cases FOR EACH ROW EXECUTE FUNCTION app.enforce_case_escalation_lifecycle();


--
-- Name: cases trg_cases_notes_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cases_notes_append_only BEFORE UPDATE OF notes ON public.cases FOR EACH ROW EXECUTE FUNCTION app.enforce_case_notes_append_only();


--
-- Name: cases trg_cases_populate_org_path; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cases_populate_org_path BEFORE INSERT OR UPDATE OF organization_id ON public.cases FOR EACH ROW EXECUTE FUNCTION app.populate_tenant_org_path();


--
-- Name: cases trg_cases_status_machine; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cases_status_machine BEFORE INSERT OR UPDATE OF status ON public.cases FOR EACH ROW EXECUTE FUNCTION app.enforce_case_status_machine();


--
-- Name: cases trg_cases_touch_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_cases_touch_updated_at BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();


--
-- Name: organizations trg_organizations_immutable_columns; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_organizations_immutable_columns BEFORE UPDATE ON public.organizations FOR EACH ROW EXECUTE FUNCTION app.enforce_organization_immutable_columns();


--
-- Name: organizations trg_organizations_populate_path; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_organizations_populate_path BEFORE INSERT ON public.organizations FOR EACH ROW EXECUTE FUNCTION app.populate_organization_path();


--
-- Name: organizations trg_organizations_touch_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_organizations_touch_updated_at BEFORE UPDATE ON public.organizations FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();


--
-- Name: sites trg_sites_populate_org_path; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sites_populate_org_path BEFORE INSERT OR UPDATE OF organization_id ON public.sites FOR EACH ROW EXECUTE FUNCTION app.populate_tenant_org_path();


--
-- Name: sites trg_sites_touch_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sites_touch_updated_at BEFORE UPDATE ON public.sites FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();


--
-- Name: sites trg_sites_validate_parent_is_customer; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_sites_validate_parent_is_customer BEFORE INSERT OR UPDATE OF organization_id ON public.sites FOR EACH ROW EXECUTE FUNCTION app.validate_site_parent_is_customer();


--
-- Name: telemetry trg_telemetry_populate_org_path; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_telemetry_populate_org_path BEFORE INSERT OR UPDATE OF organization_id ON public.telemetry FOR EACH ROW EXECUTE FUNCTION app.populate_tenant_org_path();


--
-- Name: users trg_users_populate_org_path; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_users_populate_org_path BEFORE INSERT OR UPDATE OF organization_id ON public.users FOR EACH ROW EXECUTE FUNCTION app.populate_tenant_org_path();


--
-- Name: users trg_users_touch_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_users_touch_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();


--
-- Name: users trg_users_validate_role_matches_org_type; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_users_validate_role_matches_org_type BEFORE INSERT OR UPDATE OF role, organization_id ON public.users FOR EACH ROW EXECUTE FUNCTION app.validate_user_role_matches_org_type();


--
-- Name: audit_logs audit_logs_actor_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: audit_logs audit_logs_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: cases cases_opened_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cases
    ADD CONSTRAINT cases_opened_by_user_id_fkey FOREIGN KEY (opened_by_user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: cases cases_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cases
    ADD CONSTRAINT cases_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: cases cases_site_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cases
    ADD CONSTRAINT cases_site_id_fkey FOREIGN KEY (site_id) REFERENCES public.sites(id) ON DELETE RESTRICT;


--
-- Name: organizations organizations_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: sites sites_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sites
    ADD CONSTRAINT sites_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: telemetry telemetry_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.telemetry
    ADD CONSTRAINT telemetry_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: telemetry telemetry_site_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.telemetry
    ADD CONSTRAINT telemetry_site_id_fkey FOREIGN KEY (site_id) REFERENCES public.sites(id) ON DELETE RESTRICT;


--
-- Name: users users_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: cases; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;

--
-- Name: organizations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

--
-- Name: sites; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.sites ENABLE ROW LEVEL SECURITY;

--
-- Name: telemetry; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.telemetry ENABLE ROW LEVEL SECURITY;

--
-- Name: telemetry_default; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.telemetry_default ENABLE ROW LEVEL SECURITY;

--
-- Name: telemetry_y2026m04; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.telemetry_y2026m04 ENABLE ROW LEVEL SECURITY;

--
-- Name: telemetry_y2026m05; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.telemetry_y2026m05 ENABLE ROW LEVEL SECURITY;

--
-- Name: telemetry_y2026m06; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.telemetry_y2026m06 ENABLE ROW LEVEL SECURITY;

--
-- Name: telemetry_y2026m07; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.telemetry_y2026m07 ENABLE ROW LEVEL SECURITY;

--
-- Name: telemetry_y2026m08; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.telemetry_y2026m08 ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs tenant_visibility; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_visibility ON public.audit_logs TO app_user USING (app.can_see(org_path)) WITH CHECK (app.can_see(org_path));


--
-- Name: cases tenant_visibility; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_visibility ON public.cases TO app_user USING (app.can_see(org_path)) WITH CHECK (app.can_see(org_path));


--
-- Name: organizations tenant_visibility; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_visibility ON public.organizations TO app_user USING (app.can_see(path)) WITH CHECK (app.can_see(path));


--
-- Name: sites tenant_visibility; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_visibility ON public.sites TO app_user USING (app.can_see(org_path)) WITH CHECK (app.can_see(org_path));


--
-- Name: telemetry tenant_visibility; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_visibility ON public.telemetry TO app_user USING (app.can_see(org_path)) WITH CHECK (app.can_see(org_path));


--
-- Name: telemetry_default tenant_visibility; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_visibility ON public.telemetry_default TO app_user USING (app.can_see(org_path)) WITH CHECK (app.can_see(org_path));


--
-- Name: telemetry_y2026m04 tenant_visibility; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_visibility ON public.telemetry_y2026m04 TO app_user USING (app.can_see(org_path)) WITH CHECK (app.can_see(org_path));


--
-- Name: telemetry_y2026m05 tenant_visibility; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_visibility ON public.telemetry_y2026m05 TO app_user USING (app.can_see(org_path)) WITH CHECK (app.can_see(org_path));


--
-- Name: telemetry_y2026m06 tenant_visibility; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_visibility ON public.telemetry_y2026m06 TO app_user USING (app.can_see(org_path)) WITH CHECK (app.can_see(org_path));


--
-- Name: telemetry_y2026m07 tenant_visibility; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_visibility ON public.telemetry_y2026m07 TO app_user USING (app.can_see(org_path)) WITH CHECK (app.can_see(org_path));


--
-- Name: telemetry_y2026m08 tenant_visibility; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_visibility ON public.telemetry_y2026m08 TO app_user USING (app.can_see(org_path)) WITH CHECK (app.can_see(org_path));


--
-- Name: users tenant_visibility; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_visibility ON public.users TO app_user USING (app.can_see(org_path)) WITH CHECK (app.can_see(org_path));


--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260506143000'),
('20260505181440'),
('20260505124000'),
('20260504151600'),
('20260504151500'),
('20260504151400'),
('20260504151300'),
('20260504151200'),
('20260504151100'),
('20260504151000'),
('20260504150900'),
('20260504150800'),
('20260504150700'),
('20260504150600'),
('20260504150500');

