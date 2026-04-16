-- Agent API tables: observations from peripherals, actions back to devices
-- Runs against the main Supabase database (public schema)

BEGIN;

-- Observations: flattened ContextPackets from phones, watches, etc.
CREATE TABLE IF NOT EXISTS observations (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    device_id       text NOT NULL,
    trigger_type    text NOT NULL,
    location_lat    double precision,
    location_lon    double precision,
    location_accuracy double precision,
    activity_type   text,
    heart_rate_bpm  integer,
    ambient_db      double precision,
    speech_detected boolean,
    transcript      text,
    visual_ref      text,
    audio_ref       text,
    occurred_at     timestamptz NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_observations_user_occurred
    ON observations (user_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_observations_device
    ON observations (device_id, occurred_at DESC);

-- Agent actions: responses dispatched to devices via Realtime
CREATE TABLE IF NOT EXISTS agent_actions (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    target_device   text NOT NULL,
    action_type     text NOT NULL CHECK (action_type IN ('speak', 'display', 'haptic', 'silent')),
    payload         jsonb NOT NULL DEFAULT '{}',
    priority        text NOT NULL DEFAULT 'queued' CHECK (priority IN ('immediate', 'queued')),
    status          text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'delivered', 'expired')),
    expires_at      timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_agent_actions_user_status
    ON agent_actions (user_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_agent_actions_device_pending
    ON agent_actions (target_device, status) WHERE status = 'pending';

-- RLS: users see only their own rows

ALTER TABLE observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_actions ENABLE ROW LEVEL SECURITY;

-- Authenticated users: read/write own observations
CREATE POLICY observations_user_select ON observations
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY observations_user_insert ON observations
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Authenticated users: read own actions (devices poll for pending actions)
CREATE POLICY agent_actions_user_select ON agent_actions
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

-- Authenticated users: update status on own actions (mark delivered)
CREATE POLICY agent_actions_user_update ON agent_actions
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Agent role (M2M JWT with role='agent', delegated_for=<user_id>):
-- can read observations and write actions for the delegated user
CREATE POLICY observations_agent_select ON observations
    FOR SELECT TO authenticated
    USING (
        current_setting('request.jwt.claims', true)::jsonb->>'role' = 'agent'
        AND user_id = (current_setting('request.jwt.claims', true)::jsonb->>'delegated_for')::uuid
    );

CREATE POLICY agent_actions_agent_insert ON agent_actions
    FOR INSERT TO authenticated
    WITH CHECK (
        current_setting('request.jwt.claims', true)::jsonb->>'role' = 'agent'
        AND user_id = (current_setting('request.jwt.claims', true)::jsonb->>'delegated_for')::uuid
    );

CREATE POLICY agent_actions_agent_select ON agent_actions
    FOR SELECT TO authenticated
    USING (
        current_setting('request.jwt.claims', true)::jsonb->>'role' = 'agent'
        AND user_id = (current_setting('request.jwt.claims', true)::jsonb->>'delegated_for')::uuid
    );

CREATE POLICY agent_actions_agent_update ON agent_actions
    FOR UPDATE TO authenticated
    USING (
        current_setting('request.jwt.claims', true)::jsonb->>'role' = 'agent'
        AND user_id = (current_setting('request.jwt.claims', true)::jsonb->>'delegated_for')::uuid
    )
    WITH CHECK (
        current_setting('request.jwt.claims', true)::jsonb->>'role' = 'agent'
        AND user_id = (current_setting('request.jwt.claims', true)::jsonb->>'delegated_for')::uuid
    );

-- Enable Realtime subscriptions on both tables
ALTER PUBLICATION supabase_realtime ADD TABLE observations, agent_actions;

COMMIT;
